# scripts/build_windows.ps1
# Build the onedir launcher (run_bibliometrix.exe + _internal) and Inno Setup installer.
#
# Prerequisites:
#   - Python with PyInstaller (pip install -r requirements-build.txt)
#   - Inno Setup 6+ (ISCC.exe)
#   - R-Portable present under .\R-Portable
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -SkipBake
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -SkipInstaller

[CmdletBinding()]
param(
    [switch]$SkipBake,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Find-ISCC {
    # Prefer newer Inno (7+) including per-user installs under LocalAppData.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe"),
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "ISCC.exe"
    )
    foreach ($path in $candidates) {
        if (Get-Command $path -ErrorAction SilentlyContinue) {
            return (Get-Command $path).Source
        }
        if (Test-Path $path) {
            return $path
        }
    }

    # Fallback: any "Inno Setup *" folder under common roots.
    $searchRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $searchRoots) {
        $hit = Get-ChildItem -Path $root -Directory -Filter "Inno Setup *" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "ISCC.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Find-Rscript {
    $candidates = @(
        (Join-Path $Root "R-Portable\bin\Rscript.exe"),                 # portable-r-windows
        (Join-Path $Root "R-Portable\bin\x64\Rscript.exe"),
        (Join-Path $Root "R-Portable\App\R-Portable\bin\Rscript.exe"),  # PortableApps
        (Join-Path $Root "R-Portable\App\R-Portable\bin\x64\Rscript.exe")
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$Rscript = Find-Rscript
if (-not $Rscript) {
    throw @"
Rscript not found under .\R-Portable.
Expected either:
  R-Portable\bin\Rscript.exe
  R-Portable\App\R-Portable\bin\Rscript.exe
"@
}
Write-Host "Using Rscript: $Rscript"

if (-not $SkipBake) {
    Write-Host "==> Baking bibliometrix binaries into R-Portable..."
    & $Rscript (Join-Path $Root "scripts\bake_packages.R")
    if ($LASTEXITCODE -ne 0) {
        throw "bake_packages.R failed with exit code $LASTEXITCODE"
    }
    Write-Host "==> Trimming non-runtime docs/tests/Tcl from R-Portable..."
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\trim_r_portable.ps1")
} else {
    Write-Host "==> Skipping package bake (-SkipBake)"
}

Write-Host "==> Installing/upgrading PyInstaller..."
python -m pip install --upgrade -r (Join-Path $Root "requirements-build.txt")

Write-Host "==> Building onedir launcher (run_bibliometrix.exe + _internal)..."
$distAppDir = Join-Path $Root "dist\run_bibliometrix"
$exeBuilt = Join-Path $distAppDir "run_bibliometrix.exe"
$exeRoot = Join-Path $Root "run_bibliometrix.exe"
$internalRoot = Join-Path $Root "_internal"

python -m PyInstaller `
    --noconfirm `
    --clean `
    --onedir `
    --noconsole `
    --name run_bibliometrix `
    --icon (Join-Path $Root "app_icon.ico") `
    (Join-Path $Root "run_bibliometrix.py")

if (-not (Test-Path $exeBuilt)) {
    throw "PyInstaller did not produce $exeBuilt"
}

# Stage next to R-Portable so local testing and Inno use the same layout.
if (Test-Path $internalRoot) {
    Remove-Item -LiteralPath $internalRoot -Recurse -Force
}
Copy-Item -Force $exeBuilt $exeRoot
Copy-Item -Recurse -Force (Join-Path $distAppDir "_internal") $internalRoot
Write-Host "Staged launcher at $exeRoot (with _internal\)"

if ($SkipInstaller) {
    Write-Host "==> Skipping Inno Setup (-SkipInstaller)"
    Write-Host "Done."
    exit 0
}

$iscc = Find-ISCC
if (-not $iscc) {
    throw "Inno Setup (ISCC.exe) not found. Install Inno Setup 6+ (including per-user installs) or pass -SkipInstaller."
}

Write-Host "==> Compiling installer with $iscc ..."
& $iscc (Join-Path $Root "installer_config.iss")
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$version = (Get-Content (Join-Path $Root "version.txt") -Raw).Trim()
$setup = Join-Path $Root "Output\BibliometrixSetup_$version.exe"
if (-not (Test-Path $setup)) {
    throw "Expected installer not found: $setup"
}

Write-Host ""
Write-Host "Build complete:"
Write-Host "  Launcher : $exeRoot"
Write-Host "  Installer: $setup"
Write-Host ""
Write-Host "Next: test on a clean Windows account, then upload the installer to GitHub Releases."
