<#
.SYNOPSIS
  Lab 12: delete the Azure resource group and optionally the Fabric workspace.
#>
param([switch]$Fabric)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP')

$ans = Read-Host "Delete resource group '$($env:AZ_RESOURCE_GROUP)' and everything in it? [y/N]"
if ($ans -match '^[Yy]$') {
    Invoke-Az group delete -n $env:AZ_RESOURCE_GROUP --yes --no-wait
    Write-Host 'Deletion started. Key Vault is soft-deleted (7 days): az keyvault list-deleted; az keyvault purge -n <name>'
}
if ($Fabric) {
    Assert-Env @('FABRIC_WORKSPACE_ID')
    $ans2 = Read-Host "Delete Fabric workspace $($env:FABRIC_WORKSPACE_ID) (all items)? [y/N]"
    if ($ans2 -match '^[Yy]$') {
        Invoke-Az rest --method delete --resource 'https://api.fabric.microsoft.com' --url "https://api.fabric.microsoft.com/v1/workspaces/$($env:FABRIC_WORKSPACE_ID)"
        Write-Host 'Fabric workspace deleted.'
    }
}
Write-Host 'Also: stop any local bridge (docker compose down), remove the Foundry agent/connection, pause/delete the Fabric capacity if created for this lab.'
