# Lab 11 – Rayfin app: live map and "chat with the network"

**Time:** 60 minutes · **Previous:** [Lab 10](10-foundry-agent.md) · **Next:** [Lab 12](12-cleanup.md)

> **Path:** Everyone, **if Fabric Apps is available in your capacity's region** (checked in Lab 01). Classroom students: your instructor will tell you.

## Objectives

* Scaffold a **Fabric app** with the **Rayfin** CLI, in its **own folder outside this repo**.
* Read live train positions from the Eventhouse through a Rayfin **function** (`getNetworkSnapshot`), and plot them on a map.
* Add a **chat panel** that calls a second function (`askRailAgent`), which calls the Foundry agent from Lab 10 on behalf of the user.

> **Why a function and not a KQL connector?** Rayfin 1.36.2 has paused new Kusto connector authoring:
> `npx rayfin connector add --type kusto` fails with *Connector type "kusto" is not available in this release*. The supported
> connector types are SQL analytics endpoint, Warehouse, SQL database and semantic model. A function with a delegated
> `AudienceType.Kusto` token queries the KQL database directly instead, so the map stays real-time.
>
> **Preview.** Fabric Apps is preview. **It isn't available in every Fabric region**, and functions aren't available in every region or tenant. Check
> <https://rayfin.ai/docs> and <https://learn.microsoft.com/fabric/apps/create-app-with-cli> first.

## Prerequisites

* **Fabric Apps (preview)** is enabled for you: *Admin portal > Tenant settings > Fabric Apps (preview)* (Lab 01). **Check first:** in the
  workspace, **+ New item** → search **App (preview)**. If it isn't listed, `rayfin up` will fail with *403 – The feature is not available*.
* The workspace's **capacity region supports Fabric Apps**. If **App (preview)** isn't listed even though the tenant setting is
  on, your region isn't supported yet. See [If App (preview) isn't available in your region](#if-app-preview-isnt-available-in-your-region).
* You have Contributor or above on the workspace `rail-fabric-rti` (or the app workspace), and the workspace is on a running Fabric capacity.
* Node.js 20, 22 or 24 and npm, the GitHub CLI (per the Rayfin installation guide), and Azure Functions Core Tools for the local
  functions host used by `npm run dev`.
* Labs 06 (the `NetworkSnapshot()` function), 03 (coordinates) and 10 (Foundry agent) are done.
* Grant **Viewer** on the `RailKQL` database to the **app** (the App item, for example `rail-app`, once it exists) – Rayfin 1.36
  docs say deployed functions use the app identity – and to yourself for local runs (`npm run dev` runs as you).

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
├── Real-Time-Rail-Intelligence-on-Microsoft-Fabric/   ← your clone of this repo (whatever you named the folder)
│   └── app/rayfin-starter/                            ← the overlay code
└── rail-app/                                          ← your Rayfin app (create it here)
```

If you want to keep your app in Git, give it its **own** repository. (`rail-app/` is also in this repo's `.gitignore`,
in case it's created inside by mistake.)

## If App (preview) isn't available in your region

The app doesn't need to sit in the same workspace, or region, as the Eventhouse. Its function calls the KQL database over the
Query URI, so the data can stay where it is.

1. In the Azure portal, create a small **Fabric capacity (F2)** in a region where Fabric Apps is available. Pause it when you're
   not using it, because an F SKU bills per second while it runs. A **trial** capacity won't help: it's created in your tenant's home region.
2. In Fabric, create a workspace such as `rail-fabric-rti-app` and assign it that capacity (*Workspace settings > License info*).
3. Check that **+ New item → App (preview)** is now listed in that workspace.
4. Keep `KUSTO_QUERY_URI` and `KQL_DATABASE` in `function_app.ts` pointing at your **existing** Eventhouse.
5. Deploy into the new workspace: `npx rayfin up --workspace-id <app-workspace-guid>` (the GUID after `/groups/` in the
   workspace URL). Or run `npx rayfin up --capacity-id <capacity-guid>` and let Rayfin create a workspace on that capacity.
6. Grant access to `RailKQL` as in the prerequisites (users Viewer; the app identity Viewer if the deployed function runs as the app).

Things to know:

* **Data residency.** Query results (train positions, not personal data) pass through the app's region. Check that's acceptable
  for your organisation.
* Cross-region queries add a little latency, which doesn't matter for a 2-minute refresh.
* The Foundry agent (Lab 10) is called over its endpoint, so its region doesn't matter here.
* If you can't create a capacity in a supported region, skip this lab. The Lab 08 dashboard (map) and the Foundry playground (chat)
  cover the same story.

## Option A – CLI plus overlay code

> **Rayfin 1.36 default template = "Universal App" workspace.** When you choose **✨ Use default template**, the project is an
> npm workspace: the web app is in `packages/frontend/`, and functions go in `packages/functions/` once you add the
> **functions pack**. There is **no** root `src/` and **no** `rayfin/functions/` in it. If you copy files there, or run
> `npx rayfin functions init`, `rayfin up` still deploys the untouched template – the welcome/blueprint page and a hello-world function.
> The overlay in `app/rayfin-starter/` mirrors the default layout, so you copy `packages/` onto `packages/`.

Run these from the folder **above** the repo (for example `labs/`). `LAB_REPO` is the path to your clone as seen from
inside `rail-app`, so the copy works whatever your clone folder is called.

```bash
export LAB_REPO=../Real-Time-Rail-Intelligence-on-Microsoft-Fabric    # change to your clone's folder name

# 1. Scaffold. --workspace = the Fabric workspace NAME the app is deployed to (rail-fabric-rti, or your app workspace)
npm create @microsoft/rayfin@latest -- rail-app --workspace rail-fabric-rti
#    Template: choose "✨ Use default template".
cd rail-app
npx rayfin login

# 2. Add the functions capability (NOT `npx rayfin functions init` – that creates a second, unused functions project)
npm run pack:add -- functions

# 3. Copy the overlay code (replaces the starter function; adds the map, chat and adapter files)
cp -r "$LAB_REPO"/app/rayfin-starter/packages/* packages/

# 4. Three edits
#  a) packages/functions/src/function_app.ts – set the four values in the "SET THESE FOUR VALUES" block:
#     KUSTO_QUERY_URI, KQL_DATABASE, FOUNDRY_PROJECT_ENDPOINT, FOUNDRY_AGENT_NAME (all in the lab repo .env)
#  b) packages/frontend/src/services/railClient.ts – point the import at the template's client module:
grep -rl "export.*getRayfinClient" packages/frontend/src
#     e.g. packages/frontend/src/services/rayfin.ts  →  import { getRayfinClient } from './rayfin';
#  c) packages/frontend/src/App.tsx – show the rail app instead of the welcome page:
#     replace   import { EmptyStatePreview } from './EmptyStatePreview';   with   import { RailApp } from './RailApp';
#     replace   <EmptyStatePreview />                                       with   <RailApp />
#     Leave everything else in App.tsx (the auth gate, theme and error boundary) as it is.

# 5. Generate the function types and check (Ctrl+C the dev session once it says the functions host/types are ready)
npm run dev
npm run validate:functions      # both functions must be listed in AppFunctionsSchema
npm run typecheck && npm run build

# 6. Deploy
npm run rayfin:up               # same as npx rayfin up
npx rayfin up status
```

**PowerShell.** `cp` there is `Copy-Item`, which won't merge into folders that already exist (*An item with the specified
name … already exists*). Use `robocopy`, which merges and overwrites:

```powershell
$env:LAB_REPO = "..\Real-Time-Rail-Intelligence-on-Microsoft-Fabric"     # ".." if rail-app is inside the repo
robocopy "$env:LAB_REPO\app\rayfin-starter\packages" packages /E /NJH /NJS /NDL   # exit code 1 = files copied (OK)
Get-ChildItem -Recurse packages\frontend\src | Select-String "export.*getRayfinClient" -List   # step 4b
```

> **Created `rail-app` inside the repo instead?** Then the overlay is one level up: `cp -r ../app/rayfin-starter/packages/* packages/`.
> It works, but move the app out of the repo before you commit anything.

> **Already deployed and you see the welcome page or a hello-world function?** You copied into the old flat paths. In `rail-app`:
> delete the stray `src/` folder you created at the root (not `packages/frontend/src`) and, if you ran `npx rayfin functions init`,
> delete `rayfin/functions/`. Then do steps 2–6 above. `rayfin up` updates the same App item.

`npm test` runs the template's own tests, which expect the welcome page. Update or delete `App.spec.tsx` and `Root.spec.tsx`
welcome assertions if you run them; the deploy doesn't need them.

The details are in [`app/README.md`](../../app/README.md).

## Option B – manual walkthrough (what the overlay code does)

1. **Client.** The template creates one authenticated `RayfinClient` (`getRayfinClient()`), and the functions pack wires the
   generated `AppFunctionsSchema` (from `packages/functions/src/function_app.ts`) into it. `services/railClient.ts` just
   returns `client.functions`, so `getNetworkSnapshot` and `askRailAgent` are typed.
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
| `rayfin up` fails with **403 Forbidden – The feature is not available** (at *createRayfinItem*) | Fabric can't create an App item there. Check **+ New item → App (preview)** in the workspace. If it's missing: 1) ask a Fabric admin to enable *Admin portal > Tenant settings > Fabric Apps (preview)* for you, then wait a few minutes; 2) if the setting is already on, your capacity region isn't supported. Deploy to a workspace on a capacity in a supported region (see [above](#if-app-preview-isnt-available-in-your-region)). Also check the capacity is running, not paused |
| Any other 401/403 on deploy | `npx rayfin login`, then `npx rayfin up` again |
| Map fails with *Eventhouse query failed with HTTP 401/403* | The signed-in user lacks access to `RailKQL`. Grant them **Viewer** on the database (or workspace Viewer) |
| Map fails with HTTP 401/403 even though the signed-in user has access | Rayfin 1.36 deprecates `ctx.getToken()` (used here) in favour of typed `ctx.Tokens`, and its docs say deployed functions use the **app identity**. If that applies in your release, grant the Fabric app's identity **Viewer** on `RailKQL` as well |
| Map fails with HTTP 400 | Check `KUSTO_QUERY_URI` (no trailing `/`) and `KQL_DATABASE` (the database **name**) in `function_app.ts`, and that `NetworkSnapshot()` exists (Lab 06) |
| Deployed app shows the Rayfin **welcome / blueprint** page, or only a **hello-world** function | The overlay went to the old flat paths (`src/`, `rayfin/functions/`), which the default template doesn't build. Follow Option A: `npm run pack:add -- functions`, copy `packages/*` onto `packages/`, edit `App.tsx` and `railClient.ts`, then `npm run rayfin:up` |
| PowerShell: *Copy-Item: An item with the specified name …\\packages\\frontend already exists* | `Copy-Item` doesn't merge folders. Use the `robocopy … /E` command above (or Git Bash `cp -r`). Then check `packages/frontend/src/RailApp.tsx` and `packages/frontend/src/services/railClient.ts` exist, and `packages/functions/src/function_app.ts` contains `getNetworkSnapshot` |
| `Cannot find module './rayfin'` in `railClient.ts` | Point the import at the file that `grep -rl "export.*getRayfinClient" packages/frontend/src` prints |
| `functions.getNetworkSnapshot` isn't typed, or `validate:functions` fails | Types are generated by the dev session. Run `npm run dev` from the project root until it has generated `packages/functions/src/types.ts`, then `npm run validate:functions`. Don't edit `types.ts` by hand, and don't cast the client |
| `pack:add` says `functions` is unknown, or there's no `packages/` folder | You chose a flat (older) template. Either re-scaffold with the default template, or copy `packages/frontend/src/*` into `src/` and `packages/functions/src/function_app.ts` into `rayfin/functions/src/` (after `npx rayfin functions init`), and create the client yourself as in <https://rayfin.ai/docs/functions/calling-functions> |
| Chat answers fail when deployed, but work with `npm run dev` | Deployed functions use the **app identity**, and the Foundry Fabric data agent tool supports **user identity only** (Lab 10). This is a preview limitation; use the Foundry playground for chat until it's supported |
| Calls fail locally with HTTP 502 | The local Functions host isn't running. Use `npm run dev` from the project root |
| Functions not available | Your tenant or region doesn't have them yet. The map and chat both need functions; use the Lab 08 dashboard and the Foundry playground instead |
| Map empty but the query works in a queryset | `Locations.lat/lon` is missing. Re-run Lab 03 with NaPTAN |
| The app folder shows up in `git status` of the lab repo | It was created inside the repo. Move it next to the repo, or rely on the `rail-app/` entry in `.gitignore` |
