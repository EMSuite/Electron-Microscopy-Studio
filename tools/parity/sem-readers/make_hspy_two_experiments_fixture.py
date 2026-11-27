# tools/parity/sem-readers/make_hspy_two_experiments_fixture.py — writes hyperspy-image-and-eels.hspy for EMStudioTests (#820, plan row X4).
#
#   python -I -B make_hspy_two_experiments_fixture.py <out dir>   (h5py 3.16.0, NumPy 2.5.4)
#
# A HyperSpy file may hold several signals, one group under /Experiments each (hs.save of a list, or a file gathered by hand). This
# writes HyperSpy's layout 3.3 with two: a 3 x 4 uint16 survey image (values 0..11, 0.5 nm a pixel) and a 2 x 2 x 5 float32 EELS
# spectrum image (values 0.5 * i, 2 nm a pixel, 0.25 eV a channel from -1 eV, 200 kV), so the Open route can be checked to send
# each to its room, as a Velox file's image and EELS stream go.
import sys
from pathlib import Path
import h5py
import numpy as np

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def experiment(f, name, data, axes, signal_type, extra=None):
    group = f.create_group(f"Experiments/{name}")
    group.create_dataset("data", data=data)
    for i, (axis_name, scale, offset, units, navigate) in enumerate(axes):
        axis = group.create_group(f"axis-{i}")
        axis.attrs["name"] = axis_name
        axis.attrs["size"] = data.shape[i]
        axis.attrs["scale"] = scale
        axis.attrs["offset"] = offset
        axis.attrs["units"] = units
        axis.attrs["navigate"] = navigate
    group.create_group("metadata/General").attrs["title"] = name
    group.create_group("metadata/Signal").attrs["signal_type"] = signal_type
    for path, (key, value) in (extra or {}).items():
        group.require_group("metadata/" + path).attrs[key] = value


with h5py.File(out / "hyperspy-image-and-eels.hspy", "w") as f:
    f.attrs["file_format"] = "HyperSpy"
    f.attrs["file_format_version"] = "3.3"
    experiment(f, "survey", np.arange(12, dtype=np.uint16).reshape(3, 4),
               [("y", 0.5, 0.0, "nm", False), ("x", 0.5, 0.0, "nm", False)], "")
    experiment(f, "core", (0.5 * np.arange(20, dtype=np.float32)).reshape(2, 2, 5),
               [("y", 2.0, 0.0, "nm", True), ("x", 2.0, 0.0, "nm", True), ("Energy loss", 0.25, -1.0, "eV", False)], "EELS",
               {"Acquisition_instrument/TEM": ("beam_energy", 200.0)})
print(out / "hyperspy-image-and-eels.hspy")
