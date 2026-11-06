<#
.SYNOPSIS
  Give Fabric workspace identities read access to the shared Event Hub (Instructor 1.4 / Solo 1.8, EVENTHUB_AUTH=entra).
.DESCRIPTION
  Each student enables Workspace settings > Workspace identity and sends you the "ID" shown there (not the "App ID").
  Their Eventstream "Azure Event Hubs" source then uses Authentication kind = Workspace identity - no key to share.
  Assigns 'Azure Event Hubs Data Receiver' on the namespace (EVENTHUB_NAMESPACE, or the 'shared-eventhubs' deployment).
  Safe to re-run. Needs Owner or User Access Administrator on the namespace.
  Workspace names aren't used: they aren't unique in Entra ID, and a name search also matches longer names.
.EXAMPLE
  ./scripts/grant-eventhub-reader.ps1 -Id 59cc0a5f-0000-0000-0000-000000000000
  ./scripts/grant-eventhub-reader.ps1 -Id '<student01 ID>','<student02 ID>'
  ./scripts/grant-eventhub-reader.ps1 -Id '<student01 ID>' -Remove
#>
param([Parameter(Mandatory = $true)][string[]]$Id, [string]$Namespace = '', [switch]$Remove)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP')

$Id = @($Id | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($i in $Id) {
    if ($i -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "'$i' isn't an ID. Copy the 'ID' from Workspace settings > Workspace identity (it looks like 59cc0a5f-d78a-...)."
    }
}

$role = 'Azure Event Hubs Data Receiver'
$rg = $env:AZ_RESOURCE_GROUP
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }
if (-not $Namespace) { $Namespace = $env:EVENTHUB_NAMESPACE }
if (-not $Namespace) {
    $Namespace = az deployment group show -g $rg -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv 2>$null
}
if (-not $Namespace) { throw 'Set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.ps1 first' }
$Namespace = $Namespace.Split('.')[0]
$nsId = az eventhubs namespace show -g $rg -n $Namespace --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $nsId) { throw "Event Hubs namespace '$Namespace' not found in $rg" }

$failed = 0
function Invoke-Grant([string]$Label, [string]$ObjectId) {
    if ($Remove) {
        az role assignment delete --assignee $ObjectId --role $role --scope $nsId -o none 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "  removed  $Label" } else { Write-Warning "Could not remove the role for $Label"; $script:failed++ }
        return
    }
    $out = az role assignment create --assignee-object-id $ObjectId --assignee-principal-type ServicePrincipal `
        --role $role --scope $nsId -o none 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host "  granted  $Label" }
    elseif ("$out" -match '(?i)already exists') { Write-Host "  exists   $Label" }
    else { Write-Warning "Error for ${Label}: $out"; $script:failed++ }
}

Write-Step "$role on $Namespace"
foreach ($i in $Id) {
    # "ID" on the Workspace identity page is the object ID. If the App ID was sent, look up the object ID;
    # if the directory can't be read, assume it's already the object ID.
    $oid = az ad sp show --id $i --query id -o tsv 2>$null
    if (-not $oid) { $oid = $i }
    $name = az ad sp show --id $oid --query displayName -o tsv 2>$null
    $label = if ($name) { "$i ($name)" } else { $i }
    Invoke-Grant $label $oid
}

if (-not $Remove) {
    Write-Host @"

Students can now add an Eventstream "Azure Event Hubs" source with:
  Event Hub namespace : $Namespace   Event hubs: nrod-feed (-> RawFeed), rdm-trust (-> RdmTrustRaw)
  Authentication kind : Workspace identity    Consumer group: their own (never `$Default)    Data format: JSON
A new role assignment can take a few minutes to apply.
"@
}
if ($failed -gt 0) { throw "$failed item(s) failed - see the warnings above." }
