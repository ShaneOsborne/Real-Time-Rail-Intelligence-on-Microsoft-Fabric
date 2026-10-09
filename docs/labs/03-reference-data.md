# Lab 03 – Reference data (CORPUS, SMART, NaPTAN)

**Time:** 30 minutes · **Previous:** [Lab 02](02-fabric-workspace.md) · **Next:** [Lab 04](04-rdm-kafka-eventstream.md)

## Objectives

* Download static reference data with your NROD credentials.
* Build a **`locations`** table that maps STANOX, TIPLOC, CRS and NLC codes to a name, latitude and longitude, plus **`smart_berths`**.
* Load it into the **Lakehouse** (Delta) and the KQL **`Locations`** table, so live movements can be enriched.

## Sources (verified on the Open Rail Data wiki)

| Dataset | URL | Notes |
|---|---|---|
| CORPUS | `https://publicdatafeeds.networkrail.co.uk/ntrod/SupportingFileAuthenticate?type=CORPUS` | JSON (may be gzip-compressed). STANOX, UIC, 3ALPHA (CRS), TIPLOC, NLC, NLCDESC, NLCDESC16 |
| SMART | `https://publicdatafeeds.networkrail.co.uk/ntrod/SupportingFileAuthenticate?type=SMART` | TD berth stepping → STANOX |
| SCHEDULE (optional) | `https://publicdatafeeds.networkrail.co.uk/ntrod/CifFileAuthenticate?type=CIF_ALL_FULL_DAILY&day=toc-full` | Daily JSON (gzip). Add `.CIF.gz` handling for CIF |
| BPLAN (optional) | Files are hosted on the Open Rail Data wiki (*Train Planning data (BPLAN)* page) | Released twice a year. Not used by these labs |
| NaPTAN | `https://naptan.api.dft.gov.uk/v1/access-nodes?dataFormat=csv` | About 100 MB. Rail stations have `StopType = RLY` and an ATCO code of `9100<TIPLOC>` |

All of these need **basic auth** with your NROD login and the *All Reference Data* subscription. NaPTAN doesn't need auth.

## Option A1 – automated from your machine

```bash
python -m venv .venv && source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r fabric/scripts/requirements.txt
az login
# Lab 06 must have created the Locations table first if you use --to-kql:
python fabric/scripts/apply_kql.py --file fabric/kql/01_tables.kql
python fabric/scripts/load_reference_data.py --to-kql --to-onelake
```

* `--to-kql` clears `Locations`, then ingests it in 5,000-row chunks with `.ingest inline`.
* `--to-onelake` uploads CSVs to `Files/reference/` in the Lakehouse (OneLake ADLS Gen2 endpoint) and calls the
  **Lakehouse Load Table** REST API (*preview*) to create the Delta tables `locations` and `smart_berths`.
* Downloads are saved under `data/`, which is git-ignored.

## Option A2 – automated inside Fabric (notebook)

1. In the workspace: **Import** → **Notebook** → **From this computer** → `fabric/notebooks/01_load_reference_data.ipynb`.
2. Attach **RailLakehouse** as the default lakehouse.
3. In the parameters cell, give the notebook your NROD credentials in one of two ways:
   * **Recommended – Key Vault.** Set `KEY_VAULT_URL` to the vault you created in
     [Lab 01, step 8](01-prerequisites.md#8-shared-key-vault-for-credentials-needed-from-lab-03) (the `KEY_VAULT_URL` value in `.env`).
     The notebook reads `nrod-username` and `nrod-password` with `notebookutils.credentials.getSecret`, using **your** identity.
     You already have *Key Vault Secrets Officer* if you created the vault; anyone else running the notebook needs at least
     *Key Vault Secrets User* on it.
   * **No Key Vault yet.** Leave `KEY_VAULT_URL` empty and type `NROD_USERNAME` / `NROD_PASSWORD` into the parameters cell
     **for this session only**. Clear them before you save or schedule the notebook. (A scheduled run needs the Key Vault option.)
4. **Run all**. Then load KQL `Locations` from the Lakehouse table:
   * In `RailKQL`: **+ New** → **OneLake shortcut** → *Microsoft OneLake* → `RailLakehouse` → *Tables* → `locations`.
   * Run `fabric/kql/05_reference_from_shortcut.kql`, which uses `.set-or-replace Locations <| external_table("locations") ...`.

Optional schedule: in the notebook, use **Run** → **Schedule** (daily). CORPUS and SMART change rarely, so weekly is fine.
An Azure Function on a timer is also suitable for this daily pull. A long-running host isn't needed.

## Option B – manual

1. In a browser that's signed in to the NROD portal, open the CORPUS and SMART URLs above and save the files.
2. Download the NaPTAN CSV from the URL above.
3. Lakehouse → **Files** → **Upload** the files. Then either run the notebook cells one by one (recommended) or
   use **Load to Tables** on a CSV you produced with `load_reference_data.py --download-only`.
4. Create the OneLake shortcut and run `05_reference_from_shortcut.kql` as in A2.

## Checkpoint

```kusto
Locations | summarize rows = count(), with_coords = countif(isnotnull(lat))
Locations | where crs in ("KGX", "LDS", "EDB", "MAN")
```

You should see tens of thousands of rows, and a few thousand with coordinates (stations only).

## Troubleshooting

| Symptom | Fix |
|---|---|
| HTTP 401/403 from `SupportingFileAuthenticate` | Subscribe to **All Reference Data** in *My Feeds*. Check the account is active |
| `json.decoder.JSONDecodeError` | The file was gzip-compressed or HTML (a login page). The script auto-detects gzip; HTML means an auth failure |
| Few or no coordinates | NaPTAN covers passenger stations only. Junctions and yards have no lat/lon. That's expected |
| `.ingest inline` throttled | Re-run. Lower `chunk` in `to_kql()` |
| Load Table API error | It's a preview API. Use the notebook path instead |
| `getSecret` fails with *Forbidden* / 403 | Your user lacks a Key Vault data role. Add *Key Vault Secrets User* (or *Officer*) on the vault and wait a few minutes |
| `getSecret` fails with a name/URL error | `KEY_VAULT_URL` must be the full Vault URI, e.g. `https://<name>.vault.azure.net/` |
