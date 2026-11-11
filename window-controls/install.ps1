#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param([switch]$PrepareOnly, [switch]$Restore)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Window controls require Windows.' }
if ($PrepareOnly -and $Restore) { throw 'Choose PrepareOnly or Restore.' }
$themeRoot = Join-Path $PSScriptRoot '../themes/klassy'
$settings = Get-Content -LiteralPath (Join-Path $themeRoot 'settings.json') -Raw | ConvertFrom-Json
$installRoot = Join-Path $env:LOCALAPPDATA 'windows-dotfiles/window-controls'
$statePath = Join-Path $installRoot 'state.json'
$themesKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
if (-not ('WindowsDotfiles.ThemeNativeV1' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'ThemeNative.cs')
}
$current = [WindowsDotfiles.ThemeNativeV1]::Current()
$state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }

function Assert-Hash([string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Fingerprint mismatch: $Path"
    }
}

function Set-ThemeFilePath([string]$Path) {
    if ($Path) { Set-ItemProperty -LiteralPath $themesKey -Name CurrentTheme -Value $Path }
    else { Remove-ItemProperty -LiteralPath $themesKey -Name CurrentTheme -ErrorAction SilentlyContinue }
}

if ($Restore) {
    if ($null -eq $state) { throw 'No saved original theme exists.' }
    if ($current[0] -eq $state.original.path) { Write-Output 'Original style is already active.'; return }
    if ($current[0] -ne $state.applied.path) { throw 'Another visual style is active; refusing to replace it.' }
    Assert-Hash $state.original.path $state.original.sha256
    if ($PSCmdlet.ShouldProcess($state.original.path, 'Restore original visual style')) {
        [WindowsDotfiles.ThemeNativeV1]::Apply($state.original.path, $state.original.color, $state.original.size)
        Set-ThemeFilePath $state.original.theme_file
        Write-Output 'Restored the original visual style.'
    }
    return
}

if ($null -ne $state -and $current[0] -eq $state.applied.path) {
    Assert-Hash $state.applied.path $state.applied.sha256
    if ($state.applied.atlas_sha256 -ne $settings.output_atlas_sha256) {
        throw 'Restore the previous variant before installing changed glyph artwork.'
    }
    Write-Output 'Klassy window controls are already active.'
    return
}
if ($null -ne $state -and $current[0] -ne $state.original.path) {
    throw 'Another visual style is active; refusing to replace it.'
}
Assert-Hash $current[0] $settings.base_sha256
Assert-Hash (Join-Path $themeRoot 'caption-atlas.png') $settings.output_atlas_sha256
if (-not $PSCmdlet.ShouldProcess($current[0], 'Prepare caption-only copy and optionally activate it')) { return }

$editorRoot = Join-Path $env:LOCALAPPDATA "windows-dotfiles/tools/msstyleEditor/$($settings.editor_version)"
$editor = Join-Path $editorRoot 'bin/msstyleEditor.exe'
if (-not (Test-Path -LiteralPath $editor)) {
    New-Item -ItemType Directory -Path $editorRoot -Force | Out-Null
    $archive = Join-Path $editorRoot 'msstyleEditor.zip'
    Invoke-WebRequest -Uri $settings.editor_url -OutFile $archive
    Assert-Hash $archive $settings.editor_sha256
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $editorRoot 'bin') -Force
}
Assert-Hash $editor $settings.editor_exe_sha256
$variantRoot = Join-Path $installRoot ('variants/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $variantRoot -Force | Out-Null
$variant = Join-Path $variantRoot 'Modern Office Pro - Klassy.msstyles'
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File (Join-Path $PSScriptRoot 'prepare-style.ps1') `
    -BaseStyle $current[0] -OutputStyle $variant -Editor $editor -ThemeRoot ([IO.Path]::GetFullPath($themeRoot))
if ($LASTEXITCODE -ne 0) { throw 'Preparing the visual style failed. Nothing was applied.' }
$validation = Get-Content -LiteralPath ($variant + '.validation.json') -Raw | ConvertFrom-Json
if ($validation.base_sha256 -ne $settings.base_sha256 -or -not $validation.properties_preserved -or -not $validation.strings_preserved -or
    $validation.image_resources_checked -lt 1) { throw 'Invalid prepared-style validation report.' }
Assert-Hash $variant $validation.output_sha256
if ($PrepareOnly) { Write-Output "Prepared only: $variant"; return }

$originalTheme = (Get-ItemProperty -LiteralPath $themesKey -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
if (-not $originalTheme -or -not (Test-Path -LiteralPath $originalTheme)) {
    throw 'An existing saved Windows theme is required to preserve its other settings.'
}
$themeText = [IO.File]::ReadAllText($originalTheme)
$visualStyles = [regex]::Match($themeText, '(?ims)^\[VisualStyles\]\s*\r?\n(?<body>.*?)(?=^\[|\z)')
if (-not $visualStyles.Success -or -not [regex]::IsMatch($visualStyles.Groups['body'].Value, '(?im)^Path=')) {
    throw 'The current theme has no VisualStyles Path.'
}
$patchedSection = [regex]::Replace($visualStyles.Value, '(?im)^Path=[^\r\n]*', [Text.RegularExpressions.MatchEvaluator]{ param($match) 'Path=' + $variant })
$themeText = $themeText.Remove($visualStyles.Index, $visualStyles.Length).Insert($visualStyles.Index, $patchedSection)
$themeText = [regex]::Replace($themeText, '(?im)^DisplayName=[^\r\n]*', 'DisplayName=Modern Office Pro - Klassy controls')
$themeFile = Join-Path $variantRoot 'Modern Office Pro - Klassy.theme'
[IO.File]::WriteAllText($themeFile, $themeText, [Text.UnicodeEncoding]::new($false, $true))
if ($null -eq $state) {
    Copy-Item -LiteralPath $originalTheme -Destination (Join-Path $installRoot 'original.theme')
    $original = [ordered]@{
        path = $current[0]; color = $current[1]; size = $current[2]
        sha256 = (Get-FileHash -LiteralPath $current[0]).Hash.ToLowerInvariant()
        theme_file = $originalTheme
    }
} else { $original = $state.original }
$newState = [ordered]@{
    original = $original
    applied = [ordered]@{ path = $variant; sha256 = $validation.output_sha256; atlas_sha256 = $settings.output_atlas_sha256; theme_file = $themeFile }
}
# Persist rollback before the native call, including if the process is interrupted.
$newState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8
try {
    [WindowsDotfiles.ThemeNativeV1]::Apply($variant, $current[1], $current[2])
    Set-ThemeFilePath $themeFile
} catch {
    [WindowsDotfiles.ThemeNativeV1]::Apply($current[0], $current[1], $current[2])
    Set-ThemeFilePath $originalTheme
    throw
}
Write-Output "Activated Klassy window controls. Restore with: & '$PSScriptRoot/install.ps1' -Restore"
