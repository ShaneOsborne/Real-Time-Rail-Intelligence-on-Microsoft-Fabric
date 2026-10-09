<#
.SYNOPSIS
  Deploy the STOMP bridge to Azure Container Apps (Lab 05b, Option A).
  Optional shared Event Hub tier (Lab 05c; run scripts/create-eventhub.ps1 first):
    BRIDGE_TARGET=eventhub  -> the bridge uses Key Vault secret eventhub-nrod-connection-string
    DEPLOY_RDM_RELAY=true   -> also deploys <prefix>-rdm-relay (needs RDM_KAFKA_* in .env)
.EXAMPLE
  ./scripts/deploy-bridge.ps1
  ./scripts/deploy-bridge.ps1 -WhatIf
#>
param([switch]$WhatIf)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
$target = if ($env:BRIDGE_TARGET) { $env:BRIDGE_TARGET } else { 'eventstream' }
$deployRelay = if ($env:DEPLOY_RDM_RELAY -eq 'true') { 'true' } else { 'false' }
switch ($target) {
    'eventstream' { Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION', 'NROD_USERNAME', 'NROD_PASSWORD', 'EVENTSTREAM_CONNECTION_STRING') }
    'eventhub' { Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION', 'NROD_USERNAME', 'NROD_PASSWORD') }
    default { throw "BRIDGE_TARGET must be 'eventstream' or 'eventhub'" }
}
if ($deployRelay -eq 'true') {
    Assert-Env @('RDM_KAFKA_BOOTSTRAP_SERVERS', 'RDM_KAFKA_TOPIC', 'RDM_KAFKA_CONSUMER_GROUP', 'RDM_KAFKA_USERNAME', 'RDM_KAFKA_PASSWORD')
}

$prefix = if ($env:NAME_PREFIX) { $env:NAME_PREFIX } else { 'railrti' }
$tag = if ($env:IMAGE_TAG) { $env:IMAGE_TAG } else { (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') }
$cpu = if ($env:BRIDGE_CPU) { $env:BRIDGE_CPU } else { '0.25' }
$memory = if ($env:BRIDGE_MEMORY) { $env:BRIDGE_MEMORY } else { '0.5Gi' }
$topics = if ($env:NROD_TOPICS) { $env:NROD_TOPICS } else { 'TRAIN_MVT_ALL_TOC' }
$createAcr = if ($env:CONTAINER_IMAGE) { 'false' } else { 'true' }
$rg = $env:AZ_RESOURCE_GROUP

if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }

Write-Step "Resource group $rg ($($env:AZ_LOCATION))"
Invoke-Az group create -n $rg -l $env:AZ_LOCATION -o none

$deployerId = az ad signed-in-user show --query id -o tsv 2>$null
$deployerType = 'User'
if (-not $deployerId) {
    $appId = az account show --query user.name -o tsv
    $deployerId = az ad sp show --id $appId --query id -o tsv
    $deployerType = 'ServicePrincipal'
}

$common = @(
    '--resource-group', $rg,
    '--template-file', (Join-Path $script:RepoRoot 'infra/main.bicep'),
    '--parameters', ('@' + (Join-Path $script:RepoRoot 'infra/main.parameters.json')),
    '--parameters', "location=$($env:AZ_LOCATION)", "namePrefix=$prefix", "createAcr=$createAcr",
    "containerImage=$($env:CONTAINER_IMAGE)", "imageTag=$tag", "cpu=$cpu", "memory=$memory",
    "nrodTopics=$topics", "deployerPrincipalId=$deployerId", "deployerPrincipalType=$deployerType",
    "keyVaultName=$($env:KEY_VAULT_NAME)", "bridgeTarget=$target", "deployRdmRelay=$deployRelay",
    "rdmKafkaBootstrapServers=$($env:RDM_KAFKA_BOOTSTRAP_SERVERS)", "rdmKafkaTopic=$($env:RDM_KAFKA_TOPIC)",
    "rdmKafkaConsumerGroup=$($env:RDM_KAFKA_CONSUMER_GROUP)"
)

if ($WhatIf) { Invoke-Az deployment group what-if @common --parameters deployApp=false; return }

Write-Step 'Phase 1: identity, Log Analytics, Key Vault (re-used if created in Lab 01), ACR, Container Apps environment'
Invoke-Az deployment group create -n bridge-phase1 @common --parameters deployApp=false -o none
$kv = az deployment group show -g $rg -n bridge-phase1 --query properties.outputs.keyVaultName.value -o tsv
$acr = az deployment group show -g $rg -n bridge-phase1 --query properties.outputs.acrName.value -o tsv

Write-Step "Writing secrets to Key Vault $kv (retrying while RBAC propagates)"
function Set-KvSecret([string]$Name, [string]$Value) {
    for ($i = 1; $i -le 10; $i++) {
        az keyvault secret set --vault-name $kv -n $Name --value $Value -o none 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "  set $Name"; return }
        Write-Host "  waiting for Key Vault permissions ($i/10)..."; Start-Sleep -Seconds 15
    }
    throw "Could not write secret $Name"
}
function Assert-KvSecret([string]$Name) {
    # The shared Event Hub secrets are written by scripts/create-eventhub.ps1
    az keyvault secret show --vault-name $kv -n $Name --query id -o tsv 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Key Vault secret '$Name' not found in $kv. Run ./scripts/create-eventhub.ps1 first (Lab 05c)." }
    Write-Host "  found $Name"
}
Set-KvSecret 'nrod-username' $env:NROD_USERNAME
Set-KvSecret 'nrod-password' $env:NROD_PASSWORD
if ($target -eq 'eventhub') { Assert-KvSecret 'eventhub-nrod-connection-string' }
else { Set-KvSecret 'eventstream-connection-string' $env:EVENTSTREAM_CONNECTION_STRING }
if ($deployRelay -eq 'true') {
    Set-KvSecret 'rdm-kafka-username' $env:RDM_KAFKA_USERNAME
    Set-KvSecret 'rdm-kafka-password' $env:RDM_KAFKA_PASSWORD
    Assert-KvSecret 'eventhub-rdm-connection-string'
}

if ($createAcr -eq 'true') {
    Write-Step "Building image rail-bridge:$tag in ACR $acr"
    Invoke-Az acr build -r $acr -t "rail-bridge:$tag" -t 'rail-bridge:latest' (Join-Path $script:RepoRoot 'src/bridge') -o none
}

Write-Step "Phase 2: container app (1 replica, $cpu vCPU / $memory, target=$target, RDM relay=$deployRelay)"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    az deployment group create -n bridge-phase2 @common --parameters deployApp=true -o none
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq 3) { throw 'Phase 2 failed' }
    Write-Host '  phase 2 failed (often RBAC propagation); retrying in 60s...'; Start-Sleep -Seconds 60
}
$app = az deployment group show -g $rg -n bridge-phase2 --query properties.outputs.containerAppName.value -o tsv
$relay = az deployment group show -g $rg -n bridge-phase2 --query properties.outputs.relayAppName.value -o tsv
Write-Step "Done. Container app: $app"
Write-Host "Logs:     az containerapp logs show -g $rg -n $app --follow --format text"
Write-Host "Replicas: az containerapp replica list -g $rg -n $app -o table"
Write-Host 'REMEMBER: stop any local bridge using the same NROD account / client-id.'
if ($relay) {
    Write-Host "RDM relay logs: az containerapp logs show -g $rg -n $relay --follow --format text"
    Write-Host 'REMEMBER: stop any local relay or Eventstream Kafka source using the same RDM consumer group.'
}
