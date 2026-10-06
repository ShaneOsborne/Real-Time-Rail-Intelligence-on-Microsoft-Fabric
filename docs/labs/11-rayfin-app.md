# Lab 11 – Rayfin app: live map and "chat with the network"

**Time:** 60 minutes · **Previous:** [Lab 10](10-foundry-agent.md) · **Next:** [Lab 12](12-cleanup.md)

## Objectives

* Scaffold a **Fabric app** with the **Rayfin** CLI.
* Query the Eventhouse through a **KQL (kusto) connector**, which runs with delegated auth as the signed-in user, and plot trains on a map.
* Add a **chat panel** that calls a Rayfin **function**. The function calls the Foundry agent from Lab 10 on behalf of the user.

> **Preview and experimental.** Fabric Apps is preview. Rayfin **connectors are preview** (`kusto` is a *private preview* connector type),
> and **functions and delegated auth are experimental**. None of these is available in every tenant or region. Check
> <https://rayfin.ai/docs> and <https://learn.microsoft.com/fabric/apps/create-app-with-cli> first.

## Prerequisites

* The Fabric Apps (preview) workload is enabled. You have Contributor or above on the workspace.
* Node.js 20+ and npm, and the GitHub CLI (per the Rayfin installation guide).
* Labs 06 (the `NetworkSnapshot()` function), 03 (coordinates) and 10 (Foundry agent) are done.

## Option A – CLI plus overlay code

```bash
npm create @microsoft/rayfin@latest -- rail-app --workspace <workspacename>
cd rail-app
npx rayfin login
npx rayfin connector add --type kusto --workspace-id <workspace-id> --item-id <kql-database-item-id> --name rail
#   run the pinned npm install command printed by the CLI
npx rayfin functions init                     # experimental
cp -r ../app/rayfin-starter/src/* src/
#   merge ../app/rayfin-starter/rayfin/functions/src/function_app.ts into rayfin/functions/src/function_app.ts
#   set FOUNDRY_PROJECT_ENDPOINT / FOUNDRY_AGENT_NAME constants in function_app.ts
#   render <RailApp /> from src/App.tsx
npx rayfin up --dry-run
npx rayfin up
npx rayfin up status
```

To develop locally, `npx rayfin dev` starts the frontend dev server and deploys the backend to Fabric.
Alternatively, run `npx rayfin up --exclude-services staticHosting`, then `npm run dev`.

The details are in [`app/README.md`](../../app/README.md).

## Option B – manual walkthrough (what the overlay code does)

1. **Connector.** `npx rayfin connector add --type kusto …` resolves the KQL database routing and **generates**
   `rayfin/connectors/rail/schema.ts`. Don't edit that file. Its `connectorConfig` goes into `ConnectorsRayfinClient`, and `kusto()` goes into the runtime map
   (`src/services/rayfinClient.ts`). The name `rail` must match in all four places.
2. **Query.** `loadSnapshot.ts` calls `client.connectors.rail.executeQuery({ query, clientRequestId })` with a
   `KPC.rayfin_kusto_v1;<uuid>` request ID, then normalises the result with `toQueryResult()`.
3. **Map.** `NetworkMap.tsx` projects lat/lon onto an SVG of GB and colours each dot: green is on time, amber is late, red is 15 minutes or more late. It refreshes every 30 seconds.
4. **Function.** `askRailAgent` is registered with `udf.func(name, handler, [udf.connection({ audienceType: AudienceType.AzureAI })])`.
   It gets an OBO token with `ctx.getToken(AudienceType.AzureAI)` and calls the Foundry agent.
   **TODO(verify)**: the REST path and body (`POST {project}/openai/v1/responses` with `agent_reference`). Check them against
   <https://ai.azure.com/api-reference/responses/>.
5. **Chat UI.** `ChatPanel.tsx` calls `client.functions.askRailAgent.invoke({ question })` and handles `FunctionsError`.
6. **Test the connector from the CLI**, which needs a deployed backend:
   `npx rayfin connector invoke rail executeQuery --input '{"query":"NetworkSnapshot(1h) | take 5"}'`

## Checkpoint

* The deployed app URL (printed by `rayfin up`) opens inside Fabric SSO.
* The map shows trains. The chat panel answers "Which trains are 15+ minutes late?"
* The page shows the attribution text. The app isn't described as "official", and it uses no Network Rail or National Rail logos.

## Troubleshooting

| Symptom | Fix |
|---|---|
| 401/403 on deploy | `npx rayfin login`, then `npx rayfin up` again |
| `rayfin up rejects auth.type: application` | Kusto connectors are delegated-only |
| `executeQuery` can't reach the cluster | `kusto()` is missing from the runtime map |
| `connector invoke` says "No remote endpoint configured" | Run `npx rayfin up` first |
| Functions not available | Your tenant or region doesn't have them yet. Ship the map only and link to the Foundry playground |
| Map empty but the query works | `Locations.lat/lon` is missing. Re-run Lab 03 with NaPTAN |
