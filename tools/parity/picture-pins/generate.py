"""PNG and JPEG fixtures and their pins for the app's picture reader (TEMCore `PictureImageReader`, #792, plan pins I1 to I3).

    python -I -B tools/parity/picture-pins/generate.py

Pillow 13.0.0 writes macTEMTests/Fixtures/pictures/*.{png,jpg}; the reference reading is RosettaSciIO 0.14.0's
`rsciio.image.file_reader` (imageio 2.38.1 over Pillow), and for the EXIF cases Pillow's `ImageOps.exif_transpose`, which the
reference applies nowhere (named in the pins). pins.json records per file: the reference's shape and dtype, the app's grey
(the reference's values where it is grey; the brightest of red, green and blue where it is colour: the app's rule, a named
deviation, as the reference keeps RGB) as a flat list, and the comparison (exact, or a JPEG's tolerance).
"""
import io
import json
import pathlib

import numpy as np
import imageio
import PIL
from PIL import Image, ImageOps
import rsciio
from rsciio.image import file_reader

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / 'macTEMTests/Fixtures/pictures'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(792)


def spots(h, w, dtype=np.uint8, peak=255):
    """A small diffraction-like picture: a bright centre, a few spots, noise."""
    y, x = np.mgrid[0:h, 0:w]
    img = rng.integers(0, peak // 16, size=(h, w)).astype(np.float64)
    for cy, cx in [(h / 2, w / 2), (h / 4, w / 4), (3 * h / 4, 3 * w / 4), (h / 4, 3 * w / 4)]:
        img += peak * 0.7 * np.exp(-((y - cy) ** 2 + (x - cx) ** 2) / 3.0)
    return np.clip(img, 0, peak).astype(dtype)


def grey_of(data):
    """The app's grey of the reference's array: grey as is; RGB(A) the brightest of R, G, B (alpha left out)."""
    if data.dtype.names:   # rsciio's structured rgb8 / rgba8 / rgb16 / rgba16
        rgb = np.stack([data['R'], data['G'], data['B']], axis=-1)
        return rgb.max(axis=-1)
    if data.ndim == 3:
        return data[..., :3].max(axis=-1)
    return data


cases = []


def add(name, kind, compare, reference_note=None, transpose=False):
    path = OUT / name
    data = file_reader(str(path))[0]['data']
    if transpose:
        with Image.open(path) as im:
            data = np.asarray(ImageOps.exif_transpose(im))
    grey = grey_of(np.asarray(data))
    entry = {'name': name, 'kind': kind, 'shape': list(grey.shape), 'dtype': str(grey.dtype),
             'compare': compare, 'grey': [int(v) for v in grey.ravel()]}
    if reference_note:
        entry['reference'] = reference_note
    cases.append(entry)


# I1: PNG, stored values exact.
h, w = 9, 12
Image.fromarray(spots(h, w), 'L').save(OUT / 'grey8.png')
add('grey8.png', 'png', 'exact')
Image.fromarray(spots(h, w, np.uint16, 65535)).save(OUT / 'grey16.png')
add('grey16.png', 'png', 'exact')
rgb = np.stack([spots(h, w), spots(h, w), spots(h, w)], axis=-1)
Image.fromarray(rgb, 'RGB').save(OUT / 'rgb.png')
add('rgb.png', 'png', 'exact')
rgba = np.concatenate([rgb, np.full((h, w, 1), 255, np.uint8)], axis=-1)
Image.fromarray(rgba, 'RGBA').save(OUT / 'rgba-opaque.png')
add('rgba-opaque.png', 'png', 'exact')
equal = np.repeat(spots(h, w)[..., None], 3, axis=-1)
Image.fromarray(equal, 'RGB').save(OUT / 'rgb-grey.png')
add('rgb-grey.png', 'png', 'exact')
pal = Image.fromarray(spots(h, w) // 32, 'L').convert('P')
pal.putpalette([v for i in range(256) for v in (min(255, i * 30), min(255, i * 20), min(255, i * 10))])
pal.save(OUT / 'palette.png')
add('palette.png', 'png', 'exact')
Image.fromarray(spots(h, w), 'L').save(OUT / 'interlaced.png', interlace=1)
add('interlaced.png', 'png', 'exact')
gamma = Image.fromarray(spots(h, w), 'L')
gamma.save(OUT / 'gamma.png', pnginfo=None)
# A gAMA chunk (0.45455) and an sRGB-free iCCP: decoders must not apply either to the stored values.
raw = (OUT / 'gamma.png').read_bytes()
import struct, zlib
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
ihdr_end = 8 + 25
(OUT / 'gamma.png').write_bytes(raw[:ihdr_end] + chunk(b'gAMA', struct.pack('>I', 45455)) + raw[ihdr_end:])
add('gamma.png', 'png', 'exact')
icc = Image.fromarray(rgb, 'RGB')
from PIL import ImageCms
profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('LAB'))
icc.save(OUT / 'rgb-icc.png', icc_profile=profile.tobytes())
add('rgb-icc.png', 'png', 'exact')
# Grey with alpha (LA) is left out: the reference itself fails on it (rsciio indexes a third channel).

# I2: JPEG, decoded values: grey within 1 level; colour by a tolerance measured on the Mac (stated in the test).
Image.fromarray(spots(16, 16), 'L').save(OUT / 'grey.jpg', quality=95)
add('grey.jpg', 'jpeg', 'level1')
Image.fromarray(spots(16, 16), 'L').save(OUT / 'grey-progressive.jpg', quality=95, progressive=True)
add('grey-progressive.jpg', 'jpeg', 'level1')
crgb = np.stack([spots(16, 16), spots(16, 16) // 2, spots(16, 16) // 3], axis=-1)
Image.fromarray(crgb, 'RGB').save(OUT / 'colour.jpg', quality=95)
add('colour.jpg', 'jpeg', 'colour')
Image.fromarray(crgb, 'RGB').save(OUT / 'colour-progressive.jpg', quality=95, progressive=True)
add('colour-progressive.jpg', 'jpeg', 'colour')

# I3: EXIF orientation 1 to 8 on a non-square PNG (exact) and one JPEG (as I2). The reference is Pillow's exif_transpose.
base = spots(5, 8)
for o in range(1, 9):
    im = Image.fromarray(base, 'L')
    exif = Image.Exif()
    exif[0x0112] = o
    im.save(OUT / f'exif-{o}.png', exif=exif.tobytes())
    add(f'exif-{o}.png', 'png', 'exact', 'PIL.ImageOps.exif_transpose', transpose=True)
im = Image.fromarray(spots(16, 24), 'L')
exif = Image.Exif(); exif[0x0112] = 6
im.save(OUT / 'exif-6.jpg', exif=exif.tobytes(), quality=95)
add('exif-6.jpg', 'jpeg', 'level1', 'PIL.ImageOps.exif_transpose', transpose=True)

# Refused by name: CMYK JPEG, animated PNG, and a picture past the size cap (written by the test, not here).
Image.fromarray(np.zeros((8, 8, 4), np.uint8), 'CMYK').save(OUT / 'cmyk.jpg')
frames = [Image.fromarray(spots(8, 8), 'L') for _ in range(3)]
frames[0].save(OUT / 'animated.png', save_all=True, append_images=frames[1:], duration=100)

pins = {'pillow': PIL.__version__, 'imageio': imageio.__version__, 'rosettasciio': rsciio.__version__,
        'numpy': np.__version__, 'refused': ['cmyk.jpg', 'animated.png'], 'cases': cases}
(OUT / 'pins.json').write_text(json.dumps(pins, indent=0) + '\n')
print(len(cases), 'cases')
