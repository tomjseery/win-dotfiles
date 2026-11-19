#Requires -Version 7.2
# Isolated installer recovery checks: no live uxtheme or HKCU writes.
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('caption-recovery-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $sandbox
    Add-Type @'
namespace WindowsDotfiles {
    public static class ThemeNativeV1 {
        public static string Path;
        public static int ApplyCalls;
        public static string ThemeReference;
        public static string[] Current() { return new[] { Path, "NormalColor", "NormalSize" }; }
        public static void Apply(string path, string color, string size) { Path = path; ApplyCalls++; }
    }
}
'@
    [WindowsDotfiles.ThemeNativeV1]::ThemeReference = 'unreconciled.theme'
    function Set-ItemProperty {
        param($LiteralPath, $Name, $Value)
        if ($LiteralPath -ne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -or $Name -ne 'CurrentTheme') {
            throw 'Unexpected registry write.'
        }
        [WindowsDotfiles.ThemeNativeV1]::ThemeReference = $Value
    }
    $stateRoot = Join-Path $sandbox 'windows-dotfiles/window-controls'
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $original = Join-Path $sandbox 'original.msstyles'
    $variant = Join-Path $sandbox 'variant.msstyles'
    $savedTheme = Join-Path $sandbox 'variant.theme'
    'test style' | Set-Content -LiteralPath $original
    Copy-Item -LiteralPath $original -Destination $variant
    'test theme' | Set-Content -LiteralPath $savedTheme
    $hash = (Get-FileHash -LiteralPath $original).Hash
    $settings = Get-Content (Join-Path $repository 'themes/klassy/settings.json') -Raw | ConvertFrom-Json
    @{
        original = @{ path = $original; sha256 = $hash; color = 'NormalColor'; size = 'NormalSize'; theme_file = 'original.theme' }
        applied = @{ path = $variant; sha256 = $hash; atlas_sha256 = $settings.output_atlas_sha256; theme_file = $savedTheme }
    } | ConvertTo-Json | Set-Content (Join-Path $stateRoot 'state.json')
    $installer = Join-Path $repository 'window-controls/install.ps1'

    # Restore interrupted after native activation but before CurrentTheme write.
    [WindowsDotfiles.ThemeNativeV1]::Path = $original
    & $installer -Restore -WhatIf
    if ([WindowsDotfiles.ThemeNativeV1]::ThemeReference -ne 'unreconciled.theme') { throw 'Restore WhatIf wrote registry.' }
    & $installer -Restore
    if ([WindowsDotfiles.ThemeNativeV1]::ThemeReference -ne 'original.theme' -or [WindowsDotfiles.ThemeNativeV1]::ApplyCalls -ne 0) {
        throw 'Interrupted restore did not reconcile the saved reference.'
    }

    # Installation interrupted at the same boundary; preparation must not repair persistence.
    [WindowsDotfiles.ThemeNativeV1]::ThemeReference = 'unreconciled.theme'
    [WindowsDotfiles.ThemeNativeV1]::Path = $variant
    & $installer -PrepareOnly
    & $installer -WhatIf
    if ([WindowsDotfiles.ThemeNativeV1]::ThemeReference -ne 'unreconciled.theme') { throw 'PrepareOnly/WhatIf wrote registry.' }
    & $installer
    if ([WindowsDotfiles.ThemeNativeV1]::ThemeReference -ne $savedTheme -or [WindowsDotfiles.ThemeNativeV1]::ApplyCalls -ne 0) {
        throw 'Interrupted install did not reconcile the saved reference.'
    }
    Write-Output 'Window-control interruption recovery checks passed.'
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    # Only the exact directory created above is removed.
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notlike 'caption-recovery-*') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
