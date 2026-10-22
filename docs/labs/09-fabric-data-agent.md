# Lab 09 – Fabric data agent

**Time:** 30 minutes · **Previous:** [Lab 08](08-dashboard-powerbi.md) · **Next:** [Lab 10](10-foundry-agent.md)

> **Path:** Everyone.

## Objectives

* Create a **Fabric data agent** over the `RailKQL` Eventhouse database, and optionally the `Rail Performance` semantic model. A data agent can have up to five data sources.
* Give it **agent instructions**, **data source instructions** and **example question and query pairs**, so it writes good KQL.
* **Publish** it, which Lab 10 requires.

## Prerequisites

* The tenant settings for the Fabric data agent are enabled (Lab 01), including cross-geo processing and storage if they apply.
* The data sources are on F2+ (or trial) capacity, in the same region as the data agent. F2 is the minimum SKU, not a size: the data agent adds capacity load on top of the always-on Eventstreams (see [Capacity planning and sizing](../capacity-planning.md)).

## Option A – automated

Not available in this repo. Create the data agent in the portal. All the content you need is supplied:

* [`fabric/data-agent/instructions.md`](../../fabric/data-agent/instructions.md)
* [`fabric/data-agent/example-queries.md`](../../fabric/data-agent/example-queries.md) – copy-paste ready
* [`fabric/data-agent/example-queries.json`](../../fabric/data-agent/example-queries.json) – the same pairs, for scripts and the SDK

## Option B – manual

1. Workspace → **+ New item** → **Data agent** → `Rail Network Analyst`.
2. **Add data source** → `RailKQL`. Select the tables, views and functions the agent may use:
   `TrustMovements`, `TrustCancellations`, `TrustActivations`, `Locations`, `TocCodes`, plus the materialized views
   (`TrainLatest`, `DelaysBy15Min`, `CancellationsBy15Min`, `DailyTocPerformance`). Leave `RawFeed` and `RdmTrustRaw` **out**.
3. Optionally, add the `Rail Performance` semantic model from Lab 08.
   *Optional (only if you did [Lab 04b](04b-darwin-push-port.md)):* also select `DarwinLocations` and the functions
   `DarwinLatest`, `DarwinUnconfirmedPlatforms` and `DarwinBiggestDelays`. Leave `RdmDarwinRaw` **out**.
4. **Agent instructions**: paste the *Agent instructions* section of `instructions.md`.
5. **Data source instructions** (on `RailKQL`): paste the *Data source instructions* section.
6. **Example queries** (on `RailKQL`): open [`fabric/data-agent/example-queries.md`](../../fabric/data-agent/example-queries.md)
   and, for each pair, **+ Add example** → paste the **Question** block into *Question* and the **Query** block into *Query*.
   * Use the `.md` file, not `example-queries.json`: the JSON stores line breaks as `\n`, which don't paste correctly.
   * The queries use only the tables and materialized views selected in step 2 (no custom functions), so they pass the data
     agent's schema validation. Check each example shows as valid after you add it; one that fails validation isn't used.
   * The Darwin pairs (*Optional – Darwin, Lab 04b*) need `DarwinLocations`; add them only if you did Lab 04b, and paste the
     *Optional: Darwin addendum* from `instructions.md` too.
   * **Import from JSON** in the Example queries pane expects the agent's own export format, which `example-queries.json` doesn't
     match yet. Use copy-paste for now.
7. Test it in the chat pane:
   * "Which trains are more than 15 minutes late right now?"
   * "How many cancellations in the last hour, by reason?"
   * "Show the latest departures and arrivals at Leeds." – expect a table with time, arrival/departure, headcode, origin and
     on-time status. Blank platform or origin values are normal (see Troubleshooting).
8. **Publish**. Note the URL, `…/groups/<workspace_id>/aiskills/<artifact_id>…`. Lab 10 needs both GUIDs.
9. **Share** the data agent (Read) with the people who'll use the Foundry agent or Rayfin app. They also need the **Reader** role on the KQL database.

## Checkpoint

- [ ] Answers come with KQL that uses the views and functions (expand *Show steps*)
- [ ] The agent is published, and you have the workspace and artifact IDs

## Troubleshooting

| Symptom | Fix |
|---|---|
| The agent says the data is "corrupted" or "malformed", or sends you to National Rail | Usually blank fields (no destination, platform or origin in TRUST). Re-paste the latest *Agent instructions* (they explain these fields), and make sure the station-board example query was added and is valid |
| An example query shows as invalid / isn't used | It references something not selected in step 2. The supplied examples use only tables and views: check `TrustMovements`, `TrustActivations`, `Locations`, `TocCodes` and the materialized views are all selected |
| Pasting a query from `example-queries.json` gives one long line with `\n` | Use `example-queries.md`, which has paste-ready blocks |
| The agent queries `RawFeed` | Remove it from the selected tables. Strengthen the instruction |
| "Not enough data" | Make sure the live feed is flowing (Lab 05/04). The agent filters by time |
| Users get unauthorised errors | Grant Read on the data agent **and** Reader on the KQL database |
