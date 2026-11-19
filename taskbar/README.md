# Taskbar

The existing setup uses ExplorerPatcher for centered taskbar icons and
TranslucentTB for the fluent, translucent appearance in `TranslucentTB.cfg`.

Run in an elevated PowerShell 7.2+ with winget available:

```powershell
.\taskbar\install.ps1 -WhatIf
.\taskbar\install.ps1
```

Sign out and in to reload ExplorerPatcher, or add `-RestartExplorer` for an
immediate restart. TranslucentTB restarts after its configuration is copied.
Desktop and terminal changes can be installed independently.
