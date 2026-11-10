# Terminal

An opaque `#222222` charcoal background, normal white text, Cascadia Mono at
12 points, subtle padding and matching tabs. Starship displays the directory,
Git branch and status on the first line, with a white `❯` on the second.
PowerShell command text is white; comments and history suggestions remain dim.

```powershell
.\terminal\install.ps1 -WhatIf
.\terminal\install.ps1
```

The installer merges the named Graphite scheme/theme and managed profile defaults
into the stable Windows Terminal configuration. Existing shell profiles,
shortcuts, schemes and unrelated font settings are retained. Background image
settings in profile defaults are removed.

Starship is reused from PATH or the existing Scoop installation. If missing,
winget installs `Starship.Starship`. Its configuration is copied to
`~/.config/starship.toml`, or to `STARSHIP_CONFIG` when explicitly configured.

Only the marked Graphite block in the current user's PowerShell profile is
replaced. Existing aliases, functions, agent integration and other profile code
remain intact. Changed files are backed up under
`%LOCALAPPDATA%\windows-dotfiles\backups`. Open a new PowerShell tab afterwards.

This fragment contains only appearance settings; machine-specific profiles,
account state and credentials are not copied into the repository.
Neovim owns its own colour configuration separately.
