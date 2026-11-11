# Modern Office Pro assets

Source theme: [Modern Office Pro for Windows 11 by niivu](https://www.deviantart.com/niivu/art/Modern-Office-Pro-for-Windows-11-1343839215).
The included files preserve the blue variant already installed on this workstation;
the full visual-style package is not redistributed here.

```text
cursors/                 existing selected cursor scheme and original credits
icons/folders/           installed multi-resolution folder ICOs and frame manifest
sources/                 exact original inputs for custom icon composition
build_folder_icons.py    rebuild the custom Music, Videos and OneDrive variants
```

`icons/folders/` combines Windows 11-style 16/20/24-pixel glyphs with the existing
blue 32-pixel-and-larger folder artwork. Music and Videos use the blue pack's
`folder-sound.ico` and `folder-videos.ico` large frames. This intentionally changes
icons by size, including Details view, rather than by Explorer pane.

The OneDrive variant uses the exact native-size blue folder at 32 pixels and
above, with a blue cloud outline inside its lower-right face, matching the other
folder badges. The cloud's interior retains the original folder pixels. Its small frames use
the standalone cloud glyph. The Python script performs deterministic compositing;
no image generation is involved.

From the repository root, use the locked Python environment:

```powershell
uv sync --locked
uv run python themes/modern-office-pro/build_folder_icons.py
.\desktop\install.ps1
```

`frames.json` records the source labels and each frame's SHA-256. The native
frame-selection regression checks run with `uv run pytest` on Windows. The source
ICOs in `sources/` are sufficient to rebuild the three custom variants; the other
included hybrid ICOs are retained as inputs.

The small glyphs and cloud come from the already-downloaded **Windows 11 Icons
Theme by niivu (March 2026)**. Its original [README](sources/niivu-icons-readme.txt)
credits [niivu](https://www.deviantart.com/niivu). The blue folder inputs come from
the Modern Office Pro `Icons/Folders - blue` directory. Other original large
frames came from that theme's Resource Redirect `imageres.dll`.

`cursors/` preserves the exact selected cursor bytes. Its original
[cursor credits](<cursors/cursor credits.txt>) link the port's sources:
[OpenDesktop](https://www.opendesktop.org/p/2296782) and
[Moyashos](https://ko-fi.com/moyashos).

Third-party artwork and cursor files retain their original ownership and terms;
the repository's MIT license covers its original scripts, not those assets.
