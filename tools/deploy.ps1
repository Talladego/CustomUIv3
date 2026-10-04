# Deploy only runtime addon files from this repo to the live RoR AddOns folder.
# Copies:
#   CustomUI.mod + Source\  -> Interface\AddOns\CustomUI\
# Removes anything else under Dest (docs, .git, editor clutter, etc.).
# Also deletes the legacy sibling AddOn Interface\AddOns\CustomUISettingsWindow
# (settings UI is now under CustomUI\Source\SettingsWindow\).
#
# Usage:
#   .\tools\deploy.ps1
#   .\tools\deploy.ps1 -WhatIf
#   .\tools\deploy.ps1 -AddOnsRoot "D:\Games\...\Interface\AddOns"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$AddOnsRoot = "C:\Users\talla\Games\Return of Reckoning\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DestCustomUI = Join-Path $AddOnsRoot "CustomUI"
$LegacySettingsDest = Join-Path $AddOnsRoot "CustomUISettingsWindow"

$ModSrc = Join-Path $RepoRoot "CustomUI.mod"
$SourceSrc = Join-Path $RepoRoot "Source"

function Assert-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label missing under $RepoRoot - refuse to deploy ($Path)"
    }
}

Assert-Path $ModSrc "CustomUI.mod"
Assert-Path $SourceSrc "Source\"
Assert-Path (Join-Path $SourceSrc "SettingsWindow") "Source\SettingsWindow\"
if (-not (Test-Path -LiteralPath $AddOnsRoot)) {
    throw "AddOns root missing: $AddOnsRoot"
}

Write-Host "Repo:     $RepoRoot"
Write-Host "AddOns:   $AddOnsRoot"
Write-Host "Dest:     $DestCustomUI"
Write-Host "Copy:     CustomUI.mod + Source\"
Write-Host "Remove:   legacy CustomUISettingsWindow (if present)"

if (-not $PSCmdlet.ShouldProcess($AddOnsRoot, "Deploy CustomUI runtime files and remove legacy settings AddOn")) {
    exit 0
}

function Invoke-MirrorDir {
    param(
        [Parameter(Mandatory = $true)][string]$Src,
        [Parameter(Mandatory = $true)][string]$Dest
    )
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $robocopyArgs = @(
        $Src,
        $Dest,
        "/MIR",
        "/XF", "*.bak", "*.tmp", "*.log", "Thumbs.db", ".DS_Store",
        "/XD", "__pycache__", ".git",
        "/R:2", "/W:1",
        "/NFL", "/NDL", "/NP", "/NJH", "/NJS"
    )
    # Discard robocopy stdout so callers get only the exit code (not summary lines).
    & robocopy @robocopyArgs | Out-Null
    $rc = $LASTEXITCODE
    # Robocopy: 0-7 = success (with optional extras); >=8 = failure
    if ($rc -ge 8) {
        throw "robocopy failed ($Src -> $Dest) with exit code $rc"
    }
    return ,$rc
}

function Clear-Extras {
    param(
        [Parameter(Mandatory = $true)][string]$Dest,
        [Parameter(Mandatory = $true)][hashtable]$Allowed
    )
    Get-ChildItem -LiteralPath $Dest -Force | ForEach-Object {
        if ($Allowed.ContainsKey($_.Name)) { return }
        Write-Host "Prune: $($_.FullName)"
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

# --- CustomUI ---
New-Item -ItemType Directory -Force -Path $DestCustomUI | Out-Null
$rcUi = Invoke-MirrorDir -Src $SourceSrc -Dest (Join-Path $DestCustomUI "Source")
Copy-Item -LiteralPath $ModSrc -Destination (Join-Path $DestCustomUI "CustomUI.mod") -Force
Clear-Extras -Dest $DestCustomUI -Allowed @{
    "CustomUI.mod" = $true
    "Source"       = $true
}

# --- Remove legacy separate settings AddOn (avoids duplicate CreateWindow) ---
if (Test-Path -LiteralPath $LegacySettingsDest) {
    Write-Host "Remove:  $LegacySettingsDest"
    Remove-Item -LiteralPath $LegacySettingsDest -Recurse -Force
}

$destMod = Join-Path $DestCustomUI "CustomUI.mod"
$destSource = Join-Path $DestCustomUI "Source"
$destSettings = Join-Path $destSource "SettingsWindow"
if (-not (Test-Path -LiteralPath $destMod) -or -not (Test-Path -LiteralPath $destSource)) {
    throw "Deploy incomplete: missing CustomUI.mod or Source under $DestCustomUI"
}
if (-not (Test-Path -LiteralPath $destSettings)) {
    throw "Deploy incomplete: missing Source\SettingsWindow under $DestCustomUI"
}
if (Test-Path -LiteralPath $LegacySettingsDest) {
    throw "Deploy incomplete: legacy CustomUISettingsWindow still present at $LegacySettingsDest"
}

$copiedUi = (Get-ChildItem -LiteralPath $destSource -Recurse -File).Count
Write-Host "Deploy OK (CustomUI Source files: $copiedUi, robocopy exit $rcUi)."
Write-Host "Reload UI in-game (/reload)."
exit 0
