# Lab 10b – Live semantic model for the app map

**Time:** 25 minutes · **Previous:** [Lab 10](10-foundry-agent.md) · **Next:** [Lab 11](11-rayfin-app.md)

> **Path:** Everyone doing Lab 11. Classroom students: build your own model in your own workspace, unless your instructor
> shares one.

## Why this lab exists

The Lab 11 app needs live train positions from the Eventhouse, but Rayfin 1.36.2 can't query a KQL database directly: there's
no Kusto connector and no Kusto token for functions. It *can* query a **Power BI semantic model** through its
`fabric-semanticmodel` connector. So you publish a small semantic model in **DirectQuery** mode over `NetworkSnapshot()`.
Each DAX query the app sends is translated into KQL and run against `RailKQL` at that moment, so the map stays live.

```
Rayfin app (browser) ──DAX──► semantic model "RailLiveMap" (DirectQuery) ──KQL──► RailKQL: NetworkSnapshot(4h)
        signed-in user's identity (delegated)
```

## Objectives

* Publish a DirectQuery semantic model, `RailLiveMap`, with one table, `TrainPositions`, over `NetworkSnapshot(4h)`.
* Set its data source credentials so the model can query `RailKQL`.
* Check that the model returns live rows from a DAX query.
* Note the workspace ID and model ID for Lab 11.

## Prerequisites

* Labs 03 (coordinates in `Locations`) and 06 (`NetworkSnapshot()`) are done, and this returns rows in a KQL queryset:
  `NetworkSnapshot(1h) | take 10`.
* **Power BI Desktop** (Windows, current version). The web alternative is at the end of this lab.
* Tenant setting **Semantic Model Execute Queries REST API** is enabled (*Admin portal > Tenant settings > Integration
  settings*). The Rayfin connector sends DAX through it. It's on by default in most tenants. See Lab 01.
* App users will need **Build** permission on the model (step 5).

## Option A – Power BI Desktop

### 1. Connect in DirectQuery mode

1. Power BI Desktop → **Get data** → **KQL Database** (or *Azure Data Explorer (Kusto)*).
2. **Cluster**: the `RailKQL` **Query URI** (`KUSTO_QUERY_URI` in `.env`). **Database**: `RailKQL`.
3. **Table name or Azure Data Explorer query**: paste

   ```kusto
   NetworkSnapshot(4h)
   ```

   Four hours is the most the app asks for. The app narrows it further with a DAX filter, which DirectQuery pushes down to KQL.
4. **Data connectivity mode**: **DirectQuery** → **OK**. Sign in with your organisational account if asked.
5. In the Navigator, select the query result → **Transform data** (not *Load*).

### 2. Name the table

1. In Power Query, rename the query to **`TrainPositions`** (exactly – the app's DAX uses this name).
2. Check the column types: `lat` and `lon` **Decimal number**, `delay_minutes` **Whole number**, `event_time` **Date/Time**.
   Don't add steps that can't fold (you'll get a warning that the query can't be used in DirectQuery).
3. **Close & Apply**.

You don't need visuals. Optionally add a table visual to check the data, and turn off **Auto date/time**
(*File > Options > Current file > Data load*) to keep the model small.

### 3. Publish

1. **File** → **Save as** `RailLiveMap.pbix`.
2. **Publish** → workspace **`rail-fabric-rti`** (where `RailKQL` is). It doesn't have to be the app's workspace.

### 4. Set the data source credentials

1. In Fabric, open the workspace → the **`RailLiveMap`** semantic model → **Settings** (… → *Settings*).
2. **Data source credentials** → **Edit credentials** → **OAuth2** → privacy level **Organizational** → **Sign in**.
3. Choose who the KQL queries run as:
   * **Default:** the credentials you just entered. Every app user sees the same data (it's open data), and only you need
     access to `RailKQL`.
   * **Per user:** tick **Report viewers can only access this data source with their own Power BI identities using
     DirectQuery** (SSO). Then each app user also needs **Viewer** on `RailKQL`.

### 5. Give app users access

App queries run as the **signed-in user** (the connector is delegated-only). Each user needs **Build** on the model: on the
model → **Manage permissions** → **Add user** → tick **Allow recipients to build content** (or give them workspace
*Contributor*). For yourself, as the owner, there's nothing to do.

### 6. Note the IDs for Lab 11

Open the model. The URL is `https://app.fabric.microsoft.com/groups/<workspace-id>/datasets/<model-id>/…`. Note both, or let
Lab 11 find them with:

```bash
npx rayfin connector search "RailLiveMap" --type fabric-semanticmodel --all-workspaces --json
```

## Option B – no Desktop (web only, check the table name)

1. Open a KQL queryset on `RailKQL`, run `NetworkSnapshot(4h)`, then select **Power BI report** (*Build Power BI report*).
2. Save the report as `RailLiveMap`. Fabric creates a **DirectQuery** semantic model with the same name.
3. Open the semantic model. The web flow names the table itself (often *Kusto Query Result*). Either rename it to
   `TrainPositions` in the web modelling view (**Open data model**), or set `MODEL_TABLE` in Lab 11's `loadSnapshot.ts` to
   the name you see.
4. Then do steps 4–6 of Option A.

## Checkpoint

In the workspace, open **`RailLiveMap`** → **Explore this data** (or a new DAX query in **Open data model** → *DAX query view*) and run:

```dax
EVALUATE
TOPN(10,
  FILTER('TrainPositions', 'TrainPositions'[event_time] >= NOW() - 60 / 1440),
  'TrainPositions'[event_time], DESC)
```

You should see trains from the last hour, with `lat` and `lon`. Run it again a minute later: the newest `event_time` should move on.

## Troubleshooting

| Symptom | Fix |
|---|---|
| *This query can't be used in DirectQuery* in Power Query | Remove the extra steps you added, or rebuild with only the rename and type changes |
| Model shows **no data** or a credentials error in the service | Do step 4 (credentials). DirectQuery models have no refresh schedule; they need valid credentials |
| `NetworkSnapshot` isn't recognised | Lab 06 isn't applied, or you're on the wrong database. Run `python fabric/scripts/apply_kql.py` |
| Checkpoint returns 0 rows | No live data in the last hour, or the times are off. Try `- 240 / 1440`, and check `NetworkSnapshot(1h)` in a queryset |
| Lab 11 map says *403* or *api* error | The signed-in user lacks **Build** on the model (step 5), or (with SSO) Viewer on `RailKQL` |
| Lab 11 map says *Execute Queries … disabled* | Enable the *Semantic Model Execute Queries REST API* tenant setting |
