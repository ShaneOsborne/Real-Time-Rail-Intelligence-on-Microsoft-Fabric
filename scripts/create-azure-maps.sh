#!/usr/bin/env bash
# Lab 11b: create the Azure Maps account (Gen2) + SAS identity, and grant that identity
# "Azure Maps Search and Render Data Reader" on the account.
#   ./scripts/create-azure-maps.sh
# Requires: az CLI (logged in), .env with AZ_RESOURCE_GROUP and AZ_LOCATION (or AZURE_MAPS_LOCATION).
# Optional .env: AZURE_MAPS_ALLOWED_ORIGINS=https://<your-app>.webapp.fabricapps.net,http://localhost:5173
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP AZ_LOCATION

NAME_PREFIX="${NAME_PREFIX:-railrti}"
MAPS_LOCATION="${AZURE_MAPS_LOCATION:-$AZ_LOCATION}"
[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"

log "Registering the Microsoft.Maps provider (no-op if already registered)"
az provider register -n Microsoft.Maps --wait -o none

log "Resource group $AZ_RESOURCE_GROUP"
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" -o none

ORIGINS_JSON="[]"
if [[ -n "${AZURE_MAPS_ALLOWED_ORIGINS:-}" ]]; then
  ORIGINS_JSON="[$(echo "$AZURE_MAPS_ALLOWED_ORIGINS" | sed 's/[[:space:]]//g; s/[^,][^,]*/"&"/g')]"
fi

log "Azure Maps account (Gen2) + SAS identity in $MAPS_LOCATION"
az deployment group create -g "$AZ_RESOURCE_GROUP" -n azure-maps \
  --template-file "$REPO_ROOT/infra/azuremaps.bicep" \
  --parameters location="$MAPS_LOCATION" namePrefix="$NAME_PREFIX" allowedOrigins="$ORIGINS_JSON" -o none
q() { az deployment group show -g "$AZ_RESOURCE_GROUP" -n azure-maps --query "properties.outputs.$1.value" -o tsv; }
MAPS_NAME="$(q mapsAccountName)"; MAPS_ID="$(q mapsAccountId)"; PRINCIPAL_ID="$(q identityPrincipalId)"

log "Role 'Azure Maps Search and Render Data Reader' for the SAS identity (map tiles only)"
for i in {1..10}; do
  if az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
       --role "Azure Maps Search and Render Data Reader" --scope "$MAPS_ID" -o none 2>/dev/null; then break; fi
  echo "  waiting for the identity to replicate ($i/10)..."; sleep 15
done

cat <<MSG

Done. Add these to .env:
  AZURE_MAPS_ACCOUNT_NAME=$MAPS_NAME
  AZURE_MAPS_SAS_PRINCIPAL_ID=$PRINCIPAL_ID
Next: ./scripts/new-azure-maps-sas.sh   (creates a SAS token valid for up to 24 hours)
MSG
