# win-dotfiles

Personal Windows 10 configuration, split into independently installable modules.
Each module owns its settings and PowerShell installer. Visual assets are grouped
by source theme under `themes/`.

```text
desktop/
  install.ps1             icon arrangement, cursor scheme and drive icons
  settings.json           desktop preferences and cursor role mapping
  explorer.ps1            small Windows 11 icons, large blue icons, clean folders
  reset-thumbnails.ps1    optional cache rebuild with an Explorer reload
  folder-icon.ps1         update physical folder icons while preserving settings
taskbar/
  install.ps1             ExplorerPatcher and TranslucentTB
  TranslucentTB.cfg       existing centered, translucent taskbar appearance
terminal/
  install.ps1             merge terminal settings and install shell styling
  windows-terminal.json   Graphite colour scheme, tabs and typography
  starship.toml           compact white two-line prompt
  profile.ps1             managed PowerShell styling fragment
themes/
  modern-office-pro/      blue folders, cursors, source artwork and icon builder
  windows-11/             Windows 11 drive icons and provenance
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
- [Theme assets, source links and rebuilding](themes/README.md)

Personal files and desktop shortcuts are not stored here or moved by installers.
Desktop cleanup is a separate, reversible housekeeping operation.
Neovim configuration stays in its own repository.

## License

Original scripts are [MIT licensed](LICENSE). Third-party cursor and Windows icon
assets retain their original ownership and terms; MIT does not relicense them.
See the [theme provenance](themes/README.md).
