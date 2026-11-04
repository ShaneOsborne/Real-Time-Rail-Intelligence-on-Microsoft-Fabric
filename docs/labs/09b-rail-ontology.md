# Lab 09b – Rail ontology with Fabric IQ (optional)

**Time:** 50 minutes · **Previous:** [Lab 09](09-fabric-data-agent.md) · **Next:** [Lab 10](10-foundry-agent.md)

> **Path:** Optional, after Lab 09. Solo ✅ · Instructor ✅ (needs the tenant settings below) · Classroom student ✅, in your
> own workspace, if your instructor confirms the ontology tenant setting is on.
>
> **Preview.** Ontology, the ontology agent and data agents grounded in an ontology are all **preview**. Screens and names
> change often. Steps marked *(check)* are written from the Microsoft documentation and haven't been tested end to end.

## What you'll build

An **ontology** – a business model of the rail data – and a second data agent that answers from it:

```
RailKQL tables ──► RailNetworkOntology (Fabric IQ)                 ──► Rail Network Analyst (ontology)  ──► Lab 10 Foundry agent
 OntStations        Station ──has_timing_point──► TimingPoint             data agent, grounded in the           (optional switch)
 OntTimingPoints    Train ──last_reported_at──► TimingPoint               ontology's entities and rules
 OntOperators       Train ──is_run_by──► Operator
 TrainLatest        + business rules: late, active, headcode, London, busiest
```

Then you compare it with the Lab 09 data agent on the same questions.

## Why an ontology?

The Lab 09 data agent knows the rail data only through its **instructions and example queries**. They work, but they
belong to that one agent. Rail data has traps that every agent needs to know:

* A **station** (CRS code, e.g. LDS) has several **timing points** (STANOX codes). Counting at one STANOX undercounts.
* TRUST identifies trains by a 10-character ID; people use the **headcode** inside it (1A21).
* "Late", "active", "busiest" and "in London" need agreed definitions.

An ontology defines these once – entity types, relationships and **business rules** – and binds them to the data without
copying it. Any agent that uses the ontology gets the same definitions: Fabric data agents, Foundry IQ, Copilot Studio,
operations agents, or your own code through the ontology MCP server.

**What it won't do: make answers faster.** The ontology stores definitions and bindings; queries still run on `RailKQL`.
The gain is consistency and fewer wrong answers, and less instruction-writing for each new agent.

## Prerequisites

* Labs 03, 06 and 09 done, and data flowing (`TrainLatest` has rows from the last few minutes).
* **Tenant settings** (Fabric admin; *Admin portal → Tenant settings*, also reachable from *OneLake catalog → Govern →
  Configurations → Tenant settings*):
  * **Users can create ontology (preview) items** → Enabled.
  * **Users can create Fabric items** → Enabled (already needed since Lab 02).
  * The **Fabric data agent** settings from Lab 01 (already on).
* Optional, for a nicer operator list: fill in `TocCodes` (`fabric/kql/07_toc_codes_seed.kql`) before step 1.

## 1. Create the entity tables

An entity type needs one row per thing and a string or integer key. `Locations` has several rows per station, so this
script builds clean tables: `OntStations` (key `station_crs`), `OntTimingPoints` (key `point_stanox`) and `OntOperators`
(key `operator_id`). Trains use the live `TrainLatest` materialized view directly.

```bash
python fabric/scripts/apply_kql.py --file fabric/kql/09_ontology_tables.kql
```

Or paste [`fabric/kql/09_ontology_tables.kql`](../../fabric/kql/09_ontology_tables.kql) into a KQL queryset on `RailKQL`
and run it. Check:

```kusto
OntStations | count                                   // a few thousand stations
OntTimingPoints | where point_crs == "LDS"            // Leeds: several STANOX codes
OntOperators | take 10
```

Rerun the script whenever you reload reference data (Lab 03) or change `TocCodes`. Stations, timing points and operators
change rarely; trains stay live because they come from `TrainLatest`.

## 2. Create the ontology item

1. In your workspace: **+ New item** → **Ontology (preview)**. Name it `RailNetworkOntology`.
2. If you can't see it, the tenant setting isn't on yet (or hasn't propagated – wait a few minutes).

Everything you'll enter is in [`fabric/ontology/rail-ontology.md`](../../fabric/ontology/rail-ontology.md). Build it
with the ontology agent (step 3 Option A, faster) or by hand (step 3 Option B, better for learning). Both end in the same place.

## 3. Option A – build it with the ontology agent

The built-in **ontology agent** discovers your tables, samples a few rows, proposes a definition and validates it. It
works in two modes: **Plan** (proposes and previews, changes nothing) and **Act** (applies and publishes).

1. Open `RailNetworkOntology` → **Ontology agent** on the toolbar. Make sure it's in **Plan** mode.
2. Paste the **Ontology agent prompt** from `rail-ontology.md`.
3. Review the draft in the canvas. Check against the tables in `rail-ontology.md`:
   * four entity types with the right **keys** (`station_crs`, `point_stanox`, `operator_id`, `train_id`)
   * the Train properties are **renamed** (`train_operator_id`, not `toc_id`)
   * three relationships with the right properties on each side
   Ask the agent to fix anything that's different, still in Plan mode.
4. Switch to **Act** and let it apply and publish. *(check: the exact button names)*
5. Accept its **Test the ontology** suggestion: it asks five questions of its own against the bound data.
6. Go to step 4 (rules) – the agent doesn't write the rail rules for you.

## 3. Option B – build it by hand

On the ontology **Home** canvas:

1. **Entity types.** **Add entity type** → `Station` → **Add Entity Type**. Then **…** → **Bind data** → **Add** → OneLake
   catalog → `RailKQL` → `OntStations`. Keep all columns as properties, set **`station_crs`** as the **entity type key**,
   **Create**. Add the description from `rail-ontology.md` (entity details).
2. Repeat for `TimingPoint` (`OntTimingPoints`, key `point_stanox`) and `Operator` (`OntOperators`, key `operator_id`).
3. `Train`: bind to the **`TrainLatest`** materialized view. Keep only the eight properties in `rail-ontology.md` and
   **rename** them (property names can differ from column names). Key `train_id`.
4. **Movement history (recommended).** If the binding page offers a **time series** binding, add `TrustMovements` to Train
   as described in `rail-ontology.md`. *(check: the option's name)*
5. **Relationships.** **Add relationship** → name `has_timing_point`, origin **Station**, target **TimingPoint** →
   **Create**. Leave **Use mapping table?** off; origin property `station_crs`, target property `point_crs` → **Save**.
   Repeat for `is_run_by` and `last_reported_at`.

> **Watch out.** Property names must be unique across the whole ontology, and so must relationship names (a known
> preview issue). That's why every name in this lab has an entity prefix.

## 4. Add the business rules

**Explorer → Overview → Rules → + Create rule.** For each of the seven rules in `rail-ontology.md`: enter the **Rule
name** and **Rule definition**, link the concepts listed, **Save**.

Rules are plain language that agents read to ground their answers. This is where "late", "active", "headcode", "London" and
"busiest" get one shared meaning. (Ontology also has **Activator** rules that fire alerts per entity; you don't need
those here – Lab 07 covers alerts.)

## 5. Look at it

* The **Explorer** lists the four entity types; the canvas shows the relationship graph.
* Open **Station → LDS**-style entity instances (or ask the ontology agent *"Show the timing points for station LDS"*).
* Ask the ontology agent *"How many trains are active right now?"* and expand its steps: it should use the *Active
  train* rule and query `TrainLatest`.

## 6. Create a data agent grounded in the ontology

1. **+ New item → Data agent** → `Rail Network Analyst (ontology)`.
2. **Add a data source** → search **`RailNetworkOntology`** → **Add**. The entity types appear in the Explorer.
   * If you didn't add the time series binding (step 3, Option B item 4), also add **`RailKQL`** as a second source, with the same
     tables as Lab 09, so it can answer history questions.
3. **Agent instructions**: paste the *Data agent instructions* from `rail-ontology.md`. Keep the last line, **Support
   group by in GQL** – Microsoft's documented workaround for an aggregation issue in the preview.
4. If the first questions say there's no data, wait a few minutes for the agent to initialise and ask again.
5. **Publish** it, with a description such as *"Answers questions about GB trains, stations and operators using the rail
   ontology."*

> **Don't bind to a semantic model.** Due to a current known issue, a data agent doesn't work with an ontology whose
> entities are bound to a semantic model. This lab binds to `RailKQL` tables for that reason – don't generate the ontology
> from the Lab 08 or Lab 10b semantic models for this agent.

## 7. Compare the two agents

Work through [`fabric/ontology/comparison-questions.md`](../../fabric/ontology/comparison-questions.md): eight questions,
each asked to both data agents, with a scorecard and the KQL to check each answer.

> **Watch out – freshness.** Question 7 asks for the latest movement time. It should match `TrainLatest | summarize
> max(event_time)` to within a minute or two. Microsoft's documentation says ontology bindings query the live source,
> but also that you must refresh the ontology to see new rows in some views. If the ontology agent's answer is
> noticeably older, it's reading a stored copy: ask the ontology agent to refresh the Train entity, keep using the Lab 09
> agent for "right now" questions, and note it in your scorecard. *(check)*

## 8. Optional – use it from Foundry (Lab 10)

The Lab 10 agent reaches a data agent through the **Fabric IQ (OneLake Catalog)** tool. To try the ontology version:
open the Foundry agent → **Tools** → Fabric IQ → select **`Rail Network Analyst (ontology)`** instead of (or as well as)
`Rail Network Analyst` → **Save**, and test in the playground. RailPulse (Lab 11) then uses it with no code change.

Keep the Lab 09 agent selected if the comparison showed it's better for your questions. You can switch back any time.

Other ways to use the same ontology, not covered here:
[Foundry IQ knowledge base](https://learn.microsoft.com/fabric/iq/ontology/how-to-create-agent-foundry-iq),
[Copilot Studio](https://learn.microsoft.com/fabric/iq/ontology/how-to-create-agent-copilot-studio),
[ontology MCP server](https://learn.microsoft.com/fabric/iq/ontology/how-to-use-ontology-mcp-server), and an
[operations agent](https://learn.microsoft.com/fabric/iq/ontology/how-to-create-operations-agent) that watches the
ontology and messages you in Teams – for example when delays at London stations climb.

## What about the graph?

An ontology can optionally **materialise a graph** for path questions (multi-hop, shortest path). This lab doesn't, because
graph projection currently supports only Lakehouse and mirrored-database delta tables (not Eventhouse), and a
materialised graph is a copy that needs refreshing – the opposite of live train data. A rail network graph (which timing
point follows which) is a good future extension.

## Checkpoint

* `RailNetworkOntology` shows four entity types, three relationships and seven rules.
* The ontology agent answers *"Show the timing points for station LDS"* with several STANOX codes.
* `Rail Network Analyst (ontology)` is published and answers question 1 with station names, not STANOX codes.
* Your scorecard is filled in, including the freshness check.

## Troubleshooting

| Symptom | Fix |
|---|---|
| **Ontology (preview)** isn't under *New item*, or *Unable to create the Ontology (preview) item* | A Fabric admin must enable **Users can create ontology (preview) items** (and **Users can create Fabric items**). Wait a few minutes after it's changed |
| `apply_kql.py` fails on `09_ontology_tables.kql` | Run Lab 03 and Lab 06 first: the script reads `Locations`, `TocCodes` and `TrustMovements` |
| `OntStations` is empty | `Locations` has no CRS codes: rerun Lab 03 (CORPUS) |
| `OntOperators` names are all *Operator NN* | `TocCodes` is empty. Fill `07_toc_codes_seed.kql`, run it, then rerun `09_ontology_tables.kql` |
| Binding: the key column can't be selected | Entity type keys must be **string or integer**. Use the key columns in `rail-ontology.md` |
| Saving a property or relationship fails with a duplicate-name error | Names must be unique across the ontology. Use the prefixed names in `rail-ontology.md` |
| The data agent says there's no data | Wait a few minutes after adding the ontology – the agent initialises – then ask again |
| Totals or *group by* answers are wrong or fail | Check **Support group by in GQL** is the last line of the agent instructions |
| The data agent fails with an ontology generated from a semantic model | Known preview issue: rebuild the entity bindings on the `RailKQL` tables |
| Answers about "now" lag behind the dashboard | See the freshness watch-out in step 7 |
| History questions ("in the last 30 minutes") fail on the ontology agent | Add the time series binding (step 3, Option B item 4), or add `RailKQL` as a second data source on the data agent |

## Clean-up

Delete `RailNetworkOntology` and `Rail Network Analyst (ontology)`, and the tables:
`.drop tables (OntStations, OntTimingPoints, OntOperators) ifexists`. [Lab 12](12-cleanup.md) covers this too.
