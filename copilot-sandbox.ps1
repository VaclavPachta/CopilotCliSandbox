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
    Rebuild the Docker image with the latest Copilot CLI version, reusing the
    feature set saved by install.ps1. Use -Add or -Remove to adjust features.

.PARAMETER Add
    When used with -Update: feature(s) to add to the saved config.
    Valid values: playwright, csharpls, dotnet8, dotnet9, dotnet10, all

.PARAMETER Remove
    When used with -Update: feature(s) to remove from the saved config.
    Valid values: playwright, csharpls, dotnet8, dotnet9, dotnet10, all
    Removing csharpls also deletes lsp-config.json.

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

.EXAMPLE
    .\copilot-sandbox.ps1 -Update -Add playwright

.EXAMPLE
    .\copilot-sandbox.ps1 -Update -Remove playwright -Remove dotnet8

.EXAMPLE
    .\copilot-sandbox.ps1 -Update -Remove all
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Session,

    [switch]$Update,

    [switch]$Code,

    [string[]]$Add    = @(),
    [string[]]$Remove = @()
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
# -Update: rebuild the image, reusing saved feature config
# ---------------------------------------------------------------------------
if ($Update) {
    if (-not (Test-Path $dockerfilePath)) {
        Write-Error "Dockerfile not found at '$dockerfilePath'. Please re-run install.ps1."
        exit 1
    }

    $validFeatures     = @('playwright','csharpls','dotnet8','dotnet9','dotnet10','all')
    $sandboxConfigPath = Join-Path $sharedCopilotPath "sandbox-config.json"
    $lspConfigPath     = Join-Path $sharedCopilotPath "lsp-config.json"

    # Load saved config, or bootstrap with all features for legacy installs
    if (Test-Path $sandboxConfigPath) {
        $savedConfig = Get-Content $sandboxConfigPath -Raw | ConvertFrom-Json
        $f = $savedConfig.features
        $feat = @{
            playwright = [bool]$f.playwright; csharpLs = [bool]$f.csharpLs
            dotnet8 = [bool]$f.dotnet8; dotnet9 = [bool]$f.dotnet9; dotnet10 = [bool]$f.dotnet10
        }
    } else {
        Write-Warning "No sandbox-config.json found. Assuming all features enabled (legacy install)."
        $feat = @{ playwright=$true; csharpLs=$true; dotnet8=$true; dotnet9=$true; dotnet10=$true }
    }

    # Helper: parse a string[] param into a set of normalised feature keys
    function Get-FeatureSet([string[]]$names) {
        $set = @{}
        foreach ($name in $names) {
            foreach ($item in ($name -split ',')) {
                $item = $item.Trim().ToLower()
                if ($item -notin $validFeatures) {
                    Write-Warning "Unknown feature '$item' — skipping. Valid: $($validFeatures -join ', ')"
                    continue
                }
                if ($item -eq 'all') {
                    foreach ($k in @('playwright','csharpls','dotnet8','dotnet9','dotnet10')) { $set[$k] = $true }
                } else { $set[$item] = $true }
            }
        }
        return $set
    }

    $toRemove = Get-FeatureSet $Remove
    $toAdd    = Get-FeatureSet $Add

    $csharpLsWasEnabled = $feat['csharpLs']

    # Apply removals first, then additions
    foreach ($k in $toRemove.Keys) {
        $key = if ($k -eq 'csharpls') { 'csharpLs' } else { $k }
        $feat[$key] = $false
    }
    foreach ($k in $toAdd.Keys) {
        $key = if ($k -eq 'csharpls') { 'csharpLs' } else { $k }
        $feat[$key] = $true
    }

    # Implicit dotnet10 guard: csharpls needs at least one SDK
    if ($feat['csharpLs'] -and -not ($feat['dotnet8'] -or $feat['dotnet9'] -or $feat['dotnet10'])) {
        Write-Warning "csharpls requires a .NET SDK — enabling dotnet10 automatically."
        $feat['dotnet10'] = $true
    }

    # Clean up lsp-config.json if csharpls was just removed
    if ($csharpLsWasEnabled -and -not $feat['csharpLs'] -and (Test-Path $lspConfigPath)) {
        Remove-Item $lspConfigPath -Force
        Write-Host "  Removed lsp-config.json (csharpls feature disabled)." -ForegroundColor DarkGray
    }

    # Save merged config back
    [ordered]@{
        features = [ordered]@{
            playwright = $feat['playwright']; csharpLs = $feat['csharpLs']
            dotnet8 = $feat['dotnet8']; dotnet9 = $feat['dotnet9']; dotnet10 = $feat['dotnet10']
        }
    } | ConvertTo-Json -Depth 5 | Set-Content $sandboxConfigPath -Encoding UTF8

    # Build feature summary for display
    $featureLabels = @()
    if ($feat['playwright']) { $featureLabels += 'Playwright' }
    if ($feat['csharpLs'])   { $featureLabels += 'C# LS' }
    if ($feat['dotnet8'])    { $featureLabels += '.NET 8' }
    if ($feat['dotnet9'])    { $featureLabels += '.NET 9' }
    if ($feat['dotnet10'])   { $featureLabels += '.NET 10' }
    $featureSummary = if ($featureLabels.Count -gt 0) { $featureLabels -join ', ' } else { 'lean base (no optional features)' }

    Write-Host "Rebuilding copilot-sandbox image — features: $featureSummary" -ForegroundColor Cyan

    $buildArgs = @('build', '--no-cache', '-t', 'copilot-sandbox')
    if ($feat['playwright']) { $buildArgs += '--build-arg', 'INSTALL_PLAYWRIGHT=true' }
    if ($feat['csharpLs'])   { $buildArgs += '--build-arg', 'INSTALL_CSHARP_LS=true' }
    if ($feat['dotnet8'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET8=true' }
    if ($feat['dotnet9'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET9=true' }
    if ($feat['dotnet10'])   { $buildArgs += '--build-arg', 'INSTALL_DOTNET10=true' }
    $buildArgs += '-'

    Get-Content $dockerfilePath | docker @buildArgs
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
    Write-Host "  copilot-sandbox -Update                  Rebuild image with saved features" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Update -Add playwright  Add a feature and rebuild" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Update -Remove dotnet8  Remove a feature and rebuild" -ForegroundColor Gray
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

    $firstRunArgs = @('build', '-t', 'copilot-sandbox')
    $sandboxConfigPath = Join-Path $sharedCopilotPath "sandbox-config.json"
    if (Test-Path $sandboxConfigPath) {
        $cfg = (Get-Content $sandboxConfigPath -Raw | ConvertFrom-Json).features
        if ([bool]$cfg.playwright) { $firstRunArgs += '--build-arg', 'INSTALL_PLAYWRIGHT=true' }
        if ([bool]$cfg.csharpLs)   { $firstRunArgs += '--build-arg', 'INSTALL_CSHARP_LS=true' }
        if ([bool]$cfg.dotnet8)    { $firstRunArgs += '--build-arg', 'INSTALL_DOTNET8=true' }
        if ([bool]$cfg.dotnet9)    { $firstRunArgs += '--build-arg', 'INSTALL_DOTNET9=true' }
        if ([bool]$cfg.dotnet10)   { $firstRunArgs += '--build-arg', 'INSTALL_DOTNET10=true' }
    }
    $firstRunArgs += '-'

    Get-Content $dockerfilePath | docker @firstRunArgs
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
    -e "COPILOT_SANDBOX_SESSION=$Session" `
    -v "${sharedCopilotPath}:/root/.copilot" `
    -v "${sessionPath}:/workspace" `
    copilot-sandbox
