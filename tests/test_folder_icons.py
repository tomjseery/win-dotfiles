"""Payload, artwork and Windows native frame-selection regression checks."""

import ctypes
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from collections.abc import Mapping
from ctypes import wintypes
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import cast

import pytest
from PIL import IcoImagePlugin, Image

SIZES = (256, 64, 48, 40, 32, 24, 20, 16)
ROLES = (
    "folder",
    "desktop",
    "downloads",
    "documents",
    "pictures",
    "music",
    "videos",
    "onedrive",
)


@dataclass(frozen=True, slots=True)
class Frame:
    width: int
    height: int
    colors: int
    reserved: int
    planes: int
    depth: int
    payload: bytes

    def isolated(self) -> bytes:
        return (
            struct.pack("<HHH", 0, 1, 1)
            + struct.pack(
                "<BBBBHHII",
                self.width % 256,
                self.height % 256,
                self.colors,
                self.reserved,
                1,
                32,
                len(self.payload),
                22,
            )
            + self.payload
        )


@dataclass(frozen=True, slots=True)
class BitmapPixels:
    width: int
    height: int
    depth: int
    data: bytes


class IconInfo(ctypes.Structure):
    _fields_ = [
        ("is_icon", wintypes.BOOL),
        ("x", wintypes.DWORD),
        ("y", wintypes.DWORD),
        ("mask", wintypes.HBITMAP),
        ("color", wintypes.HBITMAP),
    ]


class Bitmap(ctypes.Structure):
    _fields_ = [
        ("kind", wintypes.LONG),
        ("width", wintypes.LONG),
        ("height", wintypes.LONG),
        ("stride", wintypes.LONG),
        ("planes", wintypes.WORD),
        ("depth", wintypes.WORD),
        ("bits", ctypes.c_void_p),
    ]


@dataclass(frozen=True, slots=True)
class WindowsIcons:
    user: ctypes.CDLL
    gdi: ctypes.CDLL

    def rendered(self, path: Path, size: int) -> list[BitmapPixels]:
        icon, resource, info = wintypes.HICON(), wintypes.UINT(), IconInfo()
        try:
            assert (
                self.user.PrivateExtractIconsW(
                    str(path),
                    0,
                    size,
                    size,
                    ctypes.byref(icon),
                    ctypes.byref(resource),
                    1,
                    0,
                )
                == 1
            )
            assert self.user.GetIconInfo(icon, ctypes.byref(info))
            pixels = []
            for handle in (info.color, info.mask):
                bitmap = Bitmap()
                assert handle and self.gdi.GetObjectW(
                    handle, ctypes.sizeof(bitmap), ctypes.byref(bitmap)
                )
                length = int(bitmap.stride) * int(bitmap.height)
                data = ctypes.create_string_buffer(length)
                assert self.gdi.GetBitmapBits(handle, length, data) == length
                pixels.append(
                    BitmapPixels(
                        int(bitmap.width),
                        int(bitmap.height),
                        int(bitmap.depth),
                        data.raw,
                    )
                )
            return pixels
        finally:
            if info.color:
                assert self.gdi.DeleteObject(info.color)
            if info.mask:
                assert self.gdi.DeleteObject(info.mask)
            if icon:
                assert self.user.DestroyIcon(icon)


@pytest.fixture
def theme() -> Path:
    return Path(__file__).resolve().parents[1] / "themes/modern-office-pro"


@pytest.fixture
def windows_icons() -> WindowsIcons:
    if sys.platform == "win32":
        user = ctypes.WinDLL("user32", use_last_error=True)
        gdi = ctypes.WinDLL("gdi32", use_last_error=True)
        user.PrivateExtractIconsW.argtypes = [
            wintypes.LPCWSTR,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.POINTER(wintypes.HICON),
            ctypes.POINTER(wintypes.UINT),
            wintypes.UINT,
            wintypes.UINT,
        ]
        user.PrivateExtractIconsW.restype = wintypes.UINT
        user.GetIconInfo.argtypes = [wintypes.HICON, ctypes.POINTER(IconInfo)]
        user.GetIconInfo.restype = wintypes.BOOL
        user.DestroyIcon.argtypes = [wintypes.HICON]
        user.DestroyIcon.restype = wintypes.BOOL
        gdi.GetObjectW.argtypes = [wintypes.HGDIOBJ, ctypes.c_int, ctypes.c_void_p]
        gdi.GetObjectW.restype = ctypes.c_int
        gdi.GetBitmapBits.argtypes = [wintypes.HBITMAP, wintypes.LONG, ctypes.c_void_p]
        gdi.GetBitmapBits.restype = wintypes.LONG
        gdi.DeleteObject.argtypes = [wintypes.HGDIOBJ]
        gdi.DeleteObject.restype = wintypes.BOOL
        return WindowsIcons(user, gdi)
    pytest.skip("Windows native icon extraction")


def icon_frames(path: Path) -> dict[int, Frame]:
    data = path.read_bytes()
    reserved, kind, count = struct.unpack_from("<HHH", data)
    assert reserved == 0 and kind == 1 and count == len(SIZES)
    frames = {}
    for index in range(int(count)):
        entry = struct.unpack_from("<BBBBHHII", data, 6 + index * 16)
        width, height, colors, reserved, planes, depth, length, offset = map(int, entry)
        payload = data[offset : offset + length]
        assert len(payload) == length
        frame = Frame(
            width or 256, height or 256, colors, reserved, planes, depth, payload
        )
        assert frame.width not in frames
        frames[frame.width] = frame
    assert tuple(frames) == SIZES
    return frames


def json_object(value: object) -> Mapping[str, object]:
    assert isinstance(value, dict)
    return cast("Mapping[str, object]", value)


def json_array(value: object) -> list[object]:
    assert isinstance(value, list)
    return cast("list[object]", value)


@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("size", SIZES)
def test_payload_matches_manifest(theme: Path, role: str, size: int) -> None:
    icons = theme / "icons/folders"
    manifest = json_object(
        json.loads((icons / "frames.json").read_text(encoding="utf-8-sig"))
    )
    assets = [json_object(asset) for asset in json_array(manifest["assets"])]
    assert len(assets) == len(ROLES)
    asset = next(asset for asset in assets if asset["file"] == f"{role}.ico")
    fingerprints = [json_object(frame) for frame in json_array(asset["frames"])]
    assert len(fingerprints) == len(SIZES)
    expected = next(frame for frame in fingerprints if frame["width"] == size)
    actual = icon_frames(icons / f"{role}.ico")[size]
    assert (actual.width, actual.height) == (expected["width"], expected["height"])
    assert actual.depth > 0
    if role in {"music", "videos", "onedrive"}:
        assert actual.planes == 1 and actual.depth == 32
    assert hashlib.sha256(actual.payload).hexdigest() == expected["sha256"]


@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("size", SIZES)
@pytest.mark.skipif(sys.platform != "win32", reason="Windows native icon extraction")
def test_windows_selects_native_frame(
    theme: Path, tmp_path: Path, windows_icons: WindowsIcons, role: str, size: int
) -> None:
    path = theme / "icons/folders" / f"{role}.ico"
    single = tmp_path / "single.ico"
    single.write_bytes(icon_frames(path)[size].isolated())
    assert windows_icons.rendered(path, size) == windows_icons.rendered(single, size)


@pytest.mark.parametrize("role", ("music", "videos"))
@pytest.mark.parametrize("size", SIZES[:5])
def test_large_artwork_preserves_blue_source(theme: Path, role: str, size: int) -> None:
    assert (
        icon_frames(theme / "icons/folders" / f"{role}.ico")[size].payload
        == icon_frames(theme / "sources" / f"{role}-blue.ico")[size].payload
    )


@pytest.mark.parametrize("size", SIZES[5:])
def test_small_onedrive_preserves_cloud_source(theme: Path, size: int) -> None:
    assert (
        icon_frames(theme / "icons/folders/onedrive.ico")[size].payload
        == icon_frames(theme / "sources/onedrive-cloud.ico")[size].payload
    )


@pytest.mark.parametrize("size", SIZES[:5])
def test_onedrive_preserves_folder_outside_badge(theme: Path, size: int) -> None:
    with Image.open(theme / "sources/folder-blue.ico") as folder:
        assert isinstance(folder, IcoImagePlugin.IcoImageFile)
        base = folder.ico.getimage((size, size)).convert("RGBA")
    payload = icon_frames(theme / "icons/folders/onedrive.ico")[size].payload
    with Image.open(BytesIO(payload)) as image:
        actual = image.convert("RGBA")
    left, top = round(size * 0.61), round(size * 0.54)
    edge = round(size * 0.34)
    for y in range(size):
        for x in range(size):
            if not (left <= x < left + edge and top <= y < top + edge):
                assert actual.getpixel((x, y)) == base.getpixel((x, y))
    assert actual.tobytes() != base.tobytes()


def test_rebuild_preserves_checked_in_bytes(theme: Path, tmp_path: Path) -> None:
    copied = tmp_path / "theme"
    shutil.copytree(theme, copied)
    expected = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (copied / "icons/folders").iterdir()
    }
    subprocess.run([sys.executable, str(copied / "build_folder_icons.py")], check=True)
    assert {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (copied / "icons/folders").iterdir()
    } == expected


def test_builder_import_does_not_require_assets(theme: Path, tmp_path: Path) -> None:
    script = tmp_path / "build_folder_icons.py"
    shutil.copyfile(theme / script.name, script)
    subprocess.run(
        [
            sys.executable,
            "-c",
            "import runpy, sys; runpy.run_path(sys.argv[1])",
            str(script),
        ],
        check=True,
    )
    assert list(tmp_path.iterdir()) == [script]
