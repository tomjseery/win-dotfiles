#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'terminal/install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-dotfiles-tests-' + [guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
foreach ($name in @('USERPROFILE', 'LOCALAPPDATA', 'STARSHIP_CONFIG', 'PATH')) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$savedProfile = $PROFILE.CurrentUserCurrentHost
$starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
$starshipPath = if ($starship) { Split-Path -Parent $starship.Source } else { Join-Path $env:USERPROFILE 'scoop/apps/starship/current' }
if (-not (Test-Path -LiteralPath (Join-Path $starshipPath 'starship.exe'))) { throw 'These tests require an existing Starship executable.' }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    foreach ($case in @('new', 'empty', 'existing', 'invalid')) {
        $fixture = Join-Path $testRoot $case
        $env:USERPROFILE = $fixture
        $env:LOCALAPPDATA = Join-Path $fixture 'AppData/Local'
        $env:STARSHIP_CONFIG = Join-Path $fixture 'starship.toml'
        $env:PATH = $starshipPath + [IO.Path]::PathSeparator + $savedEnvironment.PATH
        $PROFILE.CurrentUserCurrentHost = Join-Path $fixture 'profile.ps1'
        $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $settingsPath) -Force | Out-Null
        $profileSentinel = "function Keep-MyFunction { 'untouched' }`n"
        [IO.File]::WriteAllText($PROFILE.CurrentUserCurrentHost, $profileSentinel)
        [IO.File]::WriteAllText($env:STARSHIP_CONFIG, "# existing configuration`n")
        if ($case -eq 'empty') { [IO.File]::WriteAllText($settingsPath, " `r`n`t") }
        if ($case -eq 'existing') {
            $existing = @{
                defaultProfile = '{custom-profile}'
                profiles = @{ defaults = @{ font = @{ weight = 'light' } }; list = @(@{ name = 'Keep this shell'; guid = '{custom-profile}' }) }
                actions = @(@{ command = 'copy'; keys = 'ctrl+shift+c' })
                schemes = @(@{ name = 'Keep this scheme'; background = '#112233' })
                themes = @(@{ name = 'Keep this theme'; window = @{ applicationTheme = 'light' } })
            }
            $existing | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
        }
        if ($case -eq 'invalid') {
            [IO.File]::WriteAllText($settingsPath, '{invalid')
            $paths = @($settingsPath, $env:STARSHIP_CONFIG, $PROFILE.CurrentUserCurrentHost)
            $before = @($paths | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash }) -join ','
            $refused = $false
            try { & $installer } catch { $refused = $true }
            Assert-True $refused 'Malformed existing JSON was not refused.'
            $after = @($paths | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash }) -join ','
            Assert-True ($before -eq $after) 'Malformed JSON refusal changed existing files.'
            Write-Host 'PASS invalid JSON: existing files remain unchanged.'
            continue
        }
        & $installer
        $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json -AsHashtable
        foreach ($collection in @('schemes', 'themes')) {
            Assert-True (@($settings[$collection] | Where-Object { $null -eq $_ }).Count -eq 0) "$case contains a null $collection entry."
            Assert-True (@($settings[$collection] | Where-Object name -eq 'Graphite').Count -eq 1) "$case does not contain exactly one Graphite $collection entry."
        }
        $profileText = [IO.File]::ReadAllText($PROFILE.CurrentUserCurrentHost)
        Assert-True ($profileText.StartsWith($profileSentinel.TrimEnd())) "$case changed unrelated profile code."
        if ($case -eq 'existing') {
            Assert-True ($settings.defaultProfile -eq '{custom-profile}') 'Default shell changed.'
            Assert-True ($settings.profiles.list[0].name -eq 'Keep this shell') 'Existing shell profile changed.'
            Assert-True ($settings.actions[0].keys -eq 'ctrl+shift+c') 'Existing shortcut changed.'
            Assert-True ($settings.profiles.defaults.font.weight -eq 'light') 'Unrelated font weight changed.'
            Assert-True (@($settings.schemes | Where-Object name -eq 'Keep this scheme').Count -eq 1) 'Unrelated scheme lost.'
            Assert-True (@($settings.themes | Where-Object name -eq 'Keep this theme').Count -eq 1) 'Unrelated theme lost.'
        }
        $paths = @($settingsPath, $env:STARSHIP_CONFIG, $PROFILE.CurrentUserCurrentHost)
        $before = @($paths | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash }) -join ','
        & $installer
        $after = @($paths | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash }) -join ','
        Assert-True ($before -eq $after) "$case changed files on reinstall."
        Write-Host "PASS $case settings: valid collections, preserved preferences, byte-stable reinstall."
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    $PROFILE.CurrentUserCurrentHost = $savedProfile
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('windows-dotfiles-tests-')) {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
