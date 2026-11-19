#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$cacheRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Explorer'))
$backupParent = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'windows-dotfiles/backups'))
$backup = [IO.Path]::GetFullPath((Join-Path $backupParent ('thumbnail-cache-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))))
$targets = @('thumbcache_48.db', 'thumbcache_96.db') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $cacheRoot $_)) }
if (-not $backup.StartsWith($backupParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup path escaped its directory.' }
foreach ($target in $targets) {
    if ([IO.Path]::GetDirectoryName($target) -ine $cacheRoot) { throw 'Cache path escaped its directory.' }
}

$shell = New-Object -ComObject Shell.Application
$folders = @(foreach ($window in @($shell.Windows())) {
    if ($window.Busy) { throw 'An Explorer window is busy. Retry after its operation finishes.' }
    try { $window.Document.Folder.Self.Path } catch { throw 'Could not preserve an Explorer folder location.' }
})
$session = (Get-Process -Id $PID).SessionId
$explorerPath = Join-Path $env:WINDIR 'explorer.exe'
$explorers = @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session -and $_.Path -ieq $explorerPath })
if ($explorers.Count -eq 0) { throw 'No Explorer desktop is running in this session.' }
if (-not $PSCmdlet.ShouldProcess('Explorer and its 48/96-pixel thumbnail caches', 'Back up caches, reload Explorer and reopen folder locations')) { return }

New-Item -ItemType Directory -Path $backup -Force | Out-Null
[ordered]@{ folders = $folders; cacheFiles = $targets } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding utf8NoBOM
try {
    $explorers | Stop-Process -Force
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination (Join-Path $backup ([IO.Path]::GetFileName($target))) }
    }
} finally {
    Start-Process -FilePath $explorerPath -WindowStyle Hidden
    Start-Sleep -Milliseconds 1500
    $newShell = New-Object -ComObject Shell.Application
    foreach ($folder in $folders) {
        $location = if ($folder.StartsWith('::')) { 'shell:' + $folder } else { $folder }
        $newShell.Explore($location)
    }
}
Write-Host "Small thumbnail caches reset; backups: $backup"
