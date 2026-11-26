"""The 2.3 demo spot pattern (#804, plan row Q21): one frame of pyxem's twinned nanowire 4D-STEM scan (precession, 300 kV, 144 x 144 px, uint8) (pyxem data 0.9.0,
`twinned_nanowire.hdf5`, CC BY 4.0, DOI 10.5281/zenodo.15490547), distortion-corrected and calibrated, written as a HyperSpy file of one
2D signal with the scan's own metadata. Run by .github/workflows/public-data.yml (workflow_dispatch, input extract_demo_frame) on
GitHub's runner, which reaches Zenodo; the file is printed to the log as base64 between markers, with its sha256, so a session can
take it from the log and commit it under DemoData/.

The frame: the one with the most spot pixels in an annulus around the direct beam (12 to 60 px from its centre of mass in the mean
pattern; a spot pixel is four times the annulus's median or more), i.e. the clearest Bragg spots of the wire; the scan position is
printed and written into the file's title.

    python3 -I tools/lib/extract-spot-pattern.py <twinned_nanowire.hdf5> <out.hspy> [<y> <x>]
    python3 -I tools/lib/extract-spot-pattern.py <raw-frame.hspy> <out.hspy>

Several frames tie on the score (26 spot pixels); the committed DemoData/twinned_nanowire_frame.hspy is the frame at (y 84, x 26),
which Public data run 45572788710 (2026-11-25) chose and printed, so the workflow now names it: `<y> <x>` takes that frame and
prints the scores all the same. The second form takes that raw frame as the first commit of the demo shipped it (2026-11-25, md5
1e109a2b19e0e4cff3db9186ea37ac60: `git show 278747a:DemoData/twinned_nanowire_frame.hspy`) and applies the same correction, which is
how the committed file was made (26 Nov 2026); a frame already corrected is refused.

The correction (owner's decision, 26 Nov 2026: the demo ships corrected, with a scale, so Index runs without a typed number):

* Distortion: pyxem-demos notebook "01 GaAs Nanowire - Data Inspection - Preprocessing - Unsupervised Machine Learning", cell 35
  ("Apply distortion corrections to the data due to off-axis acquisition"):
      dp.apply_affine_transformation(np.array([[0.99,0,0], [0,0.69,0], [0,0,1]]), keep_dtype=True)
  pyxem (0.14.1, the notebook's version, and 0.21.0 alike; utils convert_affine_to_transform and apply_transformation) runs
  skimage.transform.warp with (SimilarityTransform(-c) + (AffineTransform(D) + SimilarityTransform(+c))).inverse, c = ((144 - 1) / 2,
  (144 - 1) / 2), order 1, preserve_range, cval 0, then astype(uint8) (truncation). D is in skimage's (x = column, y = row) order:
  the forward map is p' = D (p - c) + c, columns by 0.99 and rows by 0.69 about the centre. Here the same map is
  scipy.ndimage.map_coordinates(frame, [(row - c) / 0.69 + c, (column - c) / 0.99 + c], order=1, mode='grid-constant', cval=0),
  which equals skimage 0.26.0's warp to 1.6e-12 before the cast (mode='constant' does not: it differs at the edges).
* Scale (`SCALE` below): by default the frame's own GaAs {111} spots. A lattice of two basis vectors is fitted to the brightest spots
  of the corrected frame (`lattice`); the scale is sqrt(3) / a / mean(|g1|, |g2|) with a = 5.6535 Å (GaAs, the tutorial's value).
  That is a calibration on this frame itself, not an independent one: Index on the demo finds GaAs {111} at 0.3064 Å⁻¹ by
  construction. The tutorial's own value, recip_cal = sqrt(3 / 5.6535**2) / 11.4 (cell 43, read off the beam-centred mean of the
  whole scan), puts {111} of this frame 5.6 % short (10.77 px, not 11.4).
"""
import base64, hashlib, sys
import h5py
import numpy as np
from scipy import ndimage

# The affine distortion correction of pyxem tutorial 01 (skimage's x, y order), applied about the pattern's centre.
AFFINE = np.array([[0.99, 0.0, 0.0], [0.0, 0.69, 0.0], [0.0, 0.0, 1.0]])
GAAS_A = 5.6535  # Å, the tutorial's lattice parameter
TUTORIAL_SCALE = np.sqrt(3 / GAAS_A**2) / 11.4  # Å⁻¹ per pixel, tutorial cell 43
# The scale the file carries: 'frame-111' (the frame's own GaAs {111}, the default), 'tutorial' (TUTORIAL_SCALE), or None (no scale:
# the axes stay in pixels, as the scan's). A change here is a new file: run the script again and update NOTICE and the app's pins.
SCALE = 'frame-111'
# The mean pattern (owner, 26 Nov 2026: one 144 px frame is too noisy for a demo): the frames of the scan whose spots correlate with the
# chosen frame's at MEAN_CORRELATION or more (background-subtracted annulus, Pearson), at most MEAN_FRAMES of the best, are averaged
# before the correction, as pyxem's tutorial averages frames of one region; the mean is kept as float32 (no cast back to uint8).
# None keeps the single frame.
MEAN_CORRELATION = 0.5
MEAN_FRAMES = 64
# The correction leaves rows 0 to 21 and 122 to 143 empty (rows x 0.69, cval 0), and their zero background puts false spots at the
# band edges: the file keeps the central square rows and columns CROP[0] to CROP[1] - 1 (the pattern's centre stays the square's).
CROP = (22, 122)
CORRECTED_NOTE = 'Distortion-corrected with pyxem tutorial 01'

source, out = sys.argv[1], sys.argv[2]


def show(group, prefix=''):
    for key, value in group.attrs.items():
        print(f'attr {prefix}@{key} = {value!r}'[:300])
    for key in group:
        item = group[key]
        if isinstance(item, h5py.Group):
            show(item, f'{prefix}/{key}')
        else:
            print(f'dataset {prefix}/{key} {item.shape} {item.dtype}')


def correct(frame):
    """pyxem's apply_affine_transformation(AFFINE, keep_dtype=True) on one frame (see the module's notes)."""
    sy, sx = frame.shape
    cy, cx = (sy - 1) / 2, (sx - 1) / 2
    inverse = np.linalg.inv(AFFINE)
    rows, cols = np.mgrid[0:sy, 0:sx].astype(np.float64)
    src_x = inverse[0, 0] * (cols - cx) + inverse[0, 1] * (rows - cy) + inverse[0, 2] + cx
    src_y = inverse[1, 0] * (cols - cx) + inverse[1, 1] * (rows - cy) + inverse[1, 2] + cy
    warped = ndimage.map_coordinates(np.asarray(frame, dtype=np.float64), [src_y, src_x], order=1, mode='grid-constant', cval=0.0)
    return warped.astype(frame.dtype)


def spots(image, count=30):
    """The brightest local maxima (7 px neighbourhood, 1 px Gaussian, top 1.5 %), each at its centroid over a 9 px median background."""
    image = np.asarray(image, dtype=np.float64)
    smooth = ndimage.gaussian_filter(image, 1.0)
    background = ndimage.median_filter(image, 9)
    peaks = np.argwhere((smooth == ndimage.maximum_filter(smooth, 7)) & (smooth > np.percentile(smooth, 98.5)))
    found = []
    for y, x in peaks:
        y0, y1, x0, x1 = max(y - 3, 0), min(y + 4, image.shape[0]), max(x - 3, 0), min(x + 4, image.shape[1])
        s = np.clip(image[y0:y1, x0:x1] - background[y0:y1, x0:x1], 0, None)
        if s.sum() <= 0:
            continue
        gy, gx = np.mgrid[y0:y1, x0:x1]
        found.append(((s * gy).sum() / s.sum(), (s * gx).sum() / s.sum(), smooth[y, x]))
    found.sort(key=lambda t: (-t[2], t[0], t[1]))
    return np.array(found[:count])[:, :2]


def lattice(image):
    """A 2D lattice (centre, g1, g2 in (row, column) px) least-squares fitted to the spots; the start is the brightest spot as the centre,
    its nearest spot as g1 and the nearest spot off g1's line (30 degrees or more) as g2. Refuses a fit that is not GaAs <110>-like."""
    points = spots(image)
    centre = points[0]
    d = points[1:] - centre
    r = np.hypot(d[:, 0], d[:, 1])
    order = np.argsort(r)
    g1 = d[order[0]]
    g2 = next(d[k] for k in order[1:] if abs(d[k] @ g1) / (np.hypot(*d[k]) * np.hypot(*g1)) < np.cos(np.radians(30)))
    basis = np.vstack([g1, g2]).T
    for _ in range(5):
        hk = np.round(np.linalg.solve(basis, (points - centre).T).T)
        residual = (points - centre) - hk @ basis.T
        on = np.hypot(residual[:, 0], residual[:, 1]) < 1.5
        design = np.hstack([np.ones((on.sum(), 1)), hk[on]])
        solution = np.linalg.lstsq(design, points[on], rcond=None)[0]
        centre, basis = solution[0], solution[1:].T
    rms = np.sqrt((((points[on] - centre) - hk[on] @ basis.T) ** 2).sum(axis=1).mean())
    g1, g2 = basis[:, 0], basis[:, 1]
    n1, n2 = np.hypot(*g1), np.hypot(*g2)
    angle = np.degrees(np.arccos(abs(g1 @ g2) / (n1 * n2)))
    print(f'lattice: centre (row {centre[0]:.3f}, column {centre[1]:.3f}), {on.sum()} of {len(points)} spots, rms {rms:.3f} px; '
          f'|g1| {n1:.4f} px, |g2| {n2:.4f} px, ratio {n1 / n2:.4f}, angle {angle:.2f} deg (GaAs 111 to 11-1 in <110>: 70.53)')
    # GaAs <110>: two {111} of equal length at 70.53 degrees. A frame or a correction that is not refuses here.
    # The cropped 100 px mean pattern holds fewer maxima above the 98.5th percentile (10 on 26 Nov 2026, rms 0.2 px): 8 will do.
    assert on.sum() >= 8 and on.sum() >= 0.6 * len(points) and rms < 1.0, 'the spots are not one lattice'
    assert abs(n1 / n2 - 1) < 0.03 and abs(angle - 70.53) < 2, 'the lattice is not two {111} at 70.5 degrees: not GaAs <110>'
    return centre, g1, g2


def scale_of(frame):
    if SCALE is None:
        return None
    if SCALE == 'tutorial':
        return float(TUTORIAL_SCALE)
    assert SCALE == 'frame-111', SCALE
    _, g1, g2 = lattice(frame)
    return float(np.sqrt(3) / GAAS_A / ((np.hypot(*g1) + np.hypot(*g2)) / 2))


with h5py.File(source, 'r') as f:
    print('root attrs', dict(f.attrs))
    experiments = f['Experiments']
    name = list(experiments.keys())[0]
    exp = experiments[name]
    show(exp, f'/Experiments/{name}')
    data = exp['data']
    print('data', data.shape, data.dtype)
    if data.ndim == 4:
        stack = np.asarray(data[...], dtype=np.float64)
        ny, nx, sy, sx = stack.shape
        mean = stack.mean(axis=(0, 1))
        yy, xx = np.mgrid[0:sy, 0:sx]
        cy, cx = (mean * yy).sum() / mean.sum(), (mean * xx).sum() / mean.sum()
        r = np.hypot(yy - cy, xx - cx)
        ring = (r >= 12) & (r <= 60)
        # Spots, not background: the pixels of the annulus at four times or more its median (the frames are noisy, so a plain sum
        # picks the brightest background, not the sharpest spots).
        annulus = stack[:, :, ring]
        median = np.median(annulus, axis=2, keepdims=True)
        score = (annulus >= 4 * np.maximum(median, 1)).sum(axis=2).astype(np.float64)
        order = np.argsort(score, axis=None)[::-1]
        print(f'centre of mass of the mean pattern: ({cy:.2f}, {cx:.2f}); annulus score mean {score.mean():.1f}')
        for k in order[:10]:
            print('top', np.unravel_index(k, score.shape), f'{score.flat[k]:.1f}')
        iy, ix = np.unravel_index(order[0], score.shape)
        if len(sys.argv) == 5:
            iy, ix = int(sys.argv[3]), int(sys.argv[4])
            print('named', (iy, ix), 'score', score[iy, ix])
        raw = data[iy, ix, :, :]
        averaged = None
        if MEAN_CORRELATION is not None:
            background = np.median(annulus, axis=2, keepdims=True)
            signal = annulus - background
            signal -= signal.mean(axis=2, keepdims=True)
            norm = np.sqrt((signal ** 2).sum(axis=2))
            chosen = signal[iy, ix]
            corr = (signal * chosen).sum(axis=2) / np.maximum(norm * norm[iy, ix], 1e-12)
            ranked = np.argsort(corr, axis=None)[::-1]
            take = [k for k in ranked[:MEAN_FRAMES] if corr.flat[k] >= MEAN_CORRELATION]
            positions = [tuple(int(v) for v in np.unravel_index(k, corr.shape)) for k in take]
            print(f'mean of {len(take)} frames, correlation {corr.flat[take[-1]]:.3f} to 1 with the chosen one:', positions)
            averaged = stack.reshape(ny * nx, sy, sx)[take].mean(axis=0)
    else:
        # The raw frame the demo first shipped: its position is the one its title names.
        assert data.ndim == 2, 'a 4D scan or one raw 2D frame'
        general = exp['metadata/General'].attrs
        assert CORRECTED_NOTE not in str(general.get('notes', '')), 'this frame is already corrected'
        iy, ix = 84, 26
        assert f'frame (y {iy}, x {ix})' in str(general['title']), 'the raw demo frame (y 84, x 26)'
        raw = data[...]
        averaged = None
    print('chosen', (int(iy), int(ix)), 'min', raw.min(), 'max', raw.max(), 'sum', float(np.asarray(raw, dtype=np.float64).sum()))
    if averaged is not None:
        frame = correct(averaged).astype(np.float32)
    else:
        frame = correct(raw)
    if CROP is not None:
        assert np.all(frame[CROP[0]:CROP[1]].sum(axis=1) > 0), 'the crop holds an empty row'
        frame = frame[CROP[0]:CROP[1], CROP[0]:CROP[1]]
    print('corrected', frame.shape, frame.dtype, 'max', frame.max(), 'sum', float(np.asarray(frame, dtype=np.float64).sum()))
    scale = scale_of(frame)
    print('scale', repr(scale), 'Å⁻¹ per pixel', f'(the tutorial: {TUTORIAL_SCALE!r})')

    with h5py.File(out, 'w', track_order=True) as g:
        for key, value in f.attrs.items():
            g.attrs[key] = value
        gexp = g.create_group('Experiments').create_group(name)
        for key, value in exp.attrs.items():
            gexp.attrs[key] = value
        gexp.create_dataset('data', data=frame, compression='gzip', compression_opts=9, track_times=False)
        # The two signal axes of the scan become the file's two axes, in their order, with the scale in Å⁻¹ per pixel; the offset stays
        # 0 (zero at pixel 0, as the scan's axes had it; the app's Diffraction room starts its centre at the middle pixel, not at the axis zero).
        signal_axes = []
        for i in range(data.ndim):
            axis = exp[f'axis-{i}']
            if not bool(axis.attrs.get('navigate', i < data.ndim - 2)):
                signal_axes.append(axis)
        assert len(signal_axes) == 2, 'two signal axes'
        for j, axis in enumerate(signal_axes):
            ga = gexp.create_group(f'axis-{j}')
            for key, value in axis.attrs.items():
                ga.attrs[key] = value
            ga.attrs['navigate'] = False
            if scale is not None:
                ga.attrs['scale'] = np.float64(scale)
                ga.attrs['offset'] = np.float64(0.0)
                ga.attrs['units'] = 'Å⁻¹'
            for key in axis:
                axis.copy(key, ga)
        for key in exp:
            if key in ('data',) or key.startswith('axis-'):
                continue
            exp.copy(key, gexp)
        what = f'mean of {len(take)} frames like frame (y {int(iy)}, x {int(ix)})' if averaged is not None else f'frame (y {int(iy)}, x {int(ix)})'
        title = (f'Twinned nanowire, {what} of pyxem twinned_nanowire, distortion-corrected '
                 f'(CC BY 4.0, doi:10.5281/zenodo.15490547)')
        general = gexp.require_group('metadata').require_group('General')
        general.attrs['title'] = title
        if scale is None:
            how = 'No scale: the axes are in pixels, as the scan\'s.'
        elif SCALE == 'tutorial':
            how = f'Scale {scale!r} 1/Å per pixel: the tutorial\'s recip_cal = sqrt(3/5.6535**2)/11.4 (cell 43).'
        else:
            how = (f'Scale {scale!r} 1/Å per pixel, calibrated on GaAs {{111}} of this frame itself (a = 5.6535 Å; sqrt(3)/a over '
                   f'the mean |g| of the two {{111}} of a lattice fitted to the spots): NOT an independent calibration. The tutorial\'s '
                   f'own value, {TUTORIAL_SCALE:.5f} 1/Å per pixel read off the scan\'s mean pattern, puts {{111}} 5.6 % short in this frame.')
        general.attrs['notes'] = (
            f'{CORRECTED_NOTE} (pyxem-demos, "01 GaAs Nanowire - Data Inspection - Preprocessing - Unsupervised Machine Learning"): '
            'apply_affine_transformation([[0.99,0,0],[0,0.69,0],[0,0,1]], keep_dtype=True), skimage warp convention (x 0.99, '
            'y 0.69 about the pattern centre ((144-1)/2, (144-1)/2)), order 1'
            + (f', of the mean of the {len(take)} frames whose spots correlate {MEAN_CORRELATION} or more with frame '
               f'(y {int(iy)}, x {int(ix)}), kept as float32' if averaged is not None else ', cast back to uint8')
            + (f'; cropped to rows and columns {CROP[0]} to {CROP[1] - 1}, the rows the correction fills. ' if CROP else '. ') + how
            + ' Written by tools/lib/extract-spot-pattern.py (Electron Microscopy Studio).')
        print('written', out)

blob = open(out, 'rb').read()
print('sha256', hashlib.sha256(blob).hexdigest(), 'md5', hashlib.md5(blob).hexdigest(), 'bytes', len(blob))
print('BEGIN-DEMO-FRAME-BASE64')
encoded = base64.b64encode(blob).decode()
for i in range(0, len(encoded), 76):
    print(encoded[i:i + 76])
print('END-DEMO-FRAME-BASE64')
