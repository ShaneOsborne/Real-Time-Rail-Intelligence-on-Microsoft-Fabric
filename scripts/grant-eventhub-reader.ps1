<#
.SYNOPSIS
  Give Fabric workspace identities read access to the shared Event Hub (Instructor 1.4 / Solo 1.8, EVENTHUB_AUTH=entra).
.DESCRIPTION
  Each student enables Workspace settings > Workspace identity and sends you the workspace name (or the identity ID).
  Their Eventstream "Azure Event Hubs" source then uses Authentication kind = Workspace identity - no key to share.
  Assigns 'Azure Event Hubs Data Receiver' on the namespace (EVENTHUB_NAMESPACE, or the 'shared-eventhubs' deployment).
  Safe to re-run. Needs Owner or User Access Administrator on the namespace, and directory read access to look up names.
.EXAMPLE
  ./scripts/grant-eventhub-reader.ps1 -Workspace 'Rail RTI - student01','Rail RTI - student02'
  ./scripts/grant-eventhub-reader.ps1 -Id 00000000-0000-0000-0000-000000000000
  ./scripts/grant-eventhub-reader.ps1 -Workspace 'Rail RTI - student01' -Remove
#>
param([string[]]$Workspace = @(), [string[]]$Id = @(), [string]$Namespace = '', [switch]$Remove)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP')
if (-not $Workspace -and -not $Id) { throw 'Give at least one -Workspace name or -Id.' }

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
foreach ($ws in $Workspace) {
    $found = @(az ad sp list --display-name $ws --query '[].id' -o tsv 2>$null | Where-Object { $_ })
    if ($found.Count -eq 1) { Invoke-Grant $ws $found[0] }
    elseif ($found.Count -eq 0) { Write-Warning "No identity named '$ws'. Is Workspace identity enabled on that workspace (name spelled exactly)?"; $failed++ }
    else { Write-Warning "$($found.Count) identities are named '$ws'. Use -Id with the ID from Workspace settings > Workspace identity."; $failed++ }
}
foreach ($i in $Id) {
    $oid = az ad sp show --id $i --query id -o tsv 2>$null
    if (-not $oid) { $oid = $i }   # no directory read access: assume it's the object ID
    Invoke-Grant $i $oid
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
