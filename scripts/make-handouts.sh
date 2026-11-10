#!/usr/bin/env bash
# Instructor 1.5: write one private handout per student, with everything they need, in one go.
# Reads the class settings from .env and Azure, finds the student consumer groups on the shared Event Hub,
# and writes handouts/<consumer group>.md (plus handouts/index.csv). Send each file to its student PRIVATELY.
#   ./scripts/make-handouts.sh                                   # every student consumer group found on the hub
#   ./scripts/make-handouts.sh --students 1-12 --notes "Lab 2.5: yes. Lab 2.8: no (region)"
#   ./scripts/make-handouts.sh --students 3,7 --maps             # also create today's Azure Maps token (Lab 2.9)
# Options: --students LIST (1-12, 3,7 or student03)  --workspace-prefix TEXT (default rail-rti-)
#          --reference-workspace NAME  --notes TEXT  --maps | --maps-token TOKEN  --out DIR (default handouts)
# With key sign-in the handouts contain the Listen key: the handouts folder is git-ignored. Delete it after the class.
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP

PREFIX="${STUDENT_CONSUMER_GROUP_PREFIX:-student}"
WS_PREFIX="${STUDENT_WORKSPACE_PREFIX:-rail-rti-}"
REF_WS="${REFERENCE_WORKSPACE_NAME:-${FABRIC_WORKSPACE_NAME:-}}"
NOTES="${HANDOUT_NOTES:-}"
AUTH="${EVENTHUB_AUTH:-key}"
NAMESPACE="${EVENTHUB_NAMESPACE:-}"
OUT="$REPO_ROOT/handouts"
STUDENTS=""
MAPS=false
MAPS_TOKEN=""

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --students)            STUDENTS="$2"; shift 2 ;;
    --workspace-prefix)    WS_PREFIX="$2"; shift 2 ;;
    --reference-workspace) REF_WS="$2"; shift 2 ;;
    --notes)               NOTES="$2"; shift 2 ;;
    --maps)                MAPS=true; shift ;;
    --maps-token)          MAPS_TOKEN="$2"; shift 2 ;;
    --namespace)           NAMESPACE="$2"; shift 2 ;;
    --out)                 OUT="$2"; shift 2 ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$AUTH" in key|entra) ;; *) echo "ERROR: EVENTHUB_AUTH must be 'key' or 'entra' (got '$AUTH')" >&2; exit 1 ;; esac

[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

# --- Event Hub ----------------------------------------------------------------------------------------
if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-eventhubs \
    --query properties.outputs.namespaceName.value -o tsv 2>/dev/null | tr -d '\r' || true)"
fi
NAMESPACE="${NAMESPACE%%.*}"
[[ -n "$NAMESPACE" ]] || { echo "ERROR: set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.sh first" >&2; exit 1; }
log "Reading the shared Event Hub $NAMESPACE"
az eventhubs namespace show -g "$AZ_RESOURCE_GROUP" -n "$NAMESPACE" -o none \
  || { echo "ERROR: namespace '$NAMESPACE' not found in $AZ_RESOURCE_GROUP (check the exact name)" >&2; exit 1; }

list_groups() {
  az eventhubs eventhub consumer-group list -g "$AZ_RESOURCE_GROUP" --namespace-name "$NAMESPACE" \
    --eventhub-name "$1" --query "[].name" -o tsv 2>/dev/null | tr -d '\r' | grep -E "^${PREFIX}[0-9]+$" | sort || true
}
NROD_GROUPS="$(list_groups nrod-feed)"
RDM_GROUPS="$(list_groups rdm-trust)"
HAS_DARWIN=false; DARWIN_GROUPS=""
if az eventhubs eventhub show -g "$AZ_RESOURCE_GROUP" --namespace-name "$NAMESPACE" -n rdm-darwin -o none 2>/dev/null; then
  HAS_DARWIN=true; DARWIN_GROUPS="$(list_groups rdm-darwin)"
  echo "  rdm-darwin found: the handouts include the optional Darwin feed (Student 1.5)"
fi
[[ -n "$NROD_GROUPS" ]] || { echo "ERROR: no '${PREFIX}NN' consumer groups on nrod-feed. Run ./scripts/add-student-consumer-groups.sh first." >&2; exit 1; }

# Which students: all groups found, or the --students list (1-12, 3,7, student03).
selected=()
if [[ -z "$STUDENTS" ]]; then
  while IFS= read -r g; do [[ -n "$g" ]] && selected+=("$g"); done <<< "$NROD_GROUPS"
else
  width="$(head -n1 <<< "$NROD_GROUPS" | sed "s/^$PREFIX//" | awk '{print length}')"
  IFS=',' read -ra parts <<< "$STUDENTS"
  for p in "${parts[@]}"; do
    p="${p//[[:space:]]/}"; p="${p#"$PREFIX"}"
    if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for (( n = 10#${BASH_REMATCH[1]}; n <= 10#${BASH_REMATCH[2]}; n++ )); do selected+=("$(printf "%s%0${width}d" "$PREFIX" "$n")"); done
    elif [[ "$p" =~ ^[0-9]+$ ]]; then
      selected+=("$(printf "%s%0${width}d" "$PREFIX" "$((10#$p))")")
    else
      echo "ERROR: --students '$p' isn't a number or range (use 1-12 or 3,7)" >&2; exit 1
    fi
  done
fi

# --- Key (key sign-in only) ------------------------------------------------------------------------------
LISTEN_KEY=""
if [[ "$AUTH" == "key" ]]; then
  LISTEN_KEY="$(az eventhubs namespace authorization-rule keys list -g "$AZ_RESOURCE_GROUP" --namespace-name "$NAMESPACE" \
    --authorization-rule-name students-listen --query primaryKey -o tsv 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$LISTEN_KEY" ]]; then
    echo "WARNING: couldn't read the students-listen key. The handouts will say [ask the instructor for the key]." >&2
    LISTEN_KEY="[ask the instructor for the key]"
  fi
  local_auth="$(az eventhubs namespace show -g "$AZ_RESOURCE_GROUP" -n "$NAMESPACE" --query disableLocalAuth -o tsv 2>/dev/null | tr -d '\r' || true)"
  if [[ "${local_auth,,}" == "true" ]]; then
    echo "WARNING: key sign-in is switched off on $NAMESPACE (disableLocalAuth=true), so the key won't work." >&2
    echo "         Use EVENTHUB_AUTH=entra (Instructor 1.4, 'Key sign-in blocked by policy') and re-run this script." >&2
  fi
fi

# --- Fabric workspace IDs (best effort) ----------------------------------------------------------------
declare -A WS_IDS=()
log "Looking up student workspaces in Fabric (optional)"
if ws_list="$(az rest --method get --resource https://api.fabric.microsoft.com \
      --url https://api.fabric.microsoft.com/v1/workspaces --query "value[].[displayName,id]" -o tsv 2>/dev/null | tr -d '\r')"; then
  while IFS=$'\t' read -r n i; do [[ -n "$n" ]] && WS_IDS["$n"]="$i"; done <<< "$ws_list"
else
  echo "  (couldn't list Fabric workspaces - the handouts will leave the workspace ID empty)"
fi

# --- Azure Maps token (optional) -------------------------------------------------------------------------
if [[ "$MAPS" == "true" && -z "$MAPS_TOKEN" ]]; then
  log "Creating today's Azure Maps token"
  MAPS_TOKEN="$("$(dirname "$0")/new-azure-maps-sas.sh" | tr -d '\r' | tail -n1)"
fi
if [[ -n "$MAPS_TOKEN" ]]; then MAPS_ROW="\`$MAPS_TOKEN\` (valid 24 hours from when it was created)"
else MAPS_ROW="Not included. If the class does Lab 2.9, the instructor sends a token each day (valid 24 hours)"; fi

# --- Write the handouts -------------------------------------------------------------------------------
FOUNDRY_EP="${FOUNDRY_PROJECT_ENDPOINT:-}"
FOUNDRY_MODEL="${FOUNDRY_MODEL_DEPLOYMENT_NAME:-}"
AGENT_BASE="${FOUNDRY_AGENT_NAME:-rail-network-agent}"; AGENT_BASE="${AGENT_BASE%-${PREFIX}[0-9]*}"
LAKEHOUSE="${FABRIC_LAKEHOUSE_NAME:-RailLakehouse}"
[[ -n "$FOUNDRY_EP" ]]    || echo "WARNING: FOUNDRY_PROJECT_ENDPOINT is empty in .env - the handouts will show a placeholder." >&2
[[ -n "$FOUNDRY_MODEL" ]] || echo "WARNING: FOUNDRY_MODEL_DEPLOYMENT_NAME is empty in .env - the handouts will show a placeholder." >&2
[[ -n "$NOTES" ]]         || echo "WARNING: no --notes given - the handouts will ask students to check with you about Labs 2.5 and 2.8." >&2

mkdir -p "$OUT"
printf 'consumer_group,workspace_name,workspace_id,agent_name,file\n' > "$OUT/index.csv"
log "Writing handouts to $OUT"
missing_rdm=0
for cg in "${selected[@]}"; do
  if ! grep -qx "$cg" <<< "$NROD_GROUPS"; then
    echo "  WARNING: $cg doesn't exist on nrod-feed - skipped. Add it with ./scripts/add-student-consumer-groups.sh" >&2; continue
  fi
  grep -qx "$cg" <<< "$RDM_GROUPS" || { echo "  WARNING: $cg is missing on rdm-trust" >&2; missing_rdm=1; }
  if [[ "$HAS_DARWIN" == "true" ]] && ! grep -qx "$cg" <<< "$DARWIN_GROUPS"; then
    echo "  WARNING: $cg is missing on rdm-darwin" >&2; missing_rdm=1
  fi
  if [[ "$HAS_DARWIN" == "true" ]]; then
    darwin_row="| Optional Darwin feed (Student 1.5) | A third source: event hub \`rdm-darwin\` (→ table \`RdmDarwinRaw\`) in its own Eventstream, \`RailEventstreamDarwin\`, with the same settings |"
    darwin_note=" Student 1.5 (Darwin) is optional: it adds to the capacity your workspace uses."
  else
    darwin_row=""; darwin_note=""
  fi
  ws="${WS_PREFIX}${cg}"
  ws_id="${WS_IDS[$ws]:-}"
  agent="${AGENT_BASE}-${cg}"
  if [[ -n "$ws_id" ]]; then ws_cell="\`$ws\` (ID \`$ws_id\`)"
  else ws_cell="\`$ws\` – create it in Student 1.2 if the instructor hasn't"; fi
  file="$OUT/$cg.md"
  if [[ "$AUTH" == "key" ]]; then
    auth_rows="| Authentication kind | Shared access key |
| Shared access key name | \`students-listen\` |
| Shared access key | \`$LISTEN_KEY\` |"
    before=""
  else
    auth_rows="| Authentication kind | **Workspace identity** (no key) |"
    before="
## Before you connect

1. Open your workspace → **Workspace settings** → **Workspace identity** → enable it (you need the **Admin** role).
2. Copy the **ID** shown there (not the **App ID**) and send it to the instructor.
3. Wait until the instructor confirms your workspace has read access, then do Student 1.4.
"
  fi
  cat > "$file" <<MD
# Real-Time Rail Intelligence – your class handout ($cg)

**Keep this private.** Don't put it in a repo, a Teams channel or a slide.

## Your details

| Item | Value |
|---|---|
| Fabric workspace | $ws_cell |
| Your consumer group (both hubs) | \`$cg\` |
| Your Foundry agent name | \`$agent\` |
| Reference Lakehouse | workspace \`${REF_WS:-[ask the instructor]}\` → \`$LAKEHOUSE\` → \`Tables/locations\` |
| Labs that work in this tenant | ${NOTES:-Check with the instructor whether Lab 2.5 (ontology) and Lab 2.8 (Fabric Apps) are available} |
| Azure Maps token (Lab 2.9, optional) | $MAPS_ROW |
$before
## Your \`.env\` settings (Student 1.1)

\`\`\`bash
FABRIC_WORKSPACE_NAME=$ws
FABRIC_WORKSPACE_ID=$ws_id
KUSTO_QUERY_URI=                 # printed by Student 1.2
FOUNDRY_PROJECT_ENDPOINT=${FOUNDRY_EP:-[ask the instructor]}
FOUNDRY_MODEL_DEPLOYMENT_NAME=${FOUNDRY_MODEL:-[ask the instructor]}
FOUNDRY_AGENT_NAME=$agent
\`\`\`

Leave the \`NROD_*\`, \`RDM_*\`, \`AZ_*\`, \`KEY_VAULT_*\` and \`EVENTHUB_*\` values empty.

## Eventstream source settings (Student 1.4)

Add an **Azure Event Hubs** source twice, once for each hub:

| Setting | Value |
|---|---|
| Event Hub namespace | \`$NAMESPACE\` |
| Event hub | \`nrod-feed\` (→ table \`RawFeed\`) and \`rdm-trust\` (→ table \`RdmTrustRaw\`) |
$auth_rows
| Consumer group | \`$cg\` (never \`\$Default\`) |
| Data format | JSON |
$darwin_row

Start at **docs/student/README.md** in the repo.$darwin_note
MD
  printf '%s,%s,%s,%s,%s\n' "$cg" "$ws" "$ws_id" "$agent" "$cg.md" >> "$OUT/index.csv"
  echo "  wrote  $cg.md   ($ws${ws_id:+, workspace found})"
done
[[ $missing_rdm -eq 0 ]] || echo "Some groups are missing on rdm-trust or rdm-darwin: re-run ./scripts/add-student-consumer-groups.sh" >&2

echo
echo "Done. Send each file in $OUT to its student privately."
if [[ "$AUTH" == "key" ]]; then
  echo "The handouts contain the Listen key. The folder is git-ignored; delete it after the class (Instructor 1.7)."
else
  echo "When students send their workspace identity ID: ./scripts/grant-eventhub-reader.sh --id <ID> [--id <ID> ...]"
fi
