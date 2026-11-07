# Builds dist/OribosExchange-<version>.zip from the OribosExchange folder.
# Usage: pwsh tools/package.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root 'OribosExchange'
$toc = Join-Path $addon 'OribosExchange.toc'

if (-not (Test-Path $toc)) {
    throw "Addon folder not found: $addon"
}

$version = [string]((Select-String -Path $toc -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value).Trim()
if (-not $version) {
    throw "Could not read ## Version from $toc"
}

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'stage'
$target = Join-Path $stage 'OribosExchange'
$zip = Join-Path $dist "OribosExchange-$version.zip"

New-Item -ItemType Directory -Force -Path $dist | Out-Null
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item (Join-Path $addon '*') $target -Recurse -Force
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $target -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

Write-Host "Wrote $zip"
