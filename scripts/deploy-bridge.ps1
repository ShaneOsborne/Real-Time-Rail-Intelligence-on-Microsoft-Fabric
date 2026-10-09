<#
.SYNOPSIS
  Deploy the STOMP bridge to Azure Container Apps (Lab 05b, Option A).
.EXAMPLE
  ./scripts/deploy-bridge.ps1
  ./scripts/deploy-bridge.ps1 -WhatIf
#>
param([switch]$WhatIf)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION', 'NROD_USERNAME', 'NROD_PASSWORD', 'EVENTSTREAM_CONNECTION_STRING')

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
    "keyVaultName=$($env:KEY_VAULT_NAME)"
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
Set-KvSecret 'nrod-username' $env:NROD_USERNAME
Set-KvSecret 'nrod-password' $env:NROD_PASSWORD
Set-KvSecret 'eventstream-connection-string' $env:EVENTSTREAM_CONNECTION_STRING

if ($createAcr -eq 'true') {
    Write-Step "Building image rail-bridge:$tag in ACR $acr"
    Invoke-Az acr build -r $acr -t "rail-bridge:$tag" -t 'rail-bridge:latest' (Join-Path $script:RepoRoot 'src/bridge') -o none
}

Write-Step "Phase 2: container app (1 replica, $cpu vCPU / $memory)"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    az deployment group create -n bridge-phase2 @common --parameters deployApp=true -o none
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq 3) { throw 'Phase 2 failed' }
    Write-Host '  phase 2 failed (often RBAC propagation); retrying in 60s...'; Start-Sleep -Seconds 60
}
$app = az deployment group show -g $rg -n bridge-phase2 --query properties.outputs.containerAppName.value -o tsv
Write-Step "Done. Container app: $app"
Write-Host "Logs:     az containerapp logs show -g $rg -n $app --follow --format text"
Write-Host "Replicas: az containerapp replica list -g $rg -n $app -o table"
Write-Host 'REMEMBER: stop any local bridge using the same NROD account / client-id.'
