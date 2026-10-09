#!/usr/bin/env bash
# Create one Event Hubs consumer group per student on the shared hubs (Lab 05c, optional shared tier).
#   ./scripts/add-student-consumer-groups.sh --prefix student --count 15          # student01 ... student15
#   ./scripts/add-student-consumer-groups.sh --prefix student --count 5 --start 16 # student16 ... student20 (!)
#   ./scripts/add-student-consumer-groups.sh --names alice,bob
# Defaults: STUDENT_CONSUMER_GROUP_PREFIX / STUDENT_CONSUMER_GROUP_COUNT from .env, hubs nrod-feed and rdm-trust,
# namespace EVENTHUB_NAMESPACE or the output of the 'shared-eventhubs' deployment (scripts/create-eventhub.sh).
# Idempotent: existing groups are skipped. Standard tier allows 20 consumer groups per event hub,
# including $Default (kept for the instructor), so at most 19 students per namespace.
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP

PREFIX="${STUDENT_CONSUMER_GROUP_PREFIX:-student}"
COUNT="${STUDENT_CONSUMER_GROUP_COUNT:-0}"
START=1
NAMES=""
HUBS="${EVENTHUB_NROD_HUB:-nrod-feed},${EVENTHUB_RDM_HUB:-rdm-trust}"
NAMESPACE="${EVENTHUB_NAMESPACE:-}"
MAX_PER_HUB=20

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  echo "Options: --prefix P --count N [--start S] | --names a,b,c   [--hubs h1,h2] [--namespace NAME]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift 2 ;;
    --count)     COUNT="$2"; shift 2 ;;
    --start)     START="$2"; shift 2 ;;
    --names)     NAMES="$2"; shift 2 ;;
    --hubs)      HUBS="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-eventhubs \
    --query properties.outputs.namespaceName.value -o tsv 2>/dev/null || true)"
fi
[[ -n "$NAMESPACE" ]] || { echo "ERROR: set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.sh first" >&2; exit 1; }

groups=()
if [[ -n "$NAMES" ]]; then
  IFS=',' read -r -a groups <<< "$NAMES"
else
  [[ "$COUNT" =~ ^[0-9]+$ && "$START" =~ ^[0-9]+$ ]] || { echo "ERROR: --count and --start must be numbers" >&2; exit 1; }
  for ((i = START; i < START + COUNT; i++)); do
    groups+=("$(printf '%s%02d' "$PREFIX" "$i")")
  done
fi
if [[ ${#groups[@]} -eq 0 ]]; then
  echo "No consumer groups requested (set --count or --names, or STUDENT_CONSUMER_GROUP_COUNT in .env)."
  exit 0
fi

IFS=',' read -r -a hubs <<< "$HUBS"
for hub in "${hubs[@]}"; do
  log "Event hub $NAMESPACE/$hub"
  existing="$(az eventhubs eventhub consumer-group list -g "$AZ_RESOURCE_GROUP" --namespace-name "$NAMESPACE" \
    --eventhub-name "$hub" --query "[].name" -o tsv)"
  have=$(grep -c . <<< "$existing" || true)
  for cg in "${groups[@]}"; do
    cg="${cg// /}"
    [[ -n "$cg" ]] || continue
    if grep -qx -- "$cg" <<< "$existing"; then
      echo "  exists   $cg"
      continue
    fi
    if (( have >= MAX_PER_HUB )); then
      echo "ERROR: $hub already has $have consumer groups (Standard limit $MAX_PER_HUB incl. \$Default)." >&2
      echo "       Use a second namespace for more students, or Premium (100 per event hub)." >&2
      exit 1
    fi
    az eventhubs eventhub consumer-group create -g "$AZ_RESOURCE_GROUP" --namespace-name "$NAMESPACE" \
      --eventhub-name "$hub" --consumer-group-name "$cg" -o none
    have=$((have + 1))
    echo "  created  $cg"
  done
  echo "  $hub now has $have of $MAX_PER_HUB consumer groups"
done

cat <<MSG

Give each student ONE consumer group name (the same name works on both hubs), for example ${groups[0]}.
Never let two Eventstreams share a consumer group - they compete for the same partitions.
MSG
