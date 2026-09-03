# scripts/enable_openblas.ps1
# Replaces the default single-threaded R reference BLAS with an optimized OpenBLAS
# to accelerate matrix computations (co-citation, coupling, network analysis) by 5x-20x.
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
$BackupRblas = Join-Path $RBinX64 "Rblas.dll.orig"

if ($Restore) {
    if (Test-Path $BackupRblas) {
        Copy-Item -Force $BackupRblas $CurrentRblas
        Write-Host "Restored reference Rblas.dll from $BackupRblas"
    } else {
        Write-Host "No backup file found at $BackupRblas; nothing to restore."
    }
    exit 0
}

Write-Host "Backing up reference Rblas.dll..."
if (-not (Test-Path $BackupRblas)) {
    Copy-Item $CurrentRblas $BackupRblas
}

# Official / trusted precompiled OpenBLAS for R on Windows (e.g. from Rtools or OpenBLAS release)
# Download OpenBLAS DLL and place as Rblas.dll
$OpenBlasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.26/openblas-0.3.26-x64.zip"
$TempZip = Join-Path $env:TEMP "openblas.zip"
$TempExtract = Join-Path $env:TEMP "openblas_extracted"

try {
    Write-Host "Downloading OpenBLAS binary package from $OpenBlasUrl..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $OpenBlasUrl -OutFile $TempZip -UseBasicParsing

    if (Test-Path $TempExtract) { Remove-Item -LiteralPath $TempExtract -Recurse -Force }
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

    $Candidates = Get-ChildItem -Path $TempExtract -Filter "*openblas*.dll" -Recurse
    if ($Candidates.Count -eq 0) {
        $Candidates = Get-ChildItem -Path $TempExtract -Filter "libopenblas.dll" -Recurse
    }

    if ($Candidates.Count -gt 0) {
        $SourceDll = $Candidates[0].FullName
        Copy-Item -Force $SourceDll $CurrentRblas
        Write-Host "Successfully installed OpenBLAS as $CurrentRblas (Original backed up to $BackupRblas)"
    } else {
        Write-Warning "Could not find OpenBLAS DLL inside downloaded archive."
    }
} catch {
    Write-Warning "Failed to download or configure OpenBLAS: $_"
    Write-Host "Reference BLAS remains active."
} finally {
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force -ErrorAction SilentlyContinue }
}
