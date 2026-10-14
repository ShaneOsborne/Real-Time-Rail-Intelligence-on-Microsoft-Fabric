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

**Which visuals to use.** Stick to visuals that are generally available for the core tiles, and try the preview ones as extras:

| Need | Use | Avoid / optional |
|---|---|---|
| One headline number | **KPI** (supports thresholds that change the tile's state/colour) | **Stat** – shown as *legacy* in the visual picker |
| Several headline numbers in one tile | **Multiple KPI** / **Multi stat** (label + value columns) – or simply several KPI tiles | – |
| Trend over time | **Time chart** | **Time series chart (preview)** – optional, good for comparing operators (see below) |
| Locations | **Map** | **Fabric map (preview)** – optional |
| Detail | **Table** | – |

Steps:

1. Workspace → **+ New item** → **Real-Time Dashboard** → `Rail Network Live`.
2. **+ Add data source** → OneLake catalog → **`RailKQL`** (not the default database named after the Eventhouse).
3. For each tile in [`fabric/dashboard/queries.kql`](../../fabric/dashboard/queries.kql): **+ Add tile** → paste the query → **Run**
   → **+ Add visual** → choose the visual below → **Apply changes**.

| # | Tile | Visual | Settings |
|---|---|---|---|
| 1 | Events per minute by feed | Time chart | X = `t`, Y = `events`, series = `feed` |
| 2 | Trains 15+ min late | **KPI** | Type **Number**. Value = `late_trains`. Turn **off** *Show a unit label* (it defaults to %). Conditional formatting: green below 20, amber 20–50, red above 50 (suggested – adjust to your data) |
| 3 | Cancellations in the last hour | **KPI** | Type **Number**. Value = `cancellations`. Turn **off** *Show a unit label* |
| 4 | Movements reported on time (%) | **KPI** | Type **Gauge**, range 0–100. Value = `on_time_pct`. Leave *Show a unit label* **on** – the % is correct here. Higher is better (green 90+, amber 80–90, red below 80 – suggested) |
| 5 | National PPM *(only with RTPPM from Lab 05)* | **KPI** | Type **Gauge**, range 0–100. Value = `ppm`. Leave the % unit label on |
| 6 | *Alternative to 2–4:* Network now | **Multiple KPI** / **Multi stat** | Label = `metric`, Value = `value`. Turn off any unit label (the values are mixed counts and a percentage) |
| 7 | Most delayed trains | Table | – |
| 8 | Average delay by operator | Time chart | X = `window_start`, Y = `avg_delay`, series = `toc_id` |
| 9 | Network map | **Map** | Define location by **Latitude and longitude**: Latitude = `lat`, Longitude = `lon`; Label = `train_id`; Size = `delay_minutes` |
| 10 | Cancellations by reason (24h) | Bar chart | – |
| 11 | Ingestion lag | Time chart | Y = `p50`, `p95` |

4. **Manage → Auto refresh**: turn it on, minimum interval **1 minute** (30 seconds is possible, but on an F2 every refresh
   runs every tile's query – see [capacity planning](../capacity-planning.md)).
5. Add the attribution as a **text (markdown) box**, not a query tile:
   * On the **Home** tab, use the option to add a **text / markdown box** – the one that has no query.
   * **Don't** use **+ New tile** and pick the **Markdown** *visual type*. That's a query tile that renders markdown returned by
     a KQL query, so it expects a query and won't show typed text.
   * **Title:** `About this data`
   * **Body** (type into the text box, not the title):

     ```markdown
     *Contains data from Network Rail Open Data / Rail Data Marketplace. Not an official service.*
     ```

   * Resize it to a slim strip along the bottom of the dashboard → **Apply changes**.
6. **Save**.

> **KPI type:** use **Number** for counts (late trains, cancellations) – they have no natural maximum, so a gauge, bar or donut
> would need an arbitrary scale and can mislead. Use **Gauge** for percentages (on time %, PPM), which always run 0–100;
> **Bar** or **Donut** work too if you prefer. If the type settings are named differently in your release, pick the closest match.
>
> **KPI unit label:** a new KPI tile shows a **%** unit label by default (*Show a unit label*). Turn it off for counts
> (tiles 2 and 3), otherwise `42` trains appears as `42%`.
>
> The exact names in the visual picker (for example *Multiple KPI* or *Multi stat*) and the KPI threshold settings can vary
> between Fabric releases. If a name differs, pick the closest match. Tile 1 uses `union isfuzzy=true`, so it works even if you
> haven't used the bridge (`RawFeed`) or Darwin (`RdmDarwinRaw`) yet.

#### Optional: preview visuals

These are **preview** features – they may change, and they aren't needed for the rest of the labs.

* **Time series chart (preview)** – duplicate tile 8 and change its visual to *Time series chart*: **Time column** = `window_start`,
  **Measured data** = `avg_delay`, **Entities** = `toc_id`. It shows each operator as its own series with a shared, synchronised
  time slider, which makes it easy to pick out one operator's bad hour.
* **Fabric map (preview)** – an alternative to the Map visual with richer basemaps and data-driven styling. Use the tile 9 query
  (`lat`, `lon`, colour or size by `delay_minutes`). Keep the standard **Map** tile as well, as the reference version.

### Darwin tiles (if you did Lab 04b)

*Optional.* Only if `DarwinLocations` is filling ([Lab 04b](04b-darwin-push-port.md)). The queries are at the end of `queries.kql`:

| Tile | Query | Visual |
|---|---|---|
| Unconfirmed platforms at a station | `DarwinUnconfirmedPlatforms("LDS", 2h)` (change the CRS code, or use a dashboard parameter) | Table |
| Biggest predicted delays (Darwin) | `DarwinBiggestDelays(1h, 20)` | Table (or Map with `lat` / `lon`) |

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

* The dashboard tiles refresh, the KPI tiles show values (not *No data*), and the map shows dots across GB.
* The Power BI live page refreshes every 30 seconds. The history page loads quickly from Direct Lake.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Map empty | `Locations` has no coordinates (Lab 03 NaPTAN step), or there are no recent movements |
| Only **Stat** is suggested for a single number | Change the visual type to **KPI** – Stat is legacy |
| Map points spread across the world | The location columns weren't set. In the Map settings choose **Latitude and longitude** and set Latitude = `lat`, Longitude = `lon` explicitly |
| A KPI count shows a % sign (for example `42%` late trains) | The KPI's *Show a unit label* is on by default. Edit the tile → turn off **Show a unit label** |
| KPI shows *No data* | The query returned no rows in the window (for example no cancellations in the last hour). Widen the window or check the source table |
| The attribution tile asks for a query, or shows nothing | You added a query tile with the **Markdown** visual type. Delete it and add a **text / markdown box** from the Home tab instead (step 5) |
| Tile 5 (PPM) fails or is empty | `RtppmNational` only fills when the Lab 05 bridge brings in RTPPM. Remove the tile until then |
| Auto page refresh greyed out | Only DirectQuery sources support it. Check the capacity admin's minimum interval |
| Slow tiles | Query materialized views rather than the raw tables. Narrow the time windows |
