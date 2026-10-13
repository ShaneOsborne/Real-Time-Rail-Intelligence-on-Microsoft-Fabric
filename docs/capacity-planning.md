# Capacity planning and sizing

This page explains how much Microsoft Fabric capacity the labs need, why, and how to size a capacity for one builder or for
a class. It also covers how to stay within your capacity and what to do if it's throttled.

> **The figures on this page are estimates.** They're worked out from Microsoft's published consumption rates at the time
> of writing, not measured in your tenant. Rates can change. Always validate with the
> [Microsoft Fabric Capacity Metrics app](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app) on your own capacity.

## Why it matters

Earlier versions of these labs said "F2 or higher". F2 is the **minimum**, not a tested size. In a proof of concept, two
always-on Kafka Eventstreams (NWR Train Movements from Lab 04 and Darwin from Lab 04b), plus Eventhouse ingestion and some
back-fills, throttled an F2 overnight: the capacity showed as degraded the next morning.

The reason is simple. An Eventstream with a live source runs **all day, every day**, so its charge never stops. An F2 has
only 2 capacity units (CUs), which is 48 CU hours a day. A few always-on streams can use most of that before the Eventhouse,
dashboards or the data agent do anything.

If you run a class on one shared capacity, every student's pipeline adds the same continuous load. **Capacity needs grow
roughly in line with the number of student pipelines.**

## How Fabric charges these workloads

| Workload | Operation | Published rate | Notes |
|---|---|---|---|
| Eventstream | Eventstream Per Hour | **0.222 CU hours per hour** | Flat charge, only while events flow. No charge if there's been no traffic for 2 hours |
| Eventstream | Data Traffic | **0.342 CU hours per GB** | Ingress and egress in the default and derived streams. Includes 24-hour retention |
| Eventstream | Processor | **From 0.778 CU hours per hour** (throughput setting *Low*) | Autoscales with throughput, logic and partitions. *Medium* and *High* start higher |
| Eventstream | Connectors | **0.611 CU hours per vCore hour** | One vCore per connector source at present. Doesn't apply to Azure Event Hubs, IoT Hub or custom endpoint sources: Event Hubs data is pulled by the Eventstream processor |
| Eventhouse | Eventhouse UpTime | Seconds active × virtual cores | Autoscale sets the size from ingestion and query load. An optional **Capacity Scheduler** minimum capacity (per 60-minute block) makes UpTime at least that baseline |

Sources:

* [Monitor capacity consumption for Eventstream](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/monitor-capacity-consumption)
* [Real-Time Intelligence consumption (Eventhouse)](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/real-time-intelligence-consumption)
* [Throttling in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/enterprise/throttling)

A CU hour per hour is the same as a continuous load of 1 CU. An F2 provides 2 CUs.

Microsoft notes that Eventstreams can run on the smallest F capacity, but other Fabric items used as destinations may need
more CUs. In these labs, that's the Eventhouse.

## Estimated load per component

**Estimates** from the published rates above, before data traffic unless stated. Validate them in the Capacity Metrics app.

| Component | Used in | Estimated continuous load | Share of an F2 (2 CUs) |
|---|---|---|---|
| Eventstream with an **Apache Kafka** source (Train Movements or Darwin) | Labs 04, 04b | ≈ **0.83 CU** (0.222 + 0.611), plus data traffic and any processor use | ≈ **42%** each |
| **Two** Kafka Eventstreams (Train Movements + Darwin) | Labs 04 + 04b | ≈ **1.67 CU** | ≈ **83%**, before the Eventhouse does anything |
| Eventstream with an **Azure Event Hubs** source | Lab 05c (students) | ≈ **1.0 CU** (0.222 + processor from 0.778 at *Low*) | ≈ 50% |
| Eventstream with a **custom endpoint** source (the bridge) | Labs 05a, 05b | Flat 0.222 CU while events flow, plus data traffic at 0.342 CU hours per GB | Lighter, but depends on volume. The NROD TD feed is about **10×** the TRUST volume |
| Eventhouse | Labs 04–11 | No fixed figure: autoscaled vCores while active, driven by ingestion and query load | Measure it during Lab 04 and budget the headroom that's left |
| Fabric data agent, Copilot, Foundry agent with the Fabric tool | Labs 09–11 | Adds CU when used | Interactive load. The Foundry Fabric tool needs a **paid F2+** capacity (trial isn't supported) |

## Sizing by scenario

**Estimates.** Start here, then check the Capacity Metrics app after the first day and adjust.

| Scenario | Suggested capacity | Notes |
|---|---|---|
| Single builder, Train Movements only (Labs 01–11) | **F2** workable but tight; **F4** comfortable | About 42% goes on streaming. Leave room for the Eventhouse, dashboards and the agent |
| Single builder + Darwin (Lab 04b) and/or the NROD bridge | **F4** minimum; **F8** with heavy dashboard refresh or agent use | Or deactivate `RailEventstreamDarwin` when you don't need it |
| Classroom: each student has their own Eventstream + Eventhouse on **one shared capacity** | Plan **~1.5–2 CU per student** (≈ 1 CU streaming + Eventhouse and queries): 5 students ≈ **F8–F16**, 10 ≈ **F16–F32**, 20 ≈ **F32–F64** | Apply workspace-level surge protection to each student workspace so one student can't starve the others. Scale up for the session, then scale down or pause afterwards |
| Classroom: **shared instructor ingestion** (one Eventstream and Eventhouse); students query it and build dashboards and agents | Instructor **F4–F8** + light interactive load per student | Far cheaper. Students don't build their own ingestion |
| Classroom: **separate capacity per student** (for example each student's own Fabric trial or F2) | Each student as a single builder | Full isolation. Trials don't support the Foundry Fabric tool or other paid-only features |

## Classrooms and shared capacities

**The key message: on a shared capacity, capacity needs grow roughly linearly with the number of student pipelines.**
Each student who builds Labs 04–06 runs at least one always-on Eventstream and an Eventhouse. Ten students means roughly
ten times the streaming load of one.

Three patterns work:

1. **Each student builds their own pipeline on one shared capacity.** Students learn the whole ingestion path, but you need a
   large capacity (see the table). Protect the class from one runaway workspace with
   **workspace-level surge protection**: it sets per-workspace limits as a percentage of capacity over a rolling 24 hours, and
   blocks a workspace that goes over its limit. Workspaces marked *mission-critical* are exempt, so don't mark student
   workspaces that way. Scale the capacity up for the session and back down (or pause it) afterwards.
2. **Shared instructor ingestion.** The instructor runs one Eventstream and one Eventhouse; students query it and build their
   own dashboards, Activator rules and agents (see Lab 05c, *The alternative: one shared instructor Eventhouse*). This is
   by far the cheapest, but students don't build ingestion themselves.
3. **A separate capacity for each student** (their own trial or a small paid F SKU). Each student is sized as a single
   builder and can't affect anyone else. Trials don't support the Foundry Fabric tool (Lab 10).

**Recommendation:** for more than about **5–10 students**, use shared instructor ingestion (pattern 2) or a separate
capacity per student (pattern 3), rather than one large shared capacity.

> **The shared Event Hub (Lab 05c) doesn't reduce Fabric capacity per student.** It solves the NROD one-connection limit and
> per-user RDM subscriptions, and it buffers data while a capacity is paused. But each student still runs their own
> Eventstream (an Azure Event Hubs source, ≈ 1 CU estimated) and their own Eventhouse, so the Fabric load per student is
> the same.

## Keeping within capacity

* **Check the Capacity Metrics app daily** during a proof of concept or course: utilisation, throttling and carry-forward
  (overage) burndown.
* **Set capacity alerts.** Use Capacity Overview Events (in Real-Time hub) with an Activator alert, so you're told about
  rising utilisation before you hit throttling.
* **Deactivate Eventstreams you aren't using** (Eventstream → **Deactivate all**, or switch off a single source). Darwin
  (Lab 04b) is the obvious candidate.
* **Pause the capacity overnight** if no-one needs live data. Pausing a capacity pauses the active Eventstream sources and
  destinations; after you resume, they start again once they're activated. Use the shared Event Hub (Lab 05c) if you need
  the overnight data buffered. Be aware that **catching up after a resume adds load**.
* **Set dashboard auto-refresh to 1 minute or longer** (Real-Time Dashboard and Power BI auto page refresh).
* **Avoid repeated back-fills and large ad-hoc queries.** Run `08_backfill.kql` once, not on a loop.
* **Check the Eventhouse has no minimum capacity** (Capacity Scheduler) set by mistake. A minimum makes UpTime at least that
  baseline, all day.
* Leave the TD feed (`TD_ALL_SIG_AREA`) off unless you need it: it's about 10× the TRUST volume.

## If your capacity is throttled

What Fabric does when a capacity is overused (from [Throttling in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/enterprise/throttling)):

| Future capacity already used | What happens |
|---|---|
| Up to 10 minutes | Overage protection: no throttling |
| 10–60 minutes | Interactive requests are delayed |
| 60 minutes – 24 hours | Interactive requests are rejected |
| More than 24 hours | Background requests are rejected too |

* Usage is smoothed over **30-second timepoints**. Real-Time Intelligence skips the 20-second delay stage and **begins
  throttling at the 60-minute rejection phase**.
* **Eventstreams aren't rejected.** Fabric reduces the CUs allocated to keep the stream open, so a stream can fall behind.
* **Eventhouse** has its own levels: *proactive* (queries throttled, ingestion continues), *reactive* (ingestion and
  queries paused, no data lost) and *extreme reactive* (data might be lost after a period).

### Recovery checklist: "capacity degraded overnight"

1. Open the **Capacity Metrics app** → select the capacity → **Compute** page. Look at the utilisation chart and the
   **Throttling** and **Overages** tabs to see when it went over 100%, and the carry-forward burndown.
2. In the utilisation details, find which items used the most CU (expect the Eventstreams and the Eventhouse).
3. **Reduce the load first:** deactivate the Eventstreams you don't need (for example `RailEventstreamDarwin`), stop
   back-fills and heavy queries, and lengthen dashboard refresh intervals.
4. **Let it burn down, or clear it:**
   * Unused capacity burns down the carry-forward over time.
   * **Temporarily scale up** the capacity to burn it down faster, then scale back.
   * **Pause and resume** the capacity to clear the accumulated future usage. You're **billed for it when you pause**.
   * Capacity overage billing, if enabled, costs **3×** the normal rate.
5. Check the Eventhouse tables are up to date (for example `RdmTrustRaw | summarize max(ingestion_time())`) and that each
   Eventstream source shows as active after a pause.
6. Resize the capacity for the steady load (see [Sizing by scenario](#sizing-by-scenario)) and set an alert.

## Caveats

* Every figure on this page is an **estimate** from published rates. Your load depends on message volume, partitions, the
  processor throughput setting, queries, dashboards and agents.
* Microsoft can change rates and behaviour. Check the linked Microsoft Learn pages and the
  [Fabric pricing page](https://azure.microsoft.com/pricing/details/microsoft-fabric/).
* **Validate in your own tenant** with the Capacity Metrics app before a class or a long-running proof of concept.
