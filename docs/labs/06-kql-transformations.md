# Lab 06 – KQL transformations: tables, update policies, materialized views and functions

**Time:** 40 minutes · **Previous:** [Lab 05b](05b-bridge-azure-container-apps.md) · **Next:** [Lab 07](07-activator-alerts.md)

> **Run this lab's scripts before any data arrives**, ideally straight after Lab 02. Labs 03–05 need the tables and mappings it creates.
> It's numbered 06 because it's easier to understand once you've seen the raw messages.

## Objectives

* Create the raw landing tables and JSON ingestion mappings.
* Parse batched TRUST JSON into typed tables by `msg_type`, using **update policies**.
* Keep the latest state for each train and the delay and cancellation summaries in **materialized views**.
* Publish reusable **functions** for the dashboards, the data agent and the app.

## Data model

```
RawFeed (bridge envelope) ──┐                       ┌─► TrustMovements (0003) ─► TrainLatest, DelaysBy15Min, DailyTocPerformance
                            ├─ ExpandTrust*() ──────┼─► TrustActivations (0001)
RdmTrustRaw (Kafka raw) ────┘   (mv-expand batches) ├─► TrustCancellations (0002) ─► CancellationsBy15Min
                                                    └─► TrustOtherEvents (0004–0008)
RawFeed ─► ParseTd() ─► TdEvents          RawFeed ─► ParseRtppm() ─► RtppmNational
Locations, TocCodes (reference)  ─► LocationByStanox(), MovementsEnriched(), LateTrains(), NetworkSnapshot(), StationBoard(), CancellationSpike()
```

| Script | Contents |
|---|---|
| `fabric/kql/01_tables.kql` | Tables, `RawFeedMapping` and `RdmTrustRawMapping`, and retention (raw 7 days, movements 365 days) |
| `fabric/kql/02_update_policies.kql` | Parsing functions and update policies (TRUST from both sources; `UnwrapRdm()` for the RDM envelope; Darwin Push Port → `DarwinLocations`) |
| `fabric/kql/03_materialized_views.kql` | `TrainLatest`, `DelaysBy15Min`, `CancellationsBy15Min`, `DailyTocPerformance` |
| `fabric/kql/04_query_functions.kql` | Query functions |
| `fabric/kql/06_sample_queries.kql` | Sample queries for exploring the data |
| `fabric/kql/07_toc_codes_seed.kql` | Template for filling `TocCodes` (TODO: fill it from the wiki) |

Each schema script is a single `.execute database script` command, so it either runs completely or stops at the first error (`ContinueOnErrors=false`).

> If you followed Lab 02, `01_tables.kql` and `02_update_policies.kql` have already run. Re-running them is safe
> (they use `create-merge` / `create-or-alter`), so you can still run everything below.

## Option A – automated

```bash
pip install -r fabric/scripts/requirements.txt
az login
python fabric/scripts/apply_kql.py            # applies 01–04 to $KUSTO_QUERY_URI / $FABRIC_KQL_DATABASE_NAME
python fabric/scripts/apply_kql.py --dry-run  # show what would run
```

The script authenticates with the Azure CLI through `azure-kusto-data` and runs each file as a management command.

## Option B – manual

1. Open **RailKQL** → **Explore your data**, or create a **KQL Queryset** attached to `RailKQL`.
2. Paste the **whole** of `01_tables.kql`, select all (**Ctrl+A**), then **Run**. The script must run as one selection, because commands inside it are separated by blank lines.
3. Repeat for `02_update_policies.kql`, `03_materialized_views.kql` and `04_query_functions.kql`, in that order.
4. Optionally, fill in and run `07_toc_codes_seed.kql`.
5. If raw data arrived before the update policies existed, run `08_backfill.kql` **once** (see Lab 04).

### Key ideas

* **Update policies** run a query over each newly ingested batch of the source table and append the result to the target table. Our query
  `ParseMovements(ExpandTrustNrod())` expands arrays with `mv-expand`, filters `header.msg_type == "0003"` and projects typed columns.
* `delay_minutes` is derived from `variation_status` and `timetable_variation`: LATE → `+n`, EARLY → `−n`, ON TIME → 0.
* **Materialized views** (`arg_max(event_time, *) by train_id`) give a cheap "current state" lookup that's always up to date.
* Timestamps are epoch milliseconds, converted by `EpochMs()`. Check the wiki for local time and UTC behaviour around BST changes.

## Checkpoint

```kusto
.show tables
.show table TrustMovements policy update
.show materialized-views | project Name, IsHealthy, IsEnabled
RawFeed | summarize count() by feed
TrustMovements | summarize count(), max(event_time) by source
LateTrains(15, 2h) | take 10
```

Then work through `fabric/kql/06_sample_queries.kql`.

To test without live data, use the bridge replay mode with the eventstream sink:
`python -m rail_bridge --source replay --replay-file tests/fixtures/replay_frames.json --sink eventstream`.
The sample messages carry fixed timestamps from October 2025, so widen the `ago()` windows (for example `ago(400d)`) when you query them.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Query schema does not match table schema` when you alter a policy | The function output columns or types differ from the target table. Compare `getschema` for both |
| Rows in `RawFeed`, none in typed tables | `.show ingestion failures`. Check that `feed == "trust"` and that `payload.header.msg_type` exists |
| Materialized view unhealthy | `.show materialized-view TrainLatest failures` |
| Script fails at the first command | Make sure you selected the **whole** file before you pressed Run |
