# Lab 05b – Deploy the bridge to Azure Container Apps

**Time:** 30 minutes · **Previous:** [Lab 05a](05a-bridge-local.md) · **Next:** [Lab 06](06-kql-transformations.md)

## Objectives

* Host the bridge 24×7 on **Azure Container Apps**, with **exactly one replica** (min = max = 1) at **0.25 vCPU / 0.5 GiB**.
* Keep secrets in **Key Vault**, read through a **user-assigned managed identity**, and send logs to **Log Analytics**.
* Build the image in **Azure Container Registry**, or use a public **GHCR** image built by CI.

Cost: about **$14/month** list-price estimate after the free grant, plus small Log Analytics, Key Vault and ACR charges. For `TD_ALL_SIG_AREA`, set `BRIDGE_CPU=0.5` and `BRIDGE_MEMORY=1Gi`.

## Prerequisites

* The bridge works locally with the eventstream sink (Lab 05a), and `EVENTSTREAM_CONNECTION_STRING` is in `.env`.
* `AZ_RESOURCE_GROUP`, `AZ_LOCATION` (for example `uksouth`, close to your Fabric capacity) and `NAME_PREFIX` are set in `.env`.
* **Stop the local bridge** (one connection per NROD account / client-id).

## Option A – automated

```bash
az login
./scripts/deploy-bridge.sh --what-if     # optional preview
./scripts/deploy-bridge.sh               # or: ./scripts/deploy-bridge.ps1
```

What it does:
1. Phase 1 Bicep (`deployApp=false`) creates the identity, Log Analytics, Key Vault, ACR (unless `CONTAINER_IMAGE` is set) and the Container Apps environment.
2. Writes `nrod-username`, `nrod-password` and `eventstream-connection-string` to Key Vault, retrying while RBAC propagates.
3. Runs `az acr build`, so you don't need Docker locally.
4. Phase 2 Bicep (`deployApp=true`) deploys the container app with Key Vault secret references, probes on `/healthz` and 1 replica.

To use the image built by GitHub Actions instead (`.github/workflows/bridge-ci.yml` pushes it to GHCR), make the package public or add registry credentials, then set:

```bash
CONTAINER_IMAGE=ghcr.io/<owner>/rail-fabric-rti-bridge:latest
```

## Option B – manual

### B1. Infrastructure (portal or CLI)

```bash
RG=rg-rail-fabric-rti; LOC=uksouth
az group create -n $RG -l $LOC
ME=$(az ad signed-in-user show --query id -o tsv)
az deployment group create -g $RG -n bridge-phase1 -f infra/main.bicep -p @infra/main.parameters.json \
  -p deployApp=false deployerPrincipalId=$ME
KV=$(az deployment group show -g $RG -n bridge-phase1 --query properties.outputs.keyVaultName.value -o tsv)
ACR=$(az deployment group show -g $RG -n bridge-phase1 --query properties.outputs.acrName.value -o tsv)
```

To do it in the portal instead, create the same resources: a *Managed identity*, a *Log Analytics workspace*, a *Key Vault* (RBAC mode; grant yourself
*Key Vault Secrets Officer* and the identity *Key Vault Secrets User*), a *Container registry* (Basic; grant the identity *AcrPull*) and a
*Container Apps environment* (Consumption) linked to Log Analytics.

### B2. Secrets

```bash
az keyvault secret set --vault-name $KV -n nrod-username --value "<NROD email>"
az keyvault secret set --vault-name $KV -n nrod-password --value "<NROD password>"
az keyvault secret set --vault-name $KV -n eventstream-connection-string --value "<Endpoint=sb://...>"
```

Typing secrets on the command line can leave them in your shell history. Use the portal (*Key Vault → Secrets → Generate/Import*) if you'd rather avoid that.

### B3. Image

```bash
az acr build -r $ACR -t rail-bridge:v1 src/bridge
```

### B4. Container app

```bash
az deployment group create -g $RG -n bridge-phase2 -f infra/main.bicep -p @infra/main.parameters.json \
  -p deployApp=true imageTag=v1 deployerPrincipalId=$ME
```

In the portal, you'd create a *Container App* with: image `<acr>.azurecr.io/rail-bridge:v1` pulled with the managed identity;
**0.25 CPU / 0.5 Gi**; **Scale min 1 / max 1**; ingress **disabled**; secrets as **Key Vault references** (identity = the UAMI);
environment variables `BRIDGE_SINK=eventstream`, `BRIDGE_SOURCE=stomp`, `NROD_TOPICS=…`, and `NROD_USERNAME`, `NROD_PASSWORD` and `EVENTSTREAM_CONNECTION_STRING` → *Reference a secret*;
and a liveness probe of HTTP GET `/healthz` on port 8080.

## Checkpoint

```bash
APP=${NAME_PREFIX:-railrti}-bridge
az containerapp replica list -g $RG -n $APP -o table          # exactly 1 replica
az containerapp logs show -g $RG -n $APP --follow --format text
```

In Log Analytics (*Logs*):

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s endswith "-bridge"
| project TimeGenerated, Log_s
| order by TimeGenerated desc
| take 50
```

(Table and column names depend on the environment's logging configuration. Newer environments may use `ContainerAppConsoleLogs`.)

In Fabric, `RawFeed | summarize max(received_utc)` should advance every few seconds.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Phase 2 fails with a Key Vault reference error | RBAC propagation can take a few minutes. The script retries. Re-run it if needed |
| `ImagePullBackOff` / unauthorized | The identity is missing *AcrPull*, or the GHCR image is private |
| App restarts repeatedly | Check the logs for NROD login errors. Make sure no local bridge uses the same client-id |
| Replica count shows 0 | `minReplicas` must be 1. Re-deploy phase 2 |
| CPU throttling with TD | Increase to `0.5` vCPU / `1Gi` |
| Rotating the Eventstream key | Update the Key Vault secret, then `az containerapp revision restart` (or deploy a new revision) |
