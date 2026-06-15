#Requires -Version 6.0
<#
.SYNOPSIS
    Installs the copilot-sandbox command into your PowerShell profile.

.DESCRIPTION
    - Copies the Dockerfile to your sandbox base path
    - Builds the copilot-sandbox Docker image (lean base by default)
    - Adds the copilot-sandbox function to your $PROFILE (idempotent: safe to re-run)

    Optional features can be included via -Add (see parameter below).
    Run without any flags to build a minimal image (Copilot CLI + core tools only).

.PARAMETER BasePath
    Override the sandbox base path. Defaults to the value of $env:COPILOT_SANDBOX_BASE_PATH,
    or ~/.copilot-sandbox if the environment variable is not set.

.PARAMETER Add
    Feature(s) to include in the image. Accepts one or more values:
      playwright  — Playwright CLI + Chromium browser
      csharpls    — C# Language Server (csharp-ls); implies dotnet10 if no SDK specified
      dotnet8     — .NET SDK 8
      dotnet9     — .NET SDK 9
      dotnet10    — .NET SDK 10
      rtk         — RTK token-optimization proxy (history shared across sessions)
      all         — all of the above

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Add playwright -Add csharpls

.EXAMPLE
    .\install.ps1 -Add all

.EXAMPLE
    .\install.ps1 -BasePath D:\MySandboxes -Add dotnet9 -Add playwright
#>
[CmdletBinding()]
param(
    [string]$BasePath,
    [string[]]$Add = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Parse -Add into resolved feature booleans
# ---------------------------------------------------------------------------
$validFeatures = @('playwright','csharpls','dotnet8','dotnet9','dotnet10','rtk','all')

$feat = @{ playwright=$false; csharpLs=$false; dotnet8=$false; dotnet9=$false; dotnet10=$false; rtk=$false }

foreach ($name in $Add) {
    foreach ($item in ($name -split ',')) {
        $item = $item.Trim().ToLower()
        if ($item -notin $validFeatures) {
            Write-Warning "Unknown feature '$item' — skipping. Valid names: $($validFeatures -join ', ')"
            continue
        }
        if ($item -eq 'all') {
            $feat['playwright']=$true; $feat['csharpLs']=$true
            $feat['dotnet8']=$true; $feat['dotnet9']=$true; $feat['dotnet10']=$true
            $feat['rtk']=$true
        } else {
            $key = if ($item -eq 'csharpls') { 'csharpLs' } else { $item }
            $feat[$key] = $true
        }
    }
}

# If csharp-ls requested but no .NET SDK selected, implicitly enable .NET 10
if ($feat['csharpLs'] -and -not ($feat['dotnet8'] -or $feat['dotnet9'] -or $feat['dotnet10'])) {
    Write-Warning "csharpls requires a .NET SDK — enabling dotnet10 automatically."
    $feat['dotnet10'] = $true
}

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

$sharedCopilotPath = Join-Path $BasePath ".copilot"

foreach ($dir in @($BasePath, $sharedCopilotPath)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Ok "Created: $dir"
    }
}

# ---------------------------------------------------------------------------
# Create default lsp-config.json with C# language server (only if csharpls)
# ---------------------------------------------------------------------------
if ($feat['csharpLs']) {
    Write-Step "Configuring C# language server..."

    $lspConfigPath = Join-Path $sharedCopilotPath "lsp-config.json"
    if (-not (Test-Path $lspConfigPath)) {
        [ordered]@{
            lspServers = [ordered]@{
                csharp = [ordered]@{
                    command          = "csharp-ls"
                    args             = @()
                    fileExtensions   = [ordered]@{ ".cs" = "csharp" }
                }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content $lspConfigPath -Encoding UTF8
        Write-Ok "Created lsp-config.json with C# language server (csharp-ls)."
    } else {
        Write-Warn "lsp-config.json already exists at '$lspConfigPath' — skipping. Add 'csharp-ls' manually if you want C# LSP support."
    }
}

# ---------------------------------------------------------------------------
# Create RTK data directory on host (shared across all sessions)
# ---------------------------------------------------------------------------
if ($feat['rtk']) {
    $rtkDataPath = Join-Path $BasePath ".rtk"
    if (-not (Test-Path $rtkDataPath)) {
        New-Item -ItemType Directory -Path $rtkDataPath -Force | Out-Null
        Write-Ok "Created RTK data directory: $rtkDataPath"
    }
}

# ---------------------------------------------------------------------------
# Upsert statusLine setting in settings.json
# ---------------------------------------------------------------------------
Write-Step "Configuring Copilot CLI settings.json for status line..."

$settingsPath = Join-Path $sharedCopilotPath "settings.json"
$statusLineConfig = [ordered]@{
    type    = "command"
    command = "/bin/bash /usr/local/bin/statusline-session.sh"
}

if (-not (Test-Path $settingsPath)) {
    [ordered]@{ statusLine = $statusLineConfig } |
        ConvertTo-Json -Depth 5 |
        Set-Content $settingsPath -Encoding UTF8
    Write-Ok "Created settings.json with statusLine config."
} else {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    # Add/overwrite statusLine key (PSCustomObject doesn't support indexer, use Add-Member)
    if ($settings.PSObject.Properties['statusLine']) {
        $settings.statusLine = $statusLineConfig
    } else {
        $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineConfig
    }
    $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
    Write-Ok "Updated settings.json with statusLine config."
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
# Copy Dockerfile to base path
# ---------------------------------------------------------------------------
Write-Step "Copying Dockerfile to base path..."

$dockerfileDest = Join-Path $BasePath "Dockerfile"
$scriptDockerfile = Join-Path $PSScriptRoot "Dockerfile"

if (Test-Path $scriptDockerfile) {
    Copy-Item $scriptDockerfile $dockerfileDest -Force
    Write-Ok "Copied Dockerfile from repo."
} else {
    Write-Error "Dockerfile not found next to install.ps1. Please clone the full repository."
    exit 1
}

# ---------------------------------------------------------------------------
# Build Docker image
# ---------------------------------------------------------------------------
$featureLabels = @()
if ($feat['playwright']) { $featureLabels += 'Playwright (Chromium)' }
if ($feat['csharpLs'])   { $featureLabels += 'C# Language Server (csharp-ls)' }
if ($feat['dotnet8'])    { $featureLabels += '.NET SDK 8' }
if ($feat['dotnet9'])    { $featureLabels += '.NET SDK 9' }
if ($feat['dotnet10'])   { $featureLabels += '.NET SDK 10' }
if ($feat['rtk'])        { $featureLabels += 'RTK' }

if ($featureLabels.Count -gt 0) {
    Write-Step "Building copilot-sandbox Docker image with features: $($featureLabels -join ', ')..."
} else {
    Write-Step "Building copilot-sandbox Docker image (lean base — no optional features)..."
}

$buildArgs = @('build', '-t', 'copilot-sandbox')
if ($feat['playwright']) { $buildArgs += '--build-arg', 'INSTALL_PLAYWRIGHT=true' }
if ($feat['csharpLs'])   { $buildArgs += '--build-arg', 'INSTALL_CSHARP_LS=true' }
if ($feat['dotnet8'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET8=true' }
if ($feat['dotnet9'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET9=true' }
if ($feat['dotnet10'])   { $buildArgs += '--build-arg', 'INSTALL_DOTNET10=true' }
if ($feat['rtk'])        { $buildArgs += '--build-arg', 'INSTALL_RTK=true' }
$buildArgs += '-'

# Pipe Dockerfile via stdin so no build context is sent — avoids uploading
# the entire base path (which may contain session data and credentials).
Get-Content $dockerfileDest | docker @buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed. Check the output above."
    exit 1
}
Write-Ok "Image 'copilot-sandbox' built successfully."

# ---------------------------------------------------------------------------
# Save feature config so -Update can reproduce the same image
# ---------------------------------------------------------------------------
Write-Step "Saving feature configuration..."

$sandboxConfig = [ordered]@{
    features = [ordered]@{
        playwright = $feat['playwright']
        csharpLs   = $feat['csharpLs']
        dotnet8    = $feat['dotnet8']
        dotnet9    = $feat['dotnet9']
        dotnet10   = $feat['dotnet10']
        rtk        = $feat['rtk']
    }
}
$sandboxConfigPath = Join-Path $sharedCopilotPath "sandbox-config.json"
$sandboxConfig | ConvertTo-Json -Depth 5 | Set-Content $sandboxConfigPath -Encoding UTF8
Write-Ok "Saved sandbox-config.json (used by 'copilot-sandbox -Update' to rebuild with the same features)."

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

if (-not $env:COPILOT_SANDBOX_GITHUB_TOKEN) {
  Write-Host "  Tip: Set COPILOT_SANDBOX_GITHUB_TOKEN to a GitHub PAT to auto-authenticate containers:" -ForegroundColor Yellow
  Write-Host "    `$env:COPILOT_SANDBOX_GITHUB_TOKEN = '<your-token>'" -ForegroundColor DarkGray
  Write-Host "  Add it to your `$PROFILE for persistence." -ForegroundColor DarkGray
  Write-Host ""
}
