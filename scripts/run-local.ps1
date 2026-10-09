<#
.SYNOPSIS
  Run the STOMP bridge locally (Lab 05a).
.EXAMPLE
  ./scripts/run-local.ps1 -Mode venv -Sink console -Replay
  ./scripts/run-local.ps1 -Mode docker -Sink eventstream
  ./scripts/run-local.ps1 -Mode test
  ./scripts/run-local.ps1 -Mode venv -Sink eventhub -Kafka   # optional RDM Kafka relay (Lab 05c)
#>
param(
    [ValidateSet('venv', 'docker', 'test')][string]$Mode = 'venv',
    [ValidateSet('console', 'file', 'eventstream', 'eventhub')][string]$Sink = 'console',
    [switch]$Replay,
    [switch]$Kafka
)
. "$PSScriptRoot/_common.ps1"
Import-DotEnv
$bridge = Join-Path $script:RepoRoot 'src/bridge'
Push-Location $bridge
try {
    $bridgeArgs = @('--sink', $Sink)
    if ($Replay) { $bridgeArgs += @('--source', 'replay', '--replay-file', (Join-Path $bridge 'tests/fixtures/replay_frames.json')) }
    elseif ($Kafka) {
        $bridgeArgs += @('--source', 'kafka')
        # The relay sends to the rdm-trust hub, not the nrod-feed hub used by the NROD bridge.
        $env:EVENTHUB_CONNECTION_STRING = $env:EVENTHUB_RDM_CONNECTION_STRING
    }

    switch ($Mode) {
        'venv' {
            if (-not (Test-Path '.venv')) { Write-Step 'Creating virtual environment'; python -m venv .venv }
            $py = if ($IsWindows -or $env:OS -eq 'Windows_NT') { '.venv/Scripts/python.exe' } else { '.venv/bin/python' }
            & $py -m pip install --quiet -r requirements.txt
            Write-Step "Starting bridge (sink=$Sink) - Ctrl+C to stop"
            & $py -m rail_bridge @bridgeArgs
        }
        'docker' {
            Assert-Command docker
            if ($Replay) { docker compose --profile offline up --build replay; break }
            if ($Kafka) {
                $env:RELAY_SINK = $Sink
                Write-Step "Starting RDM Kafka relay container (sink=$Sink)"
                docker compose --profile relay up --build rdm-relay
                break
            }
            New-Item -ItemType Directory -Force -Path 'out' | Out-Null
            $env:BRIDGE_SINK = $Sink
            Write-Step "Starting bridge container (sink=$Sink)"
            docker compose up --build bridge
        }
        'test' {
            if (-not (Test-Path '.venv')) { python -m venv .venv }
            $py = if ($IsWindows -or $env:OS -eq 'Windows_NT') { '.venv/Scripts/python.exe' } else { '.venv/bin/python' }
            & $py -m pip install --quiet -r requirements-dev.txt
            & $py -m pytest -q
        }
    }
}
finally { Pop-Location }
