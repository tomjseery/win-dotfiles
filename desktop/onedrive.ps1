#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$FolderPath,
    [Parameter(Mandatory)][string]$IconPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) { return }
if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) { throw 'OneDrive icon is missing.' }
if (-not $PSCmdlet.ShouldProcess($FolderPath, 'Set the OneDrive folder icon while retaining other desktop.ini settings')) { return }
$ini = Join-Path $FolderPath 'desktop.ini'
$exists = Test-Path -LiteralPath $ini -PathType Leaf
$attributes = if ($exists) { (Get-Item -LiteralPath $ini -Force).Attributes } else { [IO.FileAttributes]::Normal }
$directoryAttributes = (Get-Item -LiteralPath $FolderPath -Force).Attributes
$backupDirectory = Join-Path $env:LOCALAPPDATA 'windows-dotfiles/backups'
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$pathHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($FolderPath).ToLowerInvariant()))).Substring(0, 16)
$backup = Join-Path $backupDirectory "onedrive-folder-$pathHash.json"
if (-not (Test-Path -LiteralPath $backup)) {
    [ordered]@{
        path = $FolderPath; directoryAttributes = [int]$directoryAttributes
        iniAttributes = [int]$attributes
        ini = if ($exists) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($ini)) } else { $null }
    } | ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding utf8NoBOM
}
$text = if ($exists) { [IO.File]::ReadAllText($ini) } else { '' }
$value = "$IconPath,0"
$section = [regex]::Match($text, '(?ims)^\[\.ShellClassInfo\][^\S\r\n]*\r?\n(?<body>.*?)(?=^\[|\z)')
if ($section.Success) {
    $body = $section.Groups['body'].Value
    if ([regex]::IsMatch($body, '(?im)^IconResource[^\S\r\n]*=')) {
        $body = [regex]::Replace($body, '(?im)^IconResource[^\S\r\n]*=[^\r\n]*', [Text.RegularExpressions.MatchEvaluator]{ param($match) "IconResource=$value" })
    } else { $body = "IconResource=$value`r`n" + $body }
    $updated = $text.Substring(0, $section.Index) + "[.ShellClassInfo]`r`n" + $body + $text.Substring($section.Index + $section.Length)
} else { $updated = $text.TrimEnd() + "`r`n[.ShellClassInfo]`r`nIconResource=$value`r`n" }
if ($updated -cne $text) {
    if ($exists -and ($attributes -band [IO.FileAttributes]::ReadOnly)) { [IO.File]::SetAttributes($ini, $attributes -band (-bnot [IO.FileAttributes]::ReadOnly)) }
    $stream = $null
    try {
        $stream = [IO.File]::Open($ini, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $bytes = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes($updated)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.SetLength($bytes.Length)
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($exists -and ($attributes -band [IO.FileAttributes]::ReadOnly)) { [IO.File]::SetAttributes($ini, $attributes) }
    }
    if (-not $exists) { [IO.File]::SetAttributes($ini, [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System) }
}
if (-not ($directoryAttributes -band [IO.FileAttributes]::ReadOnly)) {
    [IO.File]::SetAttributes($FolderPath, $directoryAttributes -bor [IO.FileAttributes]::ReadOnly)
}
