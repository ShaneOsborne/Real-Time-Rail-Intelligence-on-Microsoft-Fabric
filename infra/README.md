# Infrastructure (Bicep)

`main.bicep` deploys the STOMP bridge hosting into one resource group:

| Resource | Notes |
|---|---|
| User-assigned managed identity | Pulls images from ACR and reads Key Vault secrets |
| Log Analytics workspace | Container Apps console logs. Retention is 30 days by default |
| Key Vault (RBAC mode) | Usually created earlier by `keyvault.bicep` (Lab 01, step 8) and re-used here: same resource group + `namePrefix` gives the same name, or pass `keyVaultName`. Secrets `nrod-username`, `nrod-password` and `eventstream-connection-string`. The deployer gets *Key Vault Secrets Officer* and the identity gets *Key Vault Secrets User* |
| Azure Container Registry (Basic, optional) | `createAcr=false` together with `containerImage=ghcr.io/...` uses a public image instead |
| Container Apps environment | Consumption workload profile |
| Container app (phase 2) | **minReplicas = maxReplicas = 1** with **0.25 vCPU / 0.5 GiB**, no ingress, liveness and startup probes on `/healthz`, and secrets as Key Vault references |
| *Optional:* RDM relay container app (phase 2, `deployRdmRelay=true`) | `<namePrefix>-rdm-relay`: same image with `BRIDGE_SOURCE=kafka`, `BRIDGE_SINK=eventhub`, 1 replica, 0.25 vCPU / 0.5 GiB. Secrets `rdm-kafka-username`, `rdm-kafka-password`, `eventhub-rdm-connection-string` |

Optional shared Event Hub parameters (Lab 05c). The defaults keep the original behaviour:

| Parameter | Default | Effect |
|---|---|---|
| `bridgeTarget` | `eventstream` | `eventhub`: the bridge reads `eventhub-nrod-connection-string` into `EVENTHUB_CONNECTION_STRING` and runs with `BRIDGE_SINK=eventhub` |
| `deployRdmRelay` | `false` | `true`: deploys the RDM relay app (needs `rdmKafkaBootstrapServers`, `rdmKafkaTopic`, `rdmKafkaConsumerGroup`) |

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

Validate without deploying: `az bicep build --file infra/main.bicep` (and `infra/eventhubs.bicep`), `./scripts/deploy-bridge.sh --what-if` or `./scripts/create-eventhub.sh --what-if`.

## `eventhubs.bicep` (optional, Lab 05c)

The shared Event Hubs tier, deployed by `scripts/create-eventhub.sh` / `.ps1` (deployment name `shared-eventhubs`):

| Resource | Notes |
|---|---|
| Event Hubs namespace (`Microsoft.EventHub/namespaces@2024-01-01`) | **Standard**, `throughputUnits` (default 1), public network access, TLS 1.2, SAS enabled. Basic isn't offered: 1 consumer group and 1-day retention |
| Event hubs `nrod-feed` and `rdm-trust` | `partitionCount` 2, `messageRetentionInDays` = `retentionDays` (default 7, the Standard maximum) |
| `bridge-send` rule on each hub | **Send** only. The script stores the connection strings in Key Vault as `eventhub-nrod-connection-string` and `eventhub-rdm-connection-string` |
| `students-listen` rule on the namespace | **Listen** only. Students use it in their Eventstream Azure Event Hubs source |
| Consumer groups | `studentConsumerGroups` (array, max 19) on both hubs. `$Default` exists automatically and is kept for the instructor |

No keys appear in the outputs. The scripts read them with `az eventhubs eventhub authorization-rule keys list` and
`az eventhubs namespace authorization-rule keys list`. `scripts/add-student-consumer-groups.sh` / `.ps1` adds groups later with the CLI.

```bash
az deployment group create -g rg-rail-fabric-rti -n shared-eventhubs -f infra/eventhubs.bicep \
  -p namePrefix=railrti studentConsumerGroups='["student01","student02"]'
```

## `keyvault.bicep` (Lab 01)

Deploys only the shared Key Vault (RBAC mode, 7-day soft delete) and grants the deployer *Key Vault Secrets Officer*. Its name, properties and role-assignment names match `main.bicep`, so the Lab 05b deployment updates the same vault rather than creating another. Run it with `scripts/create-keyvault.sh` / `.ps1`.
