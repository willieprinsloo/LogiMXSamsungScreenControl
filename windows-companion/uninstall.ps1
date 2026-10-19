#Requires -Version 5.1
<#
.SYNOPSIS
Uninstall the G9 Windows Companion for the current user.

.DESCRIPTION
Stops the running tray app, removes the Startup shortcut, and deletes the
install directory. Logs under %LOCALAPPDATA%\G9WindowsCompanion are preserved
unless -PurgeLogs is passed.

.PARAMETER PurgeLogs
Also delete the log directory at %LOCALAPPDATA%\G9WindowsCompanion.
#>
[CmdletBinding()]
param(
    [switch]$PurgeLogs
)

$ErrorActionPreference = 'Continue'
$ShortcutName = 'G9 Windows Companion.lnk'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\G9WindowsCompanion'
$LogDir     = Join-Path $env:LOCALAPPDATA 'G9WindowsCompanion'
$Shortcut   = Join-Path ([Environment]::GetFolderPath('Startup')) $ShortcutName

Write-Host '==> Stopping running instance' -ForegroundColor Cyan
Get-Process -Name 'G9WindowsCompanion' -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 500
    if (-not $_.HasExited) { $_ | Stop-Process -Force }
}

if (Test-Path $Shortcut) {
    Write-Host "==> Removing Startup shortcut: $Shortcut" -ForegroundColor Cyan
    Remove-Item -Force $Shortcut
} else {
    Write-Host "==> No Startup shortcut at $Shortcut"
}

if (Test-Path $InstallDir) {
    Write-Host "==> Removing install directory: $InstallDir" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $InstallDir
} else {
    Write-Host "==> No install directory at $InstallDir"
}

if ($PurgeLogs -and (Test-Path $LogDir)) {
    Write-Host "==> Removing logs: $LogDir" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $LogDir
}

Write-Host ''
Write-Host '✅ Uninstalled.' -ForegroundColor Green
