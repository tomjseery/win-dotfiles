"""Caption artwork preservation, native states and reproducible build checks."""

import hashlib
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import pytest
from PIL import Image


@dataclass(frozen=True, slots=True)
class Part:
    name: str
    left: int
    top: int
    right: int
    bottom: int
    count: int


@pytest.fixture
def theme() -> Path:
    return Path(__file__).resolve().parents[1] / "themes/klassy"


@pytest.fixture
def parts(theme: Path) -> list[Part]:
    raw = cast(
        "list[dict[str, object]]",
        json.loads((theme / "settings.json").read_text(encoding="utf-8-sig"))["parts"],
    )
    return [
        Part(
            cast("str", row["name"]),
            *(
                cast("int", row[key])
                for key in ("left", "top", "right", "bottom", "count")
            ),
        )
        for row in raw
    ]


def test_caption_atlas_preserves_every_pixel_outside_glyphs(
    theme: Path, parts: list[Part]
) -> None:
    with (
        Image.open(theme / "sources/modern-office-pro-atlas.png") as source,
        Image.open(theme / "caption-atlas.png") as actual,
    ):
        assert source.size == actual.size == (195, 1297)
        before, after = source.convert("RGBA"), actual.convert("RGBA")
    modified: set[tuple[int, int]] = set()
    for part in parts:
        modified.update(
            (x, y)
            for y in range(part.top, part.bottom)
            for x in range(part.left, part.right)
        )
    assert len(parts) == 40
    for y in range(before.height):
        for x in range(before.width):
            if (x, y) not in modified:
                assert before.getpixel((x, y)) == after.getpixel((x, y)), (x, y)


def test_caption_atlas_keeps_both_palettes_and_disabled_states(
    theme: Path, parts: list[Part]
) -> None:
    with Image.open(theme / "caption-atlas.png") as loaded:
        atlas = loaded.convert("RGBA")
    for part in parts:
        height = (part.bottom - part.top) // 4
        for state in range(4):
            frame = atlas.crop(
                (
                    part.left,
                    part.top + state * height,
                    part.right,
                    part.top + (state + 1) * height,
                )
            )
            alpha = frame.getchannel("A")
            assert alpha.getbbox() is not None, (part.name, state)
            assert max(alpha.tobytes()) <= (199, 255, 255, 62)[state]
            expected = (
                255
                if part.name.endswith("DARK")
                or ("CLOSE" in part.name and state in (1, 2))
                else 0
            )
            pixels = frame.tobytes()
            assert all(
                pixels[offset : offset + 3] == bytes((expected,)) * 3
                for offset in range(0, len(pixels), 4)
                if pixels[offset + 3] > 0
            )
        if "MINGLYPH" in part.name:
            normal = atlas.crop((part.left, part.top, part.right, part.top + height))
            box = normal.getchannel("A").point([0] * 40 + [255] * 216).getbbox()
            assert box is not None
            assert (box[1] + box[3]) / 2 > height / 2, part.name


def test_caption_atlas_rebuild_matches_committed_fingerprint(
    theme: Path, tmp_path: Path
) -> None:
    output = tmp_path / "rebuilt.png"
    subprocess.run(
        [sys.executable, str(theme / "build_atlas.py"), "--output", str(output)],
        check=True,
        capture_output=True,
    )
    expected = json.loads((theme / "settings.json").read_text(encoding="utf-8-sig"))[
        "output_atlas_sha256"
    ]
    assert hashlib.sha256(output.read_bytes()).hexdigest() == expected
    assert (
        hashlib.sha256((theme / "caption-atlas.png").read_bytes()).hexdigest()
        == expected
    )


def test_caption_atlas_rejects_modified_source(theme: Path, tmp_path: Path) -> None:
    copied = tmp_path / "klassy"
    shutil.copytree(theme, copied)
    (copied / "sources/modern-office-pro-atlas.png").write_bytes(b"changed")
    result = subprocess.run(
        [sys.executable, str(copied / "build_atlas.py")],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "Source atlas fingerprint mismatch" in result.stderr


@pytest.mark.skipif(
    sys.platform != "win32", reason="Windows PowerShell installer boundary"
)
def test_caption_installer_recovers_interrupted_persistence(theme: Path) -> None:
    subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(theme.parents[1] / "tests/window-controls-install.ps1"),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
