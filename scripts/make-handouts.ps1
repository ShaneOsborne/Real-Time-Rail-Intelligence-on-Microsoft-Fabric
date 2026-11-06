<#
.SYNOPSIS
  Instructor 1.5: write one private handout per student, with everything they need, in one go.
.DESCRIPTION
  Reads the class settings from .env and Azure, finds the student consumer groups on the shared Event Hub,
  and writes handouts/<consumer group>.md (plus handouts/index.csv). Send each file to its student PRIVATELY.
  With key sign-in the handouts contain the Listen key: the handouts folder is git-ignored. Delete it after the class.
.EXAMPLE
  ./scripts/make-handouts.ps1
  ./scripts/make-handouts.ps1 -Students '1-12' -Notes 'Lab 2.5: yes. Lab 2.8: no (region)'
  ./scripts/make-handouts.ps1 -Students '3,7' -Maps          # also create today's Azure Maps token (Lab 2.9)
#>
param(
    [string]$Students = '',
    [string]$WorkspacePrefix = '',
    [string]$ReferenceWorkspace = '',
    [string]$Notes = '',
    [switch]$Maps,
    [string]$MapsToken = '',
    [string]$Namespace = '',
    [string]$Out = ''
)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
Assert-Command az
Assert-Env @('AZ_RESOURCE_GROUP')

$rg = $env:AZ_RESOURCE_GROUP
$prefix = if ($env:STUDENT_CONSUMER_GROUP_PREFIX) { $env:STUDENT_CONSUMER_GROUP_PREFIX } else { 'student' }
if (-not $WorkspacePrefix) { $WorkspacePrefix = if ($env:STUDENT_WORKSPACE_PREFIX) { $env:STUDENT_WORKSPACE_PREFIX } else { 'rail-rti-' } }
if (-not $ReferenceWorkspace) { $ReferenceWorkspace = if ($env:REFERENCE_WORKSPACE_NAME) { $env:REFERENCE_WORKSPACE_NAME } else { $env:FABRIC_WORKSPACE_NAME } }
if (-not $Notes) { $Notes = $env:HANDOUT_NOTES }
$auth = if ($env:EVENTHUB_AUTH) { $env:EVENTHUB_AUTH } else { 'key' }
if ($auth -notin @('key', 'entra')) { throw "EVENTHUB_AUTH must be 'key' or 'entra' (got '$auth')" }
if (-not $Out) { $Out = Join-Path (Split-Path $PSScriptRoot -Parent) 'handouts' }
if ($env:AZ_SUBSCRIPTION_ID) { Invoke-Az account set --subscription $env:AZ_SUBSCRIPTION_ID }

# --- Event Hub
if (-not $Namespace) { $Namespace = $env:EVENTHUB_NAMESPACE }
if (-not $Namespace) {
    $Namespace = az deployment group show -g $rg -n shared-eventhubs --query properties.outputs.namespaceName.value -o tsv 2>$null
}
if (-not $Namespace) { throw 'Set EVENTHUB_NAMESPACE or run ./scripts/create-eventhub.ps1 first' }
$Namespace = $Namespace.Split('.')[0]
Write-Step "Reading the shared Event Hub $Namespace"
az eventhubs namespace show -g $rg -n $Namespace -o none
if ($LASTEXITCODE -ne 0) { throw "Namespace '$Namespace' not found in $rg (check the exact name)" }

function Get-Groups([string]$Hub) {
    @(az eventhubs eventhub consumer-group list -g $rg --namespace-name $Namespace --eventhub-name $Hub --query '[].name' -o tsv 2>$null |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^$([regex]::Escape($prefix))\d+$" } | Sort-Object)
}
$nrodGroups = Get-Groups 'nrod-feed'
$rdmGroups = Get-Groups 'rdm-trust'
$hasDarwin = $false; $darwinGroups = @()
az eventhubs eventhub show -g $rg --namespace-name $Namespace -n rdm-darwin -o none 2>$null
if ($LASTEXITCODE -eq 0) {
    $hasDarwin = $true; $darwinGroups = Get-Groups 'rdm-darwin'
    Write-Host '  rdm-darwin found: the handouts include the optional Darwin feed (Student 1.5)'
}
if (-not $nrodGroups) { throw "No '${prefix}NN' consumer groups on nrod-feed. Run ./scripts/add-student-consumer-groups.ps1 first." }

$selected = @()
if (-not $Students) { $selected = $nrodGroups }
else {
    $width = ($nrodGroups[0] -replace "^$([regex]::Escape($prefix))", '').Length
    foreach ($p in ($Students -split ',')) {
        $p = ($p.Trim()) -replace "^$([regex]::Escape($prefix))", ''
        if ($p -match '^(\d+)-(\d+)$') { foreach ($n in [int]$Matches[1]..[int]$Matches[2]) { $selected += $prefix + $n.ToString("D$width") } }
        elseif ($p -match '^\d+$') { $selected += $prefix + ([int]$p).ToString("D$width") }
        else { throw "-Students '$p' isn't a number or range (use 1-12 or 3,7)" }
    }
}

# --- Key (key sign-in only)
$listenKey = ''
if ($auth -eq 'key') {
    $listenKey = az eventhubs namespace authorization-rule keys list -g $rg --namespace-name $Namespace `
        --authorization-rule-name students-listen --query primaryKey -o tsv 2>$null
    if (-not $listenKey) {
        Write-Warning "Couldn't read the students-listen key. The handouts will say [ask the instructor for the key]."
        $listenKey = '[ask the instructor for the key]'
    }
    $localAuth = az eventhubs namespace show -g $rg -n $Namespace --query disableLocalAuth -o tsv 2>$null
    if ("$localAuth" -eq 'true') {
        Write-Warning "Key sign-in is switched off on $Namespace (disableLocalAuth=true), so the key won't work. Use EVENTHUB_AUTH=entra (Instructor 1.4) and re-run."
    }
}

# --- Fabric workspace IDs (best effort)
$wsIds = @{}
Write-Step 'Looking up student workspaces in Fabric (optional)'
$wsJson = az rest --method get --resource https://api.fabric.microsoft.com --url https://api.fabric.microsoft.com/v1/workspaces 2>$null
if ($LASTEXITCODE -eq 0 -and $wsJson) {
    foreach ($w in (($wsJson | Out-String) | ConvertFrom-Json).value) { $wsIds[$w.displayName] = $w.id }
} else { Write-Host "  (couldn't list Fabric workspaces - the handouts will leave the workspace ID empty)" }

# --- Azure Maps token (optional)
if ($Maps -and -not $MapsToken) {
    Write-Step "Creating today's Azure Maps token"
    $MapsToken = (& "$PSScriptRoot/new-azure-maps-sas.ps1" | Select-Object -Last 1)
}
$mapsRow = if ($MapsToken) { "``$MapsToken`` (valid 24 hours from when it was created)" } else { 'Not included. If the class does Lab 2.9, the instructor sends a token each day (valid 24 hours)' }

# --- Write the handouts
$foundryEp = $env:FOUNDRY_PROJECT_ENDPOINT
$foundryModel = $env:FOUNDRY_MODEL_DEPLOYMENT_NAME
$agentBase = if ($env:FOUNDRY_AGENT_NAME) { $env:FOUNDRY_AGENT_NAME -replace "-$([regex]::Escape($prefix))\d+$", '' } else { 'rail-network-agent' }
$lakehouse = if ($env:FABRIC_LAKEHOUSE_NAME) { $env:FABRIC_LAKEHOUSE_NAME } else { 'RailLakehouse' }
if (-not $foundryEp) { Write-Warning 'FOUNDRY_PROJECT_ENDPOINT is empty in .env - the handouts will show a placeholder.' }
if (-not $foundryModel) { Write-Warning 'FOUNDRY_MODEL_DEPLOYMENT_NAME is empty in .env - the handouts will show a placeholder.' }
if (-not $Notes) { Write-Warning 'No -Notes given - the handouts will ask students to check with you about Labs 2.5 and 2.8.' }
$notesCell = if ($Notes) { $Notes } else { 'Check with the instructor whether Lab 2.5 (ontology) and Lab 2.8 (Fabric Apps) are available' }
$refCell = if ($ReferenceWorkspace) { $ReferenceWorkspace } else { '[ask the instructor]' }
$epCell = if ($foundryEp) { $foundryEp } else { '[ask the instructor]' }
$modelCell = if ($foundryModel) { $foundryModel } else { '[ask the instructor]' }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$index = @('consumer_group,workspace_name,workspace_id,agent_name,file')
Write-Step "Writing handouts to $Out"
$missingRdm = $false
$tick = '`'
$fence = '```'
foreach ($cg in $selected) {
    if ($cg -notin $nrodGroups) { Write-Warning "$cg doesn't exist on nrod-feed - skipped. Add it with ./scripts/add-student-consumer-groups.ps1"; continue }
    if ($cg -notin $rdmGroups) { Write-Warning "$cg is missing on rdm-trust"; $missingRdm = $true }
    if ($hasDarwin -and $cg -notin $darwinGroups) { Write-Warning "$cg is missing on rdm-darwin"; $missingRdm = $true }
    $darwinRow = if ($hasDarwin) { "| Optional Darwin feed (Student 1.5) | A third source: event hub ${tick}rdm-darwin$tick (→ table ${tick}RdmDarwinRaw$tick) in its own Eventstream, ${tick}RailEventstreamDarwin$tick, with the same settings |" } else { '' }
    $darwinNote = if ($hasDarwin) { ' Student 1.5 (Darwin) is optional: it adds to the capacity your workspace uses.' } else { '' }
    $ws = "$WorkspacePrefix$cg"
    $wsId = if ($wsIds.ContainsKey($ws)) { $wsIds[$ws] } else { '' }
    $agent = "$agentBase-$cg"
    $wsCell = if ($wsId) { "$tick$ws$tick (ID $tick$wsId$tick)" } else { "$tick$ws$tick – create it in Student 1.2 if the instructor hasn't" }
    if ($auth -eq 'key') {
        $authRows = "| Authentication kind | Shared access key |`n| Shared access key name | ${tick}students-listen$tick |`n| Shared access key | $tick$listenKey$tick |"
        $before = ''
    } else {
        $authRows = '| Authentication kind | **Workspace identity** (no key) |'
        $before = @"

## Before you connect

1. Open your workspace → **Workspace settings** → **Workspace identity** → enable it (you need the **Admin** role).
2. Copy the **ID** shown there (not the **App ID**) and send it to the instructor.
3. Wait until the instructor confirms your workspace has read access, then do Student 1.4.
"@
    }
    $md = @"
# Real-Time Rail Intelligence – your class handout ($cg)

**Keep this private.** Don't put it in a repo, a Teams channel or a slide.

## Your details

| Item | Value |
|---|---|
| Fabric workspace | $wsCell |
| Your consumer group (both hubs) | $tick$cg$tick |
| Your Foundry agent name | $tick$agent$tick |
| Reference Lakehouse | workspace $tick$refCell$tick → $tick$lakehouse$tick → ${tick}Tables/locations$tick |
| Labs that work in this tenant | $notesCell |
| Azure Maps token (Lab 2.9, optional) | $mapsRow |
$before
## Your ${tick}.env$tick settings (Student 1.1)

${fence}bash
FABRIC_WORKSPACE_NAME=$ws
FABRIC_WORKSPACE_ID=$wsId
KUSTO_QUERY_URI=                 # printed by Student 1.2
FOUNDRY_PROJECT_ENDPOINT=$epCell
FOUNDRY_MODEL_DEPLOYMENT_NAME=$modelCell
FOUNDRY_AGENT_NAME=$agent
$fence

Leave the ${tick}NROD_*$tick, ${tick}RDM_*$tick, ${tick}AZ_*$tick, ${tick}KEY_VAULT_*$tick and ${tick}EVENTHUB_*$tick values empty.

## Eventstream source settings (Student 1.4)

Add an **Azure Event Hubs** source twice, once for each hub:

| Setting | Value |
|---|---|
| Event Hub namespace | $tick$Namespace$tick |
| Event hub | ${tick}nrod-feed$tick (→ table ${tick}RawFeed$tick) and ${tick}rdm-trust$tick (→ table ${tick}RdmTrustRaw$tick) |
$authRows
| Consumer group | $tick$cg$tick (never ${tick}`$Default$tick) |
| Data format | JSON |
$darwinRow

Start at **docs/student/README.md** in the repo.$darwinNote
"@
    Set-Content -Path (Join-Path $Out "$cg.md") -Value $md -Encoding utf8
    $index += "$cg,$ws,$wsId,$agent,$cg.md"
    $found = if ($wsId) { ', workspace found' } else { '' }
    Write-Host "  wrote  $cg.md   ($ws$found)"
}
Set-Content -Path (Join-Path $Out 'index.csv') -Value $index -Encoding utf8
if ($missingRdm) { Write-Warning 'Some groups are missing on rdm-trust or rdm-darwin: re-run ./scripts/add-student-consumer-groups.ps1' }

Write-Host ''
Write-Host "Done. Send each file in $Out to its student privately."
if ($auth -eq 'key') { Write-Host 'The handouts contain the Listen key. The folder is git-ignored; delete it after the class (Instructor 1.7).' }
else { Write-Host "When students send their workspace identity ID: ./scripts/grant-eventhub-reader.ps1 -Id '<ID>','<ID>'" }
