#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$settings = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'settings.json') | ConvertFrom-Json -AsHashtable
$destination = Join-Path $env:LOCALAPPDATA 'windows-dotfiles/desktop'

foreach ($file in $settings.cursor.roles.Values) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "cursors/$file"))) { throw "Missing cursor: $file" }
}
foreach ($file in $settings.driveIcons.Values) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "icons/$file"))) { throw "Missing drive icon: $file" }
}
if ($WhatIfPreference) {
    Write-Host "Would apply desktop auto-arrange/grid settings and install cursor/drive icons into $destination."
    return
}

foreach ($folder in @('cursors', 'icons')) {
    $target = Join-Path $destination $folder
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -File |
        Copy-Item -Destination $target -Force
}

$shell = New-Object -ComObject Shell.Application
$desktopHandle = 0
$desktop = $shell.Windows().FindWindowSW(0, 0, 8, [ref]$desktopHandle, 1)
if (-not $desktop) { throw 'The interactive Windows desktop is unavailable. Run this installer in your desktop session.' }
$view = $desktop.Document
$mask = 0x1 -bor 0x4 # FWF_AUTOARRANGE and FWF_SNAPTOGRID
$desired = 0
if ($settings.autoArrange) { $desired = $desired -bor 0x1 }
if ($settings.snapToGrid) { $desired = $desired -bor 0x4 }
$flags = ([uint32]$view.FolderFlags -band ([uint32]::MaxValue -bxor $mask)) -bor $desired
if ($view.FolderFlags -ne $flags) { $view.FolderFlags = $flags }
if (($view.FolderFlags -band $mask) -ne $desired) { throw 'Explorer did not accept the desktop arrangement settings.' }
$desktopKey = 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
New-Item -Path $desktopKey -Force | Out-Null
New-ItemProperty -LiteralPath $desktopKey -Name FFlags -Value $flags -PropertyType DWord -Force | Out-Null

$cursorKey = 'HKCU:\Control Panel\Cursors'
New-Item -Path $cursorKey -Force | Out-Null
foreach ($role in $settings.cursor.roles.Keys) {
    $file = Join-Path $destination "cursors/$($settings.cursor.roles[$role])"
    New-ItemProperty -LiteralPath $cursorKey -Name $role -Value $file -PropertyType String -Force | Out-Null
}
Set-Item -LiteralPath $cursorKey -Value $settings.cursor.name
New-ItemProperty -LiteralPath $cursorKey -Name CursorBaseSize -Value $settings.cursor.baseSize -PropertyType DWord -Force | Out-Null

$systemLetter = $env:SystemDrive.Substring(0, 1)
$fixedDrives = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [IO.DriveType]::Fixed }
foreach ($drive in $fixedDrives) {
    $letter = $drive.Name.Substring(0, 1)
    $file = if ($letter -eq $systemLetter) { $settings.driveIcons.system } else { $settings.driveIcons.fixed }
    $icon = Join-Path $destination "icons/$file"
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\$letter\DefaultIcon"
    New-Item -Path $key -Force | Out-Null
    Set-Item -LiteralPath $key -Value ('"{0}",0' -f $icon)
}

if (-not ('WindowsDotfiles.DesktopNative' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'DesktopNative.cs')
}
if (-not [WindowsDotfiles.DesktopNative]::ReloadCursors()) { throw 'Windows could not reload the saved cursor scheme.' }
[WindowsDotfiles.DesktopNative]::RefreshIcons()
Write-Host 'Desktop: auto-arranged icons, saved cursor, and Fluent drive icons applied.'
