"""Rebuild local folder variants from the credited ICO sources."""

import binascii
import hashlib
import json
import struct
import sys
import zlib
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from PIL import IcoImagePlugin, Image, ImageChops, ImageFilter

SIZES = (256, 64, 48, 40, 32, 24, 20, 16)


@dataclass(frozen=True, slots=True)
class IconFrame:
    size: int
    payload: bytes


@dataclass(frozen=True, slots=True)
class FrameFingerprint:
    width: int
    height: int
    sha256: str
    preserved_large_frame: bool

    def to_json(self) -> dict[str, object]:
        return {
            "width": self.width,
            "height": self.height,
            "sha256": self.sha256,
            "preservedLargeFrame": self.preserved_large_frame,
        }


@dataclass(frozen=True, slots=True)
class Asset:
    file: str
    large_source: str
    small_source: str
    frames: tuple[FrameFingerprint, ...] = ()

    def to_json(self) -> dict[str, object]:
        return {
            "file": self.file,
            "largeSource": self.large_source,
            "smallSource": self.small_source,
            "frames": [frame.to_json() for frame in self.frames],
        }


@dataclass(frozen=True, slots=True)
class Manifest:
    small_sizes: tuple[int, ...]
    assets: tuple[Asset, ...]

    def to_json(self) -> dict[str, object]:
        return {
            "smallSizes": list(self.small_sizes),
            "assets": [asset.to_json() for asset in self.assets],
        }


def json_mapping(value: object) -> Mapping[str, object]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise TypeError("Expected a JSON object with string keys")
    return cast("Mapping[str, object]", value)


def json_array(value: object) -> list[object]:
    if not isinstance(value, list):
        raise TypeError("Expected a JSON array")
    return cast("list[object]", value)


def json_string(value: object) -> str:
    if not isinstance(value, str):
        raise TypeError("Expected a JSON string")
    return value


def json_integer(value: object) -> int:
    if type(value) is not int:
        raise TypeError("Expected a JSON integer")
    return value


def read_manifest(path: Path) -> Manifest:
    raw = json_mapping(json.loads(path.read_text(encoding="utf-8-sig")))
    assets = []
    for value in json_array(raw["assets"]):
        asset = json_mapping(value)
        assets.append(
            Asset(
                json_string(asset["file"]),
                json_string(asset["largeSource"]),
                json_string(asset["smallSource"]),
            )
        )
    return Manifest(
        tuple(json_integer(size) for size in json_array(raw["smallSizes"])),
        tuple(assets),
    )


def frames(path: Path) -> dict[int, IconFrame]:
    data = path.read_bytes()
    result = {}
    count = int(struct.unpack_from("<H", data, 4)[0])
    for index in range(count):
        entry = struct.unpack_from("<BBBBHHII", data, 6 + index * 16)
        size, length, offset = int(entry[0]) or 256, int(entry[6]), int(entry[7])
        result[size] = IconFrame(size, data[offset : offset + length])
    return result


def write_ico(path: Path, selected: Sequence[IconFrame]) -> None:
    offset = 6 + 16 * len(selected)
    directory, payloads = bytearray(), bytearray()
    for frame in selected:
        directory += struct.pack(
            "<BBBBHHII",
            frame.size % 256,
            frame.size % 256,
            0,
            0,
            1,
            32,
            len(frame.payload),
            offset,
        )
        payloads += frame.payload
        offset += len(frame.payload)
    path.write_bytes(struct.pack("<HHH", 0, 1, len(selected)) + directory + payloads)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload))
    )


def png(image: Image.Image) -> bytes:
    # Stored DEFLATE blocks avoid platform-specific zlib compression choices.
    # The small icon pack favors identical output over compression ratio.
    rgba = image.convert("RGBA")
    stride = rgba.width * 4
    pixels = rgba.tobytes()
    rows = b"".join(
        b"\0" + pixels[offset : offset + stride]
        for offset in range(0, len(pixels), stride)
    )
    compressed = bytearray(b"\x78\x01")
    for offset in range(0, len(rows), 65535):
        block = rows[offset : offset + 65535]
        final = int(offset + len(block) == len(rows))
        compressed += struct.pack("<BHH", final, len(block), len(block) ^ 0xFFFF)
        compressed += block
    compressed += struct.pack(">I", zlib.adler32(rows))
    header = struct.pack(">IIBBBBB", rgba.width, rgba.height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", bytes(compressed))
        + png_chunk(b"IEND", b"")
    )


def native_image(icon: Image.Image, size: int) -> Image.Image:
    if not isinstance(icon, IcoImagePlugin.IcoImageFile):
        raise TypeError("Expected an ICO image")
    return icon.ico.getimage((size, size)).convert("RGBA")


def build_onedrive(sources: Path) -> list[IconFrame]:
    cloud_frames = frames(sources / "onedrive-cloud.ico")
    selected = []
    with (
        Image.open(sources / "folder-blue.ico") as folder,
        Image.open(sources / "onedrive-cloud.ico") as cloud,
    ):
        for size in SIZES:
            if size < 32:
                selected.append(cloud_frames[size])
                continue
            image = native_image(folder, size).copy()
            # Preserve the native folder; place the badge on its lower-right face.
            badge_size = round(size * 0.34)
            badge = native_image(cloud, 256).resize(
                (badge_size, badge_size), Image.Resampling.LANCZOS
            )
            alpha = badge.getchannel("A")
            stroke = max(1, round(size * 0.018))
            solid = alpha.point([0] * 128 + [255] * 128)
            inner = solid.filter(ImageFilter.MinFilter(stroke * 2 + 1))
            outline = Image.new("RGBA", badge.size, (36, 98, 215, 0))
            outline.putalpha(ImageChops.multiply(alpha, ImageChops.invert(inner)))
            image.alpha_composite(outline, (round(size * 0.61), round(size * 0.54)))
            selected.append(IconFrame(size, png(image)))
    return selected


def rebuild(root: Path) -> None:
    icons, sources = root / "icons/folders", root / "sources"
    manifest_path = icons / "frames.json"
    newline = "\r\n" if b"\r\n" in manifest_path.read_bytes() else "\n"
    manifest = read_manifest(manifest_path)
    for role in ("music", "videos"):
        current = frames(icons / f"{role}.ico")
        original = frames(sources / f"{role}-blue.ico")
        selected = [(original if size >= 32 else current)[size] for size in SIZES]
        write_ico(icons / f"{role}.ico", selected)

    write_ico(icons / "onedrive.ico", build_onedrive(sources))
    assets = []
    for asset in manifest.assets:
        if asset.file == "onedrive.ico":
            continue
        large_source = asset.large_source
        if asset.file in {"music.ico", "videos.ico"}:
            large_source = (
                f"sources/{Path(asset.file).stem}-blue.ico (Modern Office Pro blue)"
            )
        assets.append(Asset(asset.file, large_source, asset.small_source))
    assets.append(
        Asset(
            "onedrive.ico",
            "sources/folder-blue.ico + sources/onedrive-cloud.ico "
            "(Python outline corner badge)",
            "sources/onedrive-cloud.ico",
        )
    )
    fingerprinted = []
    for asset in assets:
        actual = frames(icons / asset.file)
        fingerprints = tuple(
            FrameFingerprint(
                size,
                size,
                hashlib.sha256(actual[size].payload).hexdigest(),
                size >= 32 and asset.file != "onedrive.ico",
            )
            for size in SIZES
        )
        fingerprinted.append(
            Asset(asset.file, asset.large_source, asset.small_source, fingerprints)
        )
    rebuilt = Manifest(manifest.small_sizes, tuple(fingerprinted))
    manifest_path.write_text(
        json.dumps(rebuilt.to_json(), indent=2) + "\n",
        encoding="utf-8",
        newline=newline,
    )


def main() -> None:
    if sys.version_info < (3, 12):  # noqa: UP036 - Also supports direct script execution.
        raise SystemExit("Python 3.12 or newer is required")
    rebuild(Path(__file__).resolve().parent)
    print(
        "Restored blue large Music/Videos frames and built the OneDrive corner badge."
    )


if __name__ == "__main__":
    main()
