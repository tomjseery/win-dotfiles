# Desktop

`install.ps1` enables Auto arrange icons and Align icons to grid through the live
Explorer desktop view, preserves its other flags and icon size, applies the saved
cursor scheme, and installs the drive/folder icons. Preferences are in
`settings.json`; visual assets and their provenance live under [themes](../themes/README.md).

```powershell
.\desktop\install.ps1 -WhatIf
.\desktop\install.ps1
```

Run as the logged-in desktop user. Assets are copied to
`%LOCALAPPDATA%\windows-dotfiles\desktop` so moving the repository does not break
the installed paths. The installer leaves wallpaper and personal files alone.
The existing Modern Office Pro visual style remains an external prerequisite.

## Explorer icons

`explorer.ps1` covers both modern and legacy namespace entries for Desktop,
Downloads, Documents, Pictures, Music and Videos. It also sets the registered
OneDrive namespace icon. Small Windows 11 glyphs occupy the 16/20/24-pixel frames;
32-pixel and larger frames retain the blue folders. At high DPI, the sidebar can
request a larger blue frame. Details view also uses the small glyphs.

Frame directory entries explicitly declare their actual colour depth; otherwise
Windows can downscale a larger frame instead. Installed asset paths contain a
content fingerprint to avoid reusing earlier cached images. The installer checks
the Shell's resolved physical-folder icon paths and requests a Quick access refresh.

OneDrive's physical folder has its own `desktop.ini` icon. `onedrive.ps1` updates
that entry while retaining other sections and keys. It saves the original bytes
and attributes once under `%LOCALAPPDATA%\windows-dotfiles\backups`.
Other personal folders' `desktop.ini` files are untouched.

Previous per-user registry entries are retained in
`%LOCALAPPDATA%\windows-dotfiles\backups\explorer-classes-before.json`.
Upgrades back up newly managed entries before changing them. Drive overrides use
`HKCU\Software\Classes\Applications\Explorer.exe\Drives`; actual Shell icon
locations are checked after installation.

## Folder previews

The per-user `AllFolders\Shell\Logo` value is set to `imageres.dll,-3`, resolved
through the existing resource theme, to suppress folder-content previews while
retaining image/video file thumbnails. This follows Windhawk Resource Redirect's
[folder-thumbnail mechanism](https://github.com/ramensoftware/windhawk-mods/blob/main/mods/icon-resource-redirect.wh.cpp).

Existing cached folder previews can still show white triangles beneath the blue
folders. After installing settings, explicitly reset those caches if needed:

```powershell
.\desktop\reset-thumbnails.ps1 -WhatIf
.\desktop\reset-thumbnails.ps1
```

This backs up the 48/96-pixel thumbnail caches, reloads the current session's
Explorer and reopens its folder locations. The taskbar briefly disappears.
Run after file transfers finish. File thumbnails regenerate normally; original
files are unaffected. The sidebar icons and removal of the remaining triangles
were visually confirmed on this setup.
