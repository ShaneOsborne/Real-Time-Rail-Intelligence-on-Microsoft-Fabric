<#
.SYNOPSIS
  OPTIONAL shared Event Hub tier (Lab 05c, instructor).
.DESCRIPTION
  Creates an Event Hubs Standard namespace with the event hubs nrod-feed and rdm-trust (7-day retention),
  a Send rule per hub and a namespace Listen rule for students; writes the send connection strings into the
  shared Key Vault; creates student consumer groups; and prints what students need for their Eventstream
  "Azure Event Hubs" source.
  Optional .env: EVENTHUB_NAMESPACE, EVENTHUB_THROUGHPUT_UNITS, EVENTHUB_RETENTION_DAYS,
  STUDENT_CONSUMER_GROUP_PREFIX, STUDENT_CONSUMER_GROUP_COUNT, KEY_VAULT_NAME, NAME_PREFIX.
.EXAMPLE
  ./scripts/create-eventhub.ps1
  ./scripts/create-eventhub.ps1 -WhatIf
  ./scripts/create-eventhub.ps1 -HideKey
#>
param([switch]$WhatIf, [switch]$HideKey)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION')

$prefix = if ($env:NAME_PREFIX) { $env:NAME_PREFIX } else { 'railrti' }
$tu = if ($env:EVENTHUB_THROUGHPUT_UNITS) { $env:EVENTHUB_THROUGHPUT_UNITS } else { '1' }
$days = if ($env:EVENTHUB_RETENTION_DAYS) { $env:EVENTHUB_RETENTION_DAYS } else { '7' }
$cgPrefix = if ($env:STUDENT_CONSUMER_GROUP_PREFIX) { $env:STUDENT_CONSUMER_GROUP_PREFIX } else { 'student' }
$nrodHub = 'nrod-feed'
$rdmHub = 'rdm-trust'
$rg = $env:AZ_RESOURCE_GROUP
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }

$ehParams = @(
    '--resource-group', $rg,
    '--template-file', (Join-Path $script:RepoRoot 'infra/eventhubs.bicep'),
    '--parameters', "location=$($env:AZ_LOCATION)", "namePrefix=$prefix", "namespaceName=$($env:EVENTHUB_NAMESPACE)",
    "throughputUnits=$tu", "retentionDays=$days", "nrodHubName=$nrodHub", "rdmHubName=$rdmHub"
)

Write-Step "Resource group $rg ($($env:AZ_LOCATION))"
Invoke-Az group create -n $rg -l $env:AZ_LOCATION -o none

if ($WhatIf) { Invoke-Az deployment group what-if @ehParams; return }

$deployerId = az ad signed-in-user show --query id -o tsv 2>$null
$deployerType = 'User'
if (-not $deployerId) {
    $appId = az account show --query user.name -o tsv
    $deployerId = az ad sp show --id $appId --query id -o tsv
    $deployerType = 'ServicePrincipal'
}

# Same template and deployment name as scripts/create-keyvault.ps1: re-uses the shared vault (Lab 01 step 8).
Write-Step 'Shared Key Vault (created or re-used) + Key Vault Secrets Officer for you'
Invoke-Az deployment group create -g $rg -n shared-keyvault `
    --template-file (Join-Path $script:RepoRoot 'infra/keyvault.bicep') `
    --parameters "location=$($env:AZ_LOCATION)" "namePrefix=$prefix" "keyVaultName=$($env:KEY_VAULT_NAME)" `
    "deployerPrincipalId=$deployerId" "deployerPrincipalType=$deployerType" -o none
$kv = az deployment group show -g $rg -n shared-keyvault --query properties.outputs.keyVaultName.value -o tsv

Write-Step "Event Hubs Standard namespace, hubs $nrodHub + $rdmHub, SAS rules (infra/eventhubs.bicep)"
Invoke-Az deployment group create -n shared-eventhubs @ehParams -o none
$ns = az deployment group show -g $rg -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv

Write-Step "Writing send connection strings to Key Vault $kv (retrying while RBAC propagates)"
function Set-KvSecret([string]$Name, [string]$Value) {
    for ($i = 1; $i -le 10; $i++) {
        az keyvault secret set --vault-name $kv -n $Name --value $Value -o none 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "  set $Name"; return }
        Write-Host "  waiting for Key Vault permissions ($i/10)..."; Start-Sleep -Seconds 15
    }
    throw "Could not write secret $Name"
}
function Get-SendConnectionString([string]$Hub) {
    $cs = az eventhubs eventhub authorization-rule keys list -g $rg --namespace-name $ns --eventhub-name $Hub `
        --authorization-rule-name bridge-send --query primaryConnectionString -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $cs) { throw "Could not read the bridge-send key for $Hub" }
    return $cs
}
Set-KvSecret 'eventhub-nrod-connection-string' (Get-SendConnectionString $nrodHub)
Set-KvSecret 'eventhub-rdm-connection-string' (Get-SendConnectionString $rdmHub)

if ([int]("0$($env:STUDENT_CONSUMER_GROUP_COUNT)") -gt 0) {
    Write-Step "Student consumer groups ($($cgPrefix)01..)"
    & (Join-Path $PSScriptRoot 'add-student-consumer-groups.ps1') -Namespace $ns -Prefix $cgPrefix -Count ([int]$env:STUDENT_CONSUMER_GROUP_COUNT)
}
else {
    Write-Host 'STUDENT_CONSUMER_GROUP_COUNT not set: add groups later with ./scripts/add-student-consumer-groups.ps1 -Prefix student -Count N'
}

$listenKey = if ($HideKey) {
    "(hidden - az eventhubs namespace authorization-rule keys list -g $rg --namespace-name $ns --authorization-rule-name students-listen --query primaryKey -o tsv)"
} else {
    az eventhubs namespace authorization-rule keys list -g $rg --namespace-name $ns --authorization-rule-name students-listen --query primaryKey -o tsv
}

Write-Host @"

Done. Add to .env:
  EVENTHUB_NAMESPACE=$ns
Then point the Azure apps at the hub (Lab 05b): set BRIDGE_TARGET=eventhub and DEPLOY_RDM_RELAY=true in .env, then
  ./scripts/deploy-bridge.ps1

Share with students over a private channel (never in a public repo or chat) - Eventstream > Azure Event Hubs source:
  Event Hub namespace : $ns
  Event hubs          : $nrodHub (-> RawFeed)   $rdmHub (-> RdmTrustRaw)
  Authentication      : Shared Access Key
  Key name            : students-listen
  Key                 : $listenKey
  Consumer group      : their own, e.g. $($cgPrefix)01 (never `$Default, never shared)
  Data format         : JSON
Rotate the key after the course:
  az eventhubs namespace authorization-rule keys renew -g $rg --namespace-name $ns --authorization-rule-name students-listen --key PrimaryKey
"@
