# Shared helpers for PowerShell scripts. Dot-source: . "$PSScriptRoot/_common.ps1"
$ErrorActionPreference = 'Stop'
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Import-DotEnv {
    $path = Join-Path $script:RepoRoot '.env'
    if (-not (Test-Path $path)) { return }
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $name, $value = $line -split '=', 2
        $name = $name.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        if ($name) { Set-Item -Path "Env:$name" -Value $value }
    }
}

function Assert-Env([string[]]$Names) {
    $missing = $Names | Where-Object { -not [Environment]::GetEnvironmentVariable($_) }
    if ($missing) { throw "Missing environment variable(s): $($missing -join ', ') (set them in .env)" }
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "'$Name' is not installed or not on PATH" }
}

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }

function Invoke-Az {
    # Runs az and throws on non-zero exit code.
    & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed with exit code $LASTEXITCODE" }
}
