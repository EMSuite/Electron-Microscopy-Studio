# Performance (UI-driven, 2026-10-21)

`tools/run-tests.sh ui PerformanceJourney` (not in the default `ui` run). `macTEMUITests/PerformanceJourney.swift`: five iterations per
action, each a fresh launch of the real app (Debug, kits `-O`) on the generated demo documents; the measured span runs from the click to the
element that shows the result. Machine: MacBook Pro, Apple M5 Pro (Mac17,9), macOS 27.0.1. Build: macTEM before v1.0.0 (history squashed), plus the signposts. Medians of five;
the range is under 3 % everywhere except the memory peak of the EDX action (240 to 245 MB).

| Action (demo document) | Wall clock (driver) | In the app (signpost) | Peak memory | CPU time |
|---|---|---|---|---|
| Open the demo image (launch to the file listed; 512 x 512) | 1.88 s | none (the demo is built in memory, not read from a file) | 184 MB | 0.66 s |
| FFT: click a spot, read d, then Find Spots (512 x 512) | 5.62 s | spot 2.4 ms, finder 17 ms (the transform runs before the window) | 269 MB | 2.38 s |
| EDX: Quantify to the composition table (spectrum image, pooled fit) | 2.88 s | 693 ms (spectrum, windows, fit) | 239 MB | 8.99 s |
| EELS: launch, room, a pixel's t/λ (16 x 16 x 1024) | 6.42 s (includes the launch) | map 102 ms | 170 MB | 1.16 s |
| Particles: Show Objects to the count (512 x 512, five discs) | 4.91 s | 15 ms | 264 MB | 1.27 s |
| Stack: Next to frame 2 shown (24 frames of 128 x 128) | 3.76 s | frame read 0.4 ms | 195 MB | 1.15 s |

Signposts are the median of five intervals inside the app (`Signposts` in `TEMCore`: `fft.spectrum`, `fft.spot`, `fft.find`, `edx.refresh`, `eels.map`,
`particles.analyse`, `stack.frame`, `open.image`), read by `XCTOSSignpostMetric` beside the clock. The demo documents are small and planted; the
real-data numbers (a 2048 x 2048 image, a full EDX cube) come with the owner's files.

## Launch and first-picture budgets (2.3)

`PerformanceJourney` also measures the launch itself: `testLaunchToTheWindow` (launch to the empty window's first control) and
`testLaunchToTheFirstPictureOfA2048Image` / `…4096Image` (launch with `--demo-large-image <n>`, a generated n x n 16-bit TIFF the app
writes to its temporary folder once, to the Image room's picture reading its size; signpost `open.image`). The file is written by an
unmeasured launch before the five measured ones, so the clock covers reading and drawing, not writing.

| Launch to (generated file) | Wall clock (driver) | In the app (`open.image`) | Peak memory | CPU time |
|---|---|---|---|---|
| The empty window | to come | none | to come | to come |
| The first picture, 2048 x 2048 16-bit | to come | to come | to come | to come |
| The first picture, 4096 x 4096 16-bit | to come | to come | to come | to come |

The baseline comes from one Mac pass (`tools/run-tests.sh ui PerformanceJourney/testLaunchToTheWindow
PerformanceJourney/testLaunchToTheFirstPictureOfA2048Image PerformanceJourney/testLaunchToTheFirstPictureOfA4096Image`); a later
pass more than 25 % slower on the same Mac is a regression to explain before a release.

## How to read these

The clock includes XCUITest's own cost: each `waitFor` / `waitValue` is an accessibility query of the window, and a click is a synthesized
event. The stack step reads one small frame from disk and costs 3.8 s, so about 3 s of every clock figure above is the driver, not the app (the signposts show it: the frame read takes 0.4 ms). Treat
the table as a regression guard (the same action should stay within a few percent run to run, as it does here), and as an upper bound
per action; it does not rank the actions against each other. CPU time is the app's own and does show real work: the EDX fit is the one action
that uses several cores (8.9 s of CPU in 2.9 s of wall clock).

The signpost column is the app's own compute time and is what to compare between commits; the clock column is the user-visible total with the driver's cost in it. A signpost that is not listed for an action ran before the measured window (the FFT transform runs when the room opens).

## SEM rooms (signposts in place, numbers to come)

The SEM rooms carry their own signposts in the same subsystem: `sem.map` (the navigation map's pass at the open, with the scan's mean
riding on it), `sem.quality` (image quality and dot product maps), `sem.process` (a Patterns room Process run), `sem.index.hough` and
`sem.index.dictionary` (an Indexing room run, from the plan to the last row or block), and `maps.segment` (a Maps room Segment). Instruments
shows them under the `performance` category. Their rows join the table above when they are measured on the owner's files (the Instruments
pass, #594); the demo scan (55 x 75 patterns) is too small to say anything about a real one.

Memory over a scan is a unit test, not a row here: `SEMMemoryTests` writes a 72 MB record file and checks that the map pass, the mean pass
and the Hough row loop each grow the process footprint by a few scan rows, never by the scan.

## Size table (2.5, #904)

What each room needs to open a large file: the app's peak memory footprint and its footprint at rest after the open, over the
file's stored bytes, each counted above the empty app's footprint. These factors are what the size rule (#905) uses to refuse a file
this Mac cannot hold before it reads it. Quality bar 3 sets the targets: 3 at the peak and 2 at rest.

The files are generated, a 1, 4 and 16 GB one of each kind, with random values (`tools/size-table/make_files.py`): a 16-bit TIFF
image, a 16-bit MRC image and a TIFF stack of 4096 x 4096 frames for the Image room, a float32 EELS and a uint16 EDS spectrum image
as HyperSpy files, and a kikuchipy h5ebsd scan of 60 x 60 patterns for the Patterns room. `tools/size-table/size_table.py` launches
the app once per file, opens it through the agent door's `open_file` (the File > Open path), waits until every room is idle and reads
the footprint from `get_window` (`ProcessMemory`: the kernel's `phys_footprint` and its peak since launch). `tools/size-table/run.sh`
runs it all, one size at a time; the harness ends the app by its pid when its footprint passes this Mac's memory minus 4 GB and
writes that row, under the suite's memory cap as a looser outer guard. The rule counts stored bytes: a compressed HyperSpy cube or
a sparse Velox EDS stream holds more once read, so its row in this table is what to trust for it. It is a step of the release plan,
once per feature release.

| Room | File | Stored | Time to open | Peak | At rest | Peak factor | Rest factor | Note |
|---|---|---|---|---|---|---|---|---|
| Image | image-tiff, image-mrc, stack-tiff | 1, 4, 16 GB | to come | | | | | |
| EELS | eels-hspy | 1, 4, 16 GB | to come | | | | | |
| EDS | eds-hspy | 1, 4, 16 GB | to come | | | | | |
| Patterns | patterns-h5 | 1, 4, 16 GB | to come | | | | | |
