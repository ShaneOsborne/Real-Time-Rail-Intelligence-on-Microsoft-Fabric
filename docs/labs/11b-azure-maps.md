# Lab 11b – Azure Maps basemap, satellite view and railway lines (optional)

**Time:** 45 minutes (plus a one-off 4 GB download if the railway file isn't in the repo yet) · **Previous:** [Lab 11](11-rayfin-app.md) · **Next:** [Lab 12](12-cleanup.md)

> **Path:** Optional, after Lab 11 works. Solo ✅ · Instructor: do steps 1–2 once for the class (or per student) ·
> Classroom student: only if your instructor gives you an Azure Maps token.

## What you'll build

Lab 11's simple SVG map becomes a proper map:

* **Azure Maps** basemap with a style picker: grayscale, road, night, **satellite** and satellite with labels. Zoom and pan.
* **GB railway lines** from **OS Open Zoomstack** (Ordnance Survey, Open Government Licence) drawn on top – tunnels dashed.
* The same live trains (Lab 10b semantic model → `loadSnapshot`), coloured by delay, with a pop-up on click. Refresh every 30 s.

```
Browser ─ Azure Maps tiles (SAS token from the getMapAuth function) ─┐
        ─ gb-rail.geojson (bundled with the app, OS Open Zoomstack)  ─┼─► one map
        ─ trains: railmap connector → RailLiveMap → RailKQL (Lab 11)  ─┘
```

If the Azure Maps token isn't set, the app falls back to the Lab 11 map automatically.

## How the app signs in to Azure Maps

Browsers can't safely hold an Azure Maps **key**, so the lab uses a **SAS token**, which Azure Maps designs for this:

* It's tied to a managed identity that only has **Azure Maps Search and Render Data Reader** (map tiles, nothing else).
* It's **rate-limited** (the script sets about 50 requests/second), which also caps cost.
* It **expires within 24 hours** – the maximum Azure Maps allows. You create a new one each day you use the app (step 6).

The token is stored as a Rayfin secret (`AZURE_MAPS_TOKEN`), and the `getMapAuth` function hands it to **signed-in** app
users only. Locking the Maps account's CORS to your app's address adds a little more protection (CORS isn't authorisation,
just a browser rule). Source: [Azure Maps authentication](https://learn.microsoft.com/azure/azure-maps/azure-maps-authentication).

## Costs and data

* Azure Maps **Gen2** is pay-as-you-go: map tiles (including satellite) are billed per transaction after a monthly free
  allowance. A class panning and zooming all day adds up – check [Azure Maps pricing](https://azure.microsoft.com/pricing/details/azure-maps/)
  and set an Azure budget alert. The 30-second train refresh doesn't reload tiles.
* Railway lines: *Contains OS data © Crown copyright and database right* – shown under the map (OGL v3.0).
* Map requests go to the Azure Maps account's geography. Pick its location in step 1.

## Prerequisites

* Lab 11 works (map and chat), and you know your app's **static hosting URL** (`npx rayfin up status --json` → `hostingUrl`).
* Azure: Contributor plus User Access Administrator (or Owner) on the resource group (Lab 01 §3), and `az login`.
* Only if the railway file isn't in the repo yet (step 2): Python 3.11+ and about 20 GB of free disk space.

## 1. Create the Azure Maps account (once)

1. Pick the location. Check where Azure Maps accounts can go in your subscription:

   ```bash
   az provider register -n Microsoft.Maps --wait
   az provider show -n Microsoft.Maps --query "resourceTypes[?resourceType=='accounts'].locations" -o tsv
   ```

   Use `uksouth` if it's listed; otherwise a nearby one such as `northeurope` or `westeurope`.
2. In the lab repo `.env`:

   ```bash
   AZURE_MAPS_LOCATION=uksouth          # from the list above
   AZURE_MAPS_ALLOWED_ORIGINS=https://<your-app>.webapp.fabricapps.net,http://localhost:5173
   ```

3. Run (from the lab repo root):

   ```bash
   ./scripts/create-azure-maps.sh        # PowerShell: ./scripts/create-azure-maps.ps1
   ```

   It deploys `infra/azuremaps.bicep` (Gen2 Maps account + user-assigned identity `<prefix>-maps-sas-id`, CORS rule) and
   gives the identity **Azure Maps Search and Render Data Reader** on the account. Copy the two printed values
   (`AZURE_MAPS_ACCOUNT_NAME`, `AZURE_MAPS_SAS_PRINCIPAL_ID`) into `.env`.

*Portal alternative:* create a user-assigned managed identity, then an **Azure Maps** account (pricing tier Gen2) in the same
region with that identity attached; on the Maps account → **Access control (IAM)**, give the identity *Azure Maps Search and
Render Data Reader*; and under **CORS** add your app URL.

## 2. The railway-lines file (once per repo)

Check whether the repo already has it:
`app/rayfin-maps-addon/packages/frontend/public/data/gb-rail.geojson`. If it does, skip to step 3.

If not, build it once and commit it (instructor or repo maintainer):

```bash
python -m venv .venv && source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r app/tools/requirements.txt
python app/tools/build_gb_rail.py                         # downloads OS Open Zoomstack (~4.3 GB zip) into data/zoomstack/
# already downloaded?  python app/tools/build_gb_rail.py --gpkg <path>/OS_Open_Zoomstack.gpkg
git add app/rayfin-maps-addon/packages/frontend/public/data/gb-rail.geojson
```

The script reads the Zoomstack `rail` layer (Multi Track, Single Track, Tunnel; add `--include-narrow-gauge` for heritage
lines), simplifies it to about 15 m, converts it from British National Grid to latitude/longitude, and writes a compact GeoJSON.
If the file is larger than about 10 MB, re-run with `--tolerance 30`. `data/` is git-ignored, so the big download isn't committed.
You can also download Zoomstack by hand from the [OS Data Hub](https://osdatahub.os.uk/data/downloads/open/OpenZoomstack) (GeoPackage).

## 3. Add the map to your app

From your `rail-app` folder:

```bash
npm install -w @rayfin-app/frontend azure-maps-control
cp -r "$LAB_REPO"/app/rayfin-maps-addon/packages/* packages/
```

PowerShell: `robocopy "$env:LAB_REPO\app\rayfin-maps-addon\packages" packages /E /NJH /NJS /NDL` (exit code 1 = copied).

This adds `AzureNetworkMap.tsx`, `mapAuth.ts`, `public/data/gb-rail.geojson`, and replaces `RailApp.tsx` (no settings in it).

**The `getMapAuth` function.** `packages/functions/src/function_app.ts` in the lab repo now ends with a `getMapAuth`
function. Either copy the new file again and re-enter your two Foundry values, or paste the block that starts
`// ---- Lab 11b (optional): Azure Maps credential` at the end of your file.

## 4. Create today's SAS token and store it as a Rayfin secret

```bash
# in the LAB REPO folder: prints a token valid for 24 hours, ~50 requests/second
./scripts/new-azure-maps-sas.sh              # PowerShell: ./scripts/new-azure-maps-sas.ps1
```

Copy the token (it starts `eyJ`). Then in your **rail-app** folder:

```bash
npx rayfin secret set AZURE_MAPS_TOKEN --describe="Azure Maps SAS token for the live map (expires within 24 hours)"
```

The CLI asks for the value – paste the token. (If your CLI version expects the value differently, check
`npx rayfin secret set --help`.) The value is stored in the deployed app, not in `rayfin.yml`.

For local runs (`npm run dev`), also add it to `packages/functions/local.settings.json` under `Values`:
`"AZURE_MAPS_TOKEN": "eyJ…"`. That file is git-ignored.

## 5. Generate types, check and deploy

```bash
npx rayfin dev functions apply     # wait for [typegen] and the getMapAuth URL, then Ctrl+C
npm run validate:functions && npm run typecheck && npm run build
npx rayfin up
```

## 6. Every day you use the app

The SAS token expires within 24 hours. Each morning, repeat **step 4** (new token → `npx rayfin secret set AZURE_MAPS_TOKEN`).
No redeploy is needed: the map asks `getMapAuth` for the current token. For a long-running demo, automate it with a scheduled
job that runs `new-azure-maps-sas` and updates the secret (not scripted here).

## Checkpoint

* The map opens on **grayscale**, with purple railway lines across GB and coloured train dots.
* The style picker (top right) switches to **satellite**; zoom into Leeds or York and the tracks line up with the imagery.
* Clicking a train shows its ID, location, status and delay. The count updates about every 30 seconds.
* The OS and data attribution lines are visible under the map.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App still shows the simple map | `getMapAuth` returned *not configured*: the secret isn't set (step 4), or the deployed function is old (step 5). Locally: add `AZURE_MAPS_TOKEN` to `local.settings.json` |
| Map area stays blank / tiles 401 or 403 | The SAS token expired (step 6), or the identity's role is missing (re-run `create-azure-maps`), or the request's origin isn't in the CORS list – add your exact app URL to `AZURE_MAPS_ALLOWED_ORIGINS` and re-run step 1 |
| Browser console: *Refused to load … violates the Content Security Policy* | Rayfin's hosting is blocking Azure Maps (`atlas.microsoft.com`) or the map's web workers (`blob:`). Not something the app can change; remove the secret (`npx rayfin secret delete AZURE_MAPS_TOKEN`) to return to the simple map, and report it to Rayfin |
| HTTP 429 in the console | The SAS rate limit was reached. Create a token with a higher limit: `./scripts/new-azure-maps-sas.sh 24 100` (PowerShell `-MaxRatePerSecond 100`) |
| *Railway lines file not found* | `public/data/gb-rail.geojson` is missing from your app – do step 2, then step 3 again |
| Satellite styles missing from the picker | The Maps account isn't Gen2 (the Bicep creates Gen2). Check the pricing tier in the portal |
| `create-azure-maps` fails: location not available | Choose a location from the `az provider show` list in step 1 for `AZURE_MAPS_LOCATION` |
| `Cannot find module 'azure-maps-control'` | Run `npm install -w @rayfin-app/frontend azure-maps-control` in `rail-app` |
| `functions.getMapAuth` isn't typed / `validate:functions` fails | The function isn't in `function_app.ts`, or types weren't regenerated – step 3, then `npx rayfin dev functions apply` |
| Vite warns about a large chunk | Expected: the Azure Maps library is big. Harmless |
| `build_gb_rail.py`: *No .gpkg file found* / out of disk | The zip needs ~4.3 GB and the GeoPackage ~12 GB. Free space, delete `data/zoomstack/` and re-run, or download by hand and use `--gpkg` |

## Clean-up

The Maps account and its identity are in `AZ_RESOURCE_GROUP`, so [Lab 12](12-cleanup.md) removes them. To remove only this
lab: delete the Maps account and the `<prefix>-maps-sas-id` identity, and run `npx rayfin secret delete AZURE_MAPS_TOKEN`.
