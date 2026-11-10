# Windows dotfiles

Personal Windows 10 configuration, split into independently installable modules.
Each folder owns its settings, assets and PowerShell installer.

```text
desktop/
  install.ps1             icon arrangement, cursor scheme and drive icons
  settings.json           desktop preferences and cursor role mapping
  cursors/                saved Modern Office Pro cursor files
  icons/                  Windows 11 drive icons
taskbar/
  install.ps1             ExplorerPatcher and TranslucentTB
  TranslucentTB.cfg       existing centered, translucent taskbar appearance
terminal/
  install.ps1             merge terminal settings and install shell styling
  windows-terminal.json   Graphite colour scheme, tabs and typography
  starship.toml           compact white two-line prompt
  profile.ps1             managed PowerShell styling fragment
install.ps1               select one or more modules
```

## Install

Use PowerShell 7.2 or newer on Windows 10. Preview all modules without changing
files, settings or packages:

```powershell
.\install.ps1 -WhatIf
```

Apply desktop and terminal configuration as your normal desktop user:

```powershell
.\install.ps1 -Module desktop,terminal
```

Each module can also run independently, for example `./terminal/install.ps1`.
The desktop installer needs an interactive Explorer desktop. The taskbar module
needs elevation and winget; run it in an elevated PowerShell:

```powershell
.\taskbar\install.ps1
```

`./install.ps1` selects all modules and therefore needs elevation. Taskbar changes
reload at sign-in; `-RestartExplorer` explicitly reloads Explorer immediately.
Desktop alignment, cursors and drive icons update without restarting Explorer.

## Module details

- [Desktop configuration and asset provenance](desktop/README.md)
- [Terminal configuration and merge behaviour](terminal/README.md)
- [Taskbar configuration](taskbar/README.md)

Personal files and desktop shortcuts are not stored here or moved by installers.
Desktop cleanup is a separate, reversible housekeeping operation.
Neovim configuration stays in its own repository.

## License

Original scripts are [MIT licensed](LICENSE). Third-party cursor and Windows icon
assets retain their original ownership and terms; MIT does not relicense them.
See the desktop asset provenance.
