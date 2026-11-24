#!/usr/bin/env python3
"""Planted pictures and their truth for the picture reader (#792, pins I1 to I3 of docs/design/files-exports.md in the suite).

    python3 -I tools/parity/picture-parity/make_fixtures.py macTEMTests/Fixtures/picture

Writes small PNGs and JPEGs and `truth.json`: for each file its shape after EXIF rotation and the grey value of every pixel as
the reference reads it. The reference is RosettaSciIO 0.14.0's `rsciio.image.file_reader`, which is `imageio.imread` over
Pillow; this script calls imageio 2.37.4 over Pillow 12.3.0 directly (rsciio adds axes and metadata, not values). Grey is
the app's rule, a named deviation (the reference keeps RGB): each pixel the brightest of its red, green and blue. Alpha is
dropped. Rotation is Pillow's `ImageOps.exif_transpose`.

Pinned as tools/lib/references-lock.txt pins them; any other version is refused. Pillow writes no interlaced PNG, so the
Adam7 file is encoded here by hand from the same pixels as the plain grey file (the truth is still read back by imageio).
"""
import importlib.metadata
import io
import json
import struct
import sys
import zlib
from pathlib import Path

import imageio.v2 as imageio
import numpy as np
from PIL import Image, ImageOps

PINS = {"pillow": "12.3.0", "imageio": "2.37.4", "numpy": "2.5.4"}
for name, version in PINS.items():
    found = importlib.metadata.version(name)
    if found != version:
        sys.exit(f"{name} {found} is not the pinned {version}")

W, H = 13, 9   # odd and unequal, so a transposed or mirrored read cannot pass by symmetry


def ramp(scale, offset=0):
    y, x = np.mgrid[0:H, 0:W]
    return (offset + scale * (x * 7 + y * 19 + (x * y) % 5)).astype(np.int64)


def grey8():
    return (ramp(1) % 256).astype(np.uint8)


def rgb8():
    r = (ramp(3) % 256).astype(np.uint8)
    g = (ramp(5, 40) % 256).astype(np.uint8)
    b = (255 - ramp(2) % 256).astype(np.uint8)
    return np.dstack([r, g, b])


def smooth(offset):
    """Slow ramps for JPEG: few high frequencies, so two decoders' IDCTs agree closely."""
    y, x = np.mgrid[0:H, 0:W]
    return np.clip(offset + 6 * x + 9 * y, 0, 255).astype(np.uint8)


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def adam7_grey8(pixels):
    """A grey 8-bit PNG with Adam7 interlacing, filter 0 on every row."""
    passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    raw = b""
    for x0, y0, dx, dy in passes:
        for y in range(y0, H, dy):
            row = bytes(int(pixels[y, x]) for x in range(x0, W, dx))
            if row:
                raw += b"\x00" + row
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 0, 0, 0, 1)
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(raw)) + png_chunk(b"IEND", b"")


def save(image, **options):
    buffer = io.BytesIO()
    image.save(buffer, **options)
    return buffer.getvalue()


def grey_truth(path):
    """The reference's values, then the app's grey rule."""
    with Image.open(path) as opened:
        transposed = ImageOps.exif_transpose(opened)
        buffer = io.BytesIO()
        # imageio reads what Pillow decodes; the transposed picture goes through imageio as a lossless PNG of the same mode
        transposed.save(buffer, format="PNG")
    values = np.asarray(imageio.imread(buffer.getvalue()))
    if values.ndim == 3:
        values = values[:, :, :3].max(axis=2)
    return values


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    files = {}

    g8 = grey8()
    g16 = (ramp(509, 1000) % 65536).astype(np.uint16)
    files["grey8.png"] = (save(Image.fromarray(g8, "L"), format="PNG"), "I1", 0)
    files["grey16.png"] = (save(Image.frombytes("I;16", (W, H), g16.astype("<u2").tobytes()), format="PNG"), "I1", 0)
    files["rgb8.png"] = (save(Image.fromarray(rgb8(), "RGB"), format="PNG"), "I1", 0)
    rgba = np.dstack([rgb8(), np.full((H, W), 255, np.uint8)])
    files["rgba8-opaque.png"] = (save(Image.fromarray(rgba, "RGBA"), format="PNG"), "I1", 0)
    palette = Image.fromarray(rgb8(), "RGB").quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    files["palette.png"] = (save(palette, format="PNG"), "I1", 0)
    files["grey8-interlaced.png"] = (adam7_grey8(g8), "I1", 0)
    # A gAMA chunk (1/2.2) inserted before IDAT: values must not move.
    plain = save(Image.fromarray(rgb8(), "RGB"), format="PNG")
    at = plain.index(b"IDAT") - 4
    files["rgb8-gamma.png"] = (plain[:at] + png_chunk(b"gAMA", struct.pack(">I", 45455)) + plain[at:], "I1", 0)
    from PIL import ImageCms
    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    files["rgb8-icc.png"] = (save(Image.fromarray(rgb8(), "RGB"), format="PNG", icc_profile=srgb), "I1", 0)

    files["grey-baseline.jpg"] = (save(Image.fromarray(smooth(20), "L"), format="JPEG", quality=95), "I2", 1)
    files["grey-progressive.jpg"] = (save(Image.fromarray(smooth(30), "L"), format="JPEG", quality=95, progressive=True), "I2", 1)
    colour = np.dstack([smooth(10), smooth(60), smooth(110)])
    # 4:4:4, so no chroma upsampling differs between decoders; the tolerance is checked by the test, the largest difference printed.
    files["colour-baseline.jpg"] = (save(Image.fromarray(colour, "RGB"), format="JPEG", quality=95, subsampling=0), "I2", 2)
    files["colour-progressive.jpg"] = (save(Image.fromarray(colour, "RGB"), format="JPEG", quality=95, subsampling=0,
                                            progressive=True), "I2", 2)

    for orientation in range(1, 9):
        exif = Image.Exif()
        exif[0x0112] = orientation
        files[f"orientation-{orientation}.jpg"] = (
            save(Image.fromarray(smooth(15), "L"), format="JPEG", quality=95, exif=exif.tobytes()), "I3", 1)

    truth = {"reference": "imageio 2.37.4 over Pillow 12.3.0 (RosettaSciIO 0.14.0 rsciio.image), grey by the brightest channel",
             "files": {}}
    for name, (data, pin, tolerance) in sorted(files.items()):
        path = out / name
        path.write_bytes(data)
        values = grey_truth(path)
        truth["files"][name] = {"pin": pin, "tolerance": tolerance, "height": int(values.shape[0]), "width": int(values.shape[1]),
                                "values": [int(v) for v in values.reshape(-1)]}
    (out / "truth.json").write_text(json.dumps(truth, indent=1, sort_keys=True) + "\n")

    # Refused by name, never decoded: an animation, a CMYK picture, and a header that claims 20000 x 20000 pixels.
    frames = [Image.fromarray(g8, "L"), Image.fromarray(255 - g8, "L"), Image.fromarray(g8 // 2, "L")]
    (out / "refused-animated.png").write_bytes(save(frames[0], format="PNG", save_all=True, append_images=frames[1:], duration=100))
    (out / "refused-cmyk.jpg").write_bytes(save(Image.fromarray(rgb8(), "RGB").convert("CMYK"), format="JPEG", quality=95))
    ihdr = struct.pack(">IIBBBBB", 20000, 20000, 8, 0, 0, 0, 0)
    rows = zlib.compress(b"\x00" + bytes(20000))   # one row of the 20000 the header claims
    (out / "refused-large.png").write_bytes(b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", rows)
                                            + png_chunk(b"IEND", b""))


if __name__ == "__main__":
    main(sys.argv[1])
