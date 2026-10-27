"""Lab 11b: build the GB railway-lines overlay for the Rayfin map from OS Open Zoomstack.

Reads the `rail` layer of the OS Open Zoomstack GeoPackage (British National Grid, EPSG:27700), keeps the
types the map draws, simplifies the lines, reprojects to WGS84 and writes a compact GeoJSON for the app:

    app/rayfin-maps-addon/packages/frontend/public/data/gb-rail.geojson

Run it ONCE (maintainer or instructor) and commit the output; lab users just copy it.

    python -m venv .venv && source .venv/bin/activate        # Windows: .venv\\Scripts\\activate
    pip install -r app/tools/requirements.txt
    python app/tools/build_gb_rail.py                          # downloads Zoomstack (~4.3 GB zip) to data/zoomstack/
    python app/tools/build_gb_rail.py --gpkg path/to/OS_Open_Zoomstack.gpkg   # if you already have it

Licence: OS Open Zoomstack is under the Open Government Licence v3.0. The app must show
"Contains OS data © Crown copyright and database right <year>". Layer `rail` has a `type` of
Multi Track, Single Track, Narrow Gauge or Tunnel (OS Open Zoomstack technical specification).
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DOWNLOAD_URL = "https://api.os.uk/downloads/v1/products/OpenZoomstack/downloads?area=GB&format=GeoPackage&redirect"
DEFAULT_OUT = REPO / "app/rayfin-maps-addon/packages/frontend/public/data/gb-rail.geojson"
WORK = REPO / "data/zoomstack"   # /data/ is git-ignored


def download_gpkg() -> Path:
    import requests

    WORK.mkdir(parents=True, exist_ok=True)
    zip_path = WORK / "OS_Open_Zoomstack.zip"
    if not zip_path.exists():
        print(f"Downloading OS Open Zoomstack GeoPackage (about 4.3 GB) to {zip_path} ...")
        with requests.get(DOWNLOAD_URL, stream=True, timeout=60, headers={"User-Agent": "rail-fabric-rti-lab/1.0"}) as r:
            r.raise_for_status()
            total = int(r.headers.get("content-length", 0))
            done = 0
            tmp = zip_path.with_suffix(".part")
            with open(tmp, "wb") as f:
                for chunk in r.iter_content(chunk_size=8 * 1024 * 1024):
                    f.write(chunk)
                    done += len(chunk)
                    if total:
                        print(f"\r  {done / total:6.1%}", end="", flush=True)
            tmp.rename(zip_path)
            print()
    with zipfile.ZipFile(zip_path) as z:
        member = next((m for m in z.namelist() if m.lower().endswith(".gpkg")), None)
        if not member:
            sys.exit("No .gpkg file found in the Zoomstack zip")
        target = WORK / Path(member).name
        if not target.exists():
            print(f"Extracting {member} (about 12 GB) ...")
            z.extract(member, WORK)
            (WORK / member).rename(target) if (WORK / member) != target else None
    return target


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--gpkg", type=Path, help="Path to OS_Open_Zoomstack.gpkg (otherwise it is downloaded)")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--tolerance", type=float, default=15.0, help="Simplification tolerance in metres (default 15)")
    p.add_argument("--include-narrow-gauge", action="store_true", help="Also keep heritage/narrow-gauge lines")
    a = p.parse_args()

    import geopandas as gpd
    from shapely.geometry import mapping
    from shapely.ops import linemerge, unary_union

    gpkg = a.gpkg or download_gpkg()
    print(f"Reading layer 'rail' from {gpkg}")
    gdf = gpd.read_file(gpkg, layer="rail", columns=["type"], engine="pyogrio")
    keep = {"Multi Track", "Single Track", "Tunnel"} | ({"Narrow Gauge"} if a.include_narrow_gauge else set())
    gdf = gdf[gdf["type"].isin(keep)]
    print(f"  {len(gdf):,} line features of types {sorted(keep)}")

    gdf["geometry"] = gdf.geometry.simplify(a.tolerance, preserve_topology=False)   # metres, in EPSG:27700
    gdf = gdf[~gdf.geometry.is_empty]
    gdf = gdf.to_crs(4326)

    features = []
    for rail_type, group in gdf.groupby("type"):
        merged = linemerge(unary_union(group.geometry.values))   # far fewer, longer lines
        geom = mapping(merged)

        def rnd(c):
            return [round(c[0], 5), round(c[1], 5)]                # ~1 m precision

        if geom["type"] == "LineString":
            geom["coordinates"] = [rnd(c) for c in geom["coordinates"]]
        else:
            geom["coordinates"] = [[rnd(c) for c in line] for line in geom["coordinates"]]
        features.append({"type": "Feature", "properties": {"type": rail_type}, "geometry": geom})

    out = {
        "type": "FeatureCollection",
        "attribution": f"Contains OS data © Crown copyright and database right {date.today().year}",
        "features": features,
    }
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")
    size_mb = a.out.stat().st_size / 1_048_576
    print(f"Wrote {a.out} ({size_mb:.1f} MB). Over ~10 MB? Re-run with a larger --tolerance, e.g. 30.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
