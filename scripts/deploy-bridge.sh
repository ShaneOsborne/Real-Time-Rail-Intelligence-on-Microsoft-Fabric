#!/usr/bin/env bash
# Deploy the STOMP bridge to Azure Container Apps (Lab 05b, Option A).
#   ./scripts/deploy-bridge.sh            # build image in ACR and deploy
#   ./scripts/deploy-bridge.sh --what-if  # preview phase-1 infrastructure only
# Requires: az CLI (logged in), .env with NROD_* and EVENTSTREAM_CONNECTION_STRING.
# Optional shared Event Hub tier (Lab 05c; run scripts/create-eventhub.sh first):
#   BRIDGE_TARGET=eventhub  -> the bridge uses Key Vault secret eventhub-nrod-connection-string instead
#   DEPLOY_RDM_RELAY=true   -> also deploys <prefix>-rdm-relay (needs RDM_KAFKA_* in .env)
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az

WHAT_IF="${1:-}"
BRIDGE_TARGET="${BRIDGE_TARGET:-eventstream}"
DEPLOY_RDM_RELAY="${DEPLOY_RDM_RELAY:-false}"
case "$BRIDGE_TARGET" in
  eventstream) require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD EVENTSTREAM_CONNECTION_STRING ;;
  eventhub)    require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD ;;
  *) echo "ERROR: BRIDGE_TARGET must be 'eventstream' or 'eventhub'" >&2; exit 1 ;;
esac
if [[ "$DEPLOY_RDM_RELAY" == "true" ]]; then
  require RDM_KAFKA_BOOTSTRAP_SERVERS RDM_KAFKA_TOPIC RDM_KAFKA_CONSUMER_GROUP RDM_KAFKA_USERNAME RDM_KAFKA_PASSWORD
fi

NAME_PREFIX="${NAME_PREFIX:-railrti}"
IMAGE_TAG="${IMAGE_TAG:-$(date -u +%Y%m%d%H%M%S)}"
CPU="${BRIDGE_CPU:-0.25}"
MEMORY="${BRIDGE_MEMORY:-0.5Gi}"
TOPICS="${NROD_TOPICS:-TRAIN_MVT_ALL_TOC}"
CREATE_ACR=true
[[ -n "${CONTAINER_IMAGE:-}" ]] && CREATE_ACR=false

[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

log "Resource group $AZ_RESOURCE_GROUP ($AZ_LOCATION)"
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" -o none

DEPLOYER_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
DEPLOYER_TYPE=User
if [[ -z "$DEPLOYER_ID" ]]; then
  # Running as a service principal (e.g. CI)
  DEPLOYER_ID="$(az ad sp show --id "$(az account show --query user.name -o tsv)" --query id -o tsv)"
  DEPLOYER_TYPE=ServicePrincipal
fi

common_params=(
  --resource-group "$AZ_RESOURCE_GROUP"
  --template-file "$REPO_ROOT/infra/main.bicep"
  --parameters "@$REPO_ROOT/infra/main.parameters.json"
  --parameters location="$AZ_LOCATION" namePrefix="$NAME_PREFIX" createAcr="$CREATE_ACR"
               containerImage="${CONTAINER_IMAGE:-}" imageTag="$IMAGE_TAG" cpu="$CPU" memory="$MEMORY"
               nrodTopics="$TOPICS" deployerPrincipalId="$DEPLOYER_ID" deployerPrincipalType="$DEPLOYER_TYPE"
               keyVaultName="${KEY_VAULT_NAME:-}" bridgeTarget="$BRIDGE_TARGET" deployRdmRelay="$DEPLOY_RDM_RELAY"
               rdmKafkaBootstrapServers="${RDM_KAFKA_BOOTSTRAP_SERVERS:-}" rdmKafkaTopic="${RDM_KAFKA_TOPIC:-}"
               rdmKafkaConsumerGroup="${RDM_KAFKA_CONSUMER_GROUP:-}"
)

if [[ "$WHAT_IF" == "--what-if" ]]; then
  az deployment group what-if "${common_params[@]}" --parameters deployApp=false
  exit 0
fi

log "Phase 1: identity, Log Analytics, Key Vault (re-used if created in Lab 01), ACR, Container Apps environment"
az deployment group create -n bridge-phase1 "${common_params[@]}" --parameters deployApp=false -o none
KV_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase1 --query properties.outputs.keyVaultName.value -o tsv)"
ACR_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase1 --query properties.outputs.acrName.value -o tsv)"

log "Writing secrets to Key Vault $KV_NAME (retrying while RBAC propagates)"
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
# require_secret <name>: the shared Event Hub secrets are written by scripts/create-eventhub.sh
require_secret() {
  if ! az keyvault secret show --vault-name "$KV_NAME" -n "$1" --query id -o tsv >/dev/null 2>&1; then
    echo "ERROR: Key Vault secret '$1' not found in $KV_NAME. Run ./scripts/create-eventhub.sh first (Lab 05c)." >&2
    exit 1
  fi
  echo "  found $1"
}
set_secret nrod-username "$NROD_USERNAME"
set_secret nrod-password "$NROD_PASSWORD"
if [[ "$BRIDGE_TARGET" == "eventhub" ]]; then
  require_secret eventhub-nrod-connection-string
else
  set_secret eventstream-connection-string "$EVENTSTREAM_CONNECTION_STRING"
fi
if [[ "$DEPLOY_RDM_RELAY" == "true" ]]; then
  set_secret rdm-kafka-username "$RDM_KAFKA_USERNAME"
  set_secret rdm-kafka-password "$RDM_KAFKA_PASSWORD"
  require_secret eventhub-rdm-connection-string
fi

if [[ "$CREATE_ACR" == "true" ]]; then
  log "Building image rail-bridge:$IMAGE_TAG in ACR $ACR_NAME (az acr build - no local Docker needed)"
  az acr build -r "$ACR_NAME" -t "rail-bridge:$IMAGE_TAG" -t "rail-bridge:latest" "$REPO_ROOT/src/bridge" -o none
fi

log "Phase 2: container app (1 replica, ${CPU} vCPU / ${MEMORY}, target=$BRIDGE_TARGET, RDM relay=$DEPLOY_RDM_RELAY)"
for attempt in 1 2 3; do
  if az deployment group create -n bridge-phase2 "${common_params[@]}" --parameters deployApp=true -o none; then
    break
  fi
  [[ $attempt -eq 3 ]] && { echo "ERROR: phase 2 failed" >&2; exit 1; }
  echo "  phase 2 failed (often RBAC propagation for Key Vault/ACR); retrying in 60s..."; sleep 60
done

APP_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase2 --query properties.outputs.containerAppName.value -o tsv)"
RELAY_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase2 --query properties.outputs.relayAppName.value -o tsv)"
log "Done. Container app: $APP_NAME${RELAY_NAME:+ (RDM relay: $RELAY_NAME)}"
cat <<MSG
Follow logs:
  az containerapp logs show -g $AZ_RESOURCE_GROUP -n $APP_NAME --follow --format text
Check replica count (should be 1):
  az containerapp replica list -g $AZ_RESOURCE_GROUP -n $APP_NAME -o table
REMEMBER: stop any local bridge using the same NROD account / client-id.
MSG
if [[ -n "$RELAY_NAME" ]]; then
  echo "RDM relay logs: az containerapp logs show -g $AZ_RESOURCE_GROUP -n $RELAY_NAME --follow --format text"
  echo "REMEMBER: stop any local relay or Eventstream Kafka source using the same RDM consumer group."
fi
