# Rail ontology – definition to build (Lab 2.5)

Everything to paste or enter when you build the `RailNetworkOntology` item: entity types, keys, properties,
relationships, business rules, the ontology agent prompt and the data agent instructions.

Run [`fabric/kql/09_ontology_tables.kql`](../kql/09_ontology_tables.kql) first. It creates the `Ont*` tables used below.

> **Property names must be unique across all entity types.** That's why every property has an entity prefix
> (`station_`, `point_`, `train_`, `operator_`). Keep the names below when you bind data.

## Entity types

### Station

*A passenger station, identified by its three-letter CRS code (for example LDS = Leeds). One station can have several
timing points (STANOX codes).*

| Property | Source column (`RailKQL.OntStations`) | Type | Key |
|---|---|---|---|
| `station_crs` | `station_crs` | string | ✅ |
| `station_name` | `station_name` | string | |
| `station_lat` | `station_lat` | double | |
| `station_lon` | `station_lon` | double | |
| `station_timing_points` | `station_timing_points` | integer | |

### TimingPoint

*A place on the network where TRUST reports train movements, identified by its STANOX code. Stations, junctions and
sidings are all timing points. `point_crs` links a timing point to its station; it's blank for non-station points.*

| Property | Source column (`RailKQL.OntTimingPoints`) | Type | Key |
|---|---|---|---|
| `point_stanox` | `point_stanox` | string | ✅ |
| `point_name` | `point_name` | string | |
| `point_tiploc` | `point_tiploc` | string | |
| `point_crs` | `point_crs` | string | |
| `point_lat` | `point_lat` | double | |
| `point_lon` | `point_lon` | double | |

### Operator

*A train operating company, identified by its TRUST operator code (`toc_id`).*

| Property | Source column (`RailKQL.OntOperators`) | Type | Key |
|---|---|---|---|
| `operator_id` | `operator_id` | string | ✅ |
| `operator_name` | `operator_name` | string | |

### Train

*A train running today, identified by its 10-character TRUST train ID. Its properties are its LATEST report, kept live by
the `TrainLatest` materialized view.*

Bind to the materialized view **`RailKQL.TrainLatest`** and **rename** the columns as below. Leave the other columns out.

| Property | Source column (`TrainLatest`) | Type | Key |
|---|---|---|---|
| `train_id` | `train_id` | string | ✅ |
| `train_operator_id` | `toc_id` | string | |
| `train_last_stanox` | `loc_stanox` | string | |
| `train_last_event_time` | `event_time` | datetime | |
| `train_last_event_type` | `event_type` | string | |
| `train_delay_minutes` | `delay_minutes` | integer | |
| `train_variation_status` | `variation_status` | string | |
| `train_terminated` | `train_terminated` | boolean | |

**Movement history as a time series (recommended).** The bindings above only give each train's *latest* report. To
answer "busiest station in the last 30 minutes" or "how did delays change this morning", the ontology also needs the
history. If the binding page offers a **time series** binding, add a second binding on Train from
**`RailKQL.TrustMovements`**: key column `train_id`, timestamp `event_time`, and these properties:
`movement_stanox` ← `loc_stanox`, `movement_event_type` ← `event_type`, `movement_delay_minutes` ← `delay_minutes`.

If your ontology doesn't offer a time series binding, skip it and, in step 6 of the lab, also add `RailKQL` as a second
data source on the ontology data agent, so history questions still work.

## Relationship types

Names must be unique. No mapping table: each one links a column on one entity to a column on the other.

| Relationship | Origin → target | Origin property | Target property |
|---|---|---|---|
| `has_timing_point` | Station → TimingPoint | `station_crs` | `point_crs` |
| `is_run_by` | Train → Operator | `train_operator_id` | `operator_id` |
| `last_reported_at` | Train → TimingPoint | `train_last_stanox` | `point_stanox` |

## Business rules

On the ontology: **Explorer → Overview → Rules → + Create rule** (or **New rule**). Enter the name and definition, then
link the concepts listed.

| Rule name | Rule definition | Link to |
|---|---|---|
| Late train | A train is late when `train_delay_minutes` is more than 0, and significantly late when it is 15 or more. Early trains have a negative or zero delay. | Train, `train_delay_minutes` |
| Active train | A train is active when its latest report (`train_last_event_time`) is within the last 2 hours and `train_terminated` is not true. Questions about trains "now" or "currently" mean active trains. | Train |
| Station or timing point | A station can have several timing points. To count or list movements at a station, include every timing point linked to it through `has_timing_point`, and name the station, not the timing point. | Station, TimingPoint, `has_timing_point` |
| Headcode | The headcode people use (for example 1A21) is characters 3 to 6 of `train_id`. Show the headcode in answers, with the train ID if needed. | Train, `train_id` |
| London area | "In London" means stations with `station_lat` between 51.28 and 51.70 and `station_lon` between -0.51 and 0.33 (Greater London). For another town or city use about ±0.1° around its main station. Say which area you used. | Station |
| Busiest station | "Busiest" means the most train movements (arrivals and departures) at a station in the time window asked, counted across all of its timing points. | Station, TimingPoint |
| Data source | The data is near-real-time open data from Network Rail (TRUST). It isn't official, can be incomplete, and has no train destination. Say so when asked for authoritative figures or destinations. | Train |

## Ontology agent prompt (Option A)

Paste this into the ontology agent in **Plan** mode:

```text
Build an ontology for live Great Britain train running from the RailKQL KQL database in this workspace.
Use only these sources: OntStations, OntTimingPoints, OntOperators and the TrainLatest materialized view.
Create four entity types:
- Station, key station_crs, bound to OntStations (all columns).
- TimingPoint, key point_stanox, bound to OntTimingPoints (all columns).
- Operator, key operator_id, bound to OntOperators (all columns).
- Train, key train_id, bound to TrainLatest, with only these properties renamed:
  train_id, train_operator_id (toc_id), train_last_stanox (loc_stanox), train_last_event_time (event_time),
  train_last_event_type (event_type), train_delay_minutes (delay_minutes), train_variation_status (variation_status),
  train_terminated (train_terminated).
If time series bindings are supported, also bind TrustMovements to Train as a time series: key train_id, timestamp
event_time, properties movement_stanox (loc_stanox), movement_event_type (event_type), movement_delay_minutes (delay_minutes).
Create three relationship types without mapping tables:
- has_timing_point: Station.station_crs -> TimingPoint.point_crs
- is_run_by: Train.train_operator_id -> Operator.operator_id
- last_reported_at: Train.train_last_stanox -> TimingPoint.point_stanox
Give each entity type a one-sentence business description. Don't add other sources or entity types.
```

## Data agent instructions (`Rail Network Analyst (ontology)`)

Paste into **Agent instructions**:

```text
You are a rail operations analyst for Great Britain's mainline railway. Answer questions about live and recent train
running using the RailNetworkOntology ontology. Use its entity types, relationships and business rules: the Late train,
Active train, Station or timing point, Headcode, London area and Busiest station rules define the terms people use.
Always state the time window and area you used, and use UK time. Keep answers short: one sentence, then a small table
(maximum 10 rows). The data is near-real-time open data and not official.
Support group by in GQL.
```

The last line works around a known aggregation issue in the preview ("Support group by in GQL" – from the Microsoft
documentation for data agents grounded in an ontology).
