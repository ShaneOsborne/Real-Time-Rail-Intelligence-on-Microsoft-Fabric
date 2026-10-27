#!/usr/bin/env bash
# Lab 11b: create an Azure Maps SAS token for the Rayfin app (max lifetime 24 hours, rate-limited).
#   ./scripts/new-azure-maps-sas.sh [hours=24] [maxRatePerSecond=50]
# Prints the token. Store it in the app with:  npx rayfin secret set AZURE_MAPS_TOKEN
# Requires .env: AZ_RESOURCE_GROUP, AZURE_MAPS_ACCOUNT_NAME, AZURE_MAPS_SAS_PRINCIPAL_ID (from create-azure-maps.sh).
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP AZURE_MAPS_ACCOUNT_NAME AZURE_MAPS_SAS_PRINCIPAL_ID
HOURS="${1:-24}"; RATE="${2:-50}"
[[ -n "${AZ_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZ_SUBSCRIPTION_ID"
SUB="$(az account show --query id -o tsv)"
START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXPIRY="$(date -u -d "+${HOURS} hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+"${HOURS}"H +%Y-%m-%dT%H:%M:%SZ)"
BODY="{\"signingKey\":\"primaryKey\",\"principalId\":\"$AZURE_MAPS_SAS_PRINCIPAL_ID\",\"maxRatePerSecond\":$RATE,\"start\":\"$START\",\"expiry\":\"$EXPIRY\"}"
az rest --method post \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$AZ_RESOURCE_GROUP/providers/Microsoft.Maps/accounts/$AZURE_MAPS_ACCOUNT_NAME/listSas?api-version=2023-06-01" \
  --body "$BODY" --query accountSasToken -o tsv
echo "Valid until $EXPIRY (UTC), max ~$RATE requests/second." >&2
