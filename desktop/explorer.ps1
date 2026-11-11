#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$assets = Join-Path $PSScriptRoot '../themes/modern-office-pro/icons/folders'
$assetFingerprint = ((Get-ChildItem -LiteralPath $assets -Filter '*.ico' -File | Sort-Object Name | Get-FileHash -Algorithm SHA256).Hash -join '')
$assetVersion = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($assetFingerprint))).Substring(0, 16).ToLowerInvariant()
$destination = Join-Path $env:LOCALAPPDATA "windows-dotfiles/desktop/folders/$assetVersion"
$classes = [ordered]@{
    desktop = '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}'
    downloads = @('{088e3905-0323-4b02-9826-5d99428e115f}', '{374DE290-123F-4565-9164-39C4925E467B}')
    documents = @('{d3162b92-9365-467a-956b-92703aca08af}', '{A8CDFF1C-4878-43be-B5FD-F8091C1C60D0}', '{450D8FBA-AD25-11D0-98A8-0800361B1103}')
    pictures = @('{24ad3ad4-a569-4530-98e1-ab02f9417aa8}', '{3ADD1653-EB32-4cb0-BBD7-DFA0ABB5ACCA}')
    music = @('{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}', '{1CF1260C-4DD0-4ebb-811F-33C572699FDE}')
    videos = @('{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}', '{A0953C92-50DC-43bf-BE83-3742FED03C9C}')
}
$rolePaths = [ordered]@{
    desktop = [Environment]::GetFolderPath('DesktopDirectory')
    downloads = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
    documents = [Environment]::GetFolderPath('MyDocuments')
    pictures = [Environment]::GetFolderPath('MyPictures')
    music = [Environment]::GetFolderPath('MyMusic')
    videos = [Environment]::GetFolderPath('MyVideos')
}
$oneDriveClass = '{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
if (Test-Path -LiteralPath "Registry::HKEY_CLASSES_ROOT\CLSID\$oneDriveClass") {
    $classes.onedrive = $oneDriveClass
    $rolePaths.onedrive = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal' -ErrorAction SilentlyContinue).UserFolder
    if (-not $rolePaths.onedrive) { $rolePaths.onedrive = if ($env:OneDrive) { $env:OneDrive } else { Join-Path $env:USERPROFILE 'OneDrive' } }
}
if (-not $rolePaths.downloads) { $rolePaths.downloads = Join-Path $env:USERPROFILE 'Downloads' }
foreach ($role in @($rolePaths.Keys)) { $rolePaths[$role] = [Environment]::ExpandEnvironmentVariables($rolePaths[$role]) }
foreach ($role in @('folder') + @($classes.Keys)) {
    if (-not (Test-Path -LiteralPath (Join-Path $assets "$role.ico"))) { throw "Missing Explorer icon: $role" }
}
if (-not $PSCmdlet.ShouldProcess('Current-user Explorer icons', 'Install small Windows 11 frames, retain large blue frames and disable folder-content previews')) { return }

$folderView = 'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'
$entries = @(
    foreach ($role in $classes.Keys) {
        foreach ($classId in $classes[$role]) {
            @{ key = "Software\Classes\CLSID\$classId\DefaultIcon"; name = ''; value = (Join-Path $destination "$role.ico") + ',0' }
        }
    }
    @{ key = $folderView; name = 'Logo'; value = 'imageres.dll,-3' }
)
$backupDirectory = Join-Path $env:LOCALAPPDATA 'windows-dotfiles/backups'
New-Item -ItemType Directory -Path $backupDirectory, $destination -Force | Out-Null
$snapshotPath = Join-Path $backupDirectory 'explorer-classes-before.json'
$snapshot = @()
if (Test-Path -LiteralPath $snapshotPath) { $snapshot = @(Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json) }
$savedKeys = @($snapshot | ForEach-Object { $_.key + '|' + $_.name })
$missingEntries = @($entries | Where-Object { ($_.key + '|' + $_.name) -notin $savedKeys })
if ($missingEntries.Count -gt 0) {
    $snapshot = @($snapshot) + @(foreach ($entry in $missingEntries) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($entry.key)
        try {
            $exists = $key -and ($key.GetValueNames() -contains $entry.name)
            [ordered]@{
                key = $entry.key; name = $entry.name; exists = [bool]$exists
                value = if ($exists) { $key.GetValue($entry.name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
                kind = if ($exists) { $key.GetValueKind($entry.name).ToString() } else { $null }
            }
        } finally { if ($key) { $key.Dispose() } }
    })
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $snapshotPath -Encoding utf8NoBOM
}
Get-ChildItem -LiteralPath $assets -Filter '*.ico' -File | Copy-Item -Destination $destination -Force
foreach ($entry in $entries) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($entry.key)
    try { $key.SetValue($entry.name, $entry.value, [Microsoft.Win32.RegistryValueKind]::String) } finally { $key.Dispose() }
}
if ($rolePaths.onedrive) {
    & (Join-Path $PSScriptRoot 'onedrive.ps1') -FolderPath $rolePaths.onedrive -IconPath (Join-Path $destination 'onedrive.ico')
}

if (-not ('WindowsDotfiles.DesktopNativeV2' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'DesktopNative.cs') }
[WindowsDotfiles.DesktopNativeV2]::RefreshIcons()
foreach ($role in $classes.Keys) {
    $folder = $rolePaths[$role]
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
    [WindowsDotfiles.DesktopNativeV2]::RefreshItem($folder)
    $expected = Join-Path $destination "$role.ico"
    $actual = [WindowsDotfiles.DesktopNativeV2]::GetIconLocation($folder)
    if ($actual -ine $expected) { throw "Explorer did not resolve the $role icon: $actual" }
}
$shell = New-Object -ComObject Shell.Application
$quickAccess = $shell.Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
if ($quickAccess) {
    foreach ($item in @($quickAccess.Items())) {
        if ($item.IsFolder -and (Test-Path -LiteralPath $item.Path -PathType Container)) {
            [WindowsDotfiles.DesktopNativeV2]::RefreshItem($item.Path)
        }
    }
}
foreach ($window in @($shell.Windows())) {
    try {
        if ($window.Document.Folder.Self.Path -eq '::{679F85CB-0220-4080-B29B-5540CC05AAB6}') { $window.Refresh() }
    } catch { Write-Verbose 'An Explorer window closed during refresh.' }
}
Write-Host 'Explorer: folder icon settings installed and Quick access refresh requested.'
