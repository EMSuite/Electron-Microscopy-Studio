"""The 2.3 demo spot pattern (#804, plan row Q21): one frame of pyxem's twinned nanowire 4D-STEM scan (precession, 300 kV, 144 x 144 px, uint8) (pyxem data 0.9.0,
`twinned_nanowire.hdf5`, CC BY 4.0, DOI 10.5281/zenodo.15490547), written as a HyperSpy file of one 2D signal with the scan's own
signal axes and metadata. Run by .github/workflows/public-data.yml (workflow_dispatch, input extract_demo_frame) on GitHub's runner,
which reaches Zenodo; the file is printed to the log as base64 between markers, with its sha256, so a session can take it from the
log and commit it under DemoData/.

The frame: the one with the most spot pixels in an annulus around the direct beam (12 to 60 px from its centre of mass in the mean
pattern; a spot pixel is four times the annulus's median or more), i.e. the clearest Bragg spots of the wire; the scan position is
printed and written into the file's title.

    python3 -I tools/demo/extract-spot-pattern.py <twinned_nanowire.hdf5> <out.hspy> [<y> <x>]

Several frames tie on the score (26 spot pixels); the committed DemoData/twinned_nanowire_frame.hspy is the frame at (y 84, x 26),
which Public data run 45572788710 (2026-11-25) chose and printed, so the workflow now names it: `<y> <x>` takes that frame and
prints the scores all the same.
"""
import base64, hashlib, sys
import h5py
import numpy as np

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


with h5py.File(source, 'r') as f:
    print('root attrs', dict(f.attrs))
    experiments = f['Experiments']
    name = list(experiments.keys())[0]
    exp = experiments[name]
    show(exp, f'/Experiments/{name}')
    data = exp['data']
    print('data', data.shape, data.dtype)
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
    frame = data[iy, ix, :, :]
    print('chosen', (int(iy), int(ix)), 'min', frame.min(), 'max', frame.max(), 'sum', float(np.asarray(frame, dtype=np.float64).sum()))

    with h5py.File(out, 'w', track_order=True) as g:
        for key, value in f.attrs.items():
            g.attrs[key] = value
        gexp = g.create_group('Experiments').create_group(name)
        for key, value in exp.attrs.items():
            gexp.attrs[key] = value
        gexp.create_dataset('data', data=frame, compression='gzip', compression_opts=9, track_times=False)
        # The two signal axes of the scan become the file's two axes, in their order.
        signal_axes = []
        for i in range(4):
            axis = exp[f'axis-{i}']
            if not bool(axis.attrs.get('navigate', i < 2)):
                signal_axes.append(axis)
        assert len(signal_axes) == 2, 'two signal axes'
        for j, axis in enumerate(signal_axes):
            ga = gexp.create_group(f'axis-{j}')
            for key, value in axis.attrs.items():
                ga.attrs[key] = value
            ga.attrs['navigate'] = False
            for key in axis:
                axis.copy(key, ga)
        for key in exp:
            if key in ('data',) or key.startswith('axis-'):
                continue
            exp.copy(key, gexp)
        title = f'Twinned nanowire, frame (y {int(iy)}, x {int(ix)}) of pyxem twinned_nanowire (CC BY 4.0, doi:10.5281/zenodo.15490547)'
        general = gexp.require_group('metadata').require_group('General')
        general.attrs['title'] = title
        print('written', out)

blob = open(out, 'rb').read()
print('sha256', hashlib.sha256(blob).hexdigest(), 'bytes', len(blob))
print('BEGIN-DEMO-FRAME-BASE64')
encoded = base64.b64encode(blob).decode()
for i in range(0, len(encoded), 76):
    print(encoded[i:i + 76])
print('END-DEMO-FRAME-BASE64')
