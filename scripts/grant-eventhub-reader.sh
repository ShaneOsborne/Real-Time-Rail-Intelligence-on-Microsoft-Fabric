#!/usr/bin/env bash
# Give Fabric workspace identities read access to the shared Event Hub (Instructor 1.4 / Solo 1.8, EVENTHUB_AUTH=entra).
# Each student enables Workspace settings > Workspace identity and sends you the "ID" shown there (not the "App ID").
# Their Eventstream "Azure Event Hubs" source then uses Authentication kind = Workspace identity - no key to share.
#   ./scripts/grant-eventhub-reader.sh --id 59cc0a5f-0000-0000-0000-000000000000
#   ./scripts/grant-eventhub-reader.sh --id <student01 ID> --id <student02 ID>
#   ./scripts/grant-eventhub-reader.sh --id <student01 ID> --remove     # after the course
# Assigns 'Azure Event Hubs Data Receiver' on the namespace (EVENTHUB_NAMESPACE, or the 'shared-eventhubs' deployment).
# Safe to re-run. Needs Owner or User Access Administrator on the namespace.
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP

ROLE="Azure Event Hubs Data Receiver"
NAMESPACE="${EVENTHUB_NAMESPACE:-}"
REMOVE=false
ids=()
GUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; echo "Options: --id ID [--id ID ...] [--namespace NAME] [--remove]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)        ids+=("$(tr -d '\r[:space:]' <<< "${2:-}")"); shift 2 ;;
    --workspace)
      echo "ERROR: --workspace is no longer supported. Workspace names aren't unique in Entra ID (the search also matches" >&2
      echo "       names that only START with it), so use --id with the 'ID' from Workspace settings > Workspace identity." >&2
      exit 1 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --remove)    REMOVE=true; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
done
(( ${#ids[@]} > 0 )) || { usage >&2; exit 1; }
for id in "${ids[@]}"; do
  [[ "$id" =~ $GUID_RE ]] || { echo "ERROR: '$id' isn't an ID. Copy the 'ID' from Workspace settings > Workspace identity (it looks like 59cc0a5f-d78a-...)." >&2; exit 1; }
done

[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"
if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-eventhubs \
    --query properties.outputs.namespaceName.value -o tsv 2>/dev/null | tr -d '\r' || true)"
fi
NAMESPACE="${NAMESPACE%%.*}"   # accept a fully qualified name too
[[ -n "$NAMESPACE" ]] || { echo "ERROR: set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.sh first" >&2; exit 1; }
NS_ID="$(az eventhubs namespace show -g "$AZ_RESOURCE_GROUP" -n "$NAMESPACE" --query id -o tsv | tr -d '\r')"

# The Workspace identity page shows "ID" (the object ID the role needs) and "App ID". If someone sends the App ID,
# look up the object ID; if the directory can't be read, assume it's already the object ID.
resolve_id() {
  local oid
  oid="$(az ad sp show --id "$1" --query id -o tsv 2>/dev/null | tr -d '\r')"
  if [[ -n "$oid" ]]; then echo "$oid"; else echo "$1"; fi
}

apply() {
  local label="$1" oid="$2" out
  if [[ "$REMOVE" == "true" ]]; then
    if MSYS_NO_PATHCONV=1 az role assignment delete --assignee "$oid" --role "$ROLE" --scope "$NS_ID" -o none 2>/dev/null; then
      echo "  removed  $label"
    else
      echo "  WARNING: could not remove the role for $label" >&2; failed=$((failed + 1))
    fi
    return
  fi
  if out="$(MSYS_NO_PATHCONV=1 az role assignment create --assignee-object-id "$oid" --assignee-principal-type ServicePrincipal \
        --role "$ROLE" --scope "$NS_ID" -o none 2>&1)"; then
    echo "  granted  $label"
  elif grep -qi "already exists" <<< "$out"; then
    echo "  exists   $label"
  else
    echo "  ERROR for $label: $out" >&2; failed=$((failed + 1))
  fi
}

failed=0
log "$ROLE on $NAMESPACE"
for id in "${ids[@]}"; do
  oid="$(resolve_id "$id")"
  name="$(az ad sp show --id "$oid" --query displayName -o tsv 2>/dev/null | tr -d '\r' || true)"
  apply "$id${name:+ ($name)}" "$oid"
done

if [[ "$REMOVE" != "true" ]]; then
  cat <<MSG

Students can now add an Eventstream "Azure Event Hubs" source with:
  Event Hub namespace : $NAMESPACE   Event hubs: nrod-feed (-> RawFeed), rdm-trust (-> RdmTrustRaw)
  Authentication kind : Workspace identity    Consumer group: their own (never \$Default)    Data format: JSON
A new role assignment can take a few minutes to apply.
MSG
fi
[[ $failed -eq 0 ]] || { echo "$failed item(s) failed - see the errors above." >&2; exit 1; }
