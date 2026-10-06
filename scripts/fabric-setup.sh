#!/usr/bin/env bash
# Lab 02 Option A: create the Fabric workspace items with the Fabric REST API (via `az rest`).
# Creates (idempotently): workspace (optional), Eventhouse, KQL database, Lakehouse, empty Eventstream.
# The Eventstream SOURCES/DESTINATIONS are configured manually in the portal (Labs 04/05).
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az

API="https://api.fabric.microsoft.com/v1"
RES="https://api.fabric.microsoft.com"
EH_NAME="${FABRIC_EVENTHOUSE_NAME:-RailEventhouse}"
DB_NAME="${FABRIC_KQL_DATABASE_NAME:-RailKQL}"
LH_NAME="${FABRIC_LAKEHOUSE_NAME:-RailLakehouse}"
ES_NROD="${FABRIC_EVENTSTREAM_NROD_NAME:-RailEventstreamNrod}"
ES_RDM="${FABRIC_EVENTSTREAM_RDM_NAME:-RailEventstreamRdm}"

fabric() { az rest --resource "$RES" "$@"; }

if [[ -z "${FABRIC_WORKSPACE_ID:-}" ]]; then
  require FABRIC_CAPACITY_ID FABRIC_WORKSPACE_NAME
  log "Looking for workspace '$FABRIC_WORKSPACE_NAME'"
  FABRIC_WORKSPACE_ID="$(fabric --method get --url "$API/workspaces" \
    --query "value[?displayName=='$FABRIC_WORKSPACE_NAME'].id | [0]" -o tsv)"
  if [[ -z "$FABRIC_WORKSPACE_ID" || "$FABRIC_WORKSPACE_ID" == "None" ]]; then
    log "Creating workspace on capacity $FABRIC_CAPACITY_ID"
    FABRIC_WORKSPACE_ID="$(fabric --method post --url "$API/workspaces" \
      --body "{\"displayName\":\"$FABRIC_WORKSPACE_NAME\",\"capacityId\":\"$FABRIC_CAPACITY_ID\"}" --query id -o tsv)"
  fi
fi
echo "Workspace: $FABRIC_WORKSPACE_ID"
WS="$API/workspaces/$FABRIC_WORKSPACE_ID"

# find_item <collection> <displayName>
find_item() {
  fabric --method get --url "$WS/$1" --query "value[?displayName=='$2'].id | [0]" -o tsv 2>/dev/null || true
}

# ensure_item <collection> <displayName> <json-body>  -> echoes id (handles 201 and 202/LRO by polling)
ensure_item() {
  local coll="$1" name="$2" body="$3" id i
  id="$(find_item "$coll" "$name")"
  if [[ -z "$id" || "$id" == "None" ]]; then
    echo "  creating $coll/$name" >&2
    fabric --method post --url "$WS/$coll" --body "$body" -o none >&2
    for i in {1..30}; do
      id="$(find_item "$coll" "$name")"
      [[ -n "$id" && "$id" != "None" ]] && break
      sleep 10
    done
  else
    echo "  exists  $coll/$name" >&2
  fi
  [[ -n "$id" && "$id" != "None" ]] || { echo "ERROR: $coll/$name was not created" >&2; exit 1; }
  echo "$id"
}

log "Eventhouse"
EH_ID="$(ensure_item eventhouses "$EH_NAME" "{\"displayName\":\"$EH_NAME\"}")"
log "KQL database"
DB_ID="$(ensure_item kqlDatabases "$DB_NAME" \
  "{\"displayName\":\"$DB_NAME\",\"creationPayload\":{\"databaseType\":\"ReadWrite\",\"parentEventhouseItemId\":\"$EH_ID\"}}")"
log "Lakehouse"
LH_ID="$(ensure_item lakehouses "$LH_NAME" "{\"displayName\":\"$LH_NAME\"}")"
log "Eventstreams (empty - configure sources/destinations in the portal, Labs 04/05)"
ES_RDM_ID="$(ensure_item eventstreams "$ES_RDM" "{\"displayName\":\"$ES_RDM\"}")"
ES_NROD_ID="$(ensure_item eventstreams "$ES_NROD" "{\"displayName\":\"$ES_NROD\"}")"

QUERY_URI="$(fabric --method get --url "$WS/kqlDatabases/$DB_ID" --query properties.queryServiceUri -o tsv)"

cat <<OUT

Add these to your .env:
FABRIC_WORKSPACE_ID=$FABRIC_WORKSPACE_ID
FABRIC_EVENTHOUSE_ID=$EH_ID
FABRIC_KQL_DATABASE_ID=$DB_ID
FABRIC_LAKEHOUSE_ID=$LH_ID
FABRIC_EVENTSTREAM_RDM_ID=$ES_RDM_ID
FABRIC_EVENTSTREAM_NROD_ID=$ES_NROD_ID
KUSTO_QUERY_URI=$QUERY_URI

Next: python fabric/scripts/apply_kql.py   (Lab 06 - creates tables, mappings, policies, views)
OUT
