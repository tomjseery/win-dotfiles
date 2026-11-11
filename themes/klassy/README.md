# Klassy Traditional adaptation

Matches the direction of Tommy's KDE configuration: Traditional glyphs, bold
strokes, SmallMedium size and the existing Windows rectangular hover targets.
It is a Pillow rendering adapted to fixed Windows atlas bounds, rather than a
pixel-identical Qt renderer. Normal glyph opacity is 78%; Windows' native four
glyph states and separate light/dark palettes remain available. KDE's separate
62% inactive-window opacity is not mapped onto Windows' disabled-button state.

Sources:

- [Tommy's merged Klassy configuration](https://github.com/tomjseery/dotfiles/blob/5790ca1495e88b069b1b60aa3fa20e17f5554e93/themes/current/files/.config/klassyrc).
- [Klassy geometry](https://github.com/paulmcauley/klassy/blob/9b788b2ea8d40c6a7af3b0130de9e891d41fbb30/libbreezecommon/renderdecorationbuttonicon18by18.cpp),
  Paul A McAuley, 2022–2024. The adapted geometry in `build_atlas.py` is licensed
  under GPL-2.0-only OR GPL-3.0-only; see the accompanying license texts.
- [Modern Office Pro by niivu](https://www.deviantart.com/niivu/art/Modern-Office-Pro-for-Windows-11-1343839215).
  `sources/modern-office-pro-atlas.png` is extracted from the locally installed
  `Modern Office Pro - dark.msstyles`. Its non-caption artwork retains niivu's
  ownership and terms. The generated atlas retains the same third-party artwork.
  The full visual style is an external prerequisite and is not committed.
- [msstyleEditor 2.1.2.0](https://github.com/nptr/msstyleEditor/releases/tag/2.1.2.0),
  nptr, MIT; [pinned source](https://github.com/nptr/msstyleEditor/tree/0f667ffa03974e7402510218e5515725ea5b3a83).
  `LICENSE-msstyleEditor.txt` is included; the executable is downloaded into a
  per-user tool cache and never committed.

`settings.json` records input/output hashes, the pinned editor and all 40 atlas
rectangles. `caption-atlas.png` is the generated artwork used at installation.
Rebuild with Python 3.12+, from the repository root:

```powershell
uv sync --locked
uv run python themes/klassy/build_atlas.py
uv run pytest tests/test_caption_atlas.py
```

The tests verify every pixel outside the glyph rectangles, all DPI/palette/state
combinations, the low minimize line and the committed rebuild fingerprint.
The [window-controls installer](../../window-controls/README.md) owns activation
and rollback. Do not manually replace files in `C:/Windows/Resources/Themes`.
