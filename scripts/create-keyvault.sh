#!/usr/bin/env bash
# Create the shared Key Vault and store the NROD credentials (Lab 01, step 8).
# Lab 03 (Fabric notebook) reads them from here; Lab 05b re-uses the same vault.
#   ./scripts/create-keyvault.sh
# Requires: az CLI (logged in), .env with AZ_RESOURCE_GROUP, AZ_LOCATION, NROD_USERNAME, NROD_PASSWORD.
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP AZ_LOCATION NROD_USERNAME NROD_PASSWORD

NAME_PREFIX="${NAME_PREFIX:-railrti}"
[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

log "Resource group $AZ_RESOURCE_GROUP ($AZ_LOCATION)"
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" -o none

DEPLOYER_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
DEPLOYER_TYPE=User
if [[ -z "$DEPLOYER_ID" ]]; then
  DEPLOYER_ID="$(az ad sp show --id "$(az account show --query user.name -o tsv)" --query id -o tsv)"
  DEPLOYER_TYPE=ServicePrincipal
fi

log "Key Vault (RBAC mode) + Key Vault Secrets Officer for you"
az deployment group create -g "$AZ_RESOURCE_GROUP" -n shared-keyvault \
  --template-file "$REPO_ROOT/infra/keyvault.bicep" \
  --parameters location="$AZ_LOCATION" namePrefix="$NAME_PREFIX" keyVaultName="${KEY_VAULT_NAME:-}" \
               deployerPrincipalId="$DEPLOYER_ID" deployerPrincipalType="$DEPLOYER_TYPE" -o none
KV_NAME="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-keyvault --query properties.outputs.keyVaultName.value -o tsv)"
KV_URI="$(az deployment group show -g "$AZ_RESOURCE_GROUP" -n shared-keyvault --query properties.outputs.keyVaultUri.value -o tsv)"

log "Writing NROD secrets to $KV_NAME (retrying while RBAC propagates)"
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

cat <<MSG

Done. Add these to .env:
  KEY_VAULT_NAME=$KV_NAME
  KEY_VAULT_URL=$KV_URI
Use KEY_VAULT_URL in the Lab 03 notebook. Lab 05b will re-use this vault and add the
eventstream-connection-string secret (keep AZ_RESOURCE_GROUP and NAME_PREFIX unchanged).
MSG
