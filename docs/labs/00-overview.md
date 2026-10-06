# Lab 00 – Overview, architecture, costs and caveats

**Time:** 20 minutes · **Previous:** – · **Next:** [Lab 01](01-prerequisites.md)

## Objectives

* Understand the end-to-end architecture and the data sources.
* Know which parts are automated and which you build by hand.
* Understand the costs, licensing terms and preview limitations before you start.

## What you'll build

1. **Ingest** live train movements from two sources:
   * **Rail Data Marketplace (RDM)** *NWR Train Movements* over Kafka, straight into a Fabric **Eventstream** through the Apache Kafka source connector (Lab 04).
   * **Network Rail Open Data (NROD)** over STOMP, through a small Python **bridge** that forwards to an Eventstream **custom endpoint**. The bridge runs locally (Lab 05a) or on Azure Container Apps (Lab 05b).
2. **Store and shape** the data in an **Eventhouse**. Raw JSON lands in `RawFeed` / `RdmTrustRaw`. **Update policies** split batched TRUST messages by `msg_type` into typed tables, and **materialized views** keep the latest state for each train and the delay summaries (Lab 06). Reference data (CORPUS, SMART, NaPTAN) goes into a **Lakehouse** and a KQL `Locations` table (Lab 03).
3. **Act and visualise** with **Activator** alerts (Lab 07), a **Real-Time Dashboard** and a **Power BI** report (Lab 08).
4. **Converse** through a **Fabric data agent** (Lab 09), an **Azure AI Foundry agent** that calls it (Lab 10), and a **Rayfin** Fabric app with a live map and a chat panel (Lab 11).

See the Mermaid diagram in the [README](../../README.md#architecture).

## Data sources at a glance

| Source | Protocol | Feeds used | Notes |
|---|---|---|---|
| RDM – [NWR Train Movements](https://raildata.org.uk/dataProduct/P-826477b8-3789-45e7-85bd-22c4ae9bcfae/overview) | Kafka, `SASL_SSL` + `PLAIN` | TRUST | **Beta, no SLA**. The bootstrap servers, topic, consumer group, username and password are on your subscription page |
| RDM – [Darwin Real Time Train Information (Push)](https://raildata.org.uk/dataProduct/P-3f10bf96-d8e8-4041-aa5e-d75d82c45c4e/overview) | Kafka | Darwin | Optional extension. Not parsed in these labs |
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

> **Avoid double counting.** RDM *NWR Train Movements* and NROD `TRAIN_MVT_ALL_TOC` carry the same TRUST events.
> Either use one of them for TRUST, or keep both and filter on the `source` column (`rdm` or `nrod`) in queries.
> A good split: RDM for TRUST, and the bridge for `RTPPM_ALL`, `VSTP_ALL`, `TSR_ALL_ROUTE` (and `TD_ALL_SIG_AREA` if you want it).

## Bridge hosting decision

| Option | Fit | Cost (indicative) |
|---|---|---|
| **Azure Container Apps**, min = max = 1 replica, 0.25 vCPU / 0.5 GiB | ✅ Long-lived STOMP connection, single instance, Key Vault, Log Analytics | **~$14/month** list-price estimate after the free grant. Size up for TD |
| Azure Functions (Consumption) | ❌ Not designed for a permanent socket. ✅ Fine for the **daily reference-file pull** | Low |
| Azure Functions Premium/Flex (always ready) | Works, but over-provisioned | ~$80–150+/month |
| Your laptop / Docker | ✅ Training and development | Free |

## Automated and manual parts

See the table in the [README](../../README.md#what-is-automated-and-what-is-manual). In short, everything that can be done reliably with the Fabric REST API, KQL management commands, the Azure CLI or Bicep is scripted. The Eventstream topology, Activator, dashboards, the data agent and Foundry tool connections are manual.

## Preview caveats

* The **Fabric data agent tool in Foundry** is preview. It supports **user identity (On-Behalf-Of) only**, not service principals. It needs a paid **F2+** capacity, the same tenant and the same capacity region for the data agent and its sources, and cross-geo processing/storage tenant settings where needed.
* **Fabric Apps / Rayfin** is preview. Rayfin connectors are preview (`kusto` is *private preview*) and functions are *experimental*.
* **RDM NWR Train Movements** is beta with no SLA.
* The **Lakehouse Load Table** REST API is preview.

## Licensing

* You must attribute the data source in every UI and report.
* Don't call the app or dashboards "official", and don't use Network Rail or National Rail logos.
* Code is MIT-licensed.
