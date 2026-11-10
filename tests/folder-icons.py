"""Windows-only regression check for ICO frame selection, without opening UI."""
import ctypes
from ctypes import wintypes as w
import hashlib
import json
from pathlib import Path
import struct
import tempfile

class IconInfo(ctypes.Structure):
    _fields_ = [("is_icon", w.BOOL), ("x", w.DWORD), ("y", w.DWORD),
                ("mask", w.HBITMAP), ("color", w.HBITMAP)]

class Bitmap(ctypes.Structure):
    _fields_ = [("kind", w.LONG), ("width", w.LONG), ("height", w.LONG),
                ("stride", w.LONG), ("planes", w.WORD), ("depth", w.WORD),
                ("bits", ctypes.c_void_p)]

user = ctypes.WinDLL("user32", use_last_error=True)
gdi = ctypes.WinDLL("gdi32", use_last_error=True)
user.PrivateExtractIconsW.argtypes = [w.LPCWSTR, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    ctypes.POINTER(w.HICON), ctypes.POINTER(w.UINT), w.UINT, w.UINT]
user.PrivateExtractIconsW.restype = w.UINT
user.GetIconInfo.argtypes = [w.HICON, ctypes.POINTER(IconInfo)]
user.GetIconInfo.restype = w.BOOL
user.DestroyIcon.argtypes = [w.HICON]
gdi.GetObjectW.argtypes = [w.HGDIOBJ, ctypes.c_int, ctypes.c_void_p]
gdi.GetObjectW.restype = ctypes.c_int
gdi.GetBitmapBits.argtypes = [w.HBITMAP, w.LONG, ctypes.c_void_p]
gdi.GetBitmapBits.restype = w.LONG
gdi.DeleteObject.argtypes = [w.HGDIOBJ]

def rendered(path, size):
    icon, resource, info = w.HICON(), w.UINT(), IconInfo()
    assert user.PrivateExtractIconsW(str(path), 0, size, size, ctypes.byref(icon), ctypes.byref(resource), 1, 0) == 1
    try:
        assert user.GetIconInfo(icon, ctypes.byref(info))
        pixels = []
        for handle in [info.color, info.mask]:
            bm = Bitmap()
            assert handle and gdi.GetObjectW(handle, ctypes.sizeof(bm), ctypes.byref(bm))
            length = bm.stride * bm.height
            data = ctypes.create_string_buffer(length)
            assert gdi.GetBitmapBits(handle, length, data) == length
            pixels.append((bm.width, bm.height, bm.depth, data.raw))
        return pixels
    finally:
        if info.color: gdi.DeleteObject(info.color)
        if info.mask: gdi.DeleteObject(info.mask)
        if icon: user.DestroyIcon(icon)

root = Path(__file__).resolve().parents[1] / "desktop/folders"
manifest = json.loads((root / "frames.json").read_text(encoding="utf-8-sig"))
count = 0
with tempfile.TemporaryDirectory(prefix="win-dotfiles-icons-") as temp:
    for asset in manifest["assets"]:
        path = root / asset["file"]
        data = path.read_bytes()
        assert struct.unpack_from("<HHH", data) == (0, 1, len(asset["frames"]))
        for index, frame in enumerate(asset["frames"]):
            width, height, colors, reserved, planes, depth, length, offset = struct.unpack_from("<BBBBHHII", data, 6 + index * 16)
            payload = data[offset:offset + length]
            assert len(payload) == length and hashlib.sha256(payload).hexdigest() == frame["sha256"]
            assert (width or 256, height or 256) == (frame["width"], frame["height"])
            # One unambiguous frame supplies the expected pixels. Mixed-frame
            # files must select that artwork at its native size, not downscale
            # a larger frame because its directory declares a higher depth.
            single = Path(temp) / "single.ico"
            single.write_bytes(struct.pack("<HHH", 0, 1, 1) +
                struct.pack("<BBBBHHII", width, height, colors, reserved, 1, 32, length, 22) + payload)
            assert rendered(path, frame["width"]) == rendered(single, frame["width"]), (asset["file"], frame["width"])
            count += 1
print(f"Passed: {count} native frame-selection and payload-integrity checks.")
