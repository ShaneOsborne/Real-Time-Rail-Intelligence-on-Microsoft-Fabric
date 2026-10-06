# Lab 09 – Fabric data agent

**Time:** 30 minutes · **Previous:** [Lab 08](08-dashboard-powerbi.md) · **Next:** [Lab 10](10-foundry-agent.md)

## Objectives

* Create a **Fabric data agent** over the `RailKQL` Eventhouse database, and optionally the `Rail Performance` semantic model. A data agent can have up to five data sources.
* Give it **agent instructions**, **data source instructions** and **example question and query pairs**, so it writes good KQL.
* **Publish** it, which Lab 10 requires.

## Prerequisites

* The tenant settings for the Fabric data agent are enabled (Lab 01), including cross-geo processing and storage if they apply.
* The data sources are on F2+ (or trial) capacity, in the same region as the data agent.

## Option A – automated

Not available in this repo. Create the data agent in the portal. All the content you need is supplied:

* [`fabric/data-agent/instructions.md`](../../fabric/data-agent/instructions.md)
* [`fabric/data-agent/example-queries.json`](../../fabric/data-agent/example-queries.json)

## Option B – manual

1. Workspace → **+ New item** → **Data agent** → `Rail Network Analyst`.
2. **Add data source** → `RailKQL`. Select the tables, views and functions the agent may use:
   `TrustMovements`, `TrustCancellations`, `TrustActivations`, `Locations`, `TocCodes`, plus the materialized views
   (`TrainLatest`, `DelaysBy15Min`, `CancellationsBy15Min`, `DailyTocPerformance`). Leave `RawFeed` and `RdmTrustRaw` **out**.
3. Optionally, add the `Rail Performance` semantic model from Lab 08.
4. **Agent instructions**: paste the *Agent instructions* section of `instructions.md`.
5. **Data source instructions** (on `RailKQL`): paste the *Data source instructions* section.
6. **Example queries** (on `RailKQL`): add each question and KQL pair from `example-queries.json`.
7. Test it in the chat pane:
   * "Which trains are more than 15 minutes late right now?"
   * "How many cancellations in the last hour, by reason?"
   * "Show the latest movements at Leeds."
8. **Publish**. Note the URL, `…/groups/<workspace_id>/aiskills/<artifact_id>…`. Lab 10 needs both GUIDs.
9. **Share** the data agent (Read) with the people who'll use the Foundry agent or Rayfin app. They also need the **Reader** role on the KQL database.

## Checkpoint

- [ ] Answers come with KQL that uses the views and functions (expand *Show steps*)
- [ ] The agent is published, and you have the workspace and artifact IDs

## Troubleshooting

| Symptom | Fix |
|---|---|
| The agent queries `RawFeed` | Remove it from the selected tables. Strengthen the instruction |
| "Not enough data" | Make sure the live feed is flowing (Lab 05/04). The agent filters by time |
| Users get unauthorised errors | Grant Read on the data agent **and** Reader on the KQL database |
