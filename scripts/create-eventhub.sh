#!/usr/bin/env bash
# OPTIONAL shared Event Hub tier (Instructor 1.4, or Solo 1.8 for one person). Creates an Event Hubs Standard namespace with the
# event hubs nrod-feed and rdm-trust (7-day retention), a Send rule per hub and a namespace Listen rule for
# students; writes the send connection strings into the shared Key Vault; creates student consumer groups;
# and prints what students need for their Eventstream "Azure Event Hubs" source.
# With SECRETS_SOURCE=inline (Key Vault blocked by policy, as in Solo 1.7) it doesn't touch Key Vault: it writes
# EVENTHUB_NAMESPACE, EVENTHUB_CONNECTION_STRING and EVENTHUB_RDM_CONNECTION_STRING straight into .env instead.
#   ./scripts/create-eventhub.sh
#   SECRETS_SOURCE=inline ./scripts/create-eventhub.sh
#   ./scripts/create-eventhub.sh --what-if
#   ./scripts/create-eventhub.sh --hide-key     # don't print the students' Listen key
# Requires: az CLI (logged in), .env with AZ_RESOURCE_GROUP and AZ_LOCATION.
# Optional .env: EVENTHUB_NAMESPACE, EVENTHUB_THROUGHPUT_UNITS, EVENTHUB_RETENTION_DAYS,
#                STUDENT_CONSUMER_GROUP_PREFIX, STUDENT_CONSUMER_GROUP_COUNT, KEY_VAULT_NAME, NAME_PREFIX,
#                SECRETS_SOURCE (keyvault | inline).
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP AZ_LOCATION

WHAT_IF=false
SHOW_KEY=true
for arg in "$@"; do
  case "$arg" in
    --what-if)  WHAT_IF=true ;;
    --hide-key) SHOW_KEY=false ;;
    *) echo "Usage: $0 [--what-if] [--hide-key]" >&2; exit 1 ;;
  esac
done

NAME_PREFIX="${NAME_PREFIX:-railrti}"
SECRETS_SOURCE="${SECRETS_SOURCE:-keyvault}"
case "$SECRETS_SOURCE" in keyvault|inline) ;; *) echo "ERROR: SECRETS_SOURCE must be 'keyvault' or 'inline'" >&2; exit 1 ;; esac
NROD_HUB=nrod-feed
RDM_HUB=rdm-trust
[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

eh_params=(
  --resource-group "$AZ_RESOURCE_GROUP"
  --template-file "$REPO_ROOT/infra/eventhubs.bicep"
  --parameters location="$AZ_LOCATION" namePrefix="$NAME_PREFIX" namespaceName="${EVENTHUB_NAMESPACE:-}"
               throughputUnits="${EVENTHUB_THROUGHPUT_UNITS:-1}" retentionDays="${EVENTHUB_RETENTION_DAYS:-7}"
               nrodHubName="$NROD_HUB" rdmHubName="$RDM_HUB"
)

log "Resource group $AZ_RESOURCE_GROUP ($AZ_LOCATION)"
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" -o none

if [[ "$WHAT_IF" == "true" ]]; then
  az deployment group what-if "${eh_params[@]}"
  exit 0
fi

if [[ "$SECRETS_SOURCE" == "keyvault" ]]; then
DEPLOYER_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
DEPLOYER_TYPE=User
if [[ -z "$DEPLOYER_ID" ]]; then
  DEPLOYER_ID="$(az ad sp show --id "$(az account show --query user.name -o tsv)" --query id -o tsv)"
  DEPLOYER_TYPE=ServicePrincipal
fi

# Same template and deployment name as scripts/create-keyvault.sh: re-uses the shared vault (Solo 1.1 step 8).
log "Shared Key Vault (created or re-used) + Key Vault Secrets Officer for you"
az deployment group create -g "$AZ_RESOURCE_GROUP" -n shared-keyvault \
  --template-file "$REPO_ROOT/infra/keyvault.bicep" \
  --parameters location="$AZ_LOCATION" namePrefix="$NAME_PREFIX" keyVaultName="${KEY_VAULT_NAME:-}" \
               deployerPrincipalId="$DEPLOYER_ID" deployerPrincipalType="$DEPLOYER_TYPE" -o none
KV_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-keyvault --query properties.outputs.keyVaultName.value -o tsv)"
else
  log "SECRETS_SOURCE=inline: Key Vault skipped (connection strings go into .env instead)"
fi

log "Event Hubs Standard namespace, hubs $NROD_HUB + $RDM_HUB, SAS rules (infra/eventhubs.bicep)"
az deployment group create -n shared-eventhubs "${eh_params[@]}" -o none
NS="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv)"

set_secret() {
  local name="$1" value="$2" i
  for i in {1..10}; do
    if az keyvault secret set --vault-name "$KV_NAME" -n "$name" --value "$value" -o none 2>/dev/null; then
      echo "  set $name"; return 0
    fi
    echo "  waiting for Key Vault permissions ($i/10)..."; sleep 15
  done
  echo "ERROR: could not write secret $name" >&2; exit 1
}
send_cs() {
  az eventhubs eventhub authorization-rule keys list -g "$AZ_RESOURCE_GROUP" --namespace-name "$NS" \
    --eventhub-name "$1" --authorization-rule-name bridge-send --query primaryConnectionString -o tsv
}
# set_env_var KEY VALUE: replace KEY=... in the repo-root .env, or append it. Other lines are left as they are.
set_env_var() {
  local file="$REPO_ROOT/.env" tmp
  [[ -f "$file" ]] || : > "$file"
  tmp="$(mktemp)"
  if grep -q "^[[:space:]]*$1[[:space:]]*=" "$file"; then
    K="$1" V="$2" awk '{ line=$0; sub(/\r$/, "", line) }
      line ~ "^[[:space:]]*" ENVIRON["K"] "[[:space:]]*=" { print ENVIRON["K"] "=" ENVIRON["V"]; next } { print }' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    [[ -s "$tmp" && -n "$(tail -c1 "$tmp")" ]] && echo >> "$tmp"
    printf '%s=%s\n' "$1" "$2" >> "$tmp"
  fi
  cat "$tmp" > "$file"; rm -f "$tmp"
  echo "  set $1 in .env"
}
NROD_CS="$(send_cs "$NROD_HUB")"
RDM_CS="$(send_cs "$RDM_HUB")"
[[ -n "$NROD_CS" && -n "$RDM_CS" ]] || { echo "ERROR: could not read the bridge-send connection strings" >&2; exit 1; }
if [[ "$SECRETS_SOURCE" == "keyvault" ]]; then
  log "Writing send connection strings to Key Vault $KV_NAME (retrying while RBAC propagates)"
  set_secret eventhub-nrod-connection-string "$NROD_CS"
  set_secret eventhub-rdm-connection-string "$RDM_CS"
else
  log "Writing the namespace and send connection strings to .env (keep .env private; never commit it)"
  set_env_var EVENTHUB_NAMESPACE "$NS"
  set_env_var EVENTHUB_CONNECTION_STRING "$NROD_CS"
  set_env_var EVENTHUB_RDM_CONNECTION_STRING "$RDM_CS"
fi

if [[ "${STUDENT_CONSUMER_GROUP_COUNT:-0}" =~ ^[1-9][0-9]*$ ]]; then
  log "Student consumer groups (${STUDENT_CONSUMER_GROUP_PREFIX:-student}01..)"
  bash "$REPO_ROOT/scripts/add-student-consumer-groups.sh" --namespace "$NS" \
    --prefix "${STUDENT_CONSUMER_GROUP_PREFIX:-student}" --count "$STUDENT_CONSUMER_GROUP_COUNT"
else
  echo "STUDENT_CONSUMER_GROUP_COUNT not set: add groups later with ./scripts/add-student-consumer-groups.sh --prefix student --count N"
fi

if [[ "$SHOW_KEY" == "true" ]]; then
  LISTEN_KEY="$(az eventhubs namespace authorization-rule keys list -g "$AZ_RESOURCE_GROUP" --namespace-name "$NS" \
    --authorization-rule-name students-listen --query primaryKey -o tsv)"
else
  LISTEN_KEY="(hidden - az eventhubs namespace authorization-rule keys list -g $AZ_RESOURCE_GROUP --namespace-name $NS --authorization-rule-name students-listen --query primaryKey -o tsv)"
fi

if [[ "$SECRETS_SOURCE" == "inline" ]]; then
  NEXT_STEPS="Done. .env now has EVENTHUB_NAMESPACE, EVENTHUB_CONNECTION_STRING and EVENTHUB_RDM_CONNECTION_STRING.
Then point the Azure apps at the hub (Solo 1.7), keeping the inline choice:
  SECRETS_SOURCE=inline BRIDGE_TARGET=eventhub DEPLOY_RDM_RELAY=true ./scripts/deploy-bridge.sh"
else
  NEXT_STEPS="Done. Add to .env:
  EVENTHUB_NAMESPACE=$NS
Then point the Azure apps at the hub (Solo 1.7):
  BRIDGE_TARGET=eventhub DEPLOY_RDM_RELAY=true ./scripts/deploy-bridge.sh"
fi

cat <<MSG

$NEXT_STEPS

Share with students over a private channel (never in a public repo or chat) - Eventstream > Azure Event Hubs source:
  Event Hub namespace : $NS
  Event hubs          : $NROD_HUB (-> RawFeed)   $RDM_HUB (-> RdmTrustRaw)
  Authentication      : Shared Access Key
  Key name            : students-listen
  Key                 : $LISTEN_KEY
  Consumer group      : their own, e.g. ${STUDENT_CONSUMER_GROUP_PREFIX:-student}01 (never \$Default, never shared)
  Data format         : JSON
Rotate the key after the course:
  az eventhubs namespace authorization-rule keys renew -g $AZ_RESOURCE_GROUP --namespace-name $NS --authorization-rule-name students-listen --key PrimaryKey
MSG
