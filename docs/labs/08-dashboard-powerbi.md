# Lab 08 – Real-Time Dashboard and Power BI report

**Time:** 45 minutes · **Previous:** [Lab 07](07-activator-alerts.md) · **Next:** [Lab 09](09-fabric-data-agent.md)

## Objectives

* Build a **Real-Time Dashboard** with tiles that refresh automatically.
* Build a **Power BI** report: **DirectQuery** to the KQL database for live pages (with automatic page refresh), and **Direct Lake** over the Lakehouse for history.

## Option A – automated

The tile queries are supplied in [`fabric/dashboard/queries.kql`](../../fabric/dashboard/queries.kql). You add the tiles by hand.
This repo doesn't generate the dashboard JSON definition.

## Option B – manual

### Real-Time Dashboard

1. Workspace → **+ New item** → **Real-Time Dashboard** → `Rail Network Live`.
2. **+ Add data source** → OneLake data hub → `RailKQL`.
3. For each query in `queries.kql`: **+ Add tile** → paste the query → **Run** → choose the suggested visual → **Apply changes**.
4. **Manage → Auto refresh**: enable it with a minimum interval of 30 seconds.
5. Map tile: choose the **Map** visual, with latitude `lat`, longitude `lon`, and size or colour `delay_minutes`.
6. Add a text tile with the attribution: *"Contains data from Network Rail Open Data / Rail Data Marketplace. Not an official service."*

### Power BI – live page (DirectQuery)

1. In Power BI Desktop: **Get data** → **KQL Database** (or *Azure Data Explorer (Kusto)*) → paste the `RailKQL` **Query URI**, database `RailKQL`.
2. Choose **DirectQuery**. Select the materialized views `TrainLatest` and `DelaysBy15Min`, or use the functions as queries,
   for example `LateTrains(15, 2h)`.
3. Visuals: card (count of late trains), table (worst trains), line chart (`avg_delay` by `window_start`, legend `toc_id`).
4. Page format → **Page refresh** → **Auto page refresh**, every 30 seconds. Your capacity admin sets the minimum interval.
5. Publish to the `rail-fabric-rti` workspace.

### Power BI – history (Direct Lake)

1. Turn on **OneLake availability** for `TrustMovements` (KQL database → table → *OneLake availability*), so the Eventhouse
   table is exposed as Delta, then add a shortcut to it in `RailLakehouse`. Alternatively, copy history to the Lakehouse with a pipeline.
2. In the Lakehouse, **New semantic model** → select `TrustMovements` (shortcut), `locations` and `smart_berths`. Call it `Rail Performance`.
3. Add relationships (`TrustMovements[loc_stanox]` → `locations[stanox]`) and measures, for example:
   ```DAX
   Movements = COUNTROWS(TrustMovements)
   Late 15+ = CALCULATE([Movements], TrustMovements[delay_minutes] >= 15)
   % On time = DIVIDE(CALCULATE([Movements], TrustMovements[variation_status] = "ON TIME"), [Movements])
   ```
4. Build a history report (daily trend, TOC league table) on this Direct Lake model.

## Checkpoint

* The dashboard tiles refresh, and the map shows dots across GB.
* The Power BI live page refreshes every 30 seconds. The history page loads quickly from Direct Lake.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Map empty | `Locations` has no coordinates (Lab 03 NaPTAN step), or there are no recent movements |
| Auto page refresh greyed out | Only DirectQuery sources support it. Check the capacity admin's minimum interval |
| Slow tiles | Query materialized views rather than the raw tables. Narrow the time windows |
