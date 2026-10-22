# Lab 07 – Activator alerts

**Time:** 30 minutes · **Previous:** [Lab 06](06-kql-transformations.md) · **Next:** [Lab 08](08-dashboard-powerbi.md)

> **Path:** Everyone.

## Objectives

Create **Fabric Activator** rules that notify you when:

1. a train is **more than 15 minutes late**
2. **cancellations spike** compared with the recent baseline
3. the **feed stalls** (no events for 10 minutes)
4. *(optional)* national PPM turns amber or red

The rule specifications are in [`fabric/activator/rules.md`](../../fabric/activator/rules.md).

## Option A – automated

Not available. Activator rules are created in the portal. They can't be scripted reliably from this repo.

## Option B – manual

### How alerts from a KQL queryset work

When you create an alert from a **KQL queryset** with a plain table result (no `render`), Activator runs the query on a schedule
and sends **one alert for every row the query returns**. The condition box offers **On each event** (optionally *when* a
field meets a test). There's no **grouped by** option for a plain table – that only appears for queries that render a chart
with a dimension. So the pattern in this lab is: **put the condition in the query**, make it return a row only when you want
an alert, and choose **On each event**.

Two habits avoid duplicate or missed alerts:

* **Match the time window to the schedule.** If the rule runs every 5 minutes, look back 5 minutes (`ago(5m)`). A 10-minute
  window would alert on the same train twice.
* **Return nothing when all is well.** No rows = no alert.

Each rule runs a query every few minutes and keeps the Eventhouse active (see [capacity planning](../capacity-planning.md)).
On an F2, start with Rule 1 and Rule 3 only.

### Rule 1 – Train more than 15 minutes late

1. Open a **KQL Queryset** on `RailKQL` and run:
   ```kusto
   TrustMovements
   | where received_utc > ago(5m) and delay_minutes > 15
   | summarize arg_max(event_time, delay_minutes, loc_stanox, toc_id) by train_id
   | lookup kind=leftouter (LocationByStanox() | project loc_stanox = stanox, location_name) on loc_stanox
   | project train_id, delay_minutes, location_name, loc_stanox, toc_id, event_time
   ```
   It returns one row per late train (and nothing if none are late).
2. Select **Set alert** on the top ribbon. In the **Add rule** pane:
   * **Details:** name `Train more than 15 min late`.
   * **Monitor:** every **5 minutes**.
   * **Condition:** **On each event**. (The query already filters to late trains. If you're offered *when*, you can also set
     `delay_minutes` **is greater than** `15` – it gives the same result.)
   * **Occurrence:** every time.
   * **Action:** **Send email** or **Teams → Message to individuals**. Headline: `Train @train_id is @delay_minutes min late`;
     Notes: `At @location_name (@loc_stanox), operator @toc_id`. Type `@` to pick the columns.
   * **Save location:** your workspace → **new Activator** called `RailAlerts` (later rules: the **existing** `RailAlerts`).
3. **Create**. The rule appears in the **Rules** pane of the queryset; make sure its toggle is **on**.

> On a busy day this can send a lot of messages. To get **one summary per run** instead of one per train, end the query with
> `| summarize late_trains = count(), worst = max(delay_minutes), trains = make_list(train_id, 20)` and add
> `| where late_trains > 0`.

### Rule 1 (alternative) – straight from Eventstream (lowest latency)

1. In **RailEventstreamRdm**, add a **Filter** operator (`header.msg_type == "0003"`), then **Add destination → Activator** → `RailAlerts`.
2. In Activator, create an **object** keyed by `body.train_id`, with a property using `body.timetable_variation`.
   Add a filter where `body.variation_status == "LATE"`, and a rule **becomes greater than 15**.
   (Use `payload.body.…` instead if the source is the NROD bridge's `RailEventstreamNrod`.)

This route supports per-train grouping and "at most once per …" limits, because Activator tracks each `train_id` as an object.

### Rule 2 – Cancellation spike

Query (returns a row only when there's a spike):
```kusto
CancellationSpike(15m, 6h)
| where ratio >= 2 and recent_cancellations >= 10
```
**Set alert** → every **5 minutes** → **On each event** → Teams **Channel post** (or email). Headline:
`Cancellation spike: @recent_cancellations in 15 min (@ratio× normal)`. Save to the existing `RailAlerts`.

### Rule 3 – Feed stalled

Query (returns a row only when nothing has arrived for 10 minutes):
```kusto
RdmTrustRaw
| where ingestion_time() > ago(10m)
| count
| where Count == 0
```
**Set alert** → every **5 minutes** → **On each event** → **Send email**: `No Train Movements data for 10 minutes – check the
Lab 04 Eventstream source`. If you run the NROD bridge (Lab 05), add a second rule with `RawFeed` in place of `RdmTrustRaw`.

### Rule 4 – National PPM amber or red (needs RTPPM from Lab 05a/05b)

Query:
```kusto
RtppmNational
| top 1 by snapshot_time desc
| where rag in ("A", "R")
```
**Set alert** → every **15 minutes** → **On each event** → Teams message: `National PPM is @ppm% (@rag)`.
This alerts on every run while PPM stays amber or red; use a 30–60 minute schedule if that's too often.
Skip this rule until the bridge is bringing in RTPPM.

## Checkpoint

* `RailAlerts` shows the rules as **Running**.
* Use **Test action** to confirm Teams and email delivery.
* To test end to end, temporarily lower the threshold to 1 minute.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No **grouped by** option under **Condition** | Expected for a table result from a KQL queryset. Filter in the query and use **On each event** (see "How alerts from a KQL queryset work"). Grouping is available on rendered charts with a dimension, and per-object in Activator via the Eventstream route |
| The same train alerts twice | The query window is longer than the schedule. Use `ago(5m)` with a 5-minute schedule |
| Rule 3 never fires / fires constantly | Check the query ends with `\| where Count == 0`. Without it, it returns a row (and alerts) on every run |
| Too many alerts | Add a cooldown ("at most once every 30 minutes per train") or raise the threshold |
| No alerts | Check the query returns rows for the window. Check the rule is started |
| Teams action fails | Check that the Teams app for Activator is allowed in your tenant |
