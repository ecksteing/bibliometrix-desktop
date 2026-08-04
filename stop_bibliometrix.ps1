# stop_bibliometrix.ps1
# Stops Bibliometrix Desktop launcher/R processes for THIS install only.
# Used before uninstall/upgrade so files are not locked.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\stop_bibliometrix.ps1

$ErrorActionPreference = "SilentlyContinue"
$AppDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$AppDir = [System.IO.Path]::GetFullPath($AppDir)

Get-Process -Name "run_bibliometrix" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($AppDir, [System.StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force

$names = @("Rscript.exe", "Rgui.exe", "Rterm.exe", "R.exe")
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -in $names -and
        $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($AppDir, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Milliseconds 800
