#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('desktop', 'taskbar', 'terminal', 'window-controls')]
    [string[]]$Module = @('desktop', 'taskbar', 'terminal'),
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
if ('taskbar' -in $Module -and -not $WhatIfPreference) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'The taskbar installer needs an elevated PowerShell. Desktop and terminal can run without elevation.'
    }
}
foreach ($name in $Module) {
    $arguments = @{ WhatIf = $WhatIfPreference }
    if ($name -eq 'taskbar') { $arguments.RestartExplorer = $RestartExplorer }
    & (Join-Path $PSScriptRoot "$name/install.ps1") @arguments
}
