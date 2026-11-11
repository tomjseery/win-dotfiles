#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '../desktop/folder-icon.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $tempParent ('win-dotfiles-onedrive-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $fixture 'appdata'
    $folder = Join-Path $fixture 'OneDrive folder'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $icon = Join-Path $fixture 'blue $folder.ico'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../themes/modern-office-pro/sources/folder-blue.ico') -Destination $icon
    $ini = Join-Path $folder 'desktop.ini'
    $original = "[.ShellClassInfo]`r`nIconResource=old.dll,1`r`nLocalizedResourceName=@example.dll,-1`r`n[ViewState]`r`nMode=4`r`n"
    [IO.File]::WriteAllText($ini, $original, [Text.UTF8Encoding]::new($true))
    $originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ini))
    [IO.File]::SetAttributes($ini, [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReadOnly)
    & $installer -FolderPath $folder -IconPath $icon -WhatIf
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ini)) -cne $originalBytes -or (Test-Path $env:LOCALAPPDATA)) { throw 'Dry run changed files.' }
    & $installer -FolderPath $folder -IconPath $icon
    $updated = [IO.File]::ReadAllText($ini)
    if (-not $updated.Contains("IconResource=$icon,0") -or -not $updated.Contains('LocalizedResourceName=@example.dll,-1') -or -not $updated.Contains("[ViewState]`r`nMode=4")) { throw 'Icon update lost or corrupted another setting.' }
    if (-not ((Get-Item -LiteralPath $ini -Force).Attributes -band [IO.FileAttributes]::ReadOnly)) { throw 'Read-only attribute was lost.' }
    $saved = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'windows-dotfiles/backups') -Filter '*.json' | Get-Content -Raw | ConvertFrom-Json
    if ($saved.ini -cne $originalBytes) { throw 'Backup did not retain the original bytes.' }
    $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ini))
    & $installer -FolderPath $folder -IconPath $icon
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ini)) -cne $first) { throw 'Reinstallation changed desktop.ini.' }
    Write-Host 'Folder icon installer: dry run, settings/attributes preservation, backup and repeatability passed.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempParent.TrimEnd('\') + '\win-dotfiles-onedrive-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped its temporary directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
