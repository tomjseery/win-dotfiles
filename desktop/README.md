# Desktop

`install.ps1` enables **Auto arrange icons** and **Align icons to grid** through
the live Explorer desktop view. Other folder flags and the current icon size are
preserved. The two preferences are configured in `settings.json`.

The installer copies cursor and icon assets into
`%LOCALAPPDATA%\windows-dotfiles\desktop`, then points the current user's settings
at that stable location. The repository can move without breaking those paths.
Cursor size stays at 32. System and other fixed drives get separate icons;
drive letters are discovered rather than hardcoded.

Drive overrides use `HKCU\Software\Classes\Applications\Explorer.exe\Drives`.
After refreshing each drive, the installer asks the Windows Shell for its actual
icon location and refuses to report success if it still resolves the old icon.

Run as the logged-in desktop user:

```powershell
.\desktop\install.ps1 -WhatIf
.\desktop\install.ps1
```

The installer does not change the wallpaper, move personal files, or reapply a
Windows visual style. The existing Modern Office Pro Windows theme is an external
prerequisite for that broader Explorer appearance.

## Asset provenance

`cursors/` preserves the exact cursor assets selected on this workstation from
the **Modern Office Pro** theme. The included `cursor credits.txt` credits the
Linux-to-Windows port and links its original source:

- <https://www.opendesktop.org/p/2296782>
- <https://ko-fi.com/moyashos>

`icons/drive-fixed.ico` and `icons/drive-system.ico` are extracted Windows 11
`imageres.dll.mun` resources `ICON35_1.ico` and `ICON36_1.ico`, respectively.
They come from [bartekl1/windows-ui-assets](https://github.com/bartekl1/windows-ui-assets),
pinned to commit `21970f48b8f66b4d44742cb30388c1454512d681`.
The archive documents extraction from official Windows images/VMs and notes
Microsoft's ownership. These assets are retained for personal Windows theming;
they are not covered by this repository's MIT license.

Explorer's folder-view API is documented in
[IShellFolderViewDual3](https://learn.microsoft.com/windows/win32/api/shldisp/nn-shldisp-ishellfolderviewdual3).
