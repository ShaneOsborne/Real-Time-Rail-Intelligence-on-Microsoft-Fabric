<#
.SYNOPSIS
  Lab 11b: create the Azure Maps account (Gen2) + SAS identity, and grant that identity
  "Azure Maps Search and Render Data Reader" on the account.
.EXAMPLE
  ./scripts/create-azure-maps.ps1
  # Optional .env: AZURE_MAPS_LOCATION, AZURE_MAPS_ALLOWED_ORIGINS=https://<your-app>.webapp.fabricapps.net,http://localhost:5173
#>
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION')

$prefix = if ($env:NAME_PREFIX) { $env:NAME_PREFIX } else { 'railrti' }
$rg = $env:AZ_RESOURCE_GROUP
$mapsLocation = if ($env:AZURE_MAPS_LOCATION) { $env:AZURE_MAPS_LOCATION } else { $env:AZ_LOCATION }
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }

Write-Step 'Registering the Microsoft.Maps provider (no-op if already registered)'
Invoke-Az provider register -n Microsoft.Maps --wait -o none

Write-Step "Resource group $rg"
Invoke-Az group create -n $rg -l $env:AZ_LOCATION -o none

$origins = @()
if ($env:AZURE_MAPS_ALLOWED_ORIGINS) { $origins = $env:AZURE_MAPS_ALLOWED_ORIGINS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
$paramFile = New-TemporaryFile
@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0';
   parameters = @{ location = @{ value = $mapsLocation }; namePrefix = @{ value = $prefix }; allowedOrigins = @{ value = @($origins) } } } |
  ConvertTo-Json -Depth 6 | Set-Content -Path $paramFile -Encoding utf8

Write-Step "Azure Maps account (Gen2) + SAS identity in $mapsLocation"
Invoke-Az deployment group create -g $rg -n azure-maps `
    --template-file (Join-Path $script:RepoRoot 'infra/azuremaps.bicep') --parameters "@$paramFile" -o none
Remove-Item $paramFile
function Get-Out([string]$n) { az deployment group show -g $rg -n azure-maps --query "properties.outputs.$n.value" -o tsv }
$mapsName = Get-Out 'mapsAccountName'; $mapsId = Get-Out 'mapsAccountId'; $principalId = Get-Out 'identityPrincipalId'

Write-Step "Role 'Azure Maps Search and Render Data Reader' for the SAS identity (map tiles only)"
for ($i = 1; $i -le 10; $i++) {
    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
        --role 'Azure Maps Search and Render Data Reader' --scope $mapsId -o none 2>$null
    if ($LASTEXITCODE -eq 0) { break }
    Write-Host "  waiting for the identity to replicate ($i/10)..."; Start-Sleep -Seconds 15
}

Write-Host @"

Done. Add these to .env:
  AZURE_MAPS_ACCOUNT_NAME=$mapsName
  AZURE_MAPS_SAS_PRINCIPAL_ID=$principalId
Next: ./scripts/new-azure-maps-sas.ps1   (creates a SAS token valid for up to 24 hours)
"@
