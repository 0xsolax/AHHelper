# Install the verified 0.1.1 test package. Does not alter other addons or saved variables.
# Updated by Solazhu, 2026-11-16.
[CmdletBinding()]
param(
    [string]$AddOnsDirectory = 'F:\GAME\World of Warcraft\_forever_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packagePath = Join-Path $projectRoot 'dist\SparkleBoost-0.1.1-test.zip'
$expectedHash = 'F6389986BD4C3A4D9AC97FFCF9851C9822253310164C43581C46F75E91E15B6E'
if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Package verification failed. The installer only accepts the tested 0.1.1 package.'
}
if (-not (Test-Path -LiteralPath $AddOnsDirectory -PathType Container)) {
    throw "Game AddOns directory was not found: $AddOnsDirectory"
}
$gameAddons = (Resolve-Path -LiteralPath $AddOnsDirectory).ProviderPath
$addonTarget = [IO.Path]::GetFullPath((Join-Path $gameAddons 'SparkleBoost'))
if (-not $addonTarget.StartsWith($gameAddons + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation target is outside AddOns.'
}

# Refuse existing links so files cannot be redirected outside this addon.
if (Test-Path -LiteralPath $addonTarget) {
    $targetInfo = Get-Item -LiteralPath $addonTarget
    if (-not $targetInfo.PSIsContainer -or ($targetInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Existing SparkleBoost path is not a normal directory.'
    }
    $linkedItems = @(Get-ChildItem -LiteralPath $addonTarget -Force -Recurse |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    if ($linkedItems.Count) { throw 'Existing addon contains links; no files have been overwritten.' }
}

$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$stage = Join-Path $projectRoot ('.tools\sparkleboost-install\' + $runId)
Expand-Archive -LiteralPath $packagePath -DestinationPath $stage
$addonSource = Join-Path $stage 'SparkleBoost'
$files = @(Get-ChildItem -LiteralPath $addonSource -File -Recurse)
if ($files.Count -ne 11 -or -not (Test-Path -LiteralPath (Join-Path $addonSource 'SparkleBoost.toc'))) {
    throw 'Package contents are incomplete.'
}

if (Test-Path -LiteralPath $addonTarget) {
    $backupRoot = Join-Path $projectRoot ('backups\SparkleBoost-' + $runId)
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
    Copy-Item -LiteralPath $addonTarget -Destination $backupRoot -Recurse
    $backupAddon = Join-Path $backupRoot 'SparkleBoost'
    foreach ($existing in (Get-ChildItem -LiteralPath $addonTarget -File -Recurse -Force)) {
        $relative = $existing.FullName.Substring($addonTarget.Length + 1)
        $copy = Join-Path $backupAddon $relative
        if ((Get-FileHash -LiteralPath $existing.FullName -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash) {
            throw "Backup verification failed: $relative"
        }
    }
    Write-Output "Previous version backed up: $backupRoot"
}

New-Item -ItemType Directory -Path $addonTarget -Force | Out-Null
foreach ($file in $files) {
    $relative = $file.FullName.Substring($addonSource.Length + 1)
    $destination = [IO.Path]::GetFullPath((Join-Path $addonTarget $relative))
    if (-not $destination.StartsWith($addonTarget + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package file escaped the addon directory.'
    }
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
        throw "Installed file failed verification: $relative"
    }
}
Write-Output "Installed and verified 11 files: $addonTarget"
Write-Output 'Existing installation: /reload. First installation: restart the game and enable SparkleBoost.'
Write-Output 'Click the minimap button or type /sg to open settings; left-drag the button to move it.'
Write-Output 'Enable the nearby enhancement checkbox to test the larger light effects.'
