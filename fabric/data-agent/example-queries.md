# Data agent example queries (Lab 09)

Copy each **question** into the *Question* box and each **query** block into the *Query* box of the data agent's
**Example queries** on the `RailKQL` data source. The queries are multi-line and paste as-is (`example-queries.json` holds
the same pairs for scripts and the SDK).

The queries use **only tables and materialized views** (no custom functions), so they pass the data agent's schema
validation as long as the tables in Lab 09 step 2 are selected. Add the *(Optional – Darwin, Lab 04b)* pairs only if
`DarwinLocations` is selected.

## 1. Which trains are more than 15 minutes late right now?

**Question**

```text
Which trains are more than 15 minutes late right now?
```

**Query**

```kusto
// Latest report per train (TrainLatest), 15+ minutes late, still running, in the last 2 hours.
TrainLatest
| where event_time > ago(2h) and delay_minutes >= 15 and coalesce(train_terminated, false) == false
| join kind=leftouter (Locations | where isnotempty(stanox) | summarize location_name = take_any(name) by stanox) on $left.loc_stanox == $right.stanox
| extend headcode = substring(train_id, 2, 4)
| project event_time, headcode, train_id, toc_id, delay_minutes, location_name, event_type
| order by delay_minutes desc
| take 10
```

## 2. How many trains were cancelled in the last hour, by reason code?

**Question**

```text
How many trains were cancelled in the last hour, by reason code?
```

**Query**

```kusto
TrustCancellations
| where canx_time > ago(1h)
| summarize cancellations = count() by canx_reason_code
| order by cancellations desc
```

## 3. What is the average delay by operator over the last 3 hours?

**Question**

```text
What is the average delay by operator over the last 3 hours?
```

**Query**

```kusto
DelaysBy15Min
| where window_start > ago(3h)
| summarize movements = sum(movements), avg_delay = round(avg(avg_delay), 1) by toc_id
| join kind=leftouter TocCodes on toc_id
| project toc_id, toc_name, movements, avg_delay
| order by avg_delay desc
```

## 4. Show the latest departures and arrivals at Leeds

**Question**

```text
Show the latest departures and arrivals at Leeds
```

**Query**

```kusto
// Station board for Leeds (CRS LDS) - change the CRS code for another station.
// TRUST has no destination field. Origin comes from the train's activation, so it can be blank.
let station_stanox = Locations | where crs =~ "LDS" and isnotempty(stanox) | distinct stanox;
let station_name = toscalar(Locations | where crs =~ "LDS" | take 1 | project name);
let origins = TrustActivations
    | summarize arg_max(creation_time, sched_origin_stanox) by train_id
    | join kind=leftouter (Locations | where isnotempty(stanox) | summarize origin = take_any(name) by stanox) on $left.sched_origin_stanox == $right.stanox
    | project train_id, origin;
TrustMovements
| where event_time > ago(1h) and loc_stanox in (station_stanox)
| lookup kind=leftouter origins on train_id
| extend station = station_name, headcode = substring(train_id, 2, 4)
| project event_time, station, event_type, headcode, origin, toc_id, platform, variation_status, delay_minutes, planned_time
| order by event_time desc
| take 20
```

## 5. Which locations had the most trains 15+ minutes late today?

**Question**

```text
Which locations had the most trains 15+ minutes late today?
```

**Query**

```kusto
TrustMovements
| where event_time > startofday(now()) and delay_minutes >= 15
| summarize late_trains = dcount(train_id) by loc_stanox
| join kind=leftouter (Locations | where isnotempty(stanox) | summarize location_name = take_any(name), crs = take_any(crs) by stanox) on $left.loc_stanox == $right.stanox
| top 10 by late_trains desc
| project location_name, crs, late_trains
```

## 6. Is there a spike in cancellations at the moment?

**Question**

```text
Is there a spike in cancellations at the moment?
```

**Query**

```kusto
// Cancellations in the last 15 minutes compared with the rate over the previous 6 hours.
let recent = toscalar(TrustCancellations | where canx_time > ago(15m) | count);
let base = toscalar(TrustCancellations | where canx_time between (ago(6h) .. ago(15m)) | count);
let expected = todouble(base) * 15.0 / 345.0;
print recent_cancellations = recent, expected_cancellations = round(expected, 1), ratio = iff(expected == 0, real(null), round(recent / expected, 2))
```

## 7. What percentage of movements were on time yesterday per operator?

**Question**

```text
What percentage of movements were on time yesterday per operator?
```

**Query**

```kusto
DailyTocPerformance
| where day == startofday(ago(1d))
| extend on_time_pct = round(100.0 * on_time / movements, 1)
| join kind=leftouter TocCodes on toc_id
| project toc_id, toc_name, movements, on_time_pct
| order by on_time_pct asc
```

## 8. Where is train 1A21 now?

**Question**

```text
Where is train 1A21 now?
```

**Query**

```kusto
// The 4-character headcode (e.g. 1A21) is characters 3-6 of the 10-character TRUST train_id.
TrainLatest
| where substring(train_id, 2, 4) =~ "1A21"
| join kind=leftouter (Locations | where isnotempty(stanox) | summarize location_name = take_any(name) by stanox) on $left.loc_stanox == $right.stanox
| project event_time, train_id, event_type, location_name, variation_status, delay_minutes
| order by event_time desc
```

## 9. (Optional – Darwin, Lab 04b) Which services at Leeds don't have a confirmed platform yet?

**Question**

```text
Which services at Leeds don't have a confirmed platform yet?
```

**Query**

```kusto
// Darwin: latest state per service (rid) and location; Leeds = CRS LDS (join on TIPLOC).
let leeds = Locations | where crs =~ "LDS" and isnotempty(tiploc) | distinct tiploc;
DarwinLocations
| where received_utc > ago(2h) and tiploc in (leeds)
| summarize arg_max(received_utc, *) by rid, tiploc
| where isnotempty(platform) and coalesce(platform_confirmed, false) == false
| project ssd, ptd, pta, rid, platform, platform_source, dep_delay_minutes
| order by ssd asc, ptd asc
| take 10
```

## 10. (Optional – Darwin, Lab 04b) Which trains have the biggest predicted delays right now?

**Question**

```text
Which trains have the biggest predicted delays right now?
```

**Query**

```kusto
DarwinLocations
| where received_utc > ago(1h)
| summarize arg_max(received_utc, *) by rid, tiploc
| extend delay_minutes = max_of(coalesce(arr_delay_minutes, -1440), coalesce(dep_delay_minutes, -1440))
| where delay_minutes > 0
| join kind=leftouter (Locations | where isnotempty(tiploc) | summarize name = take_any(name), crs = take_any(crs) by tiploc) on tiploc
| top 10 by delay_minutes desc
| project name, crs, rid, pta, ptd, arr_et, dep_et, delay_minutes, platform
```

## 11. (Optional – Darwin, Lab 04b) What is the expected departure time and platform of trains at York?

**Question**

```text
What is the expected departure time and platform of trains at York?
```

**Query**

```kusto
let york = Locations | where crs =~ "YRK" and isnotempty(tiploc) | distinct tiploc;
DarwinLocations
| where received_utc > ago(2h) and tiploc in (york) and isnotempty(ptd)
| summarize arg_max(received_utc, *) by rid, tiploc
| project ssd, ptd, dep_et, dep_at, platform, platform_confirmed, dep_delay_minutes, rid
| order by ssd asc, ptd asc
| take 10
```
