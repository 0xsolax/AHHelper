# Package only the installable addon. Operator: Solazhu.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $projectRoot 'AuctionPilot'
$tocPath = Join-Path $addonRoot 'AuctionPilot.toc'
$toc = Get-Content -LiteralPath $tocPath -Encoding UTF8
foreach ($entry in $toc) {
    $entry = $entry.Trim()
    if ($entry -and -not $entry.StartsWith('#')) {
        $resolved = [IO.Path]::GetFullPath((Join-Path $addonRoot $entry))
        if (-not $resolved.StartsWith($addonRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "TOC path outside addon: $entry"
        }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing TOC entry: $entry" }
    }
}
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$zipPath = Join-Path $distRoot 'AuctionPilot-0.7.0-test.zip'
Compress-Archive -LiteralPath $addonRoot -DestinationPath $zipPath -Force
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Set-Content -LiteralPath ($zipPath + '.sha256') -Value ($hash.Hash + '  AuctionPilot-0.7.0-test.zip') -Encoding ascii
Write-Output $zipPath
Write-Output $hash.Hash
