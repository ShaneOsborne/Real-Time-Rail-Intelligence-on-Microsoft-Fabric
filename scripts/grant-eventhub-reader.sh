#!/usr/bin/env bash
# Give Fabric workspace identities read access to the shared Event Hub (Instructor 1.4 / Solo 1.8, EVENTHUB_AUTH=entra).
# Each student enables Workspace settings > Workspace identity and sends you the workspace name (or the identity ID).
# Their Eventstream "Azure Event Hubs" source then uses Authentication kind = Workspace identity - no key to share.
#   ./scripts/grant-eventhub-reader.sh --workspace "Rail RTI - student01" --workspace "Rail RTI - student02"
#   ./scripts/grant-eventhub-reader.sh --id 00000000-0000-0000-0000-000000000000
#   ./scripts/grant-eventhub-reader.sh --workspace "Rail RTI - student01" --remove     # after the course
# Assigns 'Azure Event Hubs Data Receiver' on the namespace (EVENTHUB_NAMESPACE, or the 'shared-eventhubs' deployment).
# Safe to re-run. Needs Owner or User Access Administrator on the namespace, and directory read access to look up names.
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP

ROLE="Azure Event Hubs Data Receiver"
NAMESPACE="${EVENTHUB_NAMESPACE:-}"
REMOVE=false
workspaces=()
ids=()

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; echo "Options: --workspace NAME ... | --id ID ...  [--namespace NAME] [--remove]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) workspaces+=("$2"); shift 2 ;;
    --id)        ids+=("$2"); shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --remove)    REMOVE=true; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
done
(( ${#workspaces[@]} + ${#ids[@]} > 0 )) || { usage >&2; exit 1; }

[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"
if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-eventhubs \
    --query properties.outputs.namespaceName.value -o tsv 2>/dev/null | tr -d '\r' || true)"
fi
NAMESPACE="${NAMESPACE%%.*}"   # accept a fully qualified name too
[[ -n "$NAMESPACE" ]] || { echo "ERROR: set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.sh first" >&2; exit 1; }
NS_ID="$(az eventhubs namespace show -g "$AZ_RESOURCE_GROUP" -n "$NAMESPACE" --query id -o tsv | tr -d '\r')"

# object id of a workspace identity (service principal) from its display name (= the workspace name)
resolve_name() {
  local found count
  found="$(az ad sp list --display-name "$1" --query "[].id" -o tsv 2>/dev/null | tr -d '\r')"
  count=$(grep -c . <<< "$found" || true)
  if [[ "$count" -eq 1 ]]; then echo "$found"; return 0; fi
  if [[ "$count" -eq 0 ]]; then
    echo "  ERROR: no identity named '$1'. Is Workspace identity enabled on that workspace (name spelled exactly)?" >&2
  else
    echo "  ERROR: $count identities are named '$1'. Use --id with the ID from Workspace settings > Workspace identity." >&2
  fi
  return 1
}
# object id from an application (client) ID or an object ID
resolve_id() {
  local oid
  oid="$(az ad sp show --id "$1" --query id -o tsv 2>/dev/null | tr -d '\r')"
  if [[ -n "$oid" ]]; then echo "$oid"; else echo "$1"; fi   # no directory read access: assume it's the object ID
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
for ws in "${workspaces[@]}"; do
  if oid="$(resolve_name "$ws")"; then apply "$ws" "$oid"; else failed=$((failed + 1)); fi
done
for id in "${ids[@]}"; do
  apply "$id" "$(resolve_id "$id")"
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
