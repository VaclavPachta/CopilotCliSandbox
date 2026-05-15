#Requires -Version 6.0
<#
.SYNOPSIS
    Installs the copilot-sandbox command into your PowerShell profile.

.DESCRIPTION
    - Copies the Dockerfile to your sandbox base path
    - Builds the copilot-sandbox Docker image
    - Adds the copilot-sandbox function to your $PROFILE (idempotent: safe to re-run)

.PARAMETER BasePath
    Override the sandbox base path. Defaults to the value of $env:COPILOT_SANDBOX_BASE_PATH,
    or ~/.copilot-sandbox if the environment variable is not set.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -BasePath D:\MySandboxes
#>
[CmdletBinding()]
param(
    [string]$BasePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step([string]$msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Copilot CLI Sandbox  —  Installer    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Resolve base path
# ---------------------------------------------------------------------------
if (-not $BasePath) {
    $BasePath = if ($env:COPILOT_SANDBOX_BASE_PATH) {
        $env:COPILOT_SANDBOX_BASE_PATH
    } else {
        Join-Path $HOME ".copilot-sandbox"
    }
}
Write-Step "Sandbox base path : $BasePath"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
Write-Step "Checking prerequisites..."

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed or not in PATH. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ and try again."
    exit 1
}

$dockerInfo = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker is not running. Please start Docker Desktop and try again."
    exit 1
}

Write-Ok "Docker is running."

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
Write-Step "Setting up directory structure..."

foreach ($dir in @($BasePath, (Join-Path $BasePath ".copilot"))) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Ok "Created: $dir"
    }
}

# ---------------------------------------------------------------------------
# Copy copilot-sandbox.ps1 to base path
# ---------------------------------------------------------------------------
Write-Step "Copying copilot-sandbox.ps1 to base path..."

$scriptDest   = Join-Path $BasePath "copilot-sandbox.ps1"
$scriptSource = Join-Path $PSScriptRoot "copilot-sandbox.ps1"

if (Test-Path $scriptSource) {
    Copy-Item $scriptSource $scriptDest -Force
    Write-Ok "Copied copilot-sandbox.ps1 to $scriptDest"
} else {
    Write-Error "copilot-sandbox.ps1 not found next to install.ps1. Please clone the full repository."
    exit 1
}

# ---------------------------------------------------------------------------
# Write Dockerfile to base path
# ---------------------------------------------------------------------------
Write-Step "Writing Dockerfile to base path..."

$dockerfileDest = Join-Path $BasePath "Dockerfile"
$scriptDockerfile = Join-Path $PSScriptRoot "Dockerfile"

if (Test-Path $scriptDockerfile) {
    Copy-Item $scriptDockerfile $dockerfileDest -Force
    Write-Ok "Copied Dockerfile from repo."
} else {
    # Embedded fallback — kept in sync with the Dockerfile in this repo
    @'
FROM node:22-slim

# ---------------------------------------------------------------------------
# System tools
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        unzip \
        zip \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# .NET SDKs (8, 9, 10) via Microsoft install script
# ---------------------------------------------------------------------------
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet \
    && /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# ---------------------------------------------------------------------------
# GitHub Copilot CLI
# ---------------------------------------------------------------------------
RUN npm install -g @github/copilot

WORKDIR /workspace

ENTRYPOINT ["copilot"]
'@ | Set-Content $dockerfileDest -Encoding UTF8
    Write-Ok "Wrote embedded Dockerfile."
}

# ---------------------------------------------------------------------------
# Build Docker image
# ---------------------------------------------------------------------------
Write-Step "Building copilot-sandbox Docker image (this may take a minute)..."

# Pipe Dockerfile via stdin so no build context is sent — avoids uploading
# the entire base path (which may contain session data and credentials).
Get-Content $dockerfileDest | docker build -t copilot-sandbox -

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed. Check the output above."
    exit 1
}
Write-Ok "Image 'copilot-sandbox' built successfully."

# ---------------------------------------------------------------------------
# Build the thin wrapper block to inject into $PROFILE
# The wrapper resolves the base path at call-time and delegates to the
# copilot-sandbox.ps1 script stored there — keeping all logic in one place.
# ---------------------------------------------------------------------------
$functionBlock = @'

# BEGIN copilot-sandbox — managed block, do not edit manually
function copilot-sandbox {
    $basePath   = if ($env:COPILOT_SANDBOX_BASE_PATH) { $env:COPILOT_SANDBOX_BASE_PATH } else { Join-Path $HOME ".copilot-sandbox" }
    $scriptPath = Join-Path $basePath "copilot-sandbox.ps1"
    if (-not (Test-Path $scriptPath)) {
        Write-Error "copilot-sandbox.ps1 not found at '$scriptPath'. Please re-run install.ps1."
        return
    }
    & $scriptPath @args
}
# END copilot-sandbox
'@

# ---------------------------------------------------------------------------
# Inject function into $PROFILE (idempotent via BEGIN/END markers)
# ---------------------------------------------------------------------------
Write-Step "Installing copilot-sandbox function into PowerShell profile..."

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Ok "Created profile file: $PROFILE"
}

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue

if ($profileContent -match '# BEGIN copilot-sandbox') {
    Write-Warn "Existing copilot-sandbox block found — replacing it."
    # Remove the old managed block (handles both LF and CRLF line endings)
    $profileContent = $profileContent -replace '(?s)\r?\n?# BEGIN copilot-sandbox.*?# END copilot-sandbox\r?\n?', ''
    Set-Content $PROFILE $profileContent -Encoding UTF8 -NoNewline
}

Add-Content $PROFILE $functionBlock -Encoding UTF8

Write-Ok "Function installed in: $PROFILE"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          Installation complete!          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Reload your profile:" -ForegroundColor White
Write-Host "    . `$PROFILE" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Then start a session:" -ForegroundColor White
Write-Host "    copilot-sandbox MyProject" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Update Copilot CLI later:" -ForegroundColor White
Write-Host "    copilot-sandbox -Update" -ForegroundColor Yellow
Write-Host ""
