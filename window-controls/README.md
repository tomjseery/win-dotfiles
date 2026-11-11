# Window controls

Optional Klassy Traditional caption glyphs for the existing Modern Office Pro dark
visual style on Windows 10. The installer changes only a separate copy's DWM glyph
atlas: minimize, maximize, restore, close and small close at 96/120/144/192 DPI.
Colours, borders, fonts, hover backgrounds and button hitboxes remain those of the
base Windows style. Apps drawing their own titlebars may keep their own buttons.

The exact base style must already be installed and active, with its existing custom
theme support. No theme patcher, system DLL or DWM injection is installed here.
`themes/klassy/settings.json` pins the supported base fingerprint; other versions
fail before activation. Run as your normal desktop user with PowerShell 7.2+.

```powershell
./window-controls/install.ps1 -WhatIf
./window-controls/install.ps1 -PrepareOnly
./install.ps1 -Module window-controls
./window-controls/install.ps1 -Restore
```

This module is opt-in. Default installation still selects desktop, taskbar and
terminal. Python is needed only to rebuild artwork, not to install it.

The installer downloads the pinned MIT-licensed msstyleEditor 2.1.2.0 release,
checks archive/executable hashes, and loads its libmsstyle API in Windows
PowerShell 5.1. It never launches the editor UI. The preserving copy is reloaded
and checked against all style properties, effective strings/fonts and 1,432 image
resources before activation. Only the designated atlas may differ.

Generated styles, validation reports, original theme backup and rollback state live
under `%LOCALAPPDATA%/windows-dotfiles/window-controls/`. A private `.theme` copy
preserves the current theme's settings and references the new style. Activation
uses the same uxtheme API as msstyleEditor and verifies Windows' current style.
Failure attempts immediate rollback; `-Restore` restores the original style and
saved-theme reference. Changing to an unrelated theme requires resolving that
change explicitly rather than silently replacing it. Copies are retained for recovery.

After activation, check an Explorer or other native titlebar. API success does not
prove every application is drawing the new glyphs. See [source credits](../themes/klassy/README.md).
