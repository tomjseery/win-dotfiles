"""Adapt Klassy Traditional glyph geometry to the existing Windows caption atlas.

SPDX-FileCopyrightText: 2022-2024 Paul A McAuley <kde@paulmcauley.com>
SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
Geometry adapted from Klassy renderdecorationbuttonicon18by18.cpp; see README.md.
"""

import argparse
import hashlib
import json
import re
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import cast

from PIL import Image, ImageDraw

SUPERSAMPLE = 8
PART_NAME = re.compile(
    r"(SMALL)?BUTTON(CLOSE|MAX|MIN|RESTORE)GLYPH(96|120|144|192)(DARK)?"
)
type Point = tuple[float, float]
type Polyline = tuple[Point, ...]


class Glyph(Enum):
    CLOSE = ((((4.5, 4.5), (13.5, 13.5)), ((13.5, 4.5), (4.5, 13.5))), True, True)
    MAX = (
        (((4.5, 4.5), (13.5, 4.5), (13.5, 13.5), (4.5, 13.5), (4.5, 4.5)),),
        False,
        False,
    )
    MIN = ((((4.5, 13.5), (13.5, 13.5)),), True, False)
    RESTORE = (
        (
            ((7.5, 7.5), (7.5, 4.5), (13.5, 4.5), (13.5, 10.5), (10.5, 10.5)),
            ((4.5, 7.5), (10.5, 7.5), (10.5, 13.5), (4.5, 13.5), (4.5, 7.5)),
        ),
        False,
        False,
    )

    def __init__(
        self, lines: tuple[Polyline, ...], round_caps: bool, white_hover: bool
    ) -> None:
        self.lines = lines
        self.round_caps = round_caps
        self.white_hover = white_hover


@dataclass(frozen=True, slots=True)
class Part:
    name: str
    left: int
    top: int
    right: int
    bottom: int
    count: int

    @property
    def box(self) -> tuple[int, int, int, int]:
        return self.left, self.top, self.right, self.bottom


def mapping(value: object) -> Mapping[str, object]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError("Expected a JSON object")
    return cast("Mapping[str, object]", value)


def integer(value: object) -> int:
    if type(value) is not int:
        raise ValueError("Expected an integer")
    return value


def read_parts(
    settings: Mapping[str, object], size: tuple[int, int]
) -> tuple[Part, ...]:
    rows = settings["parts"]
    if not isinstance(rows, list):
        raise ValueError("Expected parts array")
    parts = []
    occupied: set[tuple[int, int]] = set()
    for row in cast("list[object]", rows):
        raw = mapping(row)
        name = raw["name"]
        if not isinstance(name, str) or not PART_NAME.fullmatch(name):
            raise ValueError("Unsupported caption glyph name")
        part = Part(
            name,
            *(integer(raw[key]) for key in ("left", "top", "right", "bottom", "count")),
        )
        if not (
            0 <= part.left < part.right <= size[0]
            and 0 <= part.top < part.bottom <= size[1]
            and part.count == 4
            and (part.bottom - part.top) % 4 == 0
        ):
            raise ValueError("Invalid caption glyph rectangle")
        pixels = {
            (x, y)
            for y in range(part.top, part.bottom)
            for x in range(part.left, part.right)
        }
        if occupied & pixels:
            raise ValueError("Overlapping caption glyph rectangles")
        occupied.update(pixels)
        parts.append(part)
    expected = {
        f"{prefix}BUTTON{kind}GLYPH{dpi}{palette}"
        for prefix, kind in (
            ("", "CLOSE"),
            ("", "MIN"),
            ("", "MAX"),
            ("", "RESTORE"),
            ("SMALL", "CLOSE"),
        )
        for dpi in (96, 120, 144, 192)
        for palette in ("", "DARK")
    }
    if {part.name for part in parts} != expected or len(parts) != 40:
        raise ValueError("Expected all 40 caption glyph strips")
    return tuple(parts)


def glyph_mask(
    glyph: Glyph, size: tuple[int, int], dpi: int, small: bool
) -> Image.Image:
    """Render the Traditional shapes within the existing glyph's fixed bounds."""
    scale = (12 if small else 16) * dpi / 96 / 18
    stroke = max(1, int((1.5 if small else 2) * dpi / 96 + 0.5))
    width, height = size
    canvas = Image.new("L", (width * SUPERSAMPLE, height * SUPERSAMPLE))
    draw = ImageDraw.Draw(canvas)

    def point(x: float, y: float) -> tuple[float, float]:
        return (
            (width / 2 + (x - 9) * scale) * SUPERSAMPLE,
            (height / 2 + (y - 9) * scale) * SUPERSAMPLE,
        )

    def line(
        points: tuple[tuple[float, float], ...], *, round_caps: bool = False
    ) -> None:
        coords = [point(x, y) for x, y in points]
        draw.line(coords, fill=255, width=stroke * SUPERSAMPLE, joint="curve")
        if round_caps:
            radius = stroke * SUPERSAMPLE / 2
            for x, y in (coords[0], coords[-1]):
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)

    for points in glyph.lines:
        line(points, round_caps=glyph.round_caps)
    return canvas.resize(size, Image.Resampling.LANCZOS)


def build(root: Path, output: Path) -> None:
    settings = mapping(json.loads((root / "settings.json").read_text(encoding="utf-8")))
    source = root / "sources/modern-office-pro-atlas.png"
    if (
        hashlib.sha256(source.read_bytes()).hexdigest()
        != settings["source_atlas_sha256"]
    ):
        raise ValueError("Source atlas fingerprint mismatch")
    with Image.open(source) as loaded:
        atlas = loaded.convert("RGBA")
    if atlas.size != (settings["atlas_width"], settings["atlas_height"]):
        raise ValueError("Source atlas size mismatch")
    parts = read_parts(settings, atlas.size)
    for part in parts:
        match = PART_NAME.fullmatch(part.name)
        assert match is not None
        small, kind, dpi, dark = match.groups()
        glyph = Glyph[kind]
        size = part.right - part.left, (part.bottom - part.top) // part.count
        mask = glyph_mask(glyph, size, int(dpi), bool(small))
        for state, opacity in enumerate((199, 255, 255, 62)):
            white = bool(dark) or (glyph.white_hover and state in (1, 2))
            frame = Image.new(
                "RGBA", size, (255, 255, 255, 0) if white else (0, 0, 0, 0)
            )
            frame.putalpha(
                mask.point([round(value * opacity / 255) for value in range(256)])
            )
            atlas.paste(frame, (part.left, part.top + state * size[1]))
    output.parent.mkdir(parents=True, exist_ok=True)
    # Uncompressed PNG is stable across platform zlib versions.
    atlas.save(output, compress_level=0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    build(root, args.output or root / "caption-atlas.png")


if __name__ == "__main__":
    if sys.version_info < (3, 12):  # noqa: UP036 -- runtime minimum for direct execution
        raise SystemExit("Python 3.12 or newer is required")
    main()
