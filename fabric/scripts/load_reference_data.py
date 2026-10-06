"""Lab 03 Option A: download NROD reference data (CORPUS, SMART) and NaPTAN rail stations,
build a `locations` table (STANOX/TIPLOC/CRS -> name, lat/lon) and load it.

Targets (combine as needed):
    --to-kql      ingest Locations into the KQL database with `.ingest inline` (chunked)
    --to-onelake  upload CSVs to the Lakehouse Files area and call the Lakehouse "Load Table" API (preview)

Examples:
    python fabric/scripts/load_reference_data.py --download-only
    python fabric/scripts/load_reference_data.py --to-kql --to-onelake

Sources (verified on the Open Rail Data wiki / data.gov.uk):
    CORPUS https://publicdatafeeds.networkrail.co.uk/ntrod/SupportingFileAuthenticate?type=CORPUS
    SMART  https://publicdatafeeds.networkrail.co.uk/ntrod/SupportingFileAuthenticate?type=SMART
    NaPTAN https://naptan.api.dft.gov.uk/v1/access-nodes?dataFormat=csv   (OGL v3.0)
Rail stations in NaPTAN use ATCO codes of the form 9100<TIPLOC>.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "data"
NROD_BASE = "https://publicdatafeeds.networkrail.co.uk/ntrod/SupportingFileAuthenticate?type="
NAPTAN_URL = "https://naptan.api.dft.gov.uk/v1/access-nodes?dataFormat=csv"
LOC_COLS = ["stanox", "tiploc", "crs", "nlc", "name", "lat", "lon"]


def load_dotenv() -> None:
    env = REPO / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def maybe_gunzip(raw: bytes) -> bytes:
    return gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw


def first_list(doc: Any) -> list[dict[str, Any]]:
    """CORPUS/SMART files are a JSON object wrapping one array (e.g. TIPLOCDATA / BERTHDATA)."""
    if isinstance(doc, list):
        return doc
    for v in doc.values():
        if isinstance(v, list):
            return v
    raise ValueError("No array found in reference file")


def clean(v: Any) -> str:
    return "" if v is None else str(v).strip()


def download_nrod(dataset: str, user: str, password: str) -> list[dict[str, Any]]:
    import requests

    print(f"Downloading {dataset} ...", flush=True)
    r = requests.get(NROD_BASE + dataset, auth=(user, password), timeout=300, allow_redirects=True)
    r.raise_for_status()
    raw = maybe_gunzip(r.content)
    (DATA / f"{dataset.lower()}.json").write_bytes(raw)
    return first_list(json.loads(raw))


def download_naptan_rail() -> dict[str, tuple[float, float, str]]:
    import requests

    print("Downloading NaPTAN (~100 MB) ...", flush=True)
    r = requests.get(NAPTAN_URL, timeout=600)
    r.raise_for_status()
    out: dict[str, tuple[float, float, str]] = {}
    for row in csv.DictReader(io.StringIO(r.content.decode("utf-8-sig"))):
        atco = row.get("ATCOCode", "")
        if row.get("StopType") == "RLY" and atco.startswith("9100"):
            try:
                out[atco[4:]] = (float(row["Latitude"]), float(row["Longitude"]), row.get("CommonName", ""))
            except (KeyError, ValueError):
                continue
    print(f"  {len(out)} rail stations with coordinates")
    return out


def build_locations(corpus: list[dict[str, Any]], coords: dict[str, tuple[float, float, str]]) -> list[dict[str, Any]]:
    rows = []
    for c in corpus:
        stanox, tiploc = clean(c.get("STANOX")), clean(c.get("TIPLOC"))
        if not stanox and not tiploc:
            continue
        lat, lon, _ = coords.get(tiploc, (None, None, ""))
        rows.append(
            {
                "stanox": stanox,
                "tiploc": tiploc,
                "crs": clean(c.get("3ALPHA")),
                "nlc": clean(c.get("NLC")),
                "name": clean(c.get("NLCDESC")),
                "lat": lat,
                "lon": lon,
            }
        )
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]], cols: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {path} ({len(rows)} rows)")


def to_kql(rows: list[dict[str, Any]], uri: str, database: str, chunk: int = 5000) -> None:
    from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

    client = KustoClient(KustoConnectionStringBuilder.with_az_cli_authentication(uri))
    client.execute_mgmt(database, ".clear table Locations data")
    for i in range(0, len(rows), chunk):
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        for r in rows[i : i + chunk]:
            w.writerow(["" if r[c] is None else r[c] for c in LOC_COLS])
        client.execute_mgmt(database, ".ingest inline into table Locations <|\n" + buf.getvalue())
        print(f"  ingested {min(i + chunk, len(rows))}/{len(rows)}")


def to_onelake(files: dict[str, Path], workspace_id: str, lakehouse_id: str) -> None:
    import requests
    from azure.identity import AzureCliCredential
    from azure.storage.filedatalake import DataLakeServiceClient

    cred = AzureCliCredential()
    svc = DataLakeServiceClient("https://onelake.dfs.fabric.microsoft.com", credential=cred)
    fs = svc.get_file_system_client(workspace_id)
    token = cred.get_token("https://api.fabric.microsoft.com/.default").token
    for table, path in files.items():
        rel = f"Files/reference/{path.name}"
        print(f"Uploading {path.name} -> {rel}")
        fs.get_file_client(f"{lakehouse_id}/{rel}").upload_data(path.read_bytes(), overwrite=True)
        url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/lakehouses/{lakehouse_id}/tables/{table}/load"
        body = {"relativePath": rel, "pathType": "File", "mode": "Overwrite", "recursive": False,
                "formatOptions": {"format": "Csv", "header": True, "delimiter": ","}}
        r = requests.post(url, json=body, headers={"Authorization": f"Bearer {token}"}, timeout=60)
        if r.status_code not in (200, 201, 202):
            raise RuntimeError(f"Load table {table} failed: {r.status_code} {r.text}")
        op = r.headers.get("Location")
        while op:
            time.sleep(int(r.headers.get("Retry-After", "5")))
            r = requests.get(op, headers={"Authorization": f"Bearer {token}"}, timeout=60)
            status = r.json().get("status", "")
            print(f"  load {table}: {status}")
            if status in ("Succeeded", "Failed"):
                break
        print(f"  table '{table}' loaded")


def main() -> int:
    load_dotenv()
    p = argparse.ArgumentParser()
    p.add_argument("--download-only", action="store_true")
    p.add_argument("--to-kql", action="store_true")
    p.add_argument("--to-onelake", action="store_true")
    p.add_argument("--skip-naptan", action="store_true", help="No coordinates (faster)")
    a = p.parse_args()

    user, pw = os.getenv("NROD_USERNAME"), os.getenv("NROD_PASSWORD")
    if not user or not pw:
        print("ERROR: NROD_USERNAME / NROD_PASSWORD required (subscribe to 'All Reference Data' in My Feeds)", file=sys.stderr)
        return 2
    DATA.mkdir(exist_ok=True)

    corpus = download_nrod("CORPUS", user, pw)
    smart = download_nrod("SMART", user, pw)
    coords = {} if a.skip_naptan else download_naptan_rail()
    locations = build_locations(corpus, coords)

    loc_csv, smart_csv = DATA / "locations.csv", DATA / "smart_berths.csv"
    write_csv(loc_csv, locations, LOC_COLS)
    smart_cols = sorted({k for r in smart for k in r})
    write_csv(smart_csv, [{k: clean(v) for k, v in r.items()} for r in smart], smart_cols)
    print(f"Locations with coordinates: {sum(1 for r in locations if r['lat'] is not None)}")

    if a.download_only:
        return 0
    if a.to_kql:
        uri = os.getenv("KUSTO_QUERY_URI")
        if not uri:
            print("ERROR: KUSTO_QUERY_URI not set", file=sys.stderr)
            return 2
        to_kql(locations, uri, os.getenv("FABRIC_KQL_DATABASE_NAME", "RailKQL"))
    if a.to_onelake:
        ws, lh = os.getenv("FABRIC_WORKSPACE_ID"), os.getenv("FABRIC_LAKEHOUSE_ID")
        if not ws or not lh:
            print("ERROR: FABRIC_WORKSPACE_ID and FABRIC_LAKEHOUSE_ID required", file=sys.stderr)
            return 2
        to_onelake({"locations": loc_csv, "smart_berths": smart_csv}, ws, lh)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
