<#
.SYNOPSIS
  Lab 02 Option A: create Fabric workspace items via the Fabric REST API (az rest).
  Eventstream sources/destinations are configured manually (Labs 04/05).
#>
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az

$api = 'https://api.fabric.microsoft.com/v1'
$res = 'https://api.fabric.microsoft.com'
$eh = if ($env:FABRIC_EVENTHOUSE_NAME) { $env:FABRIC_EVENTHOUSE_NAME } else { 'RailEventhouse' }
$db = if ($env:FABRIC_KQL_DATABASE_NAME) { $env:FABRIC_KQL_DATABASE_NAME } else { 'RailKQL' }
$lh = if ($env:FABRIC_LAKEHOUSE_NAME) { $env:FABRIC_LAKEHOUSE_NAME } else { 'RailLakehouse' }
$esNrod = if ($env:FABRIC_EVENTSTREAM_NROD_NAME) { $env:FABRIC_EVENTSTREAM_NROD_NAME } else { 'RailEventstreamNrod' }
$esRdm = if ($env:FABRIC_EVENTSTREAM_RDM_NAME) { $env:FABRIC_EVENTSTREAM_RDM_NAME } else { 'RailEventstreamRdm' }

function Invoke-Fabric([string]$Method, [string]$Url, [string]$Body, [string]$Query) {
    $a = @('rest', '--method', $Method, '--resource', $res, '--url', $Url)
    if ($Body) {
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $Body -Encoding utf8
        $a += @('--body', "@$tmp")
    }
    if ($Query) { $a += @('--query', $Query, '-o', 'tsv') } else { $a += @('-o', 'none') }
    $out = & az @a 2>$null
    if ($Body) { Remove-Item $tmp -ErrorAction SilentlyContinue }
    return $out
}

$ws = $env:FABRIC_WORKSPACE_ID
if (-not $ws) {
    Assert-Env @('FABRIC_CAPACITY_ID', 'FABRIC_WORKSPACE_NAME')
    $ws = Invoke-Fabric get "$api/workspaces" '' "value[?displayName=='$($env:FABRIC_WORKSPACE_NAME)'].id | [0]"
    if (-not $ws -or $ws -eq 'None') {
        Write-Step 'Creating workspace'
        $body = @{ displayName = $env:FABRIC_WORKSPACE_NAME; capacityId = $env:FABRIC_CAPACITY_ID } | ConvertTo-Json -Compress
        $ws = Invoke-Fabric post "$api/workspaces" $body 'id'
    }
}
Write-Host "Workspace: $ws"
$wsUrl = "$api/workspaces/$ws"

function Get-ItemId([string]$Coll, [string]$Name) {
    $id = Invoke-Fabric get "$wsUrl/$Coll" '' "value[?displayName=='$Name'].id | [0]"
    if ($id -eq 'None') { return $null } else { return $id }
}

function New-FabricItem([string]$Coll, [string]$Name, [hashtable]$Body) {
    $id = Get-ItemId $Coll $Name
    if ($id) { Write-Host "  exists  $Coll/$Name"; return $id }
    Write-Host "  creating $Coll/$Name"
    Invoke-Fabric post "$wsUrl/$Coll" ($Body | ConvertTo-Json -Depth 5 -Compress) | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        $id = Get-ItemId $Coll $Name
        if ($id) { return $id }
        Start-Sleep -Seconds 10
    }
    throw "$Coll/$Name was not created"
}

Write-Step 'Eventhouse';   $ehId = New-FabricItem 'eventhouses' $eh @{ displayName = $eh }
Write-Step 'KQL database'; $dbId = New-FabricItem 'kqlDatabases' $db @{ displayName = $db; creationPayload = @{ databaseType = 'ReadWrite'; parentEventhouseItemId = $ehId } }
Write-Step 'Lakehouse';    $lhId = New-FabricItem 'lakehouses' $lh @{ displayName = $lh }
Write-Step 'Eventstreams (empty)'
$esRdmId = New-FabricItem 'eventstreams' $esRdm @{ displayName = $esRdm }
$esNrodId = New-FabricItem 'eventstreams' $esNrod @{ displayName = $esNrod }
$queryUri = Invoke-Fabric get "$wsUrl/kqlDatabases/$dbId" '' 'properties.queryServiceUri'

Write-Host @"

Add these to your .env:
FABRIC_WORKSPACE_ID=$ws
FABRIC_EVENTHOUSE_ID=$ehId
FABRIC_KQL_DATABASE_ID=$dbId
FABRIC_LAKEHOUSE_ID=$lhId
FABRIC_EVENTSTREAM_RDM_ID=$esRdmId
FABRIC_EVENTSTREAM_NROD_ID=$esNrodId
KUSTO_QUERY_URI=$queryUri

Next: python fabric/scripts/apply_kql.py   (Lab 06)
"@
