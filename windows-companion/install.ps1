#Requires -Version 5.1
<#
.SYNOPSIS
Install the G9 Windows Companion for the current user and start it on every login.

.DESCRIPTION
Publishes the project (if a build isn't already present), copies the output to
%LOCALAPPDATA%\Programs\G9WindowsCompanion, creates a shortcut in the user's
Startup folder, and launches the app. No admin rights required.

.PARAMETER PublishDir
Optional pre-built publish folder (contents of `bin\Release\...\publish`). If
omitted, the script runs `dotnet publish -c Release -r win-x64 --self-contained false`.

.EXAMPLE
.\install.ps1

.EXAMPLE
.\install.ps1 -PublishDir .\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish
#>
[CmdletBinding()]
param(
    [string]$PublishDir
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExeName = 'G9WindowsCompanion.exe'
$ShortcutName = 'G9 Windows Companion.lnk'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\G9WindowsCompanion'
$StartupDir = [Environment]::GetFolderPath('Startup')
$Shortcut = Join-Path $StartupDir $ShortcutName

# 1. Resolve or build the published output.
if (-not $PublishDir) {
    Push-Location $Here
    try {
        Write-Host '==> dotnet publish -c Release -r win-x64 --self-contained false' -ForegroundColor Cyan
        dotnet publish -c Release -r win-x64 --self-contained false -o publish | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit $LASTEXITCODE" }
        $PublishDir = Join-Path $Here 'publish'
    } finally {
        Pop-Location
    }
}
if (-not (Test-Path (Join-Path $PublishDir $ExeName))) {
    throw "Published $ExeName not found under $PublishDir"
}

# 2. Stop any running instance.
Write-Host '==> Stopping any running instance' -ForegroundColor Cyan
Get-Process -Name 'G9WindowsCompanion' -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 500
    if (-not $_.HasExited) { $_ | Stop-Process -Force }
}

# 3. Copy the published output into place.
if (Test-Path $InstallDir) {
    Write-Host "==> Removing previous install at $InstallDir" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $InstallDir
}
Write-Host "==> Copying to $InstallDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Recurse -Path (Join-Path $PublishDir '*') -Destination $InstallDir

# 4. Startup folder shortcut (auto-start on every user login — no admin needed).
Write-Host "==> Creating Startup shortcut: $Shortcut" -ForegroundColor Cyan
$targetExe = Join-Path $InstallDir $ExeName
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($Shortcut)
$lnk.TargetPath = $targetExe
$lnk.WorkingDirectory = $InstallDir
$lnk.Description = 'G9 Keyboard Switch — Windows companion (DDC return-to-Mac)'
$lnk.WindowStyle = 7   # minimized; the app lives in the tray anyway
$lnk.Save()

# 5. Launch now.
Write-Host '==> Launching the companion' -ForegroundColor Cyan
Start-Process -FilePath $targetExe -WorkingDirectory $InstallDir

Write-Host ''
Write-Host '✅ Installed.' -ForegroundColor Green
Write-Host "    Executable: $targetExe"
Write-Host "    Startup:    $Shortcut"
Write-Host "    Logs:       $env:LOCALAPPDATA\G9WindowsCompanion\companion.log"
Write-Host ''
Write-Host 'Look for the tray icon near the clock. It will come up automatically on every login.'
