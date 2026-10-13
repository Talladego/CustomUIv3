# Pack an installable CustomUI zip: CustomUI/CustomUI.mod + CustomUI/Source/
# Unzip into Interface/AddOns/ so the game loads Interface/AddOns/CustomUI/.
# Payload matches tools/deploy.ps1 (runtime addon only; no repo docs, tools, or git).
# Usage: pwsh ./scripts/pack.ps1 [-OutDir dist]
param(
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"

function Copy-AddonSource {
    param(
        [Parameter(Mandatory = $true)][string]$Src,
        [Parameter(Mandatory = $true)][string]$Dest
    )
    # Same junk tools/deploy.ps1 drops with robocopy /XF and /XD.
    $skipFiles = @("Thumbs.db", ".DS_Store", "desktop.ini", "ehthumbs.db")
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($_.Name -in @("__pycache__", ".git")) { return }
            Copy-AddonSource -Src $_.FullName -Dest (Join-Path $Dest $_.Name)
            return
        }
        if ($_.Extension -in @(".bak", ".tmp", ".log")) { return }
        if ($skipFiles -contains $_.Name) { return }
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name)
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$modPath = Join-Path $root "CustomUI.mod"
$sourcePath = Join-Path $root "Source"
$luaPath = Join-Path $sourcePath "CustomUI.lua"

if (-not (Test-Path -LiteralPath $modPath)) {
    throw "Missing CustomUI.mod at $modPath"
}
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Missing Source\ at $sourcePath"
}

$modText = Get-Content -LiteralPath $modPath -Raw
# UiMod version= only — not VersionSettings gameVersion / windowsVersion / savedVariablesVersion.
if ($modText -notmatch '<UiMod\b[^>]*\bversion="([^"]+)"') {
    throw "Could not read UiMod version= from CustomUI.mod"
}
$version = $Matches[1]
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "CustomUI.mod UiMod version '$version' is not MAJOR.MINOR.PATCH"
}

if (-not (Test-Path -LiteralPath $luaPath)) {
    throw "Missing Source\CustomUI.lua"
}
$luaText = Get-Content -LiteralPath $luaPath -Raw
if ($luaText -notmatch 'CustomUI\.Version\s*=\s*"([^"]+)"') {
    throw "Could not read CustomUI.Version from Source\CustomUI.lua"
}
$luaVersion = $Matches[1]
if ($luaVersion -ne $version) {
    throw "Version mismatch: CustomUI.mod UiMod version=$version but CustomUI.Version=`"$luaVersion`". Bump both together."
}

$outAbs = Join-Path $root $OutDir
$stageRoot = Join-Path $outAbs "_stage"
$stageAddon = Join-Path $stageRoot "CustomUI"
$zipPath = Join-Path $outAbs ("CustomUI-{0}.zip" -f $version)

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageAddon -Force | Out-Null

Copy-Item -LiteralPath $modPath -Destination (Join-Path $stageAddon "CustomUI.mod")
Copy-AddonSource -Src $sourcePath -Dest (Join-Path $stageAddon "Source")

New-Item -ItemType Directory -Path $outAbs -Force | Out-Null
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

# Zip the CustomUI folder so extract lands as Interface/AddOns/CustomUI/
Compress-Archive -Path $stageAddon -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Host ("Packed {0}" -f $zipPath)

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value ("version={0}" -f $version)
    Add-Content -Path $env:GITHUB_OUTPUT -Value ("zip_path={0}" -f $zipPath)
    Add-Content -Path $env:GITHUB_OUTPUT -Value ("zip_name=CustomUI-{0}.zip" -f $version)
}
