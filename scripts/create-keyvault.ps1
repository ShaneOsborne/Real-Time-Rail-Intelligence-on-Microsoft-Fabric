<#
.SYNOPSIS
  Create the shared Key Vault and store the NROD credentials (Lab 01, step 8).
  Lab 03 (Fabric notebook) reads them from here; Lab 05b re-uses the same vault.
.EXAMPLE
  ./scripts/create-keyvault.ps1
#>
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP', 'AZ_LOCATION', 'NROD_USERNAME', 'NROD_PASSWORD')

$prefix = if ($env:NAME_PREFIX) { $env:NAME_PREFIX } else { 'railrti' }
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

Write-Step 'Key Vault (RBAC mode) + Key Vault Secrets Officer for you'
Invoke-Az deployment group create -g $rg -n shared-keyvault `
    --template-file (Join-Path $script:RepoRoot 'infra/keyvault.bicep') `
    --parameters "location=$($env:AZ_LOCATION)" "namePrefix=$prefix" "keyVaultName=$($env:KEY_VAULT_NAME)" `
    "deployerPrincipalId=$deployerId" "deployerPrincipalType=$deployerType" -o none
$kv = az deployment group show -g $rg -n shared-keyvault --query properties.outputs.keyVaultName.value -o tsv
$kvUri = az deployment group show -g $rg -n shared-keyvault --query properties.outputs.keyVaultUri.value -o tsv

Write-Step "Writing NROD secrets to $kv (retrying while RBAC propagates)"
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

Write-Host @"

Done. Add these to .env:
  KEY_VAULT_NAME=$kv
  KEY_VAULT_URL=$kvUri
Use KEY_VAULT_URL in the Lab 03 notebook. Lab 05b will re-use this vault and add the
eventstream-connection-string secret (keep AZ_RESOURCE_GROUP and NAME_PREFIX unchanged).
"@
