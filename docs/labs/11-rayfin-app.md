# Lab 11 – Rayfin app: live map and "chat with the network"

**Time:** 60 minutes · **Previous:** [Lab 10](10-foundry-agent.md) · **Next:** [Lab 12](12-cleanup.md)

## Objectives

* Scaffold a **Fabric app** with the **Rayfin** CLI, in its **own folder outside this repo**.
* Read live train positions from the Eventhouse through a Rayfin **function** (`getNetworkSnapshot`) that runs as the
  signed-in user, and plot them on a map.
* Add a **chat panel** that calls a second function (`askRailAgent`), which calls the Foundry agent from Lab 10 on behalf of the user.

> **Why a function and not a KQL connector?** Rayfin 1.36.2 has paused new Kusto connector authoring:
> `npx rayfin connector add --type kusto` fails with *Connector type "kusto" is not available in this release*. The supported
> connector types are SQL analytics endpoint, Warehouse, SQL database and semantic model. A function with a delegated
> `AudienceType.Kusto` token queries the KQL database directly instead, so the map stays real-time.
>
> **Preview.** Fabric Apps is preview, and functions aren't available in every Fabric region or tenant. Check
> <https://rayfin.ai/docs> and <https://learn.microsoft.com/fabric/apps/create-app-with-cli> first.

## Prerequisites

* The Fabric Apps (preview) workload is enabled. You have Contributor or above on the workspace `rail-fabric-rti`.
* Node.js 20+ and npm, and the GitHub CLI (per the Rayfin installation guide).
* Labs 06 (the `NetworkSnapshot()` function), 03 (coordinates) and 10 (Foundry agent) are done.
* App users need at least **Viewer** on the `RailKQL` database, because the function queries it as them.

### The values you'll need

| Value | What it is | Where to find it |
|---|---|---|
| Workspace **name** | The Fabric workspace from Lab 02 – where the app is deployed | `rail-fabric-rti` (or `FABRIC_WORKSPACE_NAME` in the repo `.env`) |
| **Query URI** | The KQL database's query endpoint | `KUSTO_QUERY_URI` in the repo `.env` (printed by `fabric-setup` in Lab 02), or **RailKQL → Overview → Query URI** |
| Database **name** | The KQL database | `RailKQL` |
| Foundry project endpoint, agent name | From Lab 10 | `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_AGENT_NAME` in the repo `.env` |

You don't need the workspace ID or the KQL database item ID any more – those were only for the Kusto connector. (If you need
them for something else: open the item in the Fabric portal; the URL is `…/groups/<workspace-id>/…/<item-id>…`, and both are
also in the repo `.env` as `FABRIC_WORKSPACE_ID` and `FABRIC_KQL_DATABASE_ID`.)

### Where to create the app

Create the app **next to** this repo, not inside it. The scaffold makes a complete project of its own (with
`node_modules/` and `rayfin/.env`, which holds deployment details), and it shouldn't be committed to the lab repo. For example:

```
labs/
├── rail-fabric-rti/      ← this repo (the overlay code is in app/rayfin-starter)
└── rail-app/             ← your Rayfin app (create it here)
```

If you want to keep your app in Git, give it its **own** repository. (`rail-app/` is also in this repo's `.gitignore`,
in case it's created inside by mistake.)

## Option A – CLI plus overlay code

Run these from the folder **above** the repo (for example `labs/`):

```bash
# 1. Scaffold. <workspacename> = the Fabric workspace NAME, for example rail-fabric-rti
npm create @microsoft/rayfin@latest -- rail-app --workspace rail-fabric-rti
#    When asked for a template, choose the DEFAULT. The overlay code is React + TypeScript; if the default
#    isn't a React template in your version, choose the React/Vite one instead (npx rayfin init --list-templates).
cd rail-app
npx rayfin login

# 2. Functions (needed for both the map and the chat panel)
npx rayfin functions init

# 3. Copy the overlay code from the lab repo
cp -r ../rail-fabric-rti/app/rayfin-starter/src/* src/
#    Then merge ../rail-fabric-rti/app/rayfin-starter/rayfin/functions/src/function_app.ts into
#    rayfin/functions/src/function_app.ts, and set the constants at the top of it:
#      KUSTO_QUERY_URI, KQL_DATABASE, FOUNDRY_PROJECT_ENDPOINT, FOUNDRY_AGENT_NAME
#    Finally render <RailApp /> from src/App.tsx.

# 4. Deploy and check
npx rayfin up --dry-run
npx rayfin up
npx rayfin up status
```

In PowerShell, use `Copy-Item -Recurse ..\rail-fabric-rti\app\rayfin-starter\src\* src\` for the copy step.

To develop locally, `npx rayfin dev` starts the frontend dev server and the backend. Or run
`npx rayfin up --exclude-services staticHosting`, then `npm run dev`.

The details are in [`app/README.md`](../../app/README.md).

## Option B – manual walkthrough (what the overlay code does)

1. **Client.** `src/services/rayfinClient.ts` creates a `RayfinClient<AppSchema, AppFunctionsSchema>`. `AppFunctionsSchema`
   is generated from `function_app.ts` when you build or deploy, so `client.functions.getNetworkSnapshot` and
   `client.functions.askRailAgent` are typed.
2. **Map data function.** `getNetworkSnapshot(lookbackMinutes)` in `function_app.ts`:
   * declares `udf.connection({ audienceType: AudienceType.Kusto })` and gets a delegated token with `ctx.getToken(AudienceType.Kusto)`;
   * POSTs `{ db: "RailKQL", csl: "NetworkSnapshot(60m) | take 2000" }` to `<Query URI>/v1/rest/query`;
   * returns the first result table as an array of rows.

   The query text is **fixed** – only the look-back (5–240 minutes) comes from the browser and it's validated – so users can't
   run arbitrary KQL.
3. **Map.** `loadSnapshot.ts` calls the function; `NetworkMap.tsx` projects lat/lon onto an SVG of GB and colours each dot:
   green is on time, amber is late, red is 15 minutes or more late. It refreshes every 30 seconds.
4. **Chat function.** `askRailAgent` gets an OBO token with `ctx.getToken(AudienceType.AzureAI)` and calls the Foundry agent.
   **TODO(verify)**: the REST path and body (`POST {project}/openai/v1/responses` with `agent_reference`). Check them against
   <https://ai.azure.com/api-reference/responses/>.
5. **Chat UI.** `ChatPanel.tsx` calls `client.functions.askRailAgent.invoke({ question })` and handles `FunctionsError`.

## Checkpoint

* The deployed app URL (printed by `rayfin up`) opens inside Fabric SSO.
* The map shows trains. The chat panel answers "Which trains are 15+ minutes late?"
* The page shows the attribution text. The app isn't described as "official", and it uses no Network Rail or National Rail logos.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connector type "kusto" is not available in this release` | Expected in Rayfin 1.36.2. This lab no longer uses a Kusto connector – follow Option A (function-based map) |
| 401/403 on deploy | `npx rayfin login`, then `npx rayfin up` again |
| Map fails with *Eventhouse query failed with HTTP 401/403* | The signed-in user lacks access to `RailKQL`. Grant them **Viewer** on the database (or workspace Viewer) |
| Map fails with HTTP 400 | Check `KUSTO_QUERY_URI` (no trailing `/`) and `KQL_DATABASE` (the database **name**) in `function_app.ts`, and that `NetworkSnapshot()` exists (Lab 06) |
| `client.functions.getNetworkSnapshot` isn't typed | `types.js` is generated on build. Run `npx rayfin up` (or `npx rayfin dev`) after merging `function_app.ts` |
| Calls fail locally with HTTP 502 | The local Functions host isn't running. Use `npx rayfin dev`, or deploy with `npx rayfin up` first |
| Functions not available | Your tenant or region doesn't have them yet. The map and chat both need functions; use the Lab 08 dashboard and the Foundry playground instead |
| Map empty but the query works in a queryset | `Locations.lat/lon` is missing. Re-run Lab 03 with NaPTAN |
| The app folder shows up in `git status` of the lab repo | It was created inside the repo. Move it next to the repo, or rely on the `rail-app/` entry in `.gitignore` |
