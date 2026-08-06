# scripts/trim_r_portable.ps1
# Remove bulky non-runtime trees from the bundled R install to shrink the installer.
# Safe to re-run. Does not remove package code, libs/, data/, or extdata/.
#
# Usage (from repo root, after bake_packages.R):
#   powershell -ExecutionPolicy Bypass -File .\scripts\trim_r_portable.ps1
#
$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$RPortableCandidates = @(
    (Join-Path $Root "R-Portable"),                           # portable-r-windows
    (Join-Path $Root "R-Portable\App\R-Portable")             # PortableApps
)
$RPortable = $RPortableCandidates | Where-Object { Test-Path (Join-Path $_ "library") } | Select-Object -First 1

if (-not $RPortable) {
    throw "R-Portable library not found. Tried:`n  $($RPortableCandidates -join "`n  ")"
}

$Library = Join-Path $RPortable "library"
Write-Host "Trimming R-Portable: $RPortable"

$script:RemovedDirs = 0
$script:RemovedBytes = [int64]0

function Get-TreeSizeBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Remove-Tree([string]$Path, [string]$Reason) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $bytes = Get-TreeSizeBytes $Path
    Write-Host ("Removing [{0}] {1} ({2:N1} MB)" -f $Reason, $Path, ($bytes / 1MB))
    Remove-Item -LiteralPath $Path -Recurse -Force
    $script:RemovedDirs++
    $script:RemovedBytes += $bytes
}

function Remove-LibraryDirsNamed([string[]]$Names) {
    # Exact directory name match under library/ (e.g. pkg/help, pkg/doc).
    Get-ChildItem -LiteralPath $Library -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $Names -contains $_.Name } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { Remove-Tree $_.FullName "library/$($_.Name)" }
}

# Package trees never needed by Biblioshiny at runtime.
Remove-LibraryDirsNamed @("tests", "test", "demo", "help", "html", "doc")

# R top-level bulk that desktop launches do not use.
@(
    @{ Path = (Join-Path $RPortable "doc"); Reason = "R manuals/docs" },
    @{ Path = (Join-Path $RPortable "tests"); Reason = "R test suite" },
    @{ Path = (Join-Path $RPortable "Tcl"); Reason = "Tcl/Tk (unused)" },
    @{ Path = (Join-Path $RPortable "include"); Reason = "C headers" },
    @{ Path = (Join-Path $Library "tcltk"); Reason = "tcltk package" },
    @{ Path = (Join-Path $Library "translations"); Reason = "message catalogs" }
) | ForEach-Object { Remove-Tree $_.Path $_.Reason }

Write-Host ("Removed {0} trees (~{1:N1} MB). Re-run bake_packages.R for a clean library." -f `
    $script:RemovedDirs, ($script:RemovedBytes / 1MB))
