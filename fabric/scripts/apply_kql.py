"""Apply the KQL scripts in fabric/kql (01-04) to the Eventhouse KQL database.

Usage (after `az login`):
    python fabric/scripts/apply_kql.py                      # uses KUSTO_QUERY_URI / FABRIC_KQL_DATABASE_NAME from .env
    python fabric/scripts/apply_kql.py --file fabric/kql/05_reference_from_shortcut.kql
    python fabric/scripts/apply_kql.py --dry-run
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_FILES = ["01_tables.kql", "02_update_policies.kql", "03_materialized_views.kql", "04_query_functions.kql"]


def load_dotenv() -> None:
    env = REPO / ".env"
    if not env.exists():
        return
    for line in env.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def strip_leading_comments(text: str) -> str:
    lines = text.splitlines()
    while lines and (not lines[0].strip() or lines[0].lstrip().startswith("//")):
        lines.pop(0)
    return "\n".join(lines)


def main() -> int:
    load_dotenv()
    p = argparse.ArgumentParser()
    p.add_argument("--uri", default=os.getenv("KUSTO_QUERY_URI"), help="KQL database Query URI")
    p.add_argument("--database", default=os.getenv("FABRIC_KQL_DATABASE_NAME", "RailKQL"))
    p.add_argument("--file", action="append", help="Specific .kql file(s); default 01-04")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    files = [Path(f) for f in a.file] if a.file else [REPO / "fabric" / "kql" / f for f in DEFAULT_FILES]
    if a.dry_run:
        for f in files:
            print(f"--- {f}\n{strip_leading_comments(f.read_text(encoding='utf-8'))[:400]}...\n")
        return 0
    if not a.uri:
        print("ERROR: set KUSTO_QUERY_URI (KQL database > Overview > Query URI) or pass --uri", file=sys.stderr)
        return 2

    from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

    client = KustoClient(KustoConnectionStringBuilder.with_az_cli_authentication(a.uri))
    for f in files:
        print(f"Applying {f.name} to {a.database} ...", flush=True)
        resp = client.execute_mgmt(a.database, strip_leading_comments(f.read_text(encoding="utf-8")))
        table = resp.primary_results[0] if resp.primary_results else None
        if table is not None:
            for row in table:
                d = row.to_dict()
                status = d.get("Result") or d.get("State") or ""
                if status and str(status).lower() not in ("completed", "succeeded", "success"):
                    print(f"  {d}")
        print("  done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
