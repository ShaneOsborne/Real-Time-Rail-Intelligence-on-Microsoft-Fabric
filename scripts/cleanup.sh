#!/usr/bin/env bash
# Remove Azure resources (and optionally the Fabric workspace) created by the labs.
#   ./scripts/cleanup.sh            # delete the Azure resource group
#   ./scripts/cleanup.sh --fabric   # also delete the Fabric workspace in FABRIC_WORKSPACE_ID
source "$(dirname "$0")/_common.sh"
load_env
need_cmd az
require AZ_RESOURCE_GROUP

read -r -p "Delete resource group '$AZ_RESOURCE_GROUP' and everything in it? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  az group delete -n "$AZ_RESOURCE_GROUP" --yes --no-wait
  echo "Deletion started. Key Vault is soft-deleted (7 days); purge with:"
  echo "  az keyvault list-deleted -o table && az keyvault purge -n <name>"
fi

if [[ "${1:-}" == "--fabric" ]]; then
  require FABRIC_WORKSPACE_ID
  read -r -p "Delete Fabric workspace $FABRIC_WORKSPACE_ID (all items inside)? [y/N] " ans2
  if [[ "$ans2" =~ ^[Yy]$ ]]; then
    az rest --method delete --resource "https://api.fabric.microsoft.com" \
      --url "https://api.fabric.microsoft.com/v1/workspaces/$FABRIC_WORKSPACE_ID"
    echo "Fabric workspace deleted."
  fi
fi
echo "Also: stop any local bridge (docker compose down), remove the Foundry agent/connection, and pause or delete your Fabric capacity if it was created for this lab."
