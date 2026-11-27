"""The tilted CBED pin (#1013): Si [1 1 0] at 200 kV, a 3.9 mrad probe tilted to excite 2 2̄ 0, run by abTEM 1.0.10 exactly as
the app's `CBEDRun.run` runs SimulatoKit's (the same slab, box, grid, probe, tilt, stored planes and crop), and the summed
intensity of each disc of the zero-order zone at each stored thickness.

Run (an abTEM 1.0.10 venv: python3 -m venv v && v/bin/pip install abtem==1.0.10; numpy 2.5.5, scipy 1.18.1, ase 3.29.0; about
a minute):
    <venv>/bin/python -I -B tools/parity/cbed-tilt/cbed_tilt.py [out.json]
Writes EMStudioTests/Fixtures/cbed-tilt.json, which `CBEDTiltTests` reads. float64 throughout.

The frame (the app's, row = lab x, column = lab y, #931): SimulatoKit's slab of Si [1 1 0] puts box x along [0 0 1̄] (py4DSTEM's
x reference, the shortest lattice row at right angles to the zone), y = z × x along [1̄ 1 0], and z along [1 1 0], pointing at
the source; it then mirrors every period to depth (z -> period - z) and shifts the atoms along z by the j h / 720 that keeps
the planes farthest from a slice boundary, and the multislice transmits along +z. The tilt (tx, ty) [mrad] is abTEM's
`Probe(tilt=...)`: the propagator carries exp(-2 pi i (kx tan tx + ky tan ty) dz), so the beam's transverse wave vector is
tan(t) / lambda and a zero-order reflection g meets its Bragg condition at t . g = -lambda |g|^2 / 2. 2 2̄ 0 lies along -y,
|g| = sqrt(8) / a, so its Bragg tilt is ty = +lambda |g| / 2 = +6.53 mrad (to the app's 0.01 mrad); tx = 45 mrad, at right
angles to g, takes the beam off the 1 1 1 discs and the other zero-order reflections (every other |s| at least 0.005 1/Å) so
that 2 2̄ 0 is the one strong reflection: the tilt of CBEDTiltTests' Measure Thickness run, 2.6° off [1 1 0].

Each disc's intensity is the sum of the cropped pattern over the pixels within the semiangle of the disc's centre, the centre
at g / dq from the direct beam's pixel (rows / 2, columns / 2); the numbers are fractions of the probe's intensity.
"""
import itertools
import json
import math
import sys
import warnings
from pathlib import Path

import numpy as np

warnings.filterwarnings("ignore")
import abtem  # noqa: E402
import dask  # noqa: E402
from abtem.core.energy import energy2wavelength  # noqa: E402
from ase import Atoms  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "EMStudioTests/Fixtures/cbed-tilt.json"
dask.config.set(scheduler="synchronous")
abtem.config.set({"local_diagnostics.progress_bar": False, "precision": "float64"})

A = 5.4309  # DiffractoKit's CrystalPresets.silicon
E0 = 200e3
LAMBDA = energy2wavelength(E0)
# The box axes in the cubic frame (rows): the app's slab of Si [1 1 0].
EX = np.array([0.0, 0.0, -1.0])
EZ = np.array([1.0, 1.0, 0.0]) / math.sqrt(2)
EY = np.cross(EZ, EX)
R = np.array([EX, EY, EZ])
L = np.array([A, A * math.sqrt(2), A / math.sqrt(2)])
SLICE = 1.0  # SimulationSpecimen.sliceThickness
# The pinned run's CBEDSettings: a 1.5 mrad step asked (the square box of 7 x 5 units gives 0.66 mrad per pixel), the edge at
# 40 mrad, patterns at 10 and 20 nm.
STEP, EDGE, LARGEST, EVERY = 1.5, 40.0, 20.0, 10.0


def unit():
    """The orthogonal unit (8 atoms), its z pointing at the source, before the shift and the mirror."""
    fcc = np.array([[0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0]])
    basis = np.vstack([fcc, fcc + 0.25])
    found = {}
    for n in itertools.product(range(-3, 4), repeat=3):
        for b in basis:
            p = R @ ((np.array(n) + b) * A)
            f = p / L
            f = f - np.floor(f)
            f[np.abs(f - 1) < 1e-9] = 0
            f[np.abs(f) < 1e-9] = 0
            found[tuple(np.round(f, 9))] = f * L
    atoms = np.array(list(found.values()))
    assert len(atoms) == 8, len(atoms)
    return atoms


def slab_unit():
    """The unit as SimulatoKit's `SlabBuilder.slab` makes it: shifted along z, wrapped, mirrored to depth."""
    atoms = unit()
    k = math.ceil(L[2] / SLICE)
    h = L[2] / k
    zs = sorted(set(atoms[:, 2]))

    def margin(shift):
        return min(abs((z + shift) / h - math.floor((z + shift) / h + 0.5)) * h for z in zs)

    best_j, best_f = 0, -1.0
    for j in range(720):
        f = round(margin(j * h / 720) * 1e9) / 1e9
        if f > best_f:
            best_j, best_f = j, f
    shift = best_j * h / 720

    def into(z):
        w = math.fmod(z, L[2])
        return w + L[2] if w < 0 else w

    out = atoms.copy()
    out[:, 2] = [into(L[2] - into(z + shift)) for z in atoms[:, 2]]
    return out, k, h


def square_repeats(unit_xy, reach, tol=0.005):
    """`CBEDRun.squareRepeats`."""
    low_x = max(1, math.ceil(reach / unit_xy[0] - 1e-9))
    low_y = max(1, math.ceil(reach / unit_xy[1] - 1e-9))
    square, closest = None, ((low_x, low_y), math.inf)
    for nx in range(low_x, 2 * low_x + 1):
        for ny in range(low_y, 2 * low_y + 1):
            a, b = nx * unit_xy[0], ny * unit_xy[1]
            mismatch = abs(a - b) / max(a, b)
            if mismatch <= tol and (square is None or a * b < square[1]):
                square = ((nx, ny), a * b)
            if mismatch < closest[1]:
                closest = ((nx, ny), mismatch)
    return square[0] if square else closest[0]


def fft_friendly(n):
    m = max(1, n)
    while True:
        k = m
        for p in (2, 3, 5):
            while k % p == 0:
                k //= p
        if k == 1:
            return m
        m += 1


def schoolbook_round(x):
    return math.floor(x + 0.5)


def plan(step_mrad, edge_mrad, largest_nm, step_nm):
    """`CBEDRun.plan`: the repeats across, the grid and the stored periods."""
    reach = LAMBDA / (step_mrad / 1000)
    repeats = square_repeats(L[:2], reach)
    sampling = min(0.05, LAMBDA / (3 * edge_mrad * 1e-3))
    unit_grid = (fft_friendly(math.ceil(L[0] / sampling)), fft_friendly(math.ceil(L[1] / sampling)))
    period_nm = L[2] / 10
    periods = max(1, schoolbook_round(largest_nm / period_nm))
    planes, t = [], step_nm
    while t <= largest_nm + 1e-9:
        p = min(periods, max(1, schoolbook_round(t / period_nm)))
        if not planes or planes[-1] != p:
            planes.append(p)
        t += step_nm
    if planes[-1] != periods:
        planes.append(periods)
    return repeats, (repeats[0] * unit_grid[0], repeats[1] * unit_grid[1]), planes


def run(tilt, alpha=3.9, step_mrad=1.0, edge_mrad=40.0, largest_nm=20.0, step_nm=10.0):
    """The patterns of `CBEDRun.run` at each stored thickness, cropped to the edge, and the grid facts."""
    atoms, k, h = slab_unit()
    repeats, grid, planes = plan(step_mrad, edge_mrad, largest_nm, step_nm)
    across = Atoms("Si8", positions=atoms, cell=L, pbc=True) * (repeats[0], repeats[1], 1)
    extent = (repeats[0] * L[0], repeats[1] * L[1])
    unit_potential = abtem.Potential(across, gpts=grid, slice_thickness=h, projection="infinite", parametrization="lobato")
    probe = abtem.Probe(semiangle_cutoff=alpha, energy=E0, tilt=tuple(tilt))
    probe.grid.match(unit_potential)
    wave = probe.build(scan=(extent[0] / 2, extent[1] / 2)).compute()
    edge = edge_mrad / 1000
    patterns, done = [], 0
    for plane in planes:
        stretch = abtem.CrystalPotential(unit_potential, repetitions=(1, 1, plane - done))
        wave = wave.multislice(stretch).compute()
        field = wave.diffraction_patterns(max_angle="cutoff").compute()
        values = np.asarray(field.array, dtype=np.float64)
        dq = field.sampling
        nx, ny = values.shape
        half_r = min(nx // 2, math.ceil(edge / (dq[0] * LAMBDA)))
        half_c = min(ny // 2, math.ceil(edge / (dq[1] * LAMBDA)))
        r0, c0 = nx // 2 - half_r, ny // 2 - half_c
        patterns.append(values[r0:r0 + 2 * half_r + 1, c0:c0 + 2 * half_c + 1])
        done = plane
    return dict(patterns=patterns, dq=dq, thicknesses=[p * L[2] / 10 for p in planes], grid=grid, repeats=repeats)


def g_box(hkl):
    return R @ (np.asarray(hkl, float) / A)


def zone_reflections(limit=0.8):
    """The zero-order-zone reflections of Si [1 1 0] (h + k = 0) of the face-centred lattice (h, k, l unmixed), up to
    |g| = limit 1/Å, the direct beam first. 0 0 2 and its kind are kept: the diamond glide forbids them kinematically, and
    double diffraction lights them."""
    out = [(0, 0, 0)]
    for hkl in itertools.product(range(-4, 5), repeat=3):
        h, k, l = hkl
        if hkl == (0, 0, 0) or h + k != 0 or len({h % 2, k % 2, l % 2}) != 1:
            continue
        if np.linalg.norm(np.asarray(hkl) / A) <= limit:
            out.append(hkl)
    return out


def disc_sums(pattern, dq, alpha):
    rows, columns = pattern.shape
    centre = np.array([rows // 2, columns // 2], float)
    rr, cc = np.meshgrid(np.arange(rows), np.arange(columns), indexing="ij")
    radius_r = alpha / 1000 / (dq[0] * LAMBDA)
    radius_c = alpha / 1000 / (dq[1] * LAMBDA)
    out = {}
    for hkl in zone_reflections():
        g = g_box(hkl)
        at = centre + np.array([g[0] / dq[0], g[1] / dq[1]])
        inside = ((rr - at[0]) / radius_r) ** 2 + ((cc - at[1]) / radius_c) ** 2 <= 1
        out["%d %d %d" % hkl] = float(pattern[inside].sum())
    return out


def main():
    tilt = (45.0, round(LAMBDA * math.sqrt(8) / A * 1000 / 2, 2))
    result = run(tilt, step_mrad=STEP, edge_mrad=EDGE, largest_nm=LARGEST, step_nm=EVERY)
    cases = []
    for t, pattern in zip(result["thicknesses"], result["patterns"]):
        sums = disc_sums(pattern, result["dq"], 3.9)
        bright = max((key for key in sums if key != "0 0 0"), key=lambda key: sums[key])
        cases.append({"thickness_nm": t, "discs": sums, "brightest_diffracted": bright, "total": float(pattern.sum())})
        print(f"{t:.3f} nm: brightest diffracted {bright} {sums[bright]:.5f}, 0 0 0 {sums['0 0 0']:.5f}, "
              f"2 -2 0 {sums['2 -2 0']:.5f}, -2 2 0 {sums['-2 2 0']:.5f}, sum {pattern.sum():.5f}")
    doc = {
        "source": "tools/parity/cbed-tilt/cbed_tilt.py: abTEM " + abtem.__version__ + ", numpy " + np.__version__ + ", float64",
        "specimen": "Si [1 1 0], a = 5.4309 Å, Lobato, infinite projection",
        "volts": E0, "semiangle_mrad": 3.9, "tilt_mrad": list(tilt),
        "settings": {"angular_step_mrad": STEP, "edge_mrad": EDGE, "largest_thickness_nm": LARGEST, "thickness_step_nm": EVERY},
        "grid": list(result["grid"]), "repeats": list(result["repeats"]), "dq": list(result["dq"]),
        "shape": list(result["patterns"][0].shape),
        "cases": cases,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1) + "\n")


if __name__ == "__main__":
    main()
