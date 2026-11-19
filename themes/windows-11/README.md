# Windows 11 drive icons

`icons/drives/drive-fixed.ico` and `drive-system.ico` are Windows 11
`imageres.dll.mun` resources `ICON35_1.ico` and `ICON36_1.ico`.

Source: [bartekl1/windows-ui-assets](https://github.com/bartekl1/windows-ui-assets),
pinned to commit `21970f48b8f66b4d44742cb30388c1454512d681`.
The archive documents extraction from official Windows images/VMs and notes
Microsoft's ownership. These assets are retained for personal Windows theming;
they are not covered by this repository's MIT license.

`desktop/install.ps1` copies these assets to a stable local path and assigns
separate icons to the system drive and other fixed drives.
