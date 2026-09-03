# scripts/enable_openblas.ps1
# Replaces R's reference BLAS/LAPACK DLLs with OpenBLAS for faster matrix math.
#
# R 4.5+ requires BLAS symbols such as dgemmtr_ that must be provided consistently
# across BOTH Rblas.dll and Rlapack.dll. Replacing only Rblas.dll causes startup
# failures ("entry point dgemmtr_ could not be located in Rlapack.dll").
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\enable_openblas.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\enable_openblas.ps1 -Restore
#
param(
    [switch]$Restore
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$RPortableCandidates = @(
    (Join-Path $Root "R-Portable\bin\x64"),
    (Join-Path $Root "R-Portable\App\R-Portable\bin\x64")
)

$RBinX64 = $RPortableCandidates | Where-Object { Test-Path (Join-Path $_ "Rblas.dll") } | Select-Object -First 1

if (-not $RBinX64) {
    throw "Could not locate R-Portable x64 bin directory with Rblas.dll."
}

$CurrentRblas = Join-Path $RBinX64 "Rblas.dll"
$CurrentRlapack = Join-Path $RBinX64 "Rlapack.dll"
$BackupRblas = Join-Path $RBinX64 "Rblas.dll.orig"
$BackupRlapack = Join-Path $RBinX64 "Rlapack.dll.orig"
$LibOpenBlas = Join-Path $RBinX64 "libopenblas.dll"

function Restore-ReferenceBlas {
    param([string]$BinDir)

    $restored = $false
    $rb = Join-Path $BinDir "Rblas.dll"
    $rl = Join-Path $BinDir "Rlapack.dll"
    $bb = Join-Path $BinDir "Rblas.dll.orig"
    $bl = Join-Path $BinDir "Rlapack.dll.orig"

    if (Test-Path $bb) {
        Copy-Item -Force $bb $rb
        Write-Host "Restored reference Rblas.dll from $bb"
        $restored = $true
    }
    if (Test-Path $bl) {
        Copy-Item -Force $bl $rl
        Write-Host "Restored reference Rlapack.dll from $bl"
        $restored = $true
    }
    $lob = Join-Path $BinDir "libopenblas.dll"
    if (Test-Path $lob) {
        Remove-Item -Force $lob
        Write-Host "Removed $lob"
    }
    if (-not $restored) {
        Write-Host "No .orig backups found under $BinDir; nothing to restore."
    }
}

if ($Restore) {
    Restore-ReferenceBlas -BinDir $RBinX64
    exit 0
}

Write-Host "Backing up reference Rblas.dll and Rlapack.dll..."
if (-not (Test-Path $BackupRblas)) {
    Copy-Item $CurrentRblas $BackupRblas
}
if (-not (Test-Path $BackupRlapack)) {
    Copy-Item $CurrentRlapack $BackupRlapack
}

$OpenBlasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.26/openblas-0.3.26-x64.zip"
$TempZip = Join-Path $env:TEMP "openblas.zip"
$TempExtract = Join-Path $env:TEMP "openblas_extracted"

try {
    Write-Host "Downloading OpenBLAS binary package from $OpenBlasUrl..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $OpenBlasUrl -OutFile $TempZip -UseBasicParsing

    if (Test-Path $TempExtract) { Remove-Item -LiteralPath $TempExtract -Recurse -Force }
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

    $Candidates = Get-ChildItem -Path $TempExtract -Filter "*openblas*.dll" -Recurse |
        Where-Object { $_.Length -gt 1MB } |
        Sort-Object Length -Descending

    if ($Candidates.Count -eq 0) {
        throw "Could not find OpenBLAS DLL inside downloaded archive."
    }

    $SourceDll = $Candidates[0].FullName
    Write-Host "Using OpenBLAS DLL: $SourceDll ($([math]::Round($Candidates[0].Length / 1MB, 1)) MB)"

    # R expects the same OpenBLAS build under both names (see david-cortes/R-openblas-in-windows).
    Copy-Item -Force $SourceDll $CurrentRblas
    Copy-Item -Force $SourceDll $CurrentRlapack
    Copy-Item -Force $SourceDll $LibOpenBlas

    Write-Host "Installed OpenBLAS as:"
    Write-Host "  $CurrentRblas"
    Write-Host "  $CurrentRlapack"
    Write-Host "  $LibOpenBlas"
    Write-Host "Originals backed up to .orig files in the same folder."
} catch {
    Write-Warning "Failed to download or configure OpenBLAS: $_"
    Write-Host "Restoring reference BLAS/LAPACK..."
    Restore-ReferenceBlas -BinDir $RBinX64
    exit 1
} finally {
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force -ErrorAction SilentlyContinue }
}
