# Lab 11 – Rayfin app: live map and "chat with the network"

**Time:** 60 minutes · **Previous:** [Lab 10b](10b-live-semantic-model.md) · **Next:** [Lab 11b](11b-azure-maps.md) (optional) or [Lab 12](12-cleanup.md)

> **Path:** Everyone, **if Fabric Apps is available in your capacity's region** (checked in Lab 01). Classroom students: your instructor will tell you.

## Objectives

* Scaffold a **Fabric app** with the **Rayfin** CLI, in its **own folder outside this repo**.
* Show a **live map** of trains by querying the Lab 10b semantic model (DirectQuery over `RailKQL`) through the Rayfin
  **semantic model connector**, as the signed-in user.
* Add a **chat panel** that calls a second function (`askRailAgent`), which calls the Foundry agent from Lab 10 on behalf of the user.

> **Why a semantic model and not the Eventhouse directly?** Rayfin 1.36.2 has no way to query a KQL database: there's no
> Kusto connector (`connector add --type kusto` → *not available in this release*), and functions can only get tokens for
> Sql, Storage, Fabric, AzureAI and ADO ([Connections](https://rayfin.ai/docs/functions/connections)). It does have a
> `fabric-semanticmodel` connector, so the map sends DAX to the **DirectQuery** semantic model from
> [Lab 10b](10b-live-semantic-model.md), which runs it as KQL against `RailKQL` – still live.
>
> Rayfin connectors are **preview** and may change between releases.
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
  functions host. If Core Tools is missing, `npx rayfin dev functions apply` (step 5) offers to install it.
* Labs 10 (Foundry agent) and **10b** (the `RailLiveMap` semantic model) are done.
* You have **Build** permission on `RailLiveMap` (you do if you published it). Other app users need it too (Lab 10b, step 5).
* The chat function's identity has the **Foundry User** role on the Foundry project: locally that's you; when deployed it's the
  Fabric **app identity**, which in current Fabric apps is the **owner of the App item** (normally you).

### The values you'll need

| Value | What it is | Where to find it |
|---|---|---|
| Workspace **name** | The Fabric workspace the app is deployed to | `rail-fabric-rti` (or your app workspace) |
| Semantic model **workspace ID** and **model ID** | `RailLiveMap` from Lab 10b | From its URL `…/groups/<workspace-id>/datasets/<model-id>/…`, or `npx rayfin connector search` (step 3) |
| Foundry project endpoint, agent name | From Lab 10 (step 1.4) | `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_AGENT_NAME` in the repo `.env`. Not there? Foundry portal → your project → **Overview** → **Project endpoint** (`https://<resource>.services.ai.azure.com/api/projects/<project>`); the agent name is on the **Agents** page |

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

The app doesn't need to sit in the same workspace, or region, as the Eventhouse or the semantic model. The connector names the
model by its workspace and item IDs, and the chat function calls Foundry over its endpoint, so the data stays where it is.

1. In the Azure portal, create a small **Fabric capacity (F2)** in a region where Fabric Apps is available. Pause it when you're
   not using it, because an F SKU bills per second while it runs. A **trial** capacity won't help: it's created in your tenant's home region.
2. In Fabric, create a workspace such as `rail-fabric-rti-app` and assign it that capacity (*Workspace settings > License info*).
3. Check that **+ New item → App (preview)** is now listed in that workspace.
4. Keep the connector pointing at `RailLiveMap` in its **existing** workspace (step 3 of Option A).
5. Deploy into the new workspace: `npx rayfin up --workspace-id <app-workspace-guid>` (the GUID after `/groups/` in the
   workspace URL). Or run `npx rayfin up --capacity-id <capacity-guid>` and let Rayfin create a workspace on that capacity.
6. Keep the Foundry User role for the App item's owner (see the prerequisites).

Things to know:

* **Data residency.** Query results (train positions, not personal data) pass through the app's region. Check that's acceptable
  for your organisation.
* Cross-region queries add a little latency, which doesn't matter for a 30-second refresh.
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

# 1b. Deploy the untouched template ONCE. This creates the App item and records it as the ACTIVE deployment in
#     rayfin/.deployments.json – `rayfin dev functions apply` (step 5) refuses to run without one.
#     Use the GUID of the workspace the app goes in (the part after /groups/ in its Fabric URL). A flag always wins over
#     the name given at scaffold time, and once deployed the target is recorded, so later `rayfin up` runs need no flag.
npx rayfin up --workspace-id <app-workspace-guid>

# 2. Add the capabilities: functions (chat) and connectors (map)
#    NOT `npx rayfin functions init` – that creates a second, unused functions project.
npm run pack:add -- functions
npm run pack:add -- connectors

# 3. Add the semantic model connector. The name MUST be railmap (the overlay code uses it).
npx rayfin connector search "RailLiveMap" --type fabric-semanticmodel --all-workspaces --json   # prints workspaceId, itemId
npx rayfin connector add --type fabric-semanticmodel --workspace-id <workspace-id> --item-id <model-id> --name railmap
#    It adds railmap to rayfin/rayfin.yml (auth: delegated), writes rayfin/connectors/railmap/schema.ts, updates
#    packages/frontend/src/lib/connectors.ts, and PRINTS an npm install command with pinned versions. Run that command
#    into the frontend package (add -w if it isn't there):
#      npm install -w @rayfin-app/frontend <the packages@versions it printed>
#    Check: grep -n railmap packages/frontend/src/lib/connectors.ts   (should list railmap)
#    Optional test as you:  npx rayfin connector inspect --name railmap

# 3b. Copy the overlay code (replaces the starter function; adds the map, chat and adapter files)
cp -r "$LAB_REPO"/app/rayfin-starter/packages/* packages/

# 4. Three edits
#  a) packages/functions/src/function_app.ts – set the two values in the "SET THESE TWO VALUES" block:
#     FOUNDRY_PROJECT_ENDPOINT, FOUNDRY_AGENT_NAME (both in the lab repo .env)
#  b) packages/frontend/src/services/railClient.ts – CHECK the import matches the template's client module.
#     It's set to '../lib/rayfin-client' (where the 1.36 default template puts getRayfinClient). Confirm with:
grep -rl "export.*getRayfinClient" packages/frontend/src
#     Expected: packages/frontend/src/lib/rayfin-client.ts (ignore the railClient.ts match). If it's elsewhere,
#     change the import to that path relative to services/, without .ts.
#  c) packages/frontend/src/App.tsx – show the rail app instead of the welcome page:
#     replace   import { EmptyStatePreview } from './EmptyStatePreview';   with   import { RailApp } from './RailApp';
#     replace   <EmptyStatePreview />                                       with   <RailApp />
#     Leave everything else in App.tsx (the auth gate, theme and error boundary) as it is.

# 5. Set up the local functions host and generate the function types
npx rayfin dev functions apply
#    Checks Node.js and Azure Functions Core Tools (offers to install Core Tools if missing), builds packages/functions,
#    generates packages/functions/src/types.ts and starts the local functions host. Needs the step 1b `rayfin up`.
#    Leave it running until it prints a [typegen] line AND the function URLs for askRailAgent and getMapAuth
#    (not helloWorld). Then, in a SECOND terminal, check the generated types before you stop it:
#      bash:        grep -E "askRailAgent|helloWorld" packages/functions/src/types.ts
#      PowerShell:  Select-String -Path packages\functions\src\types.ts -Pattern "askRailAgent|helloWorld"
#    You should see askRailAgent (and getMapAuth, used only by optional Lab 11b) and NOT helloWorld. Then Ctrl+C the first terminal.
#    Run it first: `npm run dev` on its own can stop with "functions not installed" until this has run once.
npm run dev                     # optional: full local loop (frontend + functions) to try the app before deploying
npm run validate:functions      # askRailAgent and getMapAuth must be listed in AppFunctionsSchema
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
> delete `rayfin/functions/`. Then do steps 2–6 above (including the connector). `rayfin up` updates the same App item.

`npm test` runs the template's own tests, which expect the welcome page. Update or delete `App.spec.tsx` and `Root.spec.tsx`
welcome assertions if you run them; the deploy doesn't need them.

The details are in [`app/README.md`](../../app/README.md).

## Option B – manual walkthrough (what the overlay code does)

1. **Client.** The template creates one authenticated `RayfinClient` (`getRayfinClient()`). The functions pack wires the
   generated `AppFunctionsSchema` into it, and the connectors pack plus `connector add` wire the `railmap` connector
   (`packages/frontend/src/lib/connectors.ts`). `services/railClient.ts` returns `client.functions` and `client.connectors.railmap`.
2. **Map data.** `loadSnapshot.ts` sends a **fixed** DAX query to `railmap.executeQuery` – `SELECTCOLUMNS(FILTER('TrainPositions',
   [event_time] >= NOW() - <minutes>/1440 …))` – with a 5,000-row guard. Only the look-back (validated, 5–240 minutes) is
   inserted, so users can't send arbitrary DAX. DirectQuery turns it into KQL against `NetworkSnapshot(4h)` in `RailKQL`.
   The connector is **delegated**, so it runs as the signed-in user. Errors come back as `status: 'error'` with a category
   (`api`, `query`, `overflow`, `network`) and a `requestId`, which the map shows.
3. **Map.** `NetworkMap.tsx` projects lat/lon onto an SVG of GB and colours each dot:
   green is on time, amber is late, red is 15 minutes or more late. It refreshes every 30 seconds.
4. **Chat function.** `askRailAgent` declares the audience in its context type – `RayfinContext<RailSchema, AudienceType.AzureAI>` –
   reads `ctx.Tokens.AzureAI`, and calls the Foundry agent. (`ctx.getToken()` and `udf.connection()` are deprecated in 1.36 and
   don't type-check any more.)
   **TODO(verify)**: the REST path and body (`POST {project}/openai/v1/responses` with `agent_reference`). Check them against
   <https://ai.azure.com/api-reference/responses/>.
5. **Chat UI.** `ChatPanel.tsx` calls `askRailAgent.invoke({ question })` and shows any error message.

## Checkpoint

* The deployed app URL (printed by `rayfin up`) opens inside Fabric SSO.
* The chat panel answers "Which trains are 15+ minutes late?"
* The map shows trains, and the count in the heading changes as trains move (within about 30 seconds).
* The page shows the attribution text. The app isn't described as "official", and it uses no Network Rail or National Rail logos.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connector type "kusto" is not available in this release` | Expected in Rayfin 1.36.2. The map uses the Lab 10b semantic model through the `fabric-semanticmodel` connector instead |
| `rayfin up` fails with **403 Forbidden – The feature is not available** (at *createRayfinItem*) | Fabric can't create an App item there. Check **+ New item → App (preview)** in the workspace. If it's missing: 1) ask a Fabric admin to enable *Admin portal > Tenant settings > Fabric Apps (preview)* for you, then wait a few minutes; 2) if the setting is already on, your capacity region isn't supported. Deploy to a workspace on a capacity in a supported region (see [above](#if-app-preview-isnt-available-in-your-region)). Also check the capacity is running, not paused |
| Any other 401/403 on deploy | `npx rayfin login`, then `npx rayfin up` again |
| `npm run build` / `rayfin dev functions apply` fails with **TS1002: Unterminated string literal** in `src/function_app.ts(<line>,…)` | A quote was lost when you pasted a value into the "SET THESE TWO VALUES" block. The line number points at the value you edited. Each line must look like `const FOUNDRY_PROJECT_ENDPOINT = 'https://….services.ai.azure.com/api/projects/…';` – a single quote at both ends, then `;`. Don't paste the `.env` line or its quotes |
| The chat says *FOUNDRY_PROJECT_ENDPOINT isn't set* | The value is still the `PASTE-…` placeholder or isn't an `https://` URL. Fix it in `function_app.ts`, then `npx rayfin up` again |
| Deployed app shows the Rayfin **welcome / blueprint** page, or only a **hello-world** function | The overlay went to the old flat paths (`src/`, `rayfin/functions/`), which the default template doesn't build. Follow Option A: `npm run pack:add -- functions`, copy `packages/*` onto `packages/`, edit `App.tsx` and `railClient.ts`, then `npm run rayfin:up` |
| PowerShell: *Copy-Item: An item with the specified name …\\packages\\frontend already exists* | `Copy-Item` doesn't merge folders. Use the `robocopy … /E` command above (or Git Bash `cp -r`). Then check `packages/frontend/src/RailApp.tsx` and `packages/frontend/src/services/railClient.ts` exist, and `packages/functions/src/function_app.ts` contains `askRailAgent` |
| `Cannot find module '../lib/rayfin-client'` in `railClient.ts` | Your template keeps the client elsewhere. Point the import at the file that `grep -rl "export.*getRayfinClient" packages/frontend/src` prints (relative to `services/`, no `.ts`) |
| Build fails: *Property 'Kusto' does not exist on type 'typeof AudienceType'* and/or *Argument of type 'AudienceType.AzureAI' is not assignable to parameter of type 'never'* | You have the older `function_app.ts`, written for `ctx.getToken()`. Rayfin 1.36.2 has no Kusto audience, and `getToken()` no longer type-checks. Copy the current `function_app.ts` from the repo (it uses `ctx.Tokens.AzureAI`; the map no longer uses a function), set the values again, then rerun `npx rayfin dev functions apply` |
| `Property 'railmap' does not exist` (on `client.connectors`), or `connectors` doesn't exist on the client | The connector isn't wired. Check `npm run pack:add -- connectors` ran, `connector add` used `--name railmap`, its printed `npm install` ran in `@rayfin-app/frontend`, and `packages/frontend/src/lib/connectors.ts` lists `railmap` in its schema, config and runtime maps. If you named it differently, use that name in `railClient.ts` |
| Map: *Map query failed (api)* with 401/403 | The signed-in user lacks **Build** on `RailLiveMap` (Lab 10b, step 5), or – if the model uses SSO – **Viewer** on `RailKQL`. Or the *Semantic Model Execute Queries REST API* tenant setting is off |
| Map: *Map query failed (query)* … `TrainPositions` / column not found | The model's table or column names differ. Set `MODEL_TABLE` in `loadSnapshot.ts`, and check the columns match `NetworkSnapshot()` (Lab 10b) |
| Map: *Map query failed (overflow)* | More than 5,000 rows or an unsafe number. Lower the look-back, or raise `resultSetRowCountLimit` in `loadSnapshot.ts` |
| Map works locally but shows 0 trains | No movements in the look-back window, or the model's credentials expired. Check the Lab 10b checkpoint query |
| `rayfin dev functions apply`: *No active deployment found. Run 'rayfin up' to deploy your Rayfin item first* | This project has no active deployment recorded in `rayfin/.deployments.json` (step 1b skipped, the file was deleted, or the project was re-scaffolded). Run `npx rayfin up list`. If your App item is listed, make it active: `npx rayfin up switch --workspace-id <workspace-guid>`. If nothing is listed, deploy once: `npx rayfin up --workspace-id <workspace-guid>` (it reuses the App item with the same name). If that fails while building the frontend, add `--exclude-services staticHosting`, run step 5, then a full `npx rayfin up` |
| `rayfin up`: *Workspace "rail-fabric-rti" not found* | The project is pointing at a workspace name that doesn't exist (for example you deployed to an app workspace with another name, Lab 11 region workaround). Pass the target explicitly – flags win: `npx rayfin up --workspace-id <workspace-guid>` (or `--workspace "<exact name>"`, or `--workspace-uri <workspace URL>`). After one successful deploy it's recorded in `rayfin/.deployments.json`. To find where the old name is stored: `Select-String -Path package.json,rayfin\.env,rayfin\rayfin.yml -Pattern rail-fabric-rti` (bash: `grep -rn rail-fabric-rti package.json rayfin/`), and change it there. You can also set `RAYFIN_WORKSPACE_ID` in your shell |
| `DeprecationWarning: [DEP0190] Passing args to a child process with shell option true` | A Node.js warning from inside the Rayfin CLI. Harmless – ignore it |
| `npm run dev` says functions aren't installed | Run `npx rayfin dev functions apply` once from the project root (step 5). It checks/installs Azure Functions Core Tools, builds `packages/functions` and generates the types. Then `npm run dev` works |
| `validate:functions` fails: *Generated AppFunctionsSchema is stale … "askRailAgent" … missing from types.ts* and *"helloWorld" remains* | `types.ts` was generated from the starter function and hasn't been regenerated since you copied in the rail functions – usually because an earlier `functions apply` failed to build (for example the TS1002 quote error) or was stopped too soon. Run `npx rayfin dev functions apply` again and leave it running until the `[typegen]` line appears and lists the rail functions; check `types.ts` as in step 5, then stop it. If `types.ts` still shows `helloWorld`, save `function_app.ts` once more while the session is running (the watcher regenerates on change), and read the diagnostic log path it prints. Never edit `types.ts` by hand |
| `functions.askRailAgent` isn't typed in the frontend | Same cause as above: regenerate `types.ts` with `npx rayfin dev functions apply`, then `npm run typecheck` |
| `pack:add` says `functions` is unknown, or there's no `packages/` folder | You chose a flat (older) template. Either re-scaffold with the default template, or copy `packages/frontend/src/*` into `src/` and `packages/functions/src/function_app.ts` into `rayfin/functions/src/` (after `npx rayfin functions init`), and create the client yourself as in <https://rayfin.ai/docs/functions/calling-functions> |
| Chat shows *InternalError: An internal execution error occured during function execution* | You have an older `function_app.ts` whose `askRailAgent` throws; deployed functions hide the reason. Copy the current file (re-enter your Foundry values), redeploy, and ask again – the chat now shows **Agent error (…)** with the real cause. Most common causes below |
| Chat: *Agent error (setup): FOUNDRY_PROJECT_ENDPOINT isn't set* | The Foundry values were reset to `PASTE-…` when you re-copied `function_app.ts`. Re-enter them (Lab 10 step 1.4) and `npx rayfin up` |
| Chat: *Agent error (HTTP 401/403)* | The deployed function runs as the **app identity** (the App item's owner). Give that account **Foundry User** on the Foundry project, and check it can chat with the agent in the Foundry playground |
| Chat: *Agent error (HTTP 404)* | `FOUNDRY_AGENT_NAME` doesn't match the agent in the project (names are case-sensitive), or the endpoint points at another project |
| Chat: *Agent error (HTTP 400)* mentioning `background` | The agent's model doesn't support background mode – switch it to gpt-5.4/5.5 (Lab 10) |
| Chat answers fail when deployed, but work with `npm run dev` | Deployed functions use the **app identity**, while the Lab 10 Fabric IQ connection runs as a **user** (`UserEntraToken`). The app identity is the App item's owner, so check that account can use the agent in the playground. Otherwise use the Foundry playground for chat |
| Chat times out or returns a partial answer | The function calls the agent synchronously, and data agent questions can take a while. Ask a narrower question (shorter time window). The Lab 10 playground and script use background mode for long questions |
| Calls fail locally with HTTP 502 | The local Functions host isn't running. Use `npm run dev`, or `npx rayfin dev functions apply` plus `npm run dev:frontend`, from the project root |
| Functions not available | Your tenant or region doesn't have them yet. The map still works (it uses the connector); use the Foundry playground for chat |
| Map empty but `NetworkSnapshot(1h)` returns rows | `Locations.lat/lon` is missing (re-run Lab 03 with NaPTAN), or the Lab 10b checkpoint query returns nothing |
| The app folder shows up in `git status` of the lab repo | It was created inside the repo. Move it next to the repo, or rely on the `rail-app/` entry in `.gitignore` |
