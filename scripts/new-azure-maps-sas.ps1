<#
.SYNOPSIS
  Lab 11b: create an Azure Maps SAS token for the Rayfin app (max lifetime 24 hours, rate-limited).
  Prints the token. Store it in the app with:  npx rayfin secret set AZURE_MAPS_TOKEN
.EXAMPLE
  ./scripts/new-azure-maps-sas.ps1 -Hours 24 -MaxRatePerSecond 50
#>
param([int]$Hours = 24, [int]$MaxRatePerSecond = 50)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP', 'AZURE_MAPS_ACCOUNT_NAME', 'AZURE_MAPS_SAS_PRINCIPAL_ID')
if ($Hours -gt 24) { throw 'Azure Maps SAS tokens can last at most 24 hours.' }
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }
$sub = az account show --query id -o tsv
$start = (Get-Date).ToUniversalTime()
$body = @{ signingKey = 'primaryKey'; principalId = $env:AZURE_MAPS_SAS_PRINCIPAL_ID; maxRatePerSecond = $MaxRatePerSecond
           start = $start.ToString('yyyy-MM-ddTHH:mm:ssZ'); expiry = $start.AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json -Compress
$bodyFile = New-TemporaryFile; Set-Content -Path $bodyFile -Value $body -Encoding utf8
$url = "https://management.azure.com/subscriptions/$sub/resourceGroups/$($env:AZ_RESOURCE_GROUP)/providers/Microsoft.Maps/accounts/$($env:AZURE_MAPS_ACCOUNT_NAME)/listSas?api-version=2023-06-01"
az rest --method post --url $url --body "@$bodyFile" --query accountSasToken -o tsv
Remove-Item $bodyFile
Write-Host "Valid until $($start.AddHours($Hours).ToString('u')) (UTC), max ~$MaxRatePerSecond requests/second." -ForegroundColor DarkGray
