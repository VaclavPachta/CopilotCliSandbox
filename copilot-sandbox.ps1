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
    Named session. Maps to <BasePath>/<Session> on disk and to /workspace inside
    the container. Creates the folder if it doesn't exist.
    Accepted positionally or as -Session.

.PARAMETER Path
    Explicit workspace path (absolute or relative to the current directory).
    The path must already exist. Use '.' for the current directory.
    Accepted positionally (auto-detected when the value contains path separators
    or starts with '.') or as -Path.

.PARAMETER Update
    Rebuild the Docker image with the latest Copilot CLI version, reusing the
    feature set saved by install.ps1. Use -Add or -Remove to adjust features.

.PARAMETER Add
    Feature(s) to add to the saved config. Triggers a rebuild automatically.
    Valid values: playwright, csharpls, dotnet8, dotnet9, dotnet10, rtk, all

.PARAMETER Remove
    Feature(s) to remove from the saved config. Triggers a rebuild automatically.
    Valid values: playwright, csharpls, dotnet8, dotnet9, dotnet10, rtk, all
    Removing csharpls also deletes lsp-config.json.

.PARAMETER Code
    Open the session folder in VS Code before launching the container.

.PARAMETER Rider
    Open the session folder in JetBrains Rider before launching the container.

.EXAMPLE
    .\copilot-sandbox.ps1 .

.EXAMPLE
    .\copilot-sandbox.ps1 -Path C:\temp\MyProject

.EXAMPLE
    .\copilot-sandbox.ps1 MyProject

.EXAMPLE
    .\copilot-sandbox.ps1 -Session MyProject

.EXAMPLE
    .\copilot-sandbox.ps1 MyProject -Code

.EXAMPLE
    .\copilot-sandbox.ps1 MyProject -Rider

.EXAMPLE
    .\copilot-sandbox.ps1 -Update

.EXAMPLE
    .\copilot-sandbox.ps1 -Add playwright

.EXAMPLE
    .\copilot-sandbox.ps1 -Remove playwright,dotnet8

.EXAMPLE
    .\copilot-sandbox.ps1 -Remove all
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Session,

    [string]$Path,

    [switch]$Update,

    [switch]$Code,

    [switch]$Rider,

    [string[]]$Add    = @(),
    [string[]]$Remove = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Implicit update: -Add or -Remove alone is enough to trigger a rebuild
if ($Add.Count -gt 0 -or $Remove.Count -gt 0) { $Update = $true }

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

    $validFeatures     = @('playwright','csharpls','dotnet8','dotnet9','dotnet10','rtk','all')
    $sandboxConfigPath = Join-Path $sharedCopilotPath "sandbox-config.json"
    $lspConfigPath     = Join-Path $sharedCopilotPath "lsp-config.json"

    # Load saved config, or bootstrap with all features for legacy installs
    if (Test-Path $sandboxConfigPath) {
        $savedConfig = Get-Content $sandboxConfigPath -Raw | ConvertFrom-Json
        $f = $savedConfig.features
        $feat = @{
            playwright = [bool]$f.playwright; csharpLs = [bool]$f.csharpLs
            dotnet8 = [bool]$f.dotnet8; dotnet9 = [bool]$f.dotnet9; dotnet10 = [bool]$f.dotnet10
            rtk = [bool]$f.rtk
        }
    } else {
        Write-Warning "No sandbox-config.json found. Assuming all features enabled (legacy install)."
        $feat = @{ playwright=$true; csharpLs=$true; dotnet8=$true; dotnet9=$true; dotnet10=$true; rtk=$false }
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
                    foreach ($k in @('playwright','csharpls','dotnet8','dotnet9','dotnet10','rtk')) { $set[$k] = $true }
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
            rtk = $feat['rtk']
        }
    } | ConvertTo-Json -Depth 5 | Set-Content $sandboxConfigPath -Encoding UTF8

    # Build feature summary for display
    $featureLabels = @()
    if ($feat['playwright']) { $featureLabels += 'Playwright' }
    if ($feat['csharpLs'])   { $featureLabels += 'C# LS' }
    if ($feat['dotnet8'])    { $featureLabels += '.NET 8' }
    if ($feat['dotnet9'])    { $featureLabels += '.NET 9' }
    if ($feat['dotnet10'])   { $featureLabels += '.NET 10' }
    if ($feat['rtk'])        { $featureLabels += 'RTK' }
    $featureSummary = if ($featureLabels.Count -gt 0) { $featureLabels -join ', ' } else { 'lean base (no optional features)' }

    Write-Host "Rebuilding copilot-sandbox image — features: $featureSummary" -ForegroundColor Cyan

    $buildArgs = @('build', '--no-cache', '-t', 'copilot-sandbox')
    if ($feat['playwright']) { $buildArgs += '--build-arg', 'INSTALL_PLAYWRIGHT=true' }
    if ($feat['csharpLs'])   { $buildArgs += '--build-arg', 'INSTALL_CSHARP_LS=true' }
    if ($feat['dotnet8'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET8=true' }
    if ($feat['dotnet9'])    { $buildArgs += '--build-arg', 'INSTALL_DOTNET9=true' }
    if ($feat['dotnet10'])   { $buildArgs += '--build-arg', 'INSTALL_DOTNET10=true' }
    if ($feat['rtk'])        { $buildArgs += '--build-arg', 'INSTALL_RTK=true' }
    $buildArgs += '-'

    Get-Content $dockerfilePath | docker @buildArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Update complete." -ForegroundColor Green
    }
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Auto-dispatch: positional arg that looks like a path → treat as -Path
# ---------------------------------------------------------------------------
if ($Session -and -not $Path) {
    $isPathLike = [System.IO.Path]::IsPathRooted($Session) -or
                  $Session -match '[/\\]' -or
                  $Session.StartsWith('.')
    if ($isPathLike) {
        $Path    = $Session
        $Session = ''
    }
}

if ($Session -and $Path) {
    Write-Error "Cannot use both -Session and -Path. Use -Session for a named session (stored in the base path) or -Path for an explicit directory."
    exit 1
}

# ---------------------------------------------------------------------------
# Require at least one of -Session or -Path
# ---------------------------------------------------------------------------
if (-not $Session -and -not $Path) {
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  copilot-sandbox <session-name>           Start a named session (created in base path if needed)" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Session <session-name>  Start a named session (named param)" -ForegroundColor Gray
    Write-Host "  copilot-sandbox .                        Mount the current directory" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Path <dir>              Mount an explicit existing directory" -ForegroundColor Gray
    Write-Host "  copilot-sandbox MyProject -Code          Start a session + open in VS Code" -ForegroundColor Gray
    Write-Host "  copilot-sandbox MyProject -Rider         Start a session + open in Rider" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Update                  Rebuild image with saved features" -ForegroundColor Gray
    Write-Host "  copilot-sandbox -Add playwright          Add a feature and rebuild" -ForegroundColor Gray
      Write-Host "  copilot-sandbox -Remove dotnet8        Remove a feature and rebuild" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Base path : $(if ($env:COPILOT_SANDBOX_BASE_PATH) { $env:COPILOT_SANDBOX_BASE_PATH } else { '~/.copilot-sandbox (default)' })" -ForegroundColor DarkGray
    exit 0
}

# ---------------------------------------------------------------------------
# Resolve workspace path
# ---------------------------------------------------------------------------
if ($Path) {
    # Path mode: absolute or relative to $PWD — must already exist
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        [System.IO.Path]::GetFullPath($Path, $PWD.Path)
    }
    if (-not (Test-Path $resolvedPath -PathType Container)) {
        Write-Error "Path '$resolvedPath' does not exist. Provide an existing directory, or use a session name to have one created automatically."
        exit 1
    }
    $sessionPath    = $resolvedPath
    $sessionDisplay = $resolvedPath
} else {
    # Session mode: named session always lives in $basePath
    $sessionPath    = Join-Path $basePath $Session
    $sessionDisplay = $sessionPath
    if (-not (Test-Path $sessionPath)) {
        Write-Host "Creating session directory: $sessionPath" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
    }
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
        if ([bool]$cfg.rtk)        { $firstRunArgs += '--build-arg', 'INSTALL_RTK=true' }
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
Write-Host "  Workspace: $sessionDisplay" -ForegroundColor Cyan
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

if ($Rider) {
    if (Get-Command rider -ErrorAction SilentlyContinue) {
        Write-Host "  Opening session folder in Rider..." -ForegroundColor DarkGray
        rider $sessionPath
    } else {
        Write-Warning "'rider' command not found. Is Rider installed with shell scripts enabled in JetBrains Toolbox?"
    }
}

$tokenArgs = @()
if ($env:COPILOT_SANDBOX_GITHUB_TOKEN) {
    $tokenArgs = @('-e', "COPILOT_GITHUB_TOKEN=$env:COPILOT_SANDBOX_GITHUB_TOKEN")
}

# Mount RTK data directory if the feature is enabled (shares token-savings history across sessions)
$rtkArgs = @()
$sandboxConfigPath = Join-Path $sharedCopilotPath "sandbox-config.json"
if (Test-Path $sandboxConfigPath) {
    $rtkCfg = (Get-Content $sandboxConfigPath -Raw | ConvertFrom-Json).features
    if ([bool]$rtkCfg.rtk) {
        $rtkDataPath = Join-Path $basePath ".rtk"
        if (-not (Test-Path $rtkDataPath)) { New-Item -ItemType Directory -Path $rtkDataPath -Force | Out-Null }
        $rtkArgs = @('-v', "${rtkDataPath}:/root/.local/share/rtk")
    }
}

docker run --rm -it `
    @tokenArgs `
    @rtkArgs `
    -e "COPILOT_SANDBOX_SESSION=$sessionDisplay" `
    -v "${sharedCopilotPath}:/root/.copilot" `
    -v "${sessionPath}:/workspace" `
    copilot-sandbox
