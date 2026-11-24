# tools/size-table/make_files.py: writes the size table's generated files (#904, plan row X12), one per room and kind, of a given
# size in GB (2^30 bytes of stored data), a block at a time so the writer itself never holds more than one block.
#
#   python -I -B make_files.py <out dir> --gb 1 [--kinds image-tiff,stack-tiff,...] [--fixture <ebsd-kikuchipy-h5ebsd.h5>]
#   python -I -B make_files.py --self-test
#
# Needs numpy, h5py, tifffile and mrcfile (the reference venv, tools/lib/python.sh, pins all four). The kinds, after the design's
# size table (suite docs/design/files-exports.md, "The size table and the refusal"):
#
#   image-tiff   Image room   one 16-bit page, square, BigTIFF from 4 GB
#   image-mrc    Image room   one 16-bit MRC image (mode 6), square
#   stack-tiff   Image room   16-bit pages of 4096 x 4096 (32 MiB each), BigTIFF
#   eels-hspy    EELS room    a float32 spectrum image, 2048 channels of 0.25 eV, HyperSpy layout 3.3, signal type EELS
#   eds-hspy     EDS room     a uint16 spectrum image, 2048 channels of 10 eV, HyperSpy layout 3.3, signal type EDS_TEM
#   patterns-h5  Patterns     kikuchipy's h5ebsd layout, the app's fixture's header with a scan of its 60 x 60 uint8 patterns
#
# The values are random (a fixed seed per file), so no reader can take a shortcut on a constant. Each file's name says its kind and
# size: image-tiff-1gb.tif, eels-hspy-4gb.hspy, ...
import argparse
import math
import shutil
import sys
import tempfile
from pathlib import Path

import h5py
import mrcfile
import numpy as np
import tifffile

GIB = 1 << 30
BLOCK = 256 << 20  # bytes written at a time
KINDS = ["image-tiff", "image-mrc", "stack-tiff", "eels-hspy", "eds-hspy", "patterns-h5"]
SUFFIX = {"image-tiff": "tif", "image-mrc": "mrc", "stack-tiff": "tif", "eels-hspy": "hspy", "eds-hspy": "hspy", "patterns-h5": "h5"}
CHANNELS = 2048
FRAME = 4096


def name(kind, gb):
    label = f"{gb:g}gb" if gb >= 1 else f"{round(gb * 1024)}mb"
    return f"{kind}-{label}.{SUFFIX[kind]}"


def rows_per_block(row_bytes):
    return max(1, BLOCK // row_bytes)


def random_rows(rng, n, shape, dtype, high):
    if np.dtype(dtype).kind == "f":
        return (rng.random((n,) + shape, dtype=np.float32) * high).astype(dtype, copy=False)
    return rng.integers(0, high, size=(n,) + shape, dtype=dtype)


def square_side(nbytes, itemsize):
    return max(16, int(math.isqrt(nbytes // itemsize)) // 16 * 16)


def image_tiff(path, nbytes, rng):
    side = square_side(nbytes, 2)
    per = rows_per_block(side * 2)

    def strips():
        for start in range(0, side, per):
            yield random_rows(rng, min(per, side - start), (side,), np.uint16, 4096)

    with tifffile.TiffWriter(path, bigtiff=side * side * 2 >= 2 * GIB) as tif:
        tif.write(strips(), shape=(side, side), dtype=np.uint16, rowsperstrip=per, photometric="minisblack")
    return f"{side} x {side} uint16"


def image_mrc(path, nbytes, rng):
    side = square_side(nbytes, 2)
    per = rows_per_block(side * 2)
    with mrcfile.new_mmap(path, shape=(side, side), mrc_mode=6, overwrite=True) as mrc:
        for start in range(0, side, per):
            n = min(per, side - start)
            mrc.data[start:start + n] = random_rows(rng, n, (side,), np.uint16, 4096)
        mrc.voxel_size = 1.0
    return f"{side} x {side} uint16"


def stack_tiff(path, nbytes, rng):
    frames = max(2, nbytes // (FRAME * FRAME * 2))
    with tifffile.TiffWriter(path, bigtiff=frames * FRAME * FRAME * 2 >= 2 * GIB) as tif:
        for _ in range(frames):
            tif.write(random_rows(rng, FRAME, (FRAME,), np.uint16, 4096), photometric="minisblack", contiguous=True)
    return f"{frames} frames of {FRAME} x {FRAME} uint16"


def hspy_cube(path, nbytes, rng, dtype, signal_type, energy):
    itemsize = np.dtype(dtype).itemsize
    side = max(2, int(math.isqrt(nbytes // (CHANNELS * itemsize))))
    per = rows_per_block(side * CHANNELS * itemsize)
    name_, scale, offset, units = energy
    with h5py.File(path, "w") as f:
        f.attrs["file_format"] = "HyperSpy"
        f.attrs["file_format_version"] = "3.3"
        group = f.create_group("Experiments/__unnamed__")
        data = group.create_dataset("data", shape=(side, side, CHANNELS), dtype=dtype, chunks=(1, min(side, 64), CHANNELS))
        for start in range(0, side, per):
            n = min(per, side - start)
            data[start:start + n] = random_rows(rng, n, (side, CHANNELS), dtype, 100)
        for i, (axis_name, s, o, u, nav, size) in enumerate([("y", 1.0, 0.0, "nm", True, side), ("x", 1.0, 0.0, "nm", True, side),
                                                             (name_, scale, offset, units, False, CHANNELS)]):
            axis = group.create_group(f"axis-{i}")
            axis.attrs.update({"name": axis_name, "size": size, "scale": s, "offset": o, "units": u, "navigate": nav})
        group.create_group("metadata/General").attrs["title"] = Path(path).stem
        group.create_group("metadata/Signal").attrs["signal_type"] = signal_type
        group.require_group("metadata/Acquisition_instrument/TEM").attrs["beam_energy"] = 200.0
    return f"{side} x {side} x {CHANNELS} {np.dtype(dtype).name}"


def patterns_h5(path, nbytes, rng, fixture):
    with h5py.File(fixture, "r") as source:
        scan = next(k for k in source if isinstance(source[k], h5py.Group) and "EBSD" in source[k])
        sy = int(np.ravel(source[f"{scan}/EBSD/Header/pattern_height"][()])[0])
        sx = int(np.ravel(source[f"{scan}/EBSD/Header/pattern_width"][()])[0])
        dtype = source[f"{scan}/EBSD/Data/patterns"].dtype
        side = max(2, int(math.isqrt(nbytes // (sy * sx * dtype.itemsize))))
        with h5py.File(path, "w") as f:
            for key in source:
                if key != scan:
                    source.copy(source[key], f, name=key)
            f.create_group(scan)
            for key in source[scan]:
                if key != "EBSD":
                    source.copy(source[f"{scan}/{key}"], f[scan], name=key)
            source.copy(source[f"{scan}/EBSD/Header"], f.require_group(f"{scan}/EBSD"), name="Header")
            header = f[f"{scan}/EBSD/Header"]
            for key, value in [("n_rows", side), ("n_columns", side)]:
                del header[key]
                header.create_dataset(key, data=np.array([value], dtype=np.int64))
            # One projection centre for the whole scan: the fixture's per-point arrays are its own scan's size.
            for key in ("pcx", "pcy", "pcz"):
                if key in header:
                    first = float(np.ravel(header[key][()])[0])
                    del header[key]
                    header.create_dataset(key, data=np.array([first], dtype=np.float64))
            data = f.create_group(f"{scan}/EBSD/Data")
            patterns = data.create_dataset("patterns", shape=(side * side, sy, sx), dtype=dtype, chunks=(min(side * side, 256), sy, sx))
            per = rows_per_block(sy * sx * dtype.itemsize)
            for start in range(0, side * side, per):
                n = min(per, side * side - start)
                patterns[start:start + n] = random_rows(rng, n, (sy, sx), dtype, 256 if dtype.itemsize == 1 else 4096)
    return f"{side} x {side} scan of {sy} x {sx} {dtype.name}"


def write(kind, out, gb, fixture, seed):
    path = out / name(kind, gb)
    nbytes = int(gb * GIB)
    rng = np.random.default_rng(seed)
    match kind:
        case "image-tiff": shape = image_tiff(path, nbytes, rng)
        case "image-mrc": shape = image_mrc(path, nbytes, rng)
        case "stack-tiff": shape = stack_tiff(path, nbytes, rng)
        case "eels-hspy": shape = hspy_cube(path, nbytes, rng, np.float32, "EELS", ("Energy loss", 0.25, -50.0, "eV"))
        case "eds-hspy": shape = hspy_cube(path, nbytes, rng, np.uint16, "EDS_TEM", ("Energy", 0.01, 0.0, "keV"))
        case "patterns-h5": shape = patterns_h5(path, nbytes, rng, fixture)
        case _: raise SystemExit(f"unknown kind {kind}; the kinds are {', '.join(KINDS)}")
    print(f"{path.name}\t{path.stat().st_size}\t{shape}", flush=True)
    return path


def default_fixture():
    return Path(__file__).resolve().parents[2] / "macTEMTests" / "Fixtures" / "ebsd-kikuchipy-h5ebsd.h5"


def self_test():
    """Each kind at 4 MB, read back with the writing library: the shape and the stored type the app is to read."""
    folder = Path(tempfile.mkdtemp(prefix="size-table-"))
    try:
        for i, kind in enumerate(KINDS):
            path = write(kind, folder, 4 / 1024, default_fixture(), i)
            match kind:
                case "image-tiff" | "stack-tiff":
                    with tifffile.TiffFile(path) as tif:
                        assert tif.pages[0].dtype == np.uint16, kind
                        assert (len(tif.pages) > 1) == (kind == "stack-tiff"), kind
                case "image-mrc":
                    with mrcfile.open(path, permissive=False) as mrc:
                        assert mrc.data.dtype == np.uint16 and mrc.data.ndim == 2
                case "eels-hspy" | "eds-hspy":
                    with h5py.File(path) as f:
                        data = f["Experiments/__unnamed__/data"]
                        assert data.shape[2] == CHANNELS and data.dtype == (np.float32 if kind == "eels-hspy" else np.uint16)
                        assert f["Experiments/__unnamed__/axis-2"].attrs["navigate"] == False  # noqa: E712 (an HDF5 bool)
                case "patterns-h5":
                    with h5py.File(path) as f:
                        scan = next(k for k in f if isinstance(f[k], h5py.Group) and "EBSD" in f[k])
                        rows = int(f[f"{scan}/EBSD/Header/n_rows"][0]) * int(f[f"{scan}/EBSD/Header/n_columns"][0])
                        assert f[f"{scan}/EBSD/Data/patterns"].shape[0] == rows
            assert path.stat().st_size >= 3 << 20, (kind, path.stat().st_size)
        print("make_files self-test: ok")
    finally:
        shutil.rmtree(folder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", nargs="?", type=Path)
    parser.add_argument("--gb", type=float, default=1)
    parser.add_argument("--kinds", default=",".join(KINDS))
    parser.add_argument("--fixture", type=Path, default=default_fixture())
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.out is None:
        parser.error("the out folder is needed")
    args.out.mkdir(parents=True, exist_ok=True)
    kinds = [k for k in args.kinds.split(",") if k]
    need = len(kinds) * args.gb * GIB * 1.05
    free = shutil.disk_usage(args.out).free
    if need > free:
        sys.exit(f"{need / GIB:.1f} GB needed for {len(kinds)} files and {free / GIB:.1f} GB free in {args.out}")
    for i, kind in enumerate(kinds):
        write(kind, args.out, args.gb, args.fixture, 1000 + i)


if __name__ == "__main__":
    main()
