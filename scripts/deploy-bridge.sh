#!/usr/bin/env bash
# Deploy the STOMP bridge to Azure Container Apps (Lab 05b, Option A).
#   ./scripts/deploy-bridge.sh            # build image in ACR and deploy
#   ./scripts/deploy-bridge.sh --what-if  # preview phase-1 infrastructure only
# Requires: az CLI (logged in), .env with NROD_* and EVENTSTREAM_CONNECTION_STRING.
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az

WHAT_IF="${1:-}"
require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD EVENTSTREAM_CONNECTION_STRING

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
)

if [[ "$WHAT_IF" == "--what-if" ]]; then
  az deployment group what-if "${common_params[@]}" --parameters deployApp=false
  exit 0
fi

log "Phase 1: identity, Log Analytics, Key Vault, ACR, Container Apps environment"
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
set_secret nrod-username "$NROD_USERNAME"
set_secret nrod-password "$NROD_PASSWORD"
set_secret eventstream-connection-string "$EVENTSTREAM_CONNECTION_STRING"

if [[ "$CREATE_ACR" == "true" ]]; then
  log "Building image rail-bridge:$IMAGE_TAG in ACR $ACR_NAME (az acr build - no local Docker needed)"
  az acr build -r "$ACR_NAME" -t "rail-bridge:$IMAGE_TAG" -t "rail-bridge:latest" "$REPO_ROOT/src/bridge" -o none
fi

log "Phase 2: container app (1 replica, ${CPU} vCPU / ${MEMORY})"
for attempt in 1 2 3; do
  if az deployment group create -n bridge-phase2 "${common_params[@]}" --parameters deployApp=true -o none; then
    break
  fi
  [[ $attempt -eq 3 ]] && { echo "ERROR: phase 2 failed" >&2; exit 1; }
  echo "  phase 2 failed (often RBAC propagation for Key Vault/ACR); retrying in 60s..."; sleep 60
done

APP_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase2 --query properties.outputs.containerAppName.value -o tsv)"
log "Done. Container app: $APP_NAME"
cat <<MSG
Follow logs:
  az containerapp logs show -g $AZ_RESOURCE_GROUP -n $APP_NAME --follow --format text
Check replica count (should be 1):
  az containerapp replica list -g $AZ_RESOURCE_GROUP -n $APP_NAME -o table
REMEMBER: stop any local bridge using the same NROD account / client-id.
MSG
