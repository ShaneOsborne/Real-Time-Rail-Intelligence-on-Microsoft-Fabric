<#
.SYNOPSIS
  Create one Event Hubs consumer group per student on the shared hubs (Lab 05c, optional shared tier).
.DESCRIPTION
  Idempotent: existing groups are skipped. Standard tier allows 20 consumer groups per event hub,
  including $Default (kept for the instructor), so at most 19 students per namespace.
  Defaults: STUDENT_CONSUMER_GROUP_PREFIX / STUDENT_CONSUMER_GROUP_COUNT from .env, hubs nrod-feed and rdm-trust,
  namespace EVENTHUB_NAMESPACE or the output of the 'shared-eventhubs' deployment (scripts/create-eventhub.ps1).
.EXAMPLE
  ./scripts/add-student-consumer-groups.ps1 -Prefix student -Count 15            # student01 ... student15
  ./scripts/add-student-consumer-groups.ps1 -Names alice,bob
#>
param(
    [string]$Prefix,
    [int]$Count = -1,
    [int]$Start = 1,
    [string[]]$Names,
    [string[]]$Hubs,
    [string]$Namespace
)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP')

$rg = $env:AZ_RESOURCE_GROUP
$maxPerHub = 20
if (-not $Prefix) { $Prefix = if ($env:STUDENT_CONSUMER_GROUP_PREFIX) { $env:STUDENT_CONSUMER_GROUP_PREFIX } else { 'student' } }
if ($Count -lt 0) { $Count = if ($env:STUDENT_CONSUMER_GROUP_COUNT) { [int]$env:STUDENT_CONSUMER_GROUP_COUNT } else { 0 } }
if (-not $Hubs) {
    $Hubs = @(
        $(if ($env:EVENTHUB_NROD_HUB) { $env:EVENTHUB_NROD_HUB } else { 'nrod-feed' }),
        $(if ($env:EVENTHUB_RDM_HUB) { $env:EVENTHUB_RDM_HUB } else { 'rdm-trust' })
    )
}
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }

if (-not $Namespace) { $Namespace = $env:EVENTHUB_NAMESPACE }
if (-not $Namespace) {
    $Namespace = az deployment group show -g $rg -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv 2>$null
}
if (-not $Namespace) { throw 'Set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.ps1 first' }

$groups = @()
if ($Names) { $groups = @($Names | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
else { for ($i = $Start; $i -lt $Start + $Count; $i++) { $groups += ('{0}{1:D2}' -f $Prefix, $i) } }
if ($groups.Count -eq 0) {
    Write-Host 'No consumer groups requested (use -Count or -Names, or STUDENT_CONSUMER_GROUP_COUNT in .env).'
    return
}

foreach ($hub in $Hubs) {
    Write-Step "Event hub $Namespace/$hub"
    $existing = @(az eventhubs eventhub consumer-group list -g $rg --namespace-name $Namespace --eventhub-name $hub --query '[].name' -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Could not list consumer groups on $hub" }
    $have = @($existing | Where-Object { $_ }).Count
    foreach ($cg in $groups) {
        if ($existing -contains $cg) { Write-Host "  exists   $cg"; continue }
        if ($have -ge $maxPerHub) {
            throw "$hub already has $have consumer groups (Standard limit $maxPerHub incl. `$Default). Use a second namespace, or Premium (100 per event hub)."
        }
        Invoke-Az eventhubs eventhub consumer-group create -g $rg --namespace-name $Namespace --eventhub-name $hub --consumer-group-name $cg -o none
        $have++
        Write-Host "  created  $cg"
    }
    Write-Host "  $hub now has $have of $maxPerHub consumer groups"
}

Write-Host @"

Give each student ONE consumer group name (the same name works on both hubs), for example $($groups[0]).
Never let two Eventstreams share a consumer group - they compete for the same partitions.
"@
