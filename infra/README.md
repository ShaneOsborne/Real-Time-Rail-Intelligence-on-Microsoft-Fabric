# Infrastructure (Bicep)

`main.bicep` deploys the STOMP bridge hosting into one resource group:

| Resource | Notes |
|---|---|
| User-assigned managed identity | Pulls images from ACR and reads Key Vault secrets |
| Log Analytics workspace | Container Apps console logs. Retention is 30 days by default |
| Key Vault (RBAC mode) | Secrets `nrod-username`, `nrod-password` and `eventstream-connection-string`. The deployer gets *Key Vault Secrets Officer* and the identity gets *Key Vault Secrets User* |
| Azure Container Registry (Basic, optional) | `createAcr=false` together with `containerImage=ghcr.io/...` uses a public image instead |
| Container Apps environment | Consumption workload profile |
| Container app (phase 2) | **minReplicas = maxReplicas = 1** with **0.25 vCPU / 0.5 GiB**, no ingress, liveness and startup probes on `/healthz`, and secrets as Key Vault references |

## Two-phase deployment

Container Apps resolves Key Vault secret references when it creates a revision, so the secrets have to exist first:

1. `deployApp=false` deploys the identity, logs, Key Vault, ACR and environment.
2. Write the secrets to Key Vault, then build the image (`az acr build`).
3. `deployApp=true` deploys the container app.

`scripts/deploy-bridge.sh` and `scripts/deploy-bridge.ps1` do all three steps and retry while RBAC role assignments propagate.

## Manual commands

```bash
az group create -n rg-rail-fabric-rti -l uksouth
az deployment group create -g rg-rail-fabric-rti -f infra/main.bicep -p @infra/main.parameters.json \
  -p deployApp=false deployerPrincipalId=$(az ad signed-in-user show --query id -o tsv)
# ... set secrets, build image ...
az deployment group create -g rg-rail-fabric-rti -f infra/main.bicep -p @infra/main.parameters.json \
  -p deployApp=true imageTag=<tag> deployerPrincipalId=$(az ad signed-in-user show --query id -o tsv)
```

Validate without deploying: `az bicep build --file infra/main.bicep` or `./scripts/deploy-bridge.sh --what-if`.
