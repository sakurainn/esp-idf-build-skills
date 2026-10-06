#requires -Version 5.1
<#
.SYNOPSIS
    Detect and activate a matching ESP-IDF environment, then run idf.py (build / flash / monitor / ...).

.DESCRIPTION
    Activation scripts are probed in order of reliability, first existing one wins:
      1) -ExportScript / -IdfPath (explicit)
      2) $env:IDF_PATH of the current shell
      3) idf_path recorded in the project's build/project_description.json (version locked by the build cache)
      4) installs under $env:IDF_TOOLS_PATH and ~/.espressif/frameworks
      5) idf.py already available on PATH (no activation needed)
    Activation and idf.py run in the SAME PowerShell session so environment variables survive.
    Platform: Windows. On Linux/macOS just run `. $IDF_PATH/export.sh` in the shell.

    NOTE: this file is intentionally ASCII-only so Windows PowerShell 5.1 reads it correctly.

.PARAMETER Project
    Project root directory (the one holding the top-level CMakeLists.txt).

.PARAMETER IdfPath
    ESP-IDF source directory (containing export.ps1). Auto-detected when omitted.

.PARAMETER ExportScript
    Explicit activation script; highest priority.

.PARAMETER Action
    build (default) / fullclean / reconfigure / menuconfig / size-components / size-files / set-target / erase-flash.

.PARAMETER Target
    Chip name used with -Action set-target.

.PARAMETER Clean
    Run idf.py fullclean before the action.

.PARAMETER Port
    Serial port, e.g. COM5 (Windows) or /dev/ttyUSB0.

.PARAMETER Flash
    Run idf.py -p <Port> flash.

.PARAMETER Monitor
    Run idf.py -p <Port> monitor.

.PARAMETER FlashMonitor
    Run idf.py -p <Port> flash monitor.

.PARAMETER DryRun
    Only print the selected activation script, then exit.

.EXAMPLE
    .\build.ps1 -Project D:\work\myapp
.EXAMPLE
    .\build.ps1 -Project D:\work\myapp -IdfPath C:\Espressif\frameworks\esp-idf-v5.3.2 -Clean
.EXAMPLE
    .\build.ps1 -Project D:\work\myapp -Port COM5 -FlashMonitor
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$IdfPath = '',
    [string]$ExportScript = '',

    [ValidateSet('build', 'fullclean', 'reconfigure', 'menuconfig', 'size-components', 'size-files', 'set-target', 'erase-flash')]
    [string]$Action = 'build',

    [string]$Target = '',
    [switch]$Clean,

    [string]$Port = '',
    [switch]$Flash,
    [switch]$Monitor,
    [switch]$FlashMonitor,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---------- discovery helpers ----------

function Find-Under([string]$namePattern, [string]$nameRegex, [string[]]$roots) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        if (-not $r) { continue }
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $items = Get-ChildItem -Path $r -Filter $namePattern -ErrorAction SilentlyContinue
        foreach ($i in @($items)) {
            if ($i.Name -match $nameRegex) { $out.Add($i.FullName) }
        }
    }
    return $out
}

function Get-ProjectIdfPath([string]$projectPath) {
    $desc = Join-Path $projectPath 'build\project_description.json'
    if (-not (Test-Path -LiteralPath $desc)) { return $null }
    try {
        $json = Get-Content -LiteralPath $desc -Raw | ConvertFrom-Json
        if ($json.idf_path -and (Test-Path -LiteralPath $json.idf_path)) { return $json.idf_path }
    } catch { }
    return $null
}

function Get-CandidateExportScripts([string]$projectPath) {
    # Each candidate is @{ Path = <activation script>; Source = <where it came from>; Pinned = <bool> }
    $candidates = New-Object System.Collections.ArrayList

    if ($ExportScript) { [void]$candidates.Add(@{ Path = $ExportScript; Source = '-ExportScript'; Pinned = $true }) }
    if ($IdfPath)       { [void]$candidates.Add(@{ Path = (Join-Path $IdfPath 'export.ps1'); Source = '-IdfPath'; Pinned = $true }) }
    if ($env:IDF_PATH)  { [void]$candidates.Add(@{ Path = (Join-Path $env:IDF_PATH 'export.ps1'); Source = 'IDF_PATH'; Pinned = $true }) }

    $proj = Get-ProjectIdfPath $projectPath
    if ($proj) { [void]$candidates.Add(@{ Path = (Join-Path $proj 'export.ps1'); Source = 'project_description.json'; Pinned = $true }) }

    # Probe roots: declared tools path, official installer layouts, and the Espressif
    # default Windows install root (used by the installation manager).
    $roots = @(
        $env:IDF_TOOLS_PATH,
        (Join-Path $env:USERPROFILE '.espressif\frameworks'),
        (Join-Path $env:USERPROFILE 'esp'),
        $(if ($env:SystemDrive) { Join-Path $env:SystemDrive 'Espressif\tools' } else { '' })
    )
    # Installation-manager layout: <tools>\*.PowerShell_profile.ps1
    foreach ($p in (Find-Under '*.PowerShell_profile.ps1' 'PowerShell_profile\.ps1$' $roots)) {
        [void]$candidates.Add(@{ Path = $p; Source = "probe:$p"; Pinned = $false })
    }
    # Official installer / manual clone layout: <root>\esp-idf*\export.ps1
    foreach ($p in (Find-Under 'export.ps1' '^export\.ps1$' $roots)) {
        [void]$candidates.Add(@{ Path = $p; Source = "probe:$p"; Pinned = $false })
    }

    # de-duplicate by path, keep order
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($c in $candidates) {
        if (-not $c.Path) { continue }
        if ($seen.ContainsKey($c.Path)) { continue }
        $seen[$c.Path] = $true
        [void]$out.Add($c)
    }
    return $out
}

# ---------- main ----------

if (-not (Test-Path -LiteralPath $Project)) { throw "Project directory not found: $Project" }
$projectPath = (Resolve-Path -LiteralPath $Project).Path

$onPath = Get-Command idf.py -ErrorAction SilentlyContinue
$script = $null
$scriptSource = $null
$pinned = $false
foreach ($c in (Get-CandidateExportScripts $projectPath)) {
    if ($c.Path -and (Test-Path -LiteralPath $c.Path)) {
        $script = (Resolve-Path -LiteralPath $c.Path).Path
        $scriptSource = $c.Source
        $pinned = $c.Pinned
        break
    }
}

if ($script) {
    Write-Host "==> activation: $script" -ForegroundColor Cyan
    Write-Host "==> picked from: $scriptSource" -ForegroundColor DarkGray
    if (-not $pinned) {
        Write-Warning "No IDF version recorded for this project and none given explicitly; picked a detected install. Pin it with -IdfPath if the build fails, and run 'idf.py fullclean' after switching versions."
    }
} elseif ($onPath) {
    Write-Host "==> no activation script found; using idf.py on PATH: $($onPath.Source)" -ForegroundColor Cyan
} else {
    throw "No usable ESP-IDF environment. Set `$env:IDF_PATH, or pass -IdfPath / -ExportScript, or install ESP-IDF first."
}
Write-Host "==> project   : $projectPath" -ForegroundColor Cyan
if ($Port) { Write-Host "==> port      : $Port" -ForegroundColor Cyan }

if ($DryRun) { Write-Host "==> DryRun done." -ForegroundColor Yellow; exit 0 }

if ($script) { . $script }
Set-Location -LiteralPath $projectPath

if ($Clean) {
    Write-Host "==> idf.py fullclean" -ForegroundColor Green
    idf.py fullclean
    if ($LASTEXITCODE -ne 0) { throw "fullclean failed (exit $LASTEXITCODE)" }
}

function Invoke-Idf {
    param([string[]]$IdfArgs)
    Write-Host "==> idf.py $($IdfArgs -join ' ')" -ForegroundColor Green
    & idf.py @IdfArgs
    if ($LASTEXITCODE -ne 0) { throw "idf.py $($IdfArgs -join ' ') failed (exit $LASTEXITCODE)" }
}

$portArgs = @()
if ($Port) { $portArgs = @('-p', $Port) }

if ($FlashMonitor) {
    Invoke-Idf ($portArgs + @('flash', 'monitor'))
} elseif ($Flash) {
    Invoke-Idf ($portArgs + @('flash'))
} elseif ($Monitor) {
    Invoke-Idf ($portArgs + @('monitor'))
} elseif ($Action -eq 'set-target') {
    if (-not $Target) { throw "-Action set-target requires -Target <chip>" }
    Invoke-Idf (@('set-target', $Target))
} else {
    Invoke-Idf ($portArgs + @($Action))
}

Write-Host "==> done" -ForegroundColor Cyan
exit 0