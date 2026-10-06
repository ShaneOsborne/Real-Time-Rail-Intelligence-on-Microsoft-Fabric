# Lab 07 – Activator alerts

**Time:** 30 minutes · **Previous:** [Lab 06](06-kql-transformations.md) · **Next:** [Lab 08](08-dashboard-powerbi.md)

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

### Rule 1 – Train > 15 minutes late (from Eventhouse)

1. Open a **KQL Queryset** on `RailKQL` and run:
   ```kusto
   TrustMovements
   | where received_utc > ago(10m) and delay_minutes > 15
   | summarize arg_max(event_time, delay_minutes, loc_stanox, toc_id) by train_id
   ```
2. Select **Set alert** (or, from a Real-Time Dashboard tile in Lab 08, **⋯ → Set alert**).
3. Choose **Run query every 5 minutes**. Condition: **On each event grouped by `train_id`** when `delay_minutes` **is greater than** 15.
4. Action: **Message me in Teams** or **Email**, with a message such as `Train {train_id} is {delay_minutes} min late at {loc_stanox}`.
5. Save it to a new Activator item called `RailAlerts`, then **Start** the rule.

### Rule 1 (alternative) – straight from Eventstream (lowest latency)

1. In **RailEventstreamNrod**, add a **Filter** operator (`msg_type == "0003"`), then **Add destination → Activator** → `RailAlerts`.
2. In Activator, create an **object** keyed by `payload.body.train_id`, with a property using `payload.body.timetable_variation`.
   Add a filter where `payload.body.variation_status == "LATE"`, and a rule **becomes greater than 15**.

### Rule 2 – Cancellation spike

Query `CancellationSpike(15m, 6h)` every 5 minutes. Condition: `ratio >= 2` **and** `recent_cancellations >= 10` → Teams channel post.

### Rule 3 – Feed stalled

Query `RawFeed | where received_utc > ago(10m) | count` every 5 minutes. Condition: `Count == 0` → email.

### Rule 4 – PPM (optional, RTPPM)

Query `RtppmNational | top 1 by snapshot_time desc`. Condition: `rag` changes to `A` or `R`.

## Checkpoint

* `RailAlerts` shows the rules as **Running**.
* Use **Test action** to confirm Teams and email delivery.
* To test end to end, temporarily lower the threshold to 1 minute.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Too many alerts | Add a cooldown ("at most once every 30 minutes per train") or raise the threshold |
| No alerts | Check the query returns rows for the window. Check the rule is started |
| Teams action fails | Check that the Teams app for Activator is allowed in your tenant |
