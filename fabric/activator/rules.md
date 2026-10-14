# Activator rules (Lab 07)

Activator rules are created in the Fabric portal. They cannot be reliably scripted from this repo,
so each rule is described here so you can recreate it exactly.

| # | Rule | Source | Condition | Action |
|---|---|---|---|---|
| 1 | **Train more than 15 minutes late** | KQL queryset alert (query below) every 5 min, **or** Eventstream → Activator destination | Queryset: filter in the query, condition **On each event** (one alert per returned row). Eventstream: object = `train_id`, rule **becomes greater than 15** | Teams message / email: "Train {train_id} is {delay_minutes} min late at {loc_stanox}" |
| 2 | **Cancellation spike** | KQL query `CancellationSpike(15m, 6h) \| where ratio >= 2 and recent_cancellations >= 10` every 5 min | **On each event** (a row is returned only on a spike) | Teams channel post to the ops channel |
| 3 | **Feed stalled** | KQL query `RdmTrustRaw \| where ingestion_time() > ago(10m) \| count \| where Count == 0` every 5 min (use `RawFeed` for the bridge) | **On each event** | Email to the lab owner – check the bridge / RDM subscription |
| 4 | **National PPM amber/red** (optional, RTPPM) | KQL query `RtppmNational \| top 1 by snapshot_time desc \| where rag in ("A", "R")` every 15 min | **On each event** | Teams message |

## KQL used by rule 1 when sourcing from Eventhouse instead of Eventstream

```kusto
TrustMovements
| where received_utc > ago(5m) and delay_minutes > 15          // window = schedule, so each train alerts once
| summarize arg_max(event_time, delay_minutes, loc_stanox, toc_id) by train_id
```

Notes
* When Activator reads directly from Eventstream it sees the **envelope** JSON produced by the bridge
  (`payload.body.timetable_variation`, `payload.body.variation_status`), not the parsed table. Add an
  Eventstream *Manage fields* / *Filter* operator (msg_type == "0003") and compute `delay_minutes` there,
  or use the Eventhouse KQL source as above (simpler, slightly higher latency).
* Throttle actions (e.g. "at most once per train per 30 minutes") so a slow train does not spam the channel.
