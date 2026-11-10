#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
$scoopStarship = Join-Path $env:USERPROFILE 'scoop/apps/starship/current/starship.exe'
if ($WhatIfPreference) {
    Write-Host 'Would merge the Graphite Windows Terminal theme, copy Starship configuration, and update the managed PowerShell profile block.'
    return
}
if (-not $starship -and -not (Test-Path -LiteralPath $scoopStarship)) {
    & winget install --id Starship.Starship --exact --source winget --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Starship installation failed.' }
}

function Write-ManagedText {
    param([string]$Path, [string]$Text)
    if ((Test-Path -LiteralPath $Path) -and [IO.File]::ReadAllText($Path) -ceq $Text) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $backupRoot = Join-Path $env:LOCALAPPDATA 'windows-dotfiles/backups'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $name = [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.bak'
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot $name)
    }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$fragment = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'windows-terminal.json') | ConvertFrom-Json -AsHashtable
$storeSettings = Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
$unpackagedSettings = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/settings.json'
$settingsPath = if (Test-Path -LiteralPath $storeSettings) { $storeSettings } elseif (Test-Path -LiteralPath $unpackagedSettings) { $unpackagedSettings } else { $storeSettings }
$settings = if (Test-Path -LiteralPath $settingsPath) { Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
if (-not $settings.Contains('profiles')) { $settings.profiles = [ordered]@{} }
if (-not $settings.profiles.Contains('defaults')) { $settings.profiles.defaults = [ordered]@{} }
$defaults = $settings.profiles.defaults
foreach ($key in @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode', 'backgroundImageAlignment')) { $defaults.Remove($key) }
foreach ($key in $fragment.profiles.defaults.Keys) {
    if ($key -eq 'font' -and $defaults.Contains('font')) {
        foreach ($fontKey in $fragment.profiles.defaults.font.Keys) { $defaults.font[$fontKey] = $fragment.profiles.defaults.font[$fontKey] }
    } else { $defaults[$key] = $fragment.profiles.defaults[$key] }
}
foreach ($collection in @('schemes', 'themes')) {
    $settings[$collection] = @($settings[$collection] | Where-Object { $_.name -ne 'Graphite' }) + @($fragment[$collection])
}
$settings.theme = $fragment.theme
Write-ManagedText -Path $settingsPath -Text (($settings | ConvertTo-Json -Depth 100) + [Environment]::NewLine)

$starshipPath = if ($env:STARSHIP_CONFIG) { $env:STARSHIP_CONFIG } else { Join-Path $env:USERPROFILE '.config/starship.toml' }
Write-ManagedText -Path $starshipPath -Text ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'starship.toml')))

$profilePath = $PROFILE.CurrentUserCurrentHost
$profileText = if (Test-Path -LiteralPath $profilePath) { [IO.File]::ReadAllText($profilePath) } else { '' }
$block = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'profile.ps1')).TrimEnd()
$pattern = '(?ms)^# >>> Graphite styling >>>\r?\n.*?^# <<< Graphite styling <<<'
if ([regex]::IsMatch($profileText, $pattern)) {
    $updated = [regex]::Replace($profileText, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $block })
} else {
    $updated = $profileText.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
}
Write-ManagedText -Path $profilePath -Text $updated
Write-Host 'Terminal: Graphite theme and white two-line PowerShell prompt applied. Open a new PowerShell tab.'
