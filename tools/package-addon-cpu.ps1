# Package only the standalone addon. Operator: Solazhu.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $projectRoot 'AddonCPU'
$toc = Get-Content -LiteralPath (Join-Path $addonRoot 'AddonCPU.toc') -Encoding UTF8
$versionLine = @($toc | Where-Object { $_ -match '^## Version: ' })
if ($versionLine.Count -ne 1) { throw 'Expected one addon version.' }
$version = ($versionLine[0] -replace '^## Version: ', '').Trim()
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$') { throw 'Invalid addon version.' }
$files = @('AddonCPU.toc', 'Core.lua', 'README.md')
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $addonRoot $name) -PathType Leaf)) {
        throw "Missing addon file: $name"
    }
}
$entries = @($toc | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($entries.Count -ne 1 -or $entries[0] -ne 'Core.lua') { throw 'Unexpected TOC entry list.' }
$actual = @(Get-ChildItem -LiteralPath $addonRoot -Force)
if ($actual.Count -ne $files.Count -or @($actual | Where-Object { $_.PSIsContainer -or $_.Name -notin $files }).Count) {
    throw 'Unexpected files in addon directory.'
}
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$zipName = "AddonCPU-$version.zip"
$zipPath = Join-Path $distRoot $zipName
Compress-Archive -LiteralPath $addonRoot -DestinationPath $zipPath -Force
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Set-Content -LiteralPath ($zipPath + '.sha256') -Value ($hash.Hash + '  ' + $zipName) -Encoding ascii
Write-Output $zipPath
Write-Output $hash.Hash
