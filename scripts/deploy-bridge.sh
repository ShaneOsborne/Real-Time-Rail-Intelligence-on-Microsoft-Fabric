#!/usr/bin/env bash
# Deploy the STOMP bridge to Azure Container Apps (Solo 1.7, Option A).
#   ./scripts/deploy-bridge.sh            # build image in ACR and deploy
#   ./scripts/deploy-bridge.sh --what-if  # preview phase-1 infrastructure only
# Requires: az CLI (logged in), .env with NROD_* and EVENTSTREAM_CONNECTION_STRING.
# Optional shared Event Hub tier (Instructor 1.4 / Solo 1.8; run scripts/create-eventhub.sh first):
#   BRIDGE_TARGET=eventhub  -> the bridge uses Key Vault secret eventhub-nrod-connection-string instead
#   DEPLOY_RDM_RELAY=true   -> also deploys <prefix>-rdm-relay (needs RDM_KAFKA_* in .env)
# Subscriptions whose policy blocks public access to Key Vault:
#   SECRETS_SOURCE=inline   -> store the secrets as encrypted Container Apps secrets instead of Key Vault references
# Event Hubs namespaces whose policy disables key (shared access) sign-in:
#   EVENTHUB_AUTH=entra     -> the bridge/relay sign in to the shared Event Hub with their managed identity
#                              (Azure Event Hubs Data Sender on EVENTHUB_NAMESPACE); no Event Hub connection strings
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az

WHAT_IF="${1:-}"
BRIDGE_TARGET="${BRIDGE_TARGET:-eventstream}"
DEPLOY_RDM_RELAY="${DEPLOY_RDM_RELAY:-false}"
SECRETS_SOURCE="${SECRETS_SOURCE:-keyvault}"
case "$SECRETS_SOURCE" in keyvault|inline) ;; *) echo "ERROR: SECRETS_SOURCE must be 'keyvault' or 'inline'" >&2; exit 1 ;; esac
EVENTHUB_AUTH="${EVENTHUB_AUTH:-key}"
case "$EVENTHUB_AUTH" in key|entra) ;; *) echo "ERROR: EVENTHUB_AUTH must be 'key' or 'entra'" >&2; exit 1 ;; esac
# Event Hub connection strings are only needed with key sign-in
EH_KEYS=false; [[ "$EVENTHUB_AUTH" == "key" ]] && EH_KEYS=true
case "$BRIDGE_TARGET" in
  eventstream) require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD EVENTSTREAM_CONNECTION_STRING ;;
  eventhub)    require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD
               [[ "$SECRETS_SOURCE" == "inline" && "$EH_KEYS" == "true" ]] && require EVENTHUB_CONNECTION_STRING
               [[ "$EH_KEYS" == "false" ]] && require EVENTHUB_NAMESPACE ;;
  *) echo "ERROR: BRIDGE_TARGET must be 'eventstream' or 'eventhub'" >&2; exit 1 ;;
esac
if [[ "$DEPLOY_RDM_RELAY" == "true" ]]; then
  require RDM_KAFKA_BOOTSTRAP_SERVERS RDM_KAFKA_TOPIC RDM_KAFKA_CONSUMER_GROUP RDM_KAFKA_USERNAME RDM_KAFKA_PASSWORD
  [[ "$SECRETS_SOURCE" == "inline" && "$EH_KEYS" == "true" ]] && require EVENTHUB_RDM_CONNECTION_STRING
  [[ "$EH_KEYS" == "false" ]] && require EVENTHUB_NAMESPACE
  # The relay feeds rdm-trust -> RdmTrustRaw, which expects NWR Train Movements (TRUST). Darwin has its own path (Solo 1.5).
  topic_lc="$(printf '%s' "$RDM_KAFKA_TOPIC" | tr '[:upper:]' '[:lower:]')"
  if [[ "$topic_lc" == *darwin* || "$topic_lc" == *push-port* || "$topic_lc" == *pushport* ]] && [[ "${ALLOW_DARWIN_RELAY:-false}" != "true" ]]; then
    echo "ERROR: RDM_KAFKA_TOPIC looks like the Darwin Push Port topic: $RDM_KAFKA_TOPIC" >&2
    echo "       The RDM relay sends to rdm-trust (RdmTrustRaw), which expects NWR Train Movements. Put the Train Movements" >&2
    echo "       topic, consumer group, username and password in RDM_KAFKA_* (as in your Solo 1.4 Kafka source)." >&2
    echo "       Darwin keeps its own Eventstream source (Solo 1.5). Set ALLOW_DARWIN_RELAY=true only if you really mean it." >&2
    exit 1
  fi
fi

NAME_PREFIX="${NAME_PREFIX:-railrti}"
IMAGE_TAG="${IMAGE_TAG:-$(date -u +%Y%m%d%H%M%S)}"
CPU="${BRIDGE_CPU:-0.25}"
MEMORY="${BRIDGE_MEMORY:-0.5Gi}"
TOPICS="${NROD_TOPICS:-RTPPM_ALL}"
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
               rdmKafkaConsumerGroup="${RDM_KAFKA_CONSUMER_GROUP:-}" secretsSource="$SECRETS_SOURCE"
               eventhubAuth="$EVENTHUB_AUTH" eventhubNamespace="${EVENTHUB_NAMESPACE:-}"
)

if [[ "$WHAT_IF" == "--what-if" ]]; then
  az deployment group what-if "${common_params[@]}" --parameters deployApp=false
  exit 0
fi

log "Phase 1: identity, Log Analytics, Key Vault (re-used if created in Solo 1.1), ACR, Container Apps environment"
az deployment group create -n bridge-phase1 "${common_params[@]}" --parameters deployApp=false -o none
KV_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase1 --query properties.outputs.keyVaultName.value -o tsv)"
ACR_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase1 --query properties.outputs.acrName.value -o tsv)"

phase2_params=()
if [[ "$SECRETS_SOURCE" == "inline" ]]; then
  log "Secrets: inline (encrypted Container Apps secrets from .env - Key Vault not used at runtime)"
  # Secure values go in a temporary parameters file (not on the command line), deleted when the script exits.
  SECRETS_FILE="$(mktemp)"; chmod 600 "$SECRETS_FILE"; trap 'rm -f "$SECRETS_FILE"' EXIT
  # Git Bash on Windows: Windows python/az need a Windows path (C:/...), not /tmp/...
  SECRETS_ARG="$SECRETS_FILE"; command -v cygpath >/dev/null 2>&1 && SECRETS_ARG="$(cygpath -m "$SECRETS_FILE")"
  PY="$(command -v python3 || command -v python || true)"
  [[ -n "$PY" ]] || { echo "ERROR: SECRETS_SOURCE=inline needs Python on the PATH (activate the .venv)" >&2; exit 1; }
  if [[ "$BRIDGE_TARGET" == "eventhub" ]]; then BRIDGE_CS="${EVENTHUB_CONNECTION_STRING:-}"; else BRIDGE_CS="${EVENTSTREAM_CONNECTION_STRING:-}"; fi
  BRIDGE_CS="$BRIDGE_CS" "$PY" - "$SECRETS_ARG" <<'PYEOF'
import json, os, sys
v = lambda k: os.environ.get(k, "")
params = {
    "nrodUsernameValue": v("NROD_USERNAME"), "nrodPasswordValue": v("NROD_PASSWORD"),
    "bridgeConnectionStringValue": v("BRIDGE_CS"),
    "rdmKafkaUsernameValue": v("RDM_KAFKA_USERNAME"), "rdmKafkaPasswordValue": v("RDM_KAFKA_PASSWORD"),
    "eventhubRdmConnectionStringValue": v("EVENTHUB_RDM_CONNECTION_STRING"),
}
doc = {"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
       "contentVersion": "1.0.0.0", "parameters": {k: {"value": x} for k, x in params.items()}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc))
PYEOF
  phase2_params=(--parameters "@$SECRETS_ARG")
else
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
    echo "ERROR: Key Vault secret '$1' not found in $KV_NAME. Run ./scripts/create-eventhub.sh first (Instructor 1.4 / Solo 1.8)." >&2
    exit 1
  fi
  echo "  found $1"
}
set_secret nrod-username "$NROD_USERNAME"
set_secret nrod-password "$NROD_PASSWORD"
if [[ "$BRIDGE_TARGET" == "eventhub" ]]; then
  [[ "$EH_KEYS" == "true" ]] && require_secret eventhub-nrod-connection-string
else
  set_secret eventstream-connection-string "$EVENTSTREAM_CONNECTION_STRING"
fi
if [[ "$DEPLOY_RDM_RELAY" == "true" ]]; then
  set_secret rdm-kafka-username "$RDM_KAFKA_USERNAME"
  set_secret rdm-kafka-password "$RDM_KAFKA_PASSWORD"
  [[ "$EH_KEYS" == "true" ]] && require_secret eventhub-rdm-connection-string
fi

fi

if [[ "$CREATE_ACR" == "true" ]]; then
  log "Building image rail-bridge:$IMAGE_TAG in ACR $ACR_NAME (az acr build - no local Docker needed)"
  az acr build -r "$ACR_NAME" -t "rail-bridge:$IMAGE_TAG" -t "rail-bridge:latest" "$REPO_ROOT/src/bridge" -o none
fi

log "Phase 2: container app (1 replica, ${CPU} vCPU / ${MEMORY}, target=$BRIDGE_TARGET, RDM relay=$DEPLOY_RDM_RELAY)"
for attempt in 1 2 3; do
  if az deployment group create -n bridge-phase2 "${common_params[@]}" "${phase2_params[@]}" --parameters deployApp=true -o none; then
    break
  fi
  if [[ $attempt -eq 3 ]]; then
    echo "ERROR: phase 2 failed." >&2
    [[ "$SECRETS_SOURCE" == "keyvault" ]] && echo "If the error says 'unable to fetch secret ... using Managed identity', Container Apps can't reach Key Vault (often a policy that disables public access or adds a firewall). Re-run with: SECRETS_SOURCE=inline ./scripts/deploy-bridge.sh" >&2
    exit 1
  fi
  echo "  phase 2 failed (often RBAC propagation for Key Vault/ACR); retrying in 60s..."; sleep 60
done

APP_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase2 --query properties.outputs.containerAppName.value -o tsv)"
RELAY_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n bridge-phase2 --query properties.outputs.relayAppName.value -o tsv)"
# A Container App keeps the secret values it started with until it restarts, and a deployment that only changes
# secrets creates no new revision. Restart the active revisions so changed secrets (inline or Key Vault) apply now.
restart_app() {
  local app="$1" rev
  for rev in $(az containerapp revision list -g "$AZ_RESOURCE_GROUP" -n "$app" --query "[?properties.active].name" -o tsv | tr -d '\r'); do
    if az containerapp revision restart -g "$AZ_RESOURCE_GROUP" -n "$app" --revision "$rev" -o none 2>/dev/null; then
      echo "  restarted $app ($rev)"
    else
      echo "  WARNING: could not restart $app ($rev). Restart it in the portal: Container App > Revisions and replicas > Restart" >&2
    fi
  done
}
# A deployment doesn't start an app that someone stopped (portal Stop / az containerapp stop). Start it again.
# Uses the REST API because older az CLI versions have no 'az containerapp start'.
start_if_stopped() {
  local app="$1" id status
  status="$(az containerapp show -g "$AZ_RESOURCE_GROUP" -n "$app" --query properties.runningStatus -o tsv 2>/dev/null | tr -d '\r')"
  if [[ "$status" == "Stopped" ]]; then
    id="$(az containerapp show -g "$AZ_RESOURCE_GROUP" -n "$app" --query id -o tsv | tr -d '\r')"
    if MSYS_NO_PATHCONV=1 az rest --method post --url "https://management.azure.com${id}/start?api-version=2024-03-01" -o none; then
      echo "  started $app (it was stopped)"
    else
      echo "  WARNING: $app is stopped and could not be started. Start it in the portal: Container App > Overview > Start" >&2
    fi
  fi
}
log "Starting stopped apps and restarting running ones so the latest secrets and settings are used"
start_if_stopped "$APP_NAME"
[[ -n "$RELAY_NAME" ]] && start_if_stopped "$RELAY_NAME"
restart_app "$APP_NAME"
[[ -n "$RELAY_NAME" ]] && restart_app "$RELAY_NAME"
if [[ "$EH_KEYS" == "false" ]]; then
  echo "  Entra ID sign-in: the apps' identity has 'Azure Event Hubs Data Sender' on $EVENTHUB_NAMESPACE."
  echo "  A new role assignment can take a few minutes; until then the logs show 'sink send failed' and the app retries."
fi

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
