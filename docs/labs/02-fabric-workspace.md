# Lab 02 – Fabric workspace, Eventhouse, KQL database, Lakehouse and Eventstreams

**Time:** 20 minutes · **Previous:** [Lab 01](01-prerequisites.md) · **Next:** [Lab 03](03-reference-data.md)

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

> The Eventstreams are created **empty**. You add their sources and destinations in the portal in Labs 04 and 05.

## Option B – manual (portal)

1. Go to <https://app.fabric.microsoft.com> → **Workspaces** → **+ New workspace** → name it `RailIntelligence` →
   *Advanced* → choose your **Fabric capacity** (or trial) → **Apply**.
2. **+ New item** → **Eventhouse** → `RailEventhouse`. Fabric also creates a default KQL database with the same name.
3. In the Eventhouse, **+ Database** → `RailKQL`. You can use the default database instead if you set
   `FABRIC_KQL_DATABASE_NAME` to its name.
4. **+ New item** → **Lakehouse** → `RailLakehouse`.
5. **+ New item** → **Eventstream** → `RailEventstreamRdm`. Repeat for `RailEventstreamNrod`.
6. Open `RailKQL` → **Overview**, copy the **Query URI** into `KUSTO_QUERY_URI` in `.env`, and note the
   workspace ID and item IDs from the browser URL (`/groups/<workspaceId>/...`).

## Checkpoint

- [ ] The workspace shows the Eventhouse, KQL database, Lakehouse and two Eventstreams
- [ ] `KUSTO_QUERY_URI`, `FABRIC_WORKSPACE_ID`, `FABRIC_LAKEHOUSE_ID` and `FABRIC_KQL_DATABASE_ID` are set in `.env`
- [ ] In a KQL queryset on `RailKQL`, `.show database` returns one row

## Troubleshooting

| Symptom | Fix |
|---|---|
| `az rest` returns 401/403 | Run `az login` with a user who is a workspace Contributor or above. Check that the tenant allows the Fabric APIs |
| `ItemDisplayNameAlreadyInUse` | An item with that name exists. The script reuses it. Remove it in the portal if you want a fresh one |
| `InsufficientCapacity` / capacity errors | Check the capacity is running (not paused) and that the workspace is assigned to it |
