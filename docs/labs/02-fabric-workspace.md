# Lab 02 – Fabric workspace, Eventhouse, KQL database, Lakehouse and Eventstreams

**Time:** 20 minutes · **Previous:** [Lab 01](01-prerequisites.md) · **Next:** [Lab 03](03-reference-data.md)

> **Path:** Solo ✅ · Instructor ✅ (your own workspace) · Classroom student ✅. If the instructor already created your workspace, put its ID in
> `FABRIC_WORKSPACE_ID` and run Option A anyway: the script reuses the workspace and creates the items in it. You don't need `FABRIC_CAPACITY_ID` then.

## Objectives

Create the Fabric items that every later lab uses:

| Item | Name (default) |
|---|---|
| Workspace | `rail-fabric-rti` |
| Eventhouse | `RailEventhouse` |
| KQL database | `RailKQL` |
| Lakehouse | `RailLakehouse` |
| Eventstream for RDM Kafka | `RailEventstreamRdm` |
| Eventstream for the NROD bridge | `RailEventstreamNrod` |
| Eventstream for Darwin (*optional*, [Lab 04b](04b-darwin-push-port.md)) | `RailEventstreamDarwin` |

## Prerequisites

Lab 01 is done, and you have `FABRIC_CAPACITY_ID` (Fabric admin portal → *Capacity settings* → your capacity → the capacity ID), unless you're reusing a workspace.

## Option A – automated

Ensure the following parameters are populated within your .env
FABRIC_CAPACITY_ID

```bash
az login
./scripts/fabric-setup.sh           # or: ./scripts/fabric-setup.ps1
```

The script uses the Fabric REST API (`POST /v1/workspaces`, `/eventhouses`, `/kqlDatabases` with
`creationPayload {databaseType: ReadWrite, parentEventhouseItemId}`, `/lakehouses` and `/eventstreams`). It's
idempotent: it reuses items with the same display name. When it finishes, it prints the IDs and the **KQL Query URI**. Copy them into `.env`.

> The Eventstreams (including the optional `RailEventstreamDarwin`) are created **empty**. You add their sources and destinations in the portal in Labs 04, 04b and 05.

## Option B – manual (portal)

1. Go to <https://app.fabric.microsoft.com> → **Workspaces** → **+ New workspace** → name it `rail-fabric-rti` →
   *Advanced* → choose your **Fabric capacity** (or trial) → **Apply**.
2. **+ New item** → **Eventhouse** → `RailEventhouse`. Fabric also creates a default KQL database with the same name.
3. In the Eventhouse, **+ Database** → `RailKQL`. You can use the default database instead if you set
   `FABRIC_KQL_DATABASE_NAME` to its name.
4. **+ New item** → **Lakehouse** → `RailLakehouse`.
5. **+ New item** → **Eventstream** → `RailEventstreamRdm`. Repeat for `RailEventstreamNrod`. *Optional:* if you'll do
   [Lab 04b](04b-darwin-push-port.md) (Darwin), also create `RailEventstreamDarwin`.
6. Open `RailKQL` → **Overview**, copy the **Query URI** into `KUSTO_QUERY_URI` in `.env`, and note the
   workspace ID and item IDs from the browser URL (`/groups/<workspaceId>/...`).

## Create the raw tables and mappings now

Labs 04 and 05 point Eventstream at **existing** tables (`RdmTrustRaw`, `RawFeed`) and **existing** JSON mappings
(`RdmTrustRawMapping`, `RawFeedMapping`). The scripts also create `RdmDarwinRaw` / `RdmDarwinRawMapping` for the optional Lab 04b. The Eventstream wizard can't pick a mapping that doesn't exist yet, so create
them before you leave this lab. (These are steps 1–2 of Lab 06. The scripts are safe to re-run later.)

**Option A – automated**

```bash
pip install -r fabric/scripts/requirements.txt
python fabric/scripts/apply_kql.py --file fabric/kql/01_tables.kql
python fabric/scripts/apply_kql.py --file fabric/kql/02_update_policies.kql
```

**Option B – manual:** open `RailKQL` → **Explore your data** (or a KQL queryset). Paste the **whole** of
`fabric/kql/01_tables.kql`, select all (**Ctrl+A**) and **Run**. Repeat for `fabric/kql/02_update_policies.kql`.

## Checkpoint

- [ ] The workspace shows the Eventhouse, KQL database, Lakehouse and two Eventstreams (three if you created the optional `RailEventstreamDarwin`)
- [ ] `.show tables` lists `RawFeed`, `RdmTrustRaw` and `RdmDarwinRaw`
- [ ] `.show table RdmTrustRaw ingestion json mappings` returns `RdmTrustRawMapping` (and the same for `RawFeed` / `RawFeedMapping`)
- [ ] `KUSTO_QUERY_URI`, `FABRIC_WORKSPACE_ID`, `FABRIC_LAKEHOUSE_ID` and `FABRIC_KQL_DATABASE_ID` are set in `.env`
- [ ] In a KQL queryset on `RailKQL`, `.show database` returns one row

## Troubleshooting

| Symptom | Fix |
|---|---|
| `az rest` returns 401/403 | Run `az login` with a user who is a workspace Contributor or above. Check that the tenant allows the Fabric APIs |
| `ItemDisplayNameAlreadyInUse` | An item with that name exists. The script reuses it. Remove it in the portal if you want a fresh one |
| `InsufficientCapacity` / capacity errors | Check the capacity is running (not paused) and that the workspace is assigned to it |
