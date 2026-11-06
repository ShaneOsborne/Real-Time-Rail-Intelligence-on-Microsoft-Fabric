<#
.SYNOPSIS
  OPTIONAL shared Event Hub tier (Instructor 1.4, or Solo 1.8 for one person).
.DESCRIPTION
  Creates an Event Hubs Standard namespace with the event hubs nrod-feed and rdm-trust (7-day retention),
  a Send rule per hub and a namespace Listen rule for students; writes the send connection strings into the
  shared Key Vault; creates student consumer groups; and prints what students need for their Eventstream
  "Azure Event Hubs" source.
  With SECRETS_SOURCE=inline (Key Vault blocked by policy, as in Solo 1.7) it doesn't touch Key Vault: it writes
  EVENTHUB_NAMESPACE, EVENTHUB_CONNECTION_STRING and EVENTHUB_RDM_CONNECTION_STRING straight into .env instead.
  Optional .env: EVENTHUB_NAMESPACE, EVENTHUB_THROUGHPUT_UNITS, EVENTHUB_RETENTION_DAYS,
  STUDENT_CONSUMER_GROUP_PREFIX, STUDENT_CONSUMER_GROUP_COUNT, KEY_VAULT_NAME, NAME_PREFIX,
  SECRETS_SOURCE (keyvault | inline).
.EXAMPLE
  ./scripts/create-eventhub.ps1
  ./scripts/create-eventhub.ps1 -WhatIf
  ./scripts/create-eventhub.ps1 -HideKey
  ./scripts/create-eventhub.ps1 -SecretsSource inline
  ./scripts/create-eventhub.ps1 -Auth entra     # no keys: policy disables key sign-in on Event Hubs
#>
param([switch]$WhatIf, [switch]$HideKey, [ValidateSet('', 'keyvault', 'inline')][string]$SecretsSource = '',
      [ValidateSet('', 'key', 'entra')][string]$Auth = '')
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
if (-not $SecretsSource) { $SecretsSource = if ($env:SECRETS_SOURCE) { $env:SECRETS_SOURCE } else { 'keyvault' } }
if ($SecretsSource -notin @('keyvault', 'inline')) { throw "SECRETS_SOURCE must be 'keyvault' or 'inline'" }
if (-not $Auth) { $Auth = if ($env:EVENTHUB_AUTH) { $env:EVENTHUB_AUTH } else { 'key' } }
if ($Auth -notin @('key', 'entra')) { throw "EVENTHUB_AUTH must be 'key' or 'entra'" }
# Where the send connection strings go: Key Vault, .env (inline), or nowhere (entra - no keys)
$mode = if ($Auth -eq 'entra') { 'entra' } else { $SecretsSource }
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

if ($mode -eq 'keyvault') {

# Same template and deployment name as scripts/create-keyvault.ps1: re-uses the shared vault (Solo 1.1 step 8).
Write-Step 'Shared Key Vault (created or re-used) + Key Vault Secrets Officer for you'
Invoke-Az deployment group create -g $rg -n shared-keyvault `
    --template-file (Join-Path $script:RepoRoot 'infra/keyvault.bicep') `
    --parameters "location=$($env:AZ_LOCATION)" "namePrefix=$prefix" "keyVaultName=$($env:KEY_VAULT_NAME)" `
    "deployerPrincipalId=$deployerId" "deployerPrincipalType=$deployerType" -o none
$kv = az deployment group show -g $rg -n shared-keyvault --query properties.outputs.keyVaultName.value -o tsv
}
elseif ($mode -eq 'inline') {
    Write-Step 'SECRETS_SOURCE=inline: Key Vault skipped (connection strings go into .env instead)'
}
else {
    Write-Step 'EVENTHUB_AUTH=entra: no keys - Key Vault and connection strings skipped'
}

Write-Step "Event Hubs Standard namespace, hubs $nrodHub + $rdmHub, SAS rules (infra/eventhubs.bicep)"
Invoke-Az deployment group create -n shared-eventhubs @ehParams -o none
$ns = az deployment group show -g $rg -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv

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
# Replace KEY=... in the repo-root .env, or append it. Other lines (and their line endings) are left as they are.
function Set-DotEnvValue([string]$Name, [string]$Value) {
    $path = Join-Path $script:RepoRoot '.env'
    $lines = if (Test-Path $path) { @(Get-Content $path) } else { @() }
    $found = $false
    $lines = @($lines | ForEach-Object {
        if ($_ -match "^\s*$([regex]::Escape($Name))\s*=") { $found = $true; "$Name=$Value" } else { $_ }
    })
    if (-not $found) { $lines += "$Name=$Value" }
    [System.IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  set $Name in .env"
}
if ($mode -eq 'entra') {
    Write-Step 'Writing EVENTHUB_NAMESPACE and EVENTHUB_AUTH=entra to .env'
    Set-DotEnvValue 'EVENTHUB_NAMESPACE' $ns
    Set-DotEnvValue 'EVENTHUB_AUTH' 'entra'
    $nsId = az eventhubs namespace show -g $rg -n $ns --query id -o tsv
    Write-Step 'Azure Event Hubs Data Sender for you (only needed to run the bridge locally against the hub)'
    az role assignment create --assignee-object-id $deployerId --assignee-principal-type $deployerType `
        --role 'Azure Event Hubs Data Sender' --scope $nsId -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host '  assigned' }
    else { Write-Warning 'Could not assign it (you need Owner or User Access Administrator). Only local runs need it.' }
    Write-Host '  The Container Apps identity gets the same role from deploy-bridge (EVENTHUB_AUTH=entra).'
}
else {
    $nrodCs = Get-SendConnectionString $nrodHub
    $rdmCs = Get-SendConnectionString $rdmHub
}
if ($mode -eq 'keyvault') {
    Write-Step "Writing send connection strings to Key Vault $kv (retrying while RBAC propagates)"
    Set-KvSecret 'eventhub-nrod-connection-string' $nrodCs
    Set-KvSecret 'eventhub-rdm-connection-string' $rdmCs
}
elseif ($mode -eq 'inline') {
    Write-Step 'Writing the namespace and send connection strings to .env (keep .env private; never commit it)'
    Set-DotEnvValue 'EVENTHUB_NAMESPACE' $ns
    Set-DotEnvValue 'EVENTHUB_CONNECTION_STRING' $nrodCs
    Set-DotEnvValue 'EVENTHUB_RDM_CONNECTION_STRING' $rdmCs
}

$cgCount = 0
if ("$($env:STUDENT_CONSUMER_GROUP_COUNT)".Trim() -match '^\d+$') { $cgCount = [int]$env:STUDENT_CONSUMER_GROUP_COUNT.Trim() }
if ($cgCount -gt 0) {
    Write-Step "Student consumer groups ($($cgPrefix)01..)"
    & (Join-Path $PSScriptRoot 'add-student-consumer-groups.ps1') -Namespace $ns -Prefix $cgPrefix -Count $cgCount
}
else {
    Write-Host "No student consumer groups created: STUDENT_CONSUMER_GROUP_COUNT is '$($env:STUDENT_CONSUMER_GROUP_COUNT)' (needs a number from 1 to 19)."
    Write-Host "Add them now with: ./scripts/add-student-consumer-groups.ps1 -Namespace $ns -Prefix $cgPrefix -Count N"
}

if ($mode -eq 'entra') {
    Write-Host @"

Done. .env now has EVENTHUB_NAMESPACE=$ns and EVENTHUB_AUTH=entra.
Then point the Azure apps at the hub (Solo 1.7): set EVENTHUB_AUTH=entra, BRIDGE_TARGET=eventhub and DEPLOY_RDM_RELAY=true
in .env (plus SECRETS_SOURCE=inline if Key Vault is blocked by policy), then ./scripts/deploy-bridge.ps1
Their managed identity gets 'Azure Event Hubs Data Sender'.

Students (and you, for your own workspace) connect with WORKSPACE IDENTITY - no key to share:
  1. Each student: Fabric workspace > Workspace settings > Workspace identity > enable it, and send you the
     "ID" shown there (not the "App ID").
  2. You give each workspace read access to the hubs:
       ./scripts/grant-eventhub-reader.ps1 -Id '<ID>','<another ID>'
  3. Eventstream > Azure Event Hubs source:
       Event Hub namespace : $ns
       Event hubs          : $nrodHub (-> RawFeed)   $rdmHub (-> RdmTrustRaw)
       Authentication kind : Workspace identity
       Consumer group      : their own, e.g. $($cgPrefix)01 (never `$Default, never shared)
       Data format         : JSON
"@
    return
}

$listenKey = if ($HideKey) {
    "(hidden - az eventhubs namespace authorization-rule keys list -g $rg --namespace-name $ns --authorization-rule-name students-listen --query primaryKey -o tsv)"
} else {
    az eventhubs namespace authorization-rule keys list -g $rg --namespace-name $ns --authorization-rule-name students-listen --query primaryKey -o tsv
}

$nextSteps = if ($SecretsSource -eq 'inline') {
    "Done. .env now has EVENTHUB_NAMESPACE, EVENTHUB_CONNECTION_STRING and EVENTHUB_RDM_CONNECTION_STRING.`n" +
    "Then point the Azure apps at the hub (Solo 1.7): set SECRETS_SOURCE=inline, BRIDGE_TARGET=eventhub and DEPLOY_RDM_RELAY=true in .env, then`n" +
    "  ./scripts/deploy-bridge.ps1"
} else {
    "Done. Add to .env:`n  EVENTHUB_NAMESPACE=$ns`n" +
    "Then point the Azure apps at the hub (Solo 1.7): set BRIDGE_TARGET=eventhub and DEPLOY_RDM_RELAY=true in .env, then`n" +
    "  ./scripts/deploy-bridge.ps1"
}

Write-Host @"

$nextSteps

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
