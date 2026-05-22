#Requires -Version 6.0
<#
.SYNOPSIS
    Run GitHub Copilot CLI in a Docker sandbox.

.DESCRIPTION
    Starts an interactive Copilot CLI session inside a Docker container.
    All Copilot config (auth, skills, agents) is shared across sessions via a
    mounted ~/.copilot directory. Each named session gets its own working directory.

    Can be run directly without installation:
        .\copilot-sandbox.ps1 MyProject

    Or installed globally via install.ps1 so it's available as:
        copilot-sandbox MyProject

.PARAMETER Session
    The session name. Maps to <BasePath>/<Session> on disk and to /workspace
    inside the container. Accepted positionally or as -Session.

.PARAMETER Update
    Rebuild the Docker image with the latest Copilot CLI version.

.PARAMETER Code
    Open the session folder in VS Code before launching the container.

.EXAMPLE
    .\copilot-sandbox.ps1 MyProject

.EXAMPLE
    .\copilot-sandbox.ps1 -Session MyProject

.EXAMPLE
    .\copilot-sandbox.ps1 MyProject -Code

.EXAMPLE
    .\copilot-sandbox.ps1 -Update
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Session,

    [switch]$Update,

    [switch]$Code
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve base path
# ---------------------------------------------------------------------------
$basePath = if ($env:COPILOT_SANDBOX_BASE_PATH) {
    $env:COPILOT_SANDBOX_BASE_PATH
} else {
    Join-Path $HOME ".copilot-sandbox"
}

$sharedCopilotPath = Join-Path $basePath ".copilot"
$dockerfilePath    = Join-Path $basePath "Dockerfile"

# Ensure base directories exist
if (-not (Test-Path $basePath))          { New-Item -ItemType Directory -Path $basePath          -Force | Out-Null }
if (-not (Test-Path $sharedCopilotPath)) { New-Item -ItemType Directory -Path $sharedCopilotPath -Force | Out-Null }

# ---------------------------------------------------------------------------
# -Update: rebuild the image with the latest Copilot CLI version
# ---------------------------------------------------------------------------
if ($Update) {
    if (-not (Test-Path $dockerfilePath)) {
        Write-Error "Dockerfile not found at '$dockerfilePath'. Please re-run install.ps1."
        exit 1
    }
    Write-Host "Rebuilding copilot-sandbox image with latest Copilot CLI..." -ForegroundColor Cyan
    Get-Content $dockerfilePath | docker build --no-cache -t copilot-sandbox -
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Update complete." -ForegroundColor Green
    }
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Require a session name
# ---------------------------------------------------------------------------
if (-not $Session) {
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  copilot-sandbox <session-name>           Start a session" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Session <session-name>  Start a session (named param)" -ForegroundColor Gray
    Write-Host "  copilot-sandbox MyProject -Code          Start a session + open in VS Code" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Update                  Rebuild image with latest CLI" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Base path : $(if ($env:COPILOT_SANDBOX_BASE_PATH) { $env:COPILOT_SANDBOX_BASE_PATH } else { '~/.copilot-sandbox (default)' })" -ForegroundColor DarkGray
    exit 0
}

# ---------------------------------------------------------------------------
# Ensure session directory exists
# ---------------------------------------------------------------------------
$sessionPath = Join-Path $basePath $Session
if (-not (Test-Path $sessionPath)) {
    Write-Host "Creating session directory: $sessionPath" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Auto-build image on first run if it doesn't exist
# ---------------------------------------------------------------------------
$imageId = docker images -q copilot-sandbox 2>$null
if (-not $imageId) {
    if (-not (Test-Path $dockerfilePath)) {
        Write-Error "Image 'copilot-sandbox' not found and Dockerfile missing at '$dockerfilePath'. Please re-run install.ps1."
        exit 1
    }
    Write-Host "Building copilot-sandbox image (first run)..." -ForegroundColor Cyan
    Get-Content $dockerfilePath | docker build -t copilot-sandbox -
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker build failed."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Session  : $Session" -ForegroundColor Cyan
Write-Host "  Workdir  : $sessionPath" -ForegroundColor DarkGray
Write-Host "  Config   : $sharedCopilotPath" -ForegroundColor DarkGray
Write-Host ""

if ($Code) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Host "  Opening session folder in VS Code..." -ForegroundColor DarkGray
        code $sessionPath
    } else {
        Write-Warning "'code' command not found. Is VS Code installed with the shell command in PATH?"
    }
}

$tokenArgs = @()
if ($env:COPILOT_SANDBOX_GITHUB_TOKEN) {
    $tokenArgs = @('-e', "COPILOT_GITHUB_TOKEN=$env:COPILOT_SANDBOX_GITHUB_TOKEN")
}

docker run --rm -it `
    @tokenArgs `
    -v "${sharedCopilotPath}:/root/.copilot" `
    -v "${sessionPath}:/workspace" `
    copilot-sandbox
