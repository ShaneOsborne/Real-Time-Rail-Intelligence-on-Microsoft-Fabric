# Start here – Overview, architecture, costs and caveats

**Time:** 20 minutes · **Next:** [choose your path](#choose-your-path)

## Objectives

* Understand the end-to-end architecture and the data sources.
* Know which parts are automated and which you build by hand.
* Understand the costs, licensing terms and preview limitations before you start.

## Choose your path

Part 1 gets live data into your own Fabric workspace. There are three versions of it, one per audience. Pick **one** and
follow its folder top to bottom. Part 2 is the same build for everyone.

| You are… | Part 1 | Then |
|---|---|---|
| **Solo builder** – your own NROD/RDM accounts, Azure and Fabric | [Solo path](solo/README.md) (Solo 1.1–1.8) | [Part 2 – the build](build/README.md) (Lab 2.1–2.10) |
| **Instructor** – setting up a class | [Instructor path](instructor/README.md) (Instructor 1.1–1.7, which reuse some solo pages) | Run [Part 2](build/README.md) yourself before the class |
| **Classroom student** – the instructor gives you a handout | [Student path](student/README.md) (Student 1.1–1.4, optional 1.5) | [Part 2 – the build](build/README.md) (Lab 2.1–2.10) |

## What you'll build

1. **Ingest** live train movements from two sources:
   * **Rail Data Marketplace (RDM)** *NWR Train Movements* over Kafka, straight into a Fabric **Eventstream** through the Apache Kafka source connector (Solo 1.4).
   * **Network Rail Open Data (NROD)** over STOMP, through a small Python **bridge** that forwards to an Eventstream **custom endpoint**. The bridge runs locally (Solo 1.6) or on Azure Container Apps (Solo 1.7).
   * *Optional shared mode (Instructor 1.4 for a class, Solo 1.8 for one person):* an **Azure Event Hubs** namespace sits between the sources and Fabric. One instructor-run
     bridge (and an RDM Kafka relay) sends to it, and each student's Eventstream reads it with an **Azure Event Hubs** source and its own
     consumer group. Use it for a class (NROD allows one connection per account; RDM subscriptions are per user) or when the Fabric
     capacity is paused overnight: Event Hubs keeps buffering for up to 7 days. The direct paths above stay the default.
     Students sign in with a Listen key, or, where a policy blocks keys on the namespace, with their **workspace identity**
     (`EVENTHUB_AUTH=entra`). The instructor can also run an optional **Darwin relay** into a third hub, `rdm-darwin`, for the
     optional Darwin class feed ([Student 1.5](student/1.5-darwin-class-feed.md)).
2. **Store and shape** the data in an **Eventhouse**. Raw JSON lands in `RawFeed` / `RdmTrustRaw`. **Update policies** split batched TRUST messages by `msg_type` into typed tables, and **materialized views** keep the latest state for each train and the delay summaries (Lab 2.1). Reference data (CORPUS, SMART, NaPTAN) goes into a **Lakehouse** and a KQL `Locations` table (Solo 1.3).
3. **Act and visualise** with **Activator** alerts (Lab 2.2), a **Real-Time Dashboard** and a **Power BI** report (Lab 2.3).
4. **Converse** through a **Fabric data agent** (Lab 2.4), an **Azure AI Foundry agent** that calls it (Lab 2.6), and a **Rayfin** Fabric app with a live map and a chat panel (Lab 2.8).

See the Mermaid diagram in the [README](../README.md#architecture).

## Data sources at a glance

| Source | Protocol | Feeds used | Notes |
|---|---|---|---|
| RDM – [NWR Train Movements](https://raildata.org.uk/dataProduct/P-826477b8-3789-45e7-85bd-22c4ae9bcfae/overview) | Kafka, `SASL_SSL` + `PLAIN` | TRUST | **Beta, no SLA**. The bootstrap servers, topic, consumer group, username and password are on your subscription page |
| RDM – [Darwin Real Time Train Information (Push)](https://raildata.org.uk/dataProduct/P-3f10bf96-d8e8-4041-aa5e-d75d82c45c4e/overview) | Kafka | Darwin | Optional extension: [Solo 1.5](solo/1.5-darwin-push-port.md) parses it into `DarwinLocations`. In a class, the instructor can relay it for everyone ([Student 1.5](student/1.5-darwin-class-feed.md)) |
| NROD – `publicdatafeeds.networkrail.co.uk` | STOMP on **61618** (OpenWire and AMQP 61612 also exist) | `TRAIN_MVT_ALL_TOC`, `TD_ALL_SIG_AREA`, `RTPPM_ALL`, `VSTP_ALL`, `TSR_ALL_ROUTE` | One account, **one connection**. Durable subscription buffer is about **5 minutes**. Capped at about 1,000 users |
| NROD reference files | HTTPS (basic auth) | CORPUS, SMART (`SupportingFileAuthenticate?type=`), SCHEDULE (`CifFileAuthenticate?type=CIF_ALL_FULL_DAILY&day=toc-full`) | Subscribe to *All Reference Data* in *My Feeds* |
| NaPTAN (DfT) | HTTPS | Rail stations (`9100<TIPLOC>` ATCO codes) with latitude and longitude | OGL v3.0 |

### TRUST message types

| `header.msg_type` | Meaning | Parsed into |
|---|---|---|
| 0001 | Activation | `TrustActivations` |
| 0002 | Cancellation | `TrustCancellations` |
| 0003 | Movement | `TrustMovements` |
| 0004 | Unidentified train | `TrustOtherEvents` |
| 0005 | Reinstatement | `TrustOtherEvents` |
| 0006 | Change of origin | `TrustOtherEvents` |
| 0007 | Change of identity | `TrustOtherEvents` |
| 0008 | Change of location | `TrustOtherEvents` |

Volumes: TRUST peaks at about 600 messages a minute (in batches), TD at about 6,000 a minute, and RTPPM at 1 a minute.

> **Avoid double counting.** RDM *NWR Train Movements* and NROD `TRAIN_MVT_ALL_TOC` carry the same TRUST events. In these labs Train Movements comes from RDM (Solo 1.4), and the bridge (Solo 1.6/1.7) brings in **RTPPM** by default (`NROD_TOPICS=RTPPM_ALL`).
> Either use one of them for TRUST, or keep both and filter on the `source` column (`rdm` or `nrod`) in queries.
> A good split: RDM for TRUST, and the bridge for `RTPPM_ALL`, `VSTP_ALL`, `TSR_ALL_ROUTE` (and `TD_ALL_SIG_AREA` if you want it).

## Bridge hosting decision

| Option | Fit | Cost (indicative) |
|---|---|---|
| **Azure Container Apps**, min = max = 1 replica, 0.25 vCPU / 0.5 GiB | ✅ Long-lived STOMP connection, single instance, Key Vault, Log Analytics | **~$14/month** list-price estimate after the free grant. Size up for TD |
| Azure Functions (Consumption) | ❌ Not designed for a permanent socket. ✅ Fine for the **daily reference-file pull** | Low |
| Azure Functions Premium/Flex (always ready) | Works, but over-provisioned | ~$80–150+/month |
| Your laptop / Docker | ✅ Training and development | Free |

For classes or paused capacities, add the optional shared **Azure Event Hubs Standard** tier ([Instructor 1.4](instructor/1.4-shared-event-hub.md) for a class, [Solo 1.8](solo/1.8-shared-event-hub.md) for one person): about **$22/month** for 1 throughput unit plus a few dollars of ingress, and **~$14/month** more if you also run the RDM relay app (list-price estimates). The optional Darwin relay app adds about **$28/month** (estimate) and needs 2 or more throughput units.

## Fabric capacity requirements

Always-on Eventstreams charge capacity all day, every day, so size the capacity for the feeds you'll run. These are
**estimates** from Microsoft's published rates; validate them with the Capacity Metrics app.

| Scenario | Suggested capacity |
|---|---|
| Single builder, Train Movements only (Solo 1.1 to Lab 2.8) | F2 workable but tight; F4 comfortable |
| Single builder + Darwin (Solo 1.5) and/or the NROD bridge | F4 minimum; F8 with heavy dashboard or agent use |
| Class on one shared capacity, each student with their own pipeline | ~1.5–2 CU per student (10 students ≈ F16–F32) |

Each Eventstream with an Apache Kafka source uses roughly 0.83 CU (≈ 42% of an F2) continuously. Two of them on an F2 can
throttle it overnight. For details, classroom patterns and throttling recovery, see
[Capacity planning and sizing](capacity-planning.md).

## Automated and manual parts

See the table in the [README](../README.md#what-is-automated-and-what-is-manual). In short, everything that can be done reliably with the Fabric REST API, KQL management commands, the Azure CLI or Bicep is scripted. The Eventstream topology, Activator, dashboards, the data agent and Foundry tool connections are manual.

## Preview caveats

* Lab 2.6 uses the **Fabric IQ (OneLake Catalog)** tool in Foundry (preview). The older Fabric data agent tool stops being supported on **6 November 2026**. Use a background-mode model (gpt-5.4/5.5 recommended). Calls run as the signed-in user. It needs a paid **F2+** capacity, the same tenant and the same capacity region for the data agent and its sources, and cross-geo processing/storage tenant settings where needed.
* **Fabric Apps / Rayfin** is preview. Rayfin 1.36.2 can't query a KQL database (no Kusto connector or token), so Lab 2.8's map reads a DirectQuery semantic model over `RailKQL` (Lab 2.7) through the preview `fabric-semanticmodel` connector; the chat uses a Rayfin function, and functions aren't available in every tenant or region. **Fabric Apps itself isn't available in every Fabric region.** Check *New item → App (preview)* during Part 1 (Solo 1.1 or Instructor 1.1), and see Lab 2.8 for the workaround.
* **RDM NWR Train Movements** is beta with no SLA.
* The **Lakehouse Load Table** REST API is preview.

## Licensing

* You must attribute the data source in every UI and report.
* Don't call the app or dashboards "official", and don't use Network Rail or National Rail logos.
* Code is MIT-licensed.
