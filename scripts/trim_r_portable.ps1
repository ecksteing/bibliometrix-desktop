# scripts/trim_r_portable.ps1
# Optional: remove bulky test/demo trees from the bundled R library to shrink
# the installer. Safe to re-run. Does not remove package code needed at runtime.
#
# Usage (from repo root, after bake_packages.R):
#   powershell -ExecutionPolicy Bypass -File .\scripts\trim_r_portable.ps1

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$LibraryCandidates = @(
    (Join-Path $Root "R-Portable\library"),                    # portable-r-windows
    (Join-Path $Root "R-Portable\App\R-Portable\library")      # PortableApps
)
$Library = $LibraryCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $Library) {
    throw "Library not found. Tried:`n  $($LibraryCandidates -join "`n  ")"
}
Write-Host "Trimming library: $Library"

$patterns = @(
    "*\tests",
    "*\test",
    "*\demo"
)

$removed = 0
foreach ($pattern in $patterns) {
    Get-ChildItem -Path $Library -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like (Join-Path $Library $pattern) } |
        ForEach-Object {
            Write-Host "Removing $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
            $removed++
        }
}

Write-Host "Removed $removed directories. Re-run bake_packages.R if you need a clean library again."
