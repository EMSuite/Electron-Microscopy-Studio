# Parity

Every function the app computes itself (not through a kit), its reference, its state and its tolerance: the SEM program's in the
sections below, the TEM rooms' own numbers in the last one; the kits' own functions are listed in their `docs/parity.md`. The
rule: match the pinned Python reference within the tolerance that package's own tests use, never stricter. The SEM references are
pinned in `tools/parity/sem/requirements.lock` (CPython 3.14): kikuchipy 0.13.1, orix 0.15.0, pyebsdindex 0.3.10.1, diffsims 0.7.0,
diffpy.structure 3.5.0, HyperSpy 2.5.0, exspy 0.3.2, rosettasciio 0.15.0, DefDAP 1.3.1, scikit-image 0.26.0, SciPy 1.18.1,
NumPy 2.5.4, tifffile 2026.10.15 and matplotlib 3.11.2, over h5py 3.16.0 and numba 0.68.1; NexusLIMS, which is on no index, by the
sha256 of its `tescan_tif.py` (`f29d59ad…f67`, main of 2026-11-07, `tools/parity/sem/sem-image/tescan_reference.py`). The TEM
harnesses' references are pinned in `tools/lib/references-lock.txt` (the last section).

## Readers (exact)

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| The EBSD and TKD files: h5ebsd (kikuchipy, Bruker Esprit, EDAX OIM, Oxford H5OINA), EDAX `.up1`/`.up2`, Oxford `.ebsp`, NORDIF `Pattern.dat`, the `.ang` and `.ctf` maps, the map files without patterns (H5OINA, orix, Bruker, EDAX, EMsoft) and the projection-centre conventions | kikuchipy 0.13.1 and orix 0.15.0, as FormatoKit's `docs/parity.md` lists them (section EBSD) | FormatoKit's `FormatoEBSDTests` and its m1 bundles; here the app's doors and rooms on the same fixtures (`EBSDH5ContentTests`, `EBSDH5OxfordMapTests`, `EBSDH5VendorMapTests`, `H5EBSDHeaderBoundsTests`, `NORDIFOpeningTests`, `SEMReaderBundleParityTests`) | exact | read by FormatoKit since 2.6.1 (`FormatoEBSD`, FormatoKit 0.23.1, #852); the reader rows, what each refuses and its tolerances moved there with the readers. FormatoKit hands a map over as columns (`EBSDMapColumns`); the app makes the `CrystalMap` from them with DiffractoKit (`EBSDMapColumns.crystalMap()`, `Sources/TEMSEM/EBSDFileMaps.swift`), orix's `eu2qu` and phase matching |
| `EBSDOpening.open`, `EDAXOpening.open`, `OxfordOpening.open` (the app's doors) | `EDAXOpening` and `OxfordOpening` door tests | `EDAXBinaryReaderTests`, `OxfordBinaryReaderTests`, `NORDIFOpeningTests` | exact | one `EBSDDataset`: the `.ang`/`.ctf` of the same name as its crystal map when the point counts agree (else a note), a version 1 `.up1` taking the `.ang`'s grid, the `.ang`'s `x-star`/`y-star`/`z-star` as a TSL projection centre, a map alone refused (D-SEM-25) |
| `HyperSpySpectrumFile.header`, `read` (`.hspy`: one spectrum in HyperSpy's own HDF5 layout) | `rsciio.hspy.file_reader` (RosettaSciIO 0.15.0, `rsciio/hspy/_api.py`: `Experiments/<title>/data`, the `axis-<i>` groups, the metadata tree as groups of attributes) | `ShippedDemoDataTests.testTheSEMEDSSpectrumReadsBackToItsTruth` on the shipped `DemoData/EDS_SEM_TM002.hspy` (axis, signal type, beam energy, microscope, elements, total and peak counts); `SEMEDSParityTests` reads the same file into the `m7/eds-*-tm002` bundles exspy made from it | exact | refused with one sentence each: not HDF5, no `Experiments` group, several experiments, no numeric data, not one spectrum (a navigation axis or a dataset that is not 1D), no calibrated energy axis; spectrum images in this layout are a later port; no test reaches the six refusals yet |


### EBSD refusals in the app's words

FormatoKit words a reader's refusal in one sentence that names the file and no app or room (`EBSDReadError`, with a typed
`Reason`); its `docs/parity.md` quotes them and says which test reaches each. The app says the ones that name the process, the
readers or a room as it did up to 2.6.0 (`EBSDReadError.inAppWords`): "… was not given access to it: open it with File > Open…, drop
it on the window or open it from the Finder.", a filter, a size or a type the app "does not have" or "does not read", where an EDS-only
H5OINA's spectrum opens instead, and which room opens a file that holds patterns or a map alone. `EBSDReadErrorWordsTests` holds each
of these against the kit's sentence; every other sentence is the kit's. The size sentences of `EBSDDataset.sizeRefusal` follow the
file's name ("scan.h5: its scan is 0 x 75 positions; a scan needs at least one row and one column.", "scan.h5: its patterns are 0 x
60 pixels; a pattern needs at least one row and one column.").


## Pictures (PNG and JPEG)

| Function | Reference | Test | Tolerance | State |
|---|---|---|---|---|
| `PictureImageReader.read` (ImageIO's decoded samples, no drawing; grey by the brightest channel) | RosettaSciIO 0.14.0 `rsciio.image.file_reader`, which is imageio 2.37.4 over Pillow 12.3.0; truth written by `tools/parity/picture-parity/make_fixtures.py` | `PictureImageReaderTests` on 20 planted files in `EMStudioTests/Fixtures/picture` | PNG exact per pixel (I1: grey 8 and 16 bit, RGB, RGBA, palette, Adam7, gAMA, iCCP); JPEG grey within 1 level, colour 4:4:4 within 2 (I2; two decoders, the largest difference is printed by the test); EXIF orientation 1 to 8 as Pillow's `ImageOps.exif_transpose` (I3) | live. Named deviation: the reference keeps RGB, the app reads grey (each pixel the brightest of its red, green and blue, the rule of #541). Refused by name: animations, CMYK, more than 16384 × 16384 pixels. A picture has no scale and is "not counts" |

## SEM images (TIFF)

| Function | Reference | Test | Tolerance | State |
|---|---|---|---|---|
| `SEMImageMetadata.read` (Thermo/FEI tags 34680/34682) | RosettaSciIO 0.15.0 `_axes_fei`, `mapping_fei`; tifffile 2026.10.15 `read_fei_metadata` | `SEMImageMetadataTests` on the five Helios test files' tags (bundles `m1/read-sem-tiff-fei-*`) | axes rtol 1e-4 (RosettaSciIO's `test_read_FEI_navcam_metadata`); metadata numbers 1e-9 relative, texts exact (its tests: 7 places) | live; matched upstream except one quirk: RosettaSciIO's `_order_axes_by_name` puts the x scale (HFW / ResolutionX) on the height axis and the y scale on the width axis. macEM keeps each on its own axis; on the one non-square test file (navcam, 2.5e-6 apart) the difference is inside upstream's tolerance. FormatoKit 0.12.1 parses the same INI in three non-public copies: `AcquisitionMetadata.feiSections` (in `AcquisitionMetadataTIFF.swift`) takes the INI only from an ASCII or UNDEFINED tag, works by Unicode scalar and strips Python's whitespace (U+001F too), where this port takes any tag type, finds `[` and `=` by Character and strips Foundation's whitespace; `TIFFAppImage.feiSections` skips a `Key=` line, where this port stores the empty value; `TIFFSignals.feiMetadata` types each value through `astype`. This port stays until the kit makes one public (D-SEM-62) |
| `SEMImageMetadata.read` (Zeiss tag 34118) | RosettaSciIO `_axes_zeiss`, `mapping_cz_sem`; tifffile `read_cz_sem` | the same, on the three Zeiss test files' tags (bundles `m1/read-sem-tiff-zeiss*`) | the same | live |
| `SEMImageMetadata.read` (Tescan tag 50431) | NexusLIMS `tescan_tif` (`_extract_embedded_hdr` pipeline, field units; transcribed in `tools/parity/sem/sem-image/tescan_reference.py`); no RosettaSciIO branch | NexusLIMS's `tescan-pfib_dataZeroed.tif` tag (MIT) and a planted header | exact (every section and key; values as stored, converted by NexusLIMS's factors) | live (D-SEM-89) |
| Databar rows (Thermo `DatabarHeight`, Tescan `ImageStripSize`) | tifffile's parse of the same bytes; no reader maps it | the five Helios files (29 and 39 rows) and a plant | exact | live; Zeiss never cropped (D-SEM-63) |
| Spot, chamber pressure, Thermo detector | tifffile's parse; RosettaSciIO does not map them | the same files | exact | live, noted in the room |

The references are the harness bundles `m1/read-sem-tiff-*` (`tools/parity/sem/emit.py`, the pinned stack): one per RosettaSciIO 0.15.0 SEM test TIFF. The two #130 commits as fixtures (`fei-helios`, `zeiss`) are also read whole; the other six are read by `emit.py` from RosettaSciIO's `tiff_FEI_Helios.zip` and `tiff_Zeiss_SEM.zip` (GPL-3.0-or-later, `fetch-data.sh`) and stay out of the repo. Each bundle holds the vendor tag's bytes, which `SEMImageMetadataTests.testEveryRosettaSciIOSEMFileReadsAsTheReference` plants on every PR (D-SEM-90). The Tescan reference is `EMStudioTests/Fixtures/sem-tiff/tescan-reference.json`, written by `tools/parity/sem/sem-image/tescan_reference.py`.

## Pattern processing

Methods: kikuchipy's static and dynamic background correction, described with its processing pipeline in Ånes et al. (2020),
IOP Conf. Ser.: Mater. Sci. Eng. 891, 012002: a static background (acquired, or the scan's mean pattern) subtracted from or divided
into every pattern, then each pattern's own Gaussian blur (spatial, or a low-pass filter in the frequency domain) as its dynamic
background. References: `tools/parity/sem/background_reference.py` (kikuchipy 0.13.1, numpy 2.5.4, scipy 1.18.1) on
`nickel_ebsd_large` (Aanes et al. 2020, CC BY 4.0); fixtures under `EMStudioTests/Fixtures/sem/background/`, tests in
`SEMBackgroundParityTests`.
kikuchipy computes in float32 (numba, fastmath) and casts back to the pattern's integer type by truncation; TEMCore computes in
float64. The rescaled values agree to 1e-5 relative (measured at most 1.1e-6); the cast patterns differ by one grey level where
kikuchipy's float32 value lands on the other side of an integer: measured on all 4125 patterns, 0.05 % (static subtract),
0.10 % (static divide), 0.007 % (dynamic, frequency) and 0.006 % (dynamic, spatial) of the pixels, never more than one level.
Upstream's own tests compare hand-written 3 x 3 uint8 answers exactly (`test_remove_static_background`,
`test_remove_dynamic_background_spatial`) and the frequency route at `atol=1e-4` on float answers.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `PatternProcessing.rescale` | `pattern._pattern._rescale_with_min_max` | through every row below | values 1e-5 relative | a flat pattern (max == min) is refused with `.nonFinite`; kikuchipy returns NaN |
| `PatternProcessing.removeStaticBackground` / `...Values` (subtract, divide, `scaleBackground`) | `_remove_static_background_subtract` / `_divide` | `testStaticBackground…` | values 1e-5 relative; uint8 within one grey level on at most 1 % of a pattern's pixels (measured 22 of 3600 at worst), 0.2 % of a whole set | uint16 rescales to 0 … 65535 (`dtype_range`); a zero in a divided background is refused with `.nonFinite` |
| `PatternProcessing.meanBackground` | `patterns.mean(axis=0).astype(dtype)` | `testMeanBackground…` | exact | the static background of a file that carries none |
| `PatternProcessing.dynamicBackground` (frequency) | `get_dynamic_background` / `filters.fft_barnes._fft_filter` with `_dynamic_background_frequency_space_setup` | `testDynamicBackgroundFrequency…` | 1e-5 relative (measured 4.9e-7) | computed as the separable nearest-edge correlation with the `int(truncate · std)` px `scipy.signal.windows.gaussian` window, the operator the padded real FFT evaluates (taps i − 15 … i + 14 for the default 30 px window, symmetric for an odd one); not an FFT, decision D-SEM-17 |
| `PatternProcessing.dynamicBackground` (spatial) | `scipy.ndimage.gaussian_filter(sigma=std, truncate=truncate)` | `testDynamicBackgroundSpatial…` | 1e-5 relative (measured 6.7e-8) | ImagoKit's `SeparableFilters.gaussianFilter`, mode reflect |
| `PatternProcessing.removeDynamicBackground` / `...Values` (subtract, divide; frequency, spatial; `std`, `truncate`) | `_remove_dynamic_background` | `testRemoveDynamicBackground…`, `testFigureF2…`, `testWholeSetF2…` (opt-in, `$MACEM_DATA/sem/nickel_ebsd_large`) | as the static rows | `std` defaults to the pattern width / 8 |
| `PatternProcessing.percentile` | `numpy.nanpercentile` (method `linear`) | `testPercentileIsNumpysLinearRule`, through the row below | exact | numpy's virtual index and `_lerp` (from the upper neighbour at a fraction of one half or more) |
| `PatternProcessing.rescaleIntensity` / `...Values` (`percentiles`) | `kikuchipy.pattern.rescale_intensity` (`EBSD.rescale_intensity`) | `SEMIntensityParityTests.testRescaleIntensity…` on `m2/intensity-*` | uint8 within one grey level (the bundle's); measured exact on all 2 × 9 patterns | the division is a product with the reciprocal, as numba's fastmath compiles `_rescale_with_min_max`; a plain division moves 6 % of a full-range pattern's pixels down one grey level |
| `PatternProcessing.normalizeIntensity` (`numStd`, `divideBySquareRoot`) | `_normalize_intensity` (`EBSD.normalize_intensity` on float32) | `testNormalizeIntensity…` | rtol 1e-5, atol 1e-6 (1e-8 with the square root); measured 4.8e-7 | float64 mean and population std, float32 out |
| `PatternProcessing.downsample` / `bin` | `_downsample2d` / `_bin2d` (`EBSD.downsample`) | `testDownsample…`, `testRoomChain…` | uint8 within one grey level; measured exact for factors 2 and 3 | float32 sums and rescale with the reciprocal, as kikuchipy's kernel; a size not divisible by the factor is refused (`.parameter("factor")`), kikuchipy points at `crop` |

NLPAR (`Sources/TEMSEM/Patterns/NLPAR.swift`, tests `SEMNLPARParityTests`): PyEBSDIndex 0.3.10.1's CPU path (`nlpar_cpu`;
Brewick, Wright and Rowenhorst 2019, Ultramicroscopy 200, 50), references `tools/parity/sem/emit.py` cases
`m2/nlpar-nickel-ebsd-large` (the shipped demo scan, run in every unit-test pass) and `m2/nlpar-kikuchipy-h5ebsd`.
pyebsdindex has no NLPAR test of its own; the tolerances are the harness rule for float32 results (D-SEM-13). The port keeps
pyebsdindex's float32 arithmetic and order of sums (D-SEM-30), so σ and the distances are expected bit-identical and the
denoised values differ only where float64 `exp` rounds differently.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `NLPAR.autoMask` | `NLPAR.makeautomask` | `testSmallScan…`, `testNickel…` | exact | circle of radius 0.98 · min(h, w) / 2, compared in float32 |
| `NLPAR.tiles` | `NLPAR._calcchunks` | same | exact | budget fixed at 32e9 bytes (D-SEM-31) |
| `NLPAR.estimateNoise` | `NLPAR.calcsigma_cpu(nn=1)` / `sigma_numba` | same | σ rtol 1e-5; distances rtol 1e-5, atol 1e-5 | per-tile saturation level 0.9961 · max; edge slots stay 0, as upstream; rows run in parallel with the serial loop's arithmetic, so the values do not depend on the cores (#624) |
| `NLPAR.optimiseLambda` | `NLPAR.opt_lambda_cpu` | same | rtol 1e-4 | SciPy 1.18.1 Nelder–Mead in one dimension with bounds [0.001, 10], fatol and xatol 1e-4 |
| `NLPAR.denoise`, `NLPAR.run` | `NLPAR.calcnlpar_cpu` / `nlpar_nb` | `testNickel…`, `testHugeLambda…` | rtol 1e-5, atol 1e-4 | window shifted inward at edges; tiles narrower than the window run as one tile and a window larger than the scan is refused (D-SEM-31) |


### Known limits and decisions

- D-SEM-17 (2026-11-06): the frequency-domain dynamic background is the direct separable correlation, not a padded FFT. Reason:
  kikuchipy's window is an outer product of one `scipy.signal.windows.gaussian`, its padding is edge replication and its crop
  reads no zero-padded sample, so the padded real FFT evaluates exactly this correlation; the direct form keeps the float64
  reference path, has no padding bookkeeping and costs 2 · M multiplies per pixel (M = 30 by default). A Metal or Accelerate
  path behind the same parity test is phase 2's optimisation (P2-01, the Patterns room's processing).
- Figure F2 (`docs/sem/north-star.md`): `tools/parity/sem/background_figure.py` draws the reference pattern beside the one the
  unit test `testFigureF2PatternZeroAfterStaticAndDynamicBackground` writes to `$TMPDIR/macTEM-F2-ours.u8` (and prints as base64).

## Orientation maths

orix 0.15.0's quaternion package (rotations and their conversions, point groups, orientation regions, orientations and
misorientations, vectors and the stereographic projection, `CrystalLattice` and `Miller`, fundamental sectors, the TSL and Euler
colour keys, and orientation sampling) moved to DiffractoKit 0.25.0 with its tests and bundles (#850, DiffractoKit#179):
`DiffractoOrientation`, `Sources/DiffractoOrientation/Orix/`. DiffractoKit's `docs/parity.md` holds its rows, references and
tolerances. The check that the `.ang` reader's Bunge Euler conversion is the kit's `RotationConversions.eu2qu` moved to FormatoKit
with the reader (#852); the app makes its rotations with `eu2qu` itself (`EBSDMapColumns.crystalMap()`).

## Crystal map

orix 0.15.0's `orix.crystal_map` (`CrystalMap`, `PhaseList`, `CrystalPhase`, the neighbour misorientation, `AngleHistogram`) and
the numbers of the Maps room's pictures and analysis moved to DiffractoKit 0.27.0 with their tests and bundles (#851,
DiffractoKit#180): `DiffractoOrientation`, `Sources/DiffractoOrientation/Maps/`. DiffractoKit's `docs/parity.md` holds their
rows, references and tolerances. The app keeps the checks that read maps with its own readers
(`CrystalMapParityTests.testTheTwoPhaseMapSlicesAsOrix` on the `.ang` reader, `testTheCTFReaderHandsTheF7MapThrough`, and figure
F7 on the whole Ti map) and the room's layers, rasters, hover, colour key and unit cell (`Sources/TEMSEM/CrystalMap/`).

| Function | Reference | Test | Tolerance | Notes |
| --- | --- | --- | --- | --- |
| `OrientationMaps` (`raster` of IPF-X, IPF-Y, IPF-Z and phase layers on the map's grid, `gridShape`, `pointIndexGrid`, `readout`, `keyImage`, `unitCellEdges`), the Maps room (P3-04) | `CrystalMap.get_map_data` of `IPFColorKeyTSL.orientation2color` per phase along the sample direction, and of `phases.colors_rgb`, as `CrystalMap.plot` draws them | `MapsRoomTests` on `m3/maps-room-sdss` (the sdss map's three IPF maps and its phase map, 100 × 117 × 3) and `m3/ipf-sdss-ferrite-austenite` (F6) | IPF atol 1e-6; phase colours exact | matched upstream: not indexed points black in an IPF map and white in the phase map (orix's fill); the key image is the exact TSL colour per pixel (D-SEM-40); key corners labelled only for cubic groups, whose Cartesian axes are the crystal's (D-SEM-80); the unit cell drawn from the phase's lattice, else orix's default lattice of its system |
| `MapAnalysis` (`run`: grain map, KAM, GOS, GND, grain table, mean lineal intercept and ASTM number, `boundaryEdges`, `outline`, `slip`), `MapTexture` (`compute`), the Maps room complete (P5-04, Segment) | DefDAP 1.3.1 `EbsdMap.find_grains`, `calc_kam`, `calc_nye`, `Grain.calc_average_ori`, `calc_grod`, `calc_average_schmid_factors`, `calc_slip_traces`; orix 0.15.0 `pole_density_function`, MTEX-style ODF sections (Hielscher and Schaeben 2008); ASTM E112 | `MapsAnalysisTests` on `m5/grains-sdss` (the room's Segment at DefDAP's settings) and on the ported functions it lays out | grain map and sizes exact; KAM and GOS atol 1e-6 (the bundle's); slip, GND and texture the ported functions' own (exact wiring) | the room's defaults are the design's (5°), the test runs DefDAP's (10°); Schmid factors and traces in the map's frame, without DefDAP's EDAX frame change (D-SEM-101); ODF from at most 5000 points (D-SEM-102) |
| `IndexingComparison` (the Indexing room's Compare: per-point disorientation of two results, its histogram, median and share over 2°), `PointGroup.disorientationBinsTop` | orix 0.15.0 `Orientation.angle_with` per (A phase, B phase) group (equal to `Misorientation.angle` for one group); `numpy.rad2deg`, `histogram` on `arange(0, top + 1)`, `median`, `mean(angle > 2)`; the bins top from `OrientationRegion.from_symmetry(G, G).vertices()` | `testPlantedComparisonMatchesOrix` (`m4/indexing-compare-planted`), `testTheDemoScanComparesAsOrixDoes` (`m4/indexing-compare-nickel-large`), `testFigureF8ThroughTheRoom` | outcomes, edges, counts and the share exact; angles atol 1e-7 rad (-1 in the bundle where not compared); the median atol 5.8e-6° (1e-7 rad) | Grimmer 1974, Morawiec 2004 (disorientation), Mackenzie 1958 (432's 62.8°). The pairing rule is the app's (D-SEM-97): one phase a side by Laue class, else by name within one; the phase index masks, never the quaternion. Every compared angle lies at least 1.46e-5° (2.5e-7 rad, Hough against the 4° dictionary) from a 1° edge and from 2°, above the port difference, so the counts and the share are exact; the planted case redraws any angle within 1e-3° of a whole degree. The demo scan reads 0.436° Hough against the file, 2.443° the 4° dictionary against the file, 2.373° Hough against the dictionary |

## Crystal map writers

The `.ang` and `.ctf` writers are FormatoKit's since 2.6.1 (`FormatoEBSD`, #852), and write an `EBSDMapGrid`; the app lays a
`CrystalMap` out as that grid (`EBSDMapGrid(_:)`, `Sources/TEMSEM/EBSDFileMaps.swift`) and calls them with its own name on the
header lines (figure F18). The byte bundles stay here, where a `CrystalMap` is made: `CrystalMapWriterParityTests`, bundles
`m8/write-*` from `tools/parity/sem/writer_cases.py`.

| Function | Reference | Test | Tolerance | Notes |
| --- | --- | --- | --- | --- |
| `ANGWriter` (FormatoKit; `text(of:options:)`, `write`; `Options`: the four columns' properties, extra columns, the `OPERATOR:` line) | `orix.io.plugins.ang.file_writer` | `testANGFilesMatchOrixByteForByte`, `testWrittenMapsReadBackAsTheOriginals`, `testExtraPropertyColumnFollowsOrix` | bytes exact; read back within the written precision | orix's layout to the byte: phases reversed in the header (EDAX OIM 7.2), proper point group under EDAX's alias, numpy's 5-decimal rounding, property columns in float32, column widths from the column's largest value, 4π/0/−1/180 where not indexed or not in data, coordinates restarted at 0 on the data extent. The app writes `OPERATOR: Electron Microscopy Studio` (macEM up to 2.1.0); the test writes orix's line |
| `CTFWriter` (FormatoKit; `text(of:project:author:)`, `write`) | `tools/parity/sem/ctf_writer.py` (no writer in the pinned stack), read back by `orix.io.plugins.ctf.file_reader` | `testCTFFilesMatchTheReferenceWriterByteForByte`, `testWrittenMapsReadBackAsTheOriginals` | bytes exact; read back within the written precision | AZtec's layout (D-SEM-54): Laue ids as orix's reader numbers them, Euler in degrees at 4 decimals, phase 0 and Euler 0 where not indexed, Bands/Error/MAD/BC/BS from properties of those names, else 0 with Error 3 where not indexed. A phase that names a space group but no point group is written as Laue group −1. An integer cell with no integer value (the NaN past the last point of a map whose points do not fill its grid, a NaN in data, or a value beyond Int) takes its column's fallback, cell by cell: 0 in Bands, BC and BS, and in Error 3 where not indexed, 0 where indexed (#440). The reference writer raises `IndexError` on a map whose points do not fill its grid (orix's `get_map_data`), and casts a NaN or out-of-range value in data to an undefined integer (the int64 minimum on x86-64) |
| `EBSDMapGrid(_:)` (was `CrystalMapExtent`) | `create_coordinate_arrays` and `get_map_data` as orix's writer uses them | through both writers | exact | a 1D map is one row with y step 1; a map with no axis (one point) is refused; the phases with their proper point group (orix's `proper_subgroup`) and Laue group |

## Grains, KAM and GOS (figures F11, F12)

DefDAP 1.3.1's grain boundaries, grains, KAM, GROD and GOS moved to DiffractoKit 0.27.0 with their tests and bundles (#851,
DiffractoKit#180, `Sources/DiffractoOrientation/Maps/Grains/`); DiffractoKit's `docs/parity.md` holds their rows. The app keeps
the two checks that read maps with its readers: `SEMGrainParityTests.testGrainsOfTheTwoPhaseSteelMatchDefDAP` (`m5/grains-sdss`,
the `.ang` reader) and `testFiguresF11AndF12GrainsKAMAndGOSOfTheTiMap` (`m5/grains-ti-full`, the `.ctf` reader, fetched),
at the tolerances DiffractoKit states.

## Pole figures, inverse pole figures and the ODF (figure F13)

orix 0.15.0's pole density function and pole figures and the ODF moved to DiffractoKit 0.27.0 with their tests and bundles
(#851, DiffractoKit#180, `Sources/DiffractoOrientation/Maps/Texture/`); DiffractoKit's `docs/parity.md` holds their rows. The app
keeps figure F13 on the whole Ti map read by its `.ctf` reader (`SEMTextureParityTests.testFigureF13OnTheTiMap`, fetched) and
the rasters its Texture tab draws (`Sources/TEMSEM/Texture/TextureRaster.swift`).

| Function | Reference | Test | Tolerance | Notes |
| --- | --- | --- | --- | --- |
| `TextureRaster.stereographic`, `.section` | none (drawing) | `testRastersDrawTheBinsTheyFallIn` | each pixel the value of its bin | values, not colours: the Maps room colours them with the shared colormap (D-SEM-68) |

## Slip analysis and GND density

DefDAP 1.3.1's slip systems, Schmid factors, slip traces, the Nye tensor and GND density moved to DiffractoKit 0.27.0 with
their tests and bundles (#851, DiffractoKit#180, `Sources/DiffractoOrientation/Maps/Deformation/`); DiffractoKit's
`docs/parity.md` holds their rows. The Maps room's wiring stays in `MapsAnalysisTests`, which calls the kit's slip API with
`Rotation(unit:)`.

## Patterns room

Methods: virtual backscatter electron images, the intensity a rectangle of the detector collects at every scan point, and their
colour mix of three rectangles into red, green and blue, as Wright et al. (2015), Ultramicroscopy 148, 132, and Nolze, Hielscher
and Winkelmann (2017), Cryst. Res. Technol. 52, 1600252, describe them (both cited by kikuchipy's virtual BSE tutorial).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `EBSDBrowsing.meanIntensityMap` (the navigation map) | `EBSD.mean(axis=(2, 3))` (numpy's float64 mean over the two pattern axes) | `PatternsRoomTests` on a planted 2 x 3 scan of uint16 patterns and on the first and last pattern of `ebsd-kikuchipy-h5ebsd.h5`; `VirtualBSETests` against `mean_intensity_map` of `m1/vbse-*` | rtol 1e-7 (the bundle's); exact to the map's `Float` rounding on the planted scan | read one scan row per slab; the demo dataset (`DemoDocuments.ebsd`) is generated, so it has no reference |
| `VirtualBSEGrid.edges` / `rect(of:)` (the detector grid) | `VirtualBSEImager.grid_rows` / `grid_cols` / `roi_from_grid` sliced by HyperSpy's `UniformDataAxis.value2index` | `VirtualBSETests` against `tile_bounds` of `m1/vbse-*`; 60/7, 50/7 and 64/5 edges measured on HyperSpy 2.5.0 | exact | numpy `linspace` rounded to the nearest pixel, half to even |
| `VirtualBSEImaging.images` (one image per detector rectangle: the tiles, an explicit ROI, the whole detector) | `VirtualBSEImager.get_images_from_grid`, `EBSD.get_virtual_bse_intensity` | `VirtualBSETests` against `grid_images` and `roi_image` of `m1/vbse-kikuchipy-h5ebsd` (3 x 3, every run) and `m1/vbse-nickel-ebsd-large` (55 x 75, on the shipped `DemoData/nickel_ebsd_large/patterns_v2.h5`, every run) | exact (float64 sums of integer counts) | one pass over the scan in rows |
| `VirtualBSEImaging.rgb` (the colour mix) | `VirtualBSEImager.get_rgb_image(normalize=True)`: `_normalize_image` then `rescale_intensity` | the same, against `rgb_image` | within 1 count (the bundle's atol) | the channels are normalised in float32 as the reference does (median, population std, 127 + 79.6875 (x − median) / std, clipped), the three rescaled together from their common min and max and truncated to uint8 as `astype`; measured in Python on both scans: 0 counts off |

## Master patterns and their projection (figure F15)

References: `tools/parity/sem/emit.py` cases `m6/read-master-pattern-*` and `m6/project-master-pattern-*` (kikuchipy 0.13.1,
orix 0.15.0) on kikuchipy's in-package Ni 20 kV master pattern (EMsoft, Callahan and De Graef 2013; the square Lambert
projection of Roşca 2010), its 11-energy dummy file and planted TKD and ECP files; tests in `MasterPatternParityTests`. kikuchipy
projects in float64 (numba, fastmath) and casts to the output type; TEMCore projects in float64 too. Upstream's own tests compare
simulated patterns with `np.allclose` (rtol 1e-5, atol 1e-8). A numpy port of the Swift steps gave kikuchipy's float32 and uint8
patterns bit for bit on all three projection bundles (2026-11-06).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `EMsoftMasterPatternReader.read` (EBSD, TKD, ECP; Lambert, stereographic; upper, lower, both; all, nearest, range of energies) | `kikuchipy.io.plugins.emsoft_{ebsd,tkd,ecp}_master_pattern.file_reader` | `testTheNickelMasterPatternReadsAsKikuchipyReadsIt`, `testMultiEnergyMasterPatternsOfEachTypeRead` | exact (values, shapes, axes, phase) | the Lambert asymmetric positions summed and cast back to the stored type (uint8 wraps), the stereographic patterns flipped up-down, energies compared in float32; ECP Lambert: see below |
| `SpaceGroupPointGroup.pointGroup` | `orix.quaternion.symmetry.get_point_group(n, proper=False)`, `contains_inversion` | `testEverySpaceGroupMapsToOrixsPointGroup` | exact, all 230 | decides whether one hemisphere is enough for a projection |
| `EBSDMasterPattern.EnergyAxis.index` | `hyperspy.axes.UniformDataAxis.value2index` (round) | `testTheReaderRefusesWhatKikuchipyRefuses` | exact | truncated at 1e-12, half rounded towards zero, refused outside the axis |
| `MasterPatternProjection.sampleToDetector` | `detectors._ebsd_detector._sample_to_detector_matrix` | `m6/project-master-pattern-*` | rtol 1e-7 | |
| `MasterPatternProjection.gnomonicBounds` | `EBSDDetector.gnomonic_bounds` (Britton et al. 2016) | same | rtol 1e-7 | |
| `MasterPatternProjection.directionCosines` | `_get_direction_cosines_for_fixed_pc` / `_varying_pc` | same | rtol 1e-7 | |
| `MasterPatternProjection.project` (float32, float64, uint8, uint16) | `EBSDMasterPattern.get_patterns` (`_project_single_pattern_from_master_pattern`, `_vector2lambert`, `_get_lambert_interpolation_parameters`, `_rescale_with_min_max`) | `testTheDocsExample…`, `testFigureF15…`, `testATiltedDetector…` | float: rtol 1e-5, atol 1e-8; integer: 1 count | a flat pattern is refused (kikuchipy divides by zero); the master pattern must be Lambert, with both hemispheres unless the point group holds the inversion |
| `MasterPatternProjectionMetal.project` (float32 GPU) | `MasterPatternProjection.project` (float64 CPU) | `testTheMetalPathMatchesTheCPUReference` (skipped without a Metal device) | 1e-3 absolute on the -1 to 1 scale | float32 emulation of the kernel measured 3.2e-5 (it takes 1 - |z| as (x² + y²) / (1 + |z|) against float32 cancellation near the pole); `patternsFloat32` picks it from 10⁶ pattern pixels |
| `MasterPatternProjectionMetal.Projector` (a dictionary chunk by chunk, #624) | `MasterPatternProjectionMetal.project` in one go | `testTheProjectorGivesTheOneShotPatternsChunkByChunk` (skipped without a Metal device), `testAProjectionPastThe32BitIndexIsRefused` | exact | the master pattern and the cosines uploaded once per run; more than 2³² − 1 output values per chunk (the kernel's 32-bit index) refused as `tooLarge` |
| `MasterPatternProjectionMetal.project` on a float32 master pattern (EMsoft's type) | `MasterPatternProjection.project` (float64 CPU), which keeps a float32 master pattern's intensities (`get_patterns`: `rescale = dtype_out != self.data.dtype`) | `testTheMetalPathProjectsAFloat32MasterPatternAsStored` (skipped without a Metal device) | 1e-3 of the pattern's half range | the GPU rescaled every pattern to -1 to 1 until 2026-11-07; results change for a float32 master pattern on the GPU path only (NDP scores; NCC centres and scales each pattern, so its scores do not move) |

### Known limits and decisions

- D-SEM-32 (2026-11-06): the Ni 20 kV master pattern of F15 and of the demo is kikuchipy's in-package uint8 copy, not the
  float32 Zenodo file (record 7498645), which the cloud sandbox cannot fetch.
- D-SEM-33 (2026-11-06): an ECP Lambert dataset of rank 4 is read as (numset, energy, y, x). kikuchipy 0.13.1 does not prepend the
  numset slice for ECP, so its energy pick slices the numset axis and returns an empty array; the ECP bundle therefore covers the
  whole-energy Lambert readings and every stereographic one.
- D-SEM-34 (2026-11-06): the GPU path's bound (1e-3 on -1 to 1) is ours, not upstream's: kikuchipy has no float32 projection.
  For a float32 master pattern, which neither path rescales, the bound is taken on the pattern's half range (2026-11-07).
- Figure F15 (`docs/sem/north-star.md`): `tools/parity/sem/master_pattern_figure.py` draws the reference patterns beside the ones
  `testFigureF15NickelMasterPatternOnTheNorthStarDetector` writes to `$TMPDIR/macTEM-F15-ours.u8` (and prints as base64).

## Dictionary indexing (figure F9)

References: `tools/parity/sem/dictionary_cases.py` (kikuchipy 0.13.1, orix 0.15.0), bundles `m4/dictionary-indexing-*`, tests in
`SEMDictionaryIndexingParityTests`. Method: Chen et al. (2015), Microsc. Microanal. 21, 739; Jackson et al. (2019), Integr.
Mater. Manuf. Innov. 8, 226. kikuchipy matches in float32 by default (`da.einsum`, BLAS) and in float64 on request; TEMCore's
reference path prepares and multiplies in float64, the GPU path multiplies in float32. Upstream's tests state no score
tolerance; the brief's rtol 1e-4 holds for float32 runs, `np.allclose`'s rtol 1e-5 for float64 runs. A float64 numpy mirror
of the Swift steps matched every bundle: float32 runs within 2.3e-6, the float64 run within 1e-14, every index in order
(2026-11-07).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `DictionaryIndexing.prepare` (NCC: centre, unit norm; NDP: unit norm) | `NormalizedCrossCorrelationMetric` / `NormalizedDotProductMetric.prepare_experimental`, `prepare_dictionary` | through every run | — | the signal mask drops pixels before the normalisation; a flat pattern's values are NaN, as kikuchipy's |
| `DictionaryIndexing.index` (dictionary in memory; CPU float64) | `EBSD.dictionary_indexing` (`_dictionary_indexing`, `_match_chunk`) | `testNCCMatchesKikuchipyInFloat32AndFloat64`, `testNDPMatchesKikuchipy`, `testSignalAndNavigationMasksMatchKikuchipy`, `testChunksGiveTheSameResult` | scores rtol 1e-4 (float32 runs), 1e-5 (float64); indices exact where scores do not tie | ties ranked by the lower simulation index (D-SEM-72), so any chunking gives the same result; `keepN` clamped to the dictionary |
| `DictionaryIndexing.index` (master pattern, chunk by chunk) | `get_patterns(dtype_out=float32)` then `dictionary_indexing` | `testProjectingTheDictionaryInChunksMatchesTheDictionaryInMemory`, `testFigureF9…` | equal to the in-memory dictionary; F9 as below | the dictionary is never held whole |
| `DictionaryIndexing.Result.crystalMap` | the returned `CrystalMap` (`rotations`, `prop`, `create_coordinate_arrays`) | `testCrystalMapOfTheResult` | quaternions atol 1e-7, Euler 1e-6, coordinates exact | the app's `CrystalMap` with `isInData` false where the navigation mask leaves a point out (its score NaN, index -1; kikuchipy: `np.empty`); the best score and index as properties |
| `DictionaryIndexingMetal` (float32 GPU product, `MPSMatrixMultiplication` since #624) | the CPU float64 product | `testTheMetalPathMatchesTheCPUReference` (skipped without a Metal device) | 1e-5 absolute on scores; against kikuchipy rtol 1e-4, with the GPU-projected dictionary 1e-3 | automatic from 10⁹ products (patterns x dictionary x pixels) on a device Metal Performance Shaders supports; two chunks in flight, buffers made once per run. The CPU reference keeps one fixed-order dot product per score, so any chunking gives the same bits (a BLAS product blocks its sums by the matrices' shapes) |
| F9 whole scan | `m4/dictionary-indexing-nickel-ebsd-large` | `testFigureF9WholeScanIndexedAgainstTheNickelDictionary`, `testTheCorrectedBlockMatchesKikuchipy` | best match ≥ 99.5 % equal, best scores rtol 1e-2; block rtol 1e-4 | D-SEM-73 |
| `OrientationSimilarityMap.compute`, `DictionaryIndexing.Result.orientationSimilarityMap` (Marquardt et al. 2017, Microsc. Microanal. 23, 1144) | `kikuchipy.indexing.orientation_similarity_map` (scipy `generic_filter`, origin at size // 2, outside −1) | `testOrientationSimilarityMapMatchesKikuchipy`, `testOrientationSimilarityMapOfFigureF9` (`m4/orientation-similarity-map`) | exact (float32) | defaults, n_best 5 to 2 normalised, 3 x 3, even 2 x 2 and corner-centred footprints; F9's whole scan; D-SEM-88 |
| `DictionaryMapMerge.merge`, `Merged.crystalMap` | `kikuchipy.indexing.merge_crystal_maps` (with `simulation_indices_prop`) | `testMergeMatchesKikuchipy` (`m4/merge-crystal-maps`) | exact; rotations atol 1e-15 (orix normalises them again) | float32 means of the best n, first map on a tie, stable merge sort over n-major map-minor order, shifted indices, equal phases kept once, different ones renamed, navigation masks, the best match alone (keep_n 1, 1-D properties); kikuchipy's OSM of each merge without masks on its `merged_simulation_indices`, exact; `chosenMaps` and `picked` are `merge`'s per-point steps; D-SEM-88, D-SEM-98 |
| F9 through the Indexing room's plan: `DictionaryIndexingPlan.indexBlock` (the room's per-pattern source, the shipped master pattern as the room opens it, orix's 4° sample of the file phase's point group, the file's detector with F9's PC) | `m4/dictionary-indexing-nickel-ebsd-large` | `IndexingDictionaryRoomTests.testFigureF9ThroughTheRoomsPlan` | as F9: best match ≥ 99.5 % equal, best scores rtol 1e-2 | the room's runs use the file's mean PC, 0.002 from F9's fixed one (0.1 px on the 60 px pattern), so the parity run sets F9's; D-SEM-91, D-SEM-92 |
| Dictionary indexing through the Indexing room: `IndexingSession.index` with Method · Dictionary (block by block, chunk progress, Stop, the map, the readout, the exports) | the run's own `DictionaryIndexing.Result` and dictionary | `IndexingDictionaryRoomTests.testDictionaryThroughTheRoom` (10°, fast) | solutions equal the result's best rotations and scores exactly, each the dictionary's rotation at its best simulation index; the crystal map's `scores` and `simulation_indices` exact; the .ang's CI within its five decimals | display and files only; the numbers are `DictionaryIndexing`'s. Not compared with F9: at 10° kikuchipy 0.13.1 itself sits a median 45.2° from its 4° best on this scan (6°: 30.8°; 4°: 0°), measured 2026-11-07, so a 10° dictionary is too coarse for these 60 × 60 patterns |
| The Indexing room's OSM layer: `IndexingResult.similarity` as dictionary blocks land (Marquardt et al. 2017) | `m4/orientation-similarity-map` (F9's map), kikuchipy's map of the rows kept | `IndexingDictionaryRoomTests.testTheRoomsSimilarityMapIsKikuchipysAsBlocksLand`; `testDictionaryThroughTheRoom` (the run's own matches) | exact | F9's matches landed in blocks of 1, 19, 1 and 34 rows; D-SEM-92 |
| Dictionary indexing against several phases in the Indexing room: `IndexingResult.land(_:rows:)` with one result per phase (`DictionaryMapMerge.chosenMaps`, `picked`), its OSM layer, its crystal map | `m4/merge-crystal-maps` (`two`, `renamed`, `best` and their `_osm`, whole maps); after each block, the port's merge and OSM of the rows landed | `IndexingDictionaryPhasesTests` (blocks of 1, 3 and 2 rows; 3 and 3; 6); `IndexingDictionaryRoomTests.testTwoPhasesThroughTheRoom` (10°, fast: two phases on one master pattern tie at every point) | exact: each point's phase, its matches, the merged crystal map's ids, rotations, `scores`, `simulation_indices` and phase list, the OSM after each block; the tied run's matches equal the one-phase run's and its OSM twice that run's | the choice on the scores as the run made them (float64), a point no phase scores not indexed, Keep 1 allowed, the room's phase names and colours and its (dy, dx) steps; D-SEM-98 |

### Known limits and decisions

- D-SEM-72 (2026-11-07): ties ranked by the lower simulation index; masked points carry NaN and -1.
- D-SEM-73 (2026-11-07): F9's dictionary and its chain tolerance.
- D-SEM-88 (2026-11-07): the OSM and the merge work on the dictionary result's keep_n matches; refusals and phase equality without atoms. A Python mirror of the Swift steps matched both bundles exactly (2026-11-07).
- D-SEM-91 (2026-11-07): the Indexing room's dictionary takes one phase (several since D-SEM-98) and a master pattern of its space group, the file's detector
  with one (mean) PC, and figure F9's settings by default (4°, NCC, keep 5, no mask).
- D-SEM-92 (2026-11-07): the room runs the scan in blocks of rows against the whole dictionary; Stop keeps whole blocks; a NaN score
  (no contrast) is not indexed in the room and its files; the OSM layer is kikuchipy's map of the rows landed, a point not indexed
  showing none.
- D-SEM-96 (2026-11-07): the room's Euler layer is `EulerColorKey` of the phase's point group (held by
  `testEulerColourKeyMatchesOrixForEveryGroup`; through the room by `IndexingMapLayerTests` and `testFigureF8ThroughTheRoom`); the
  scalar layers are drawn from their values (`IndexingRaster.scalarPixels`, NaN where a point has none) with the Map Display's
  colormap and window, which change no number.
- D-SEM-97 (2026-11-07): Compare's disorientation is orix's `angle_with` (not `__sub__`, whose reduce is first-hit across two
  groups); DiffractoKit's `SEMOrientationParityTests` also holds `angles(with:)` to orix's cubic `Misorientation.angle`. `angles(with:)` now gives
  orix's 0 for a zero quaternion under a group with improper elements (it gave π); no shipped caller fed it one. The room's runs
  are kept per method, which changes no number.
- D-SEM-98 (2026-11-07): the room's dictionary takes every phase on, one dictionary each on one backend, merged per block as
  `merge_crystal_maps` with its defaults; its OSM uses each phase's indices made distinct (index · phases + phase) where kikuchipy
  shifts each map past the previous map's largest index: the same counts, exact against the bundle. Departures: the choice compares
  the scores unrounded (kikuchipy's dtype is the maps' own, float32 in the bundles, so `merge` rounds); Keep 1 is allowed where
  kikuchipy raises on (M, 1) properties; a point no phase scores is not indexed where `nanargmax` raises; the merged map keeps the
  room's names, colours and (dy, dx) steps where kikuchipy renames, recolours and passes (dx, dy).
- D-SEM-99 (2026-11-07): `Open in Maps` shows the Indexing room's run in the Maps room as `IndexingSession.crystalMap()` builds it
  for the .ang and .ctf exports (`IndexingMapsHandOffTests` holds the two equal), so the Maps room's layers of a run are the
  room's own numbers; no new numerics.
- Figure F9 (`docs/sem/north-star.md`): `tools/parity/sem/dictionary_figure.py` draws kikuchipy's IPF-Z map beside the one from
  the indices `testFigureF9WholeScanIndexedAgainstTheNickelDictionary` writes to `$TMPDIR/macTEM-F9-ours.i32` (and prints as
  base64), the score map and the points whose best match differs.

## Kikuchi simulation (figure F14)

References: `tools/parity/sem/emit.py` cases `m6/kikuchi-*`, `m6/geometrical-simulation-*` and `m6/kinematic-master-pattern-ni`
(`simulation_cases.py`; kikuchipy 0.13.1, diffsims 0.7.0, orix 0.15.0, diffpy.structure 3.5.0) on `fixtures/simulation_cases.json`
and the shipped `nickel_ebsd_large`; tests in `SEMKikuchiSimulationParityTests`. Methods: the geometrical simulation of Kikuchi
band centre lines and zone axes in the gnomonic projection (Britton et al. 2016, *Tutorial: Crystal orientations and EBSD*,
Mater. Charact. 117, 113; kikuchipy's `KikuchiPatternSimulator`), the kinematical master pattern of band intensities |F| or |F|²
between the Bragg lines (Winkelmann 2009, kikuchipy's `calculate_master_pattern`), kinematical structure factors with the
International Tables' X-ray parameters and the refraction-corrected wavelength with Doyle and Turner's mean inner potential
(De Graef and McHenry 2007). Upstream's own tests compare the master pattern with `np.allclose` and the coordinates with
`np.allclose` too; the bundles keep numpy's float64 default (rtol 1e-7) and the brief's 1e-6 px on pixels.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `CrystalLattice.diffpy` (`base`, `recbase`, `volume`, `rnorm`, `orixAligned`) | diffpy.structure `Lattice` (`setLatPar`, `cosd`); orix `Phase.structure` re-alignment | `testLatticeBasesAsDiffpyAndOrix` | rtol 1e-7, atol 1e-12; the closed-form orix base within 1e-12 of the re-aligned one | orix rounds its re-aligned base to 12 decimals, so does the port; one lattice type with the Miller vectors' `CrystalLattice` (#202) |
| `KikuchiScatteringTables` | diffsims `ATOMIC_SCATTERING_PARAMS`, `ATOMIC_SCATTERING_PARAMETERS_DOYLETURNER` | `testScatteringTablesAreDiffsims` | exact | generated by `simulation_tables.py` |
| `KikuchiReflectors.symmetrised` | `ReciprocalLatticeVector.symmetrise` (orix `Miller.symmetrise(unique=True)`) | `test…ReflectorsAsDiffsims` (Ni, Ti, Al2Cu) | exact (indices, order, multiplicity) | |
| `KikuchiReflectors.minDSpacing`, `allowed(centering:)` | `from_min_dspacing`, `allowed` | same | exact | `allowed` is nil for a primitive hexagonal lattice, where diffsims raises |
| `KikuchiReflectors.dSpacing`, `structureFactors(cell:)`, `braggAngles` | `dspacing`, `calculate_structure_factor("xtables")`, `calculate_theta` | same | rtol 1e-7 | \|F\| only: diffsims computes F once per family and copies it to the members, so the phase of F is the representative's; atom B factors are ignored, as diffsims ignores them |
| `KikuchiWavelength.refractionCorrected` | `diffsims.utils.sim_utils.get_refraction_corrected_wavelength` | same, at 10, 20, 30 kV | rtol 1e-7 | the mean inner potential over the first asymmetric atom's orbit, as diffsims takes it |
| `GeometricalKikuchiSimulation.simulate` | `KikuchiPatternSimulator.on_detector` (`lines_coordinates`, `zone_axes_coordinates`, `_zone_axes_labels`) | `testFigureF14…`, `testTiltedTitaniumDetectorAsKikuchipy`, `testOverlayOnTheDemoNickelIsFigureF14` | hkl, [uvw], labels exact; pixels rtol 1e-7, atol 1e-6 px; gnomonic rtol 1e-7 | the line ends lie on the circle of `maxRGnomonic`: kikuchipy takes the largest r_max of the detector it is given, the whole scan's for F14 |
| `GeometricalKikuchiSimulation.roundIndices` | orix `Miller.round` (`_round_indices`, max index 20) | `testRoundIndicesAsOrix` and the zone axes above | exact | |
| `GeometricalKikuchiSimulation.Line.edges` (band edges, #201) | `KikuchiPatternSimulator.plot(mode="bands")`: orix `Vector3d.get_circle` at π/2 ∓ θ about `vector_detector`, put on the detector by `on_detector`'s formula | `testBandEdgesAsKikuchipyBands` (`m6/geometrical-band-edges-nickel`) | rtol 1e-5, atol 1e-8 (orix's own `get_circle` tests, np.allclose defaults), visibility exact | θ from the bundle; the overlay's own θ is checked within 0.1 % (`testOverlayBandEdgesOnTheDemoNickel`, D-SEM-94) |
| `KinematicMasterPattern.lambert`, `lambertVector` (the Kinematical overlay, #201) | kikuchipy `get_pattern` on `_lambert2vector` directions (normalised; the lower hemisphere with z negated), then `EBSDMasterPattern.get_patterns` | `testKinematicOverlayOfTheNickelAsKikuchipy` (`m6/kinematic-overlay-nickel`) | master pattern rtol 1e-5, atol 1e-8; patterns rtol 1e-6, atol 1e-5 (float32) | not kikuchipy's `as_lambert` (cubic spline of the stereographic pattern): D-SEM-95; the overlay's own path correlates above 0.95 (`testKinematicalOverlayOnTheDemoNickel`) |
| `KinematicMasterPattern.calculate` | `KikuchiPatternSimulator.calculate_master_pattern` (stereographic, `_get_pattern`) | `testKinematicMasterPatternOfNickelAsKikuchipy` | rtol 1e-5, atol 1e-8 | emitted with numba on one thread: kikuchipy's parallel loop adds into shared pixels |

### Known limits and decisions

- D-SEM-93 (2026-11-07): the overlay draws the geometrical simulation in the Patterns room from the file's crystal map; see
  docs/decisions.md. kikuchipy's lines and zone axes are drawn, the band edges with `Band width` (D-SEM-94), and the
  kinematical simulation with its master pattern with `Kinematical` (D-SEM-95).
- D-SEM-94 (2026-11-07): the overlay's Bragg angles use the relativistic wavelength without diffsims' mean inner potential
  (a file's phase carries no atoms the app reads): θ is 0.07 % larger at 20 kV than diffsims' (0.15 % at 10 kV).
- D-SEM-95 (2026-11-07): the Kinematical overlay's master pattern is kikuchipy's band rule on the Lambert grid with every band
  intensity 1 (no |F| without atoms), not `as_lambert`'s spline of the stereographic pattern. The design's Dynamical overlay
  (an EMsoft master pattern of the phase) is not offered in the Patterns room.

## Pattern quality

References: `tools/parity/sem/emit.py` cases `m2/quality-kikuchipy-h5ebsd` and `m2/quality-nickel-ebsd-large` (kikuchipy
0.13.1, numpy 2.5.4, scipy 1.18.1; north-star figure F3); tests in `SEMQualityParityTests`. kikuchipy computes in float32
(the FFT of the float32 pattern, numba fastmath sums, dot products in the float32 output type); TEMCore in float64. The
bundles hold rtol 1e-5, the float32 bound.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `PatternQuality.frequencyVectors` | `pattern._pattern.fft_frequency_vectors` | `testFrequencyVectors…` | exact | |
| `PatternQuality.ImageQuality` / `imageQuality` / `imageQualityMap` (`normalize` on, off) | `get_image_quality`, `_get_image_quality`, `EBSD.get_image_quality` (Krieger Lassen 1994) | `testImageQuality…`, `testWholeRawScan…`, `testBlockOfCorrected…` | 1e-5 relative (measured 8.5e-8; 2.6e-6 unnormalised) | ImagoKit's `FFT2DDouble` for the transform; one plan per pattern shape |
| `PatternQuality.averageNeighbourDotProductMap` (window rectangular or circular of any size, `zeroMean`, `normalize`) | `EBSD.get_average_neighbour_dot_product_map`, `_map_helper._neighbour_dot_products` (Brewick, Wright & Rowenhorst 2019) | `testAverageDotProduct…`, `testWholeRawScan…`, `testBlockOfCorrected…` | 1e-5 relative (measured 5.6e-7) | edge rule: cells outside the map are no neighbours (SciPy `generic_filter`, constant −1); NaN dot products skipped as `np.nanmean` |
| F3 end to end (the app's background removal, then both maps) | kikuchipy's docs chain, whole scan | `testFigureF3…` | IQ 1e-2 relative, ADP 5e-3 relative | inherits D-SEM-18's one-grey-level background differences, decision D-SEM-36 |

### Known limits and decisions

- D-SEM-36 (2026-11-06): the quality maps are held to rtol 1e-5 on kikuchipy's own input patterns (raw scan, a 6 x 6 block
  and the 3 x 3 fixture of its corrected patterns); the end-to-end F3 chain on the app's corrected patterns to rtol 1e-2 (IQ)
  and 5e-3 (ADP). Reason: the image quality is a ratio of spectrum sums that moves by about 5e-4 relative when 0.2 % of the
  pixels shift by one grey level (measured), so D-SEM-18's background differences propagate; a float64 replica of the chain
  measured 5.3e-3 (IQ) and 1.1e-3 (ADP) at worst. Both maps run on the CPU in float64: the 4125 nickel patterns take well
  under a second, so a Metal path does not pay (D16).

## Detector geometry and projection-centre calibration

References: `tools/parity/sem/detector_cases.py` (kikuchipy 0.13.1), bundles `m2/detector-*` and `m2/pc-moving-screen-si`,
tests in `SEMDetectorGeometryParityTests`. kikuchipy computes these in float64 (the rotation and the coordinate maps under
numba fastmath); its own tests compare at `atol=1e-6` (gnomonic ranges), `1e-4` (rotations as quaternions, the moving-screen
PC) and `np.allclose` defaults (coordinates).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `EBSDDetectorGeometry.Convention(kikuchipyName:)`, `init(…, convention:)`, `brukerCenter`, `center(_:in:)`, `centers(in:)` | `EBSDDetector(pc, convention)`, `pc_tsl`, `pc_oxford`, `pc_emsoft(4/5)` | `testEveryConventionName…`, `testBrukerWritten…`, `testConventionRoundTrip…` | rtol 1e-7, atol 1e-12; round trip 1e-12 | aliases edax/amatek → TSL, aztec → Oxford, emsoft = emsoft5 |
| `height`, `width`, `binnedPixelSize`, `unbinnedShape`, `specimenScintillatorDistance` | same names | `testSizesGnomonicBounds…` | rtol 1e-7 | |
| `gnomonicBounds`, `gnomonicScale`, `rMax` | `gnomonic_bounds`, `x_scale`/`y_scale`, `r_max` (Britton et al. 2016) | `testSizesGnomonicBounds…` | rtol 1e-7 | `rMax` keeps kikuchipy's corner list (D-SEM-46) |
| `gnomonic(pixel:pc:)`, `pixel(gnomonic:pc:)` | `to_gnomonic_coords`, `to_pixel_coords` | `testPixelToGnomonicAndBack…` | rtol 1e-7, atol 1e-12 | (y, x) order as kikuchipy |
| `sampleToDetector`, `detectorToSample`, `FrameRotation` | `sample_to_detector` (`_sample_to_detector_matrix`) | `testSampleToDetector…`, `testAzimuthalTurnsAboutDetectorY` | rtol 1e-7, atol 1e-12 | the matrix, rows = detector axes in sample coordinates; quaternions come with the orientation core (P3-01) |
| TKD set-ups | `EBSDDetector` with TKD angles | `testTKDGeometryAsKikuchipy` | rtol 1e-7, atol 1e-12 | D-SEM-47 |
| `PCCalibrationMovingScreen` (Hjelen et al. 1991) | `PCCalibrationMovingScreen` | `testMovingScreenPCOfSiliconAsKikuchipy` (figure F5) | rtol 1e-5 | line crossings in closed form where kikuchipy calls `np.linalg.det`; `standardDeviation` is numpy's `std` of `pc_all` |

- Figure F5 (`docs/sem/north-star.md`): `tools/parity/sem/detector_figure.py` draws si_in and si_out5mm with the marked
  points, the out → in lines and the PC, kikuchipy's beside the one `testMovingScreenPCOfSiliconAsKikuchipy` prints
  (`F5 ours …` in the test log, passed with `--ours`).

## SEM-EDS map readers (exact)

| Function | Reference | Test | Tolerance | Notes |
| --- | --- | --- | --- | --- |
| `BrukerEDSReader.read` (`.bcf`: SFS container, header XML, images, hypermap; `.spx`) | `rsciio.bruker.file_reader` with `unbcf_fast` (RosettaSciIO 0.15.0) | `SEMEDSMapReaderTests` on every `m7/read-bcf-*` and `m7/read-spx-*` bundle | counts, axes, metadata, image pixels exact | the map's x axis takes the y resolution as upstream does (`DX` unused); counts held as UInt32 whatever dtype upstream reports (D-SEM-77); a file that is not SFS refused with a sentence where upstream raises |
| `EDAXEDSReader.read` (`.spd` with `.spc` and `.ipr`, `.lsd` with `.csv`, `.spc`) | `rsciio.edax.file_reader` | `m7/read-spd-*`, `m7/read-lsd-line-scan-crop`, `m7/read-spc-single` | exact | elements sorted as upstream; an `.spd`/`.lsd` without its `.spc` refused at the EDS room's door (D-SEM-78). Exact wherever the `.ipr` can be read (the unit tests, outside the sandbox): a map takes its µm per pixel from the `.ipr` named after its electron image (the header's `fName`: `Live Map 2_Img.ipr` beside `spd_map_crop8.spd` in the fixtures). In the sandboxed app that `.ipr` is read only when the electron image's name is the map's own (`map.spd` beside `map.ipr`, the related item `RelatedFileAccess` asks macOS for); otherwise the map opens without a pixel size (scale 1, no unit), on rsciio's fallback for a missing `.ipr`. The reader notes this in `SEMEDSFile.notes`, which the app does not show (read from the code, not yet driven in a signed build, #102) |
| `JEOLEDSReader.read` (`.pts`, `.eds`, `.img`, `.map`, `.asw`) | `rsciio.jeol.file_reader` with `SI_dtype=uint32, read_em_image=True` | `m7/read-pts-*`, `m7/read-jeol-*`, `m7/read-asw-*` | exact | an incomplete last frame dropped as upstream; frames summed; an `.asw` whose view files are missing refused naming the file, where upstream raises `FileNotFoundError` |
| `CSRSpectrumImage.sum`, `windowSums` | numpy sums over the dense cube | `testTheSparseStoreSumsExactly`, the summed spectrum of every map bundle | exact (UInt64) | the EDS room's spectrum image for these files (D-SEM-76) |

## SEM-EDS (exspy's window path)

References: the bundles `m7/eds-lines-tm002` (F16) and `m7/eds-quant-tm002` (F17, with the X-ray line table as its `db_` arrays) in
`tools/parity/sem` (exspy 0.3.2, HyperSpy 2.5.0) on the BAM TM002 spectrum (`fixtures/exspy_EDS_SEM_TM002.hspy`); tests in
`SEMEDSParityTests`. Port: `Sources/TEMSEM/EDS/SEMEDSLines.swift` (Fiori and Newbury 1978 for the line width; Cliff and
Lorimer 1975 for the k-factor ratio); SpectroKit's model-fit quantification is unchanged and stays the EDS room's own path.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `XrayLineDatabase` | `exspy._misc.elements.elements` | `testXrayLineDatabaseIsExspys` | exact | generated by `make_xray_database.py` (D-SEM-61) |
| `SEMEDSLines.lines(forElements:)` | `EDSSpectrum._get_lines_from_elements` (`add_lines()`) | `testFigureF16…`, `testLinesFollowTheBeamEnergy…` | exact | Kα/Lα/Mα in range, the first below half the beam energy; an element exspy lists without lines adds none (exspy raises) |
| `fwhm(atKeV:)` | `get_FWHM_at_Energy` | `testFigureF17…` | rtol 1e-7 | keV axis only: an eV file is converted on reading |
| `integrationWindows`, `backgroundWindows` | `estimate_integration_windows`, `estimate_background_windows` | `testFigureF16…`, `testDefaultBackgroundWindows…` | rtol 1e-7 | exspy's in-place merge of overlapping windows kept as it is: with (5, 2) on TM002 every line takes C Kα's left window |
| `index(of:)`, `channels(from:to:)` | HyperSpy `UniformDataAxis.value2index`, `_get_array_slices` | `testChannelRoundingIsHyperSpys` | exact | half a channel towards zero (non-negative energy), away from zero (negative) |
| `intensities` | `get_lines_intensity` | `testFigureF16…`, `testExspyDocstringIntensities` | rtol 1e-7 (measured bit-equal) | a window off the axis or narrower than one channel is refused where HyperSpy raises |
| `cliffLorimer`, `weightToAtomic`, `quantify` | `quantification_cliff_lorimer` (× 100), `material.weight_to_atomic` | `testFigureF17…`, `testCliffLorimerFloor…` | rtol 1e-7 | no absorption correction; k-factors typed (D-SEM-7, D-SEM-59); not on screen since D-SEM-107, kept for F17. SpectroKit 0.13.2 ports the same chain as `CliffLorimer.weightFractions` (`SpectroEDX/Quant/CliffLorimer.swift`, package access), public through `EDXQuantification.quantify`: the same operations in the same order and the same 95 atomic weights, but that route refuses negative or non-finite intensities and a composition that is not finite, and by default (`.refuse`) fewer than two lines above the 0.1-count floor; exspy and this port's `cliffLorimer` refuse none of these and return what the arithmetic gives (a negative count enters the sum as it is, so a share can fall below 0 % or rise above 100 %; a non-finite count gives NaN; zeros, or 100 % for the one line above the floor, when fewer than two lines are above it) |
| `Conditions.takeOffAngleDeg` | `get_take_off_angle` / `take_off_angle` | `testTM002Conditions…` | rtol 1e-7 | exspy's defaults (130 eV, 35°, 0°, 0°) for what a file leaves out |

## Pattern filters (FFT filter, CLAHE, neighbour averaging)

References: the `m2/fft-filter-*`, `m2/clahe-*` and `m2/average-neighbours-*` bundles of `tools/parity/sem/emit.py` (kikuchipy
0.13.1, scikit-image 0.26.0, scipy 1.18.1) on the committed 3 x 3 cut and on `nickel_ebsd_large` (pattern (0, 0) for the
per-pattern filters, the scan's 4 x 4 corner for averaging); each bundle carries its input patterns. Tests in
`SEMPatternFilterParityTests`. kikuchipy's FFTs run in float32 and its rescaling in float32 numba fastmath, so the float64 port agrees within one grey level where an upstream value
lands on the other side of an integer, and exactly where upstream's arithmetic is reproduced (CLAHE).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `PatternWindow.lowpass`, `.highpass`, `*` | `filters.window.lowpass_fft_filter`, `highpass_fft_filter`, `Window * Window` | `testWindowsMatchKikuchipy` | rtol 1e-12 | `cutoffWidth` defaults to `cutoff / 2`; distances from `shape // 2` |
| `PatternWindow.gaussian`, `.modifiedHann`, `.rectangular`, `.circular`, custom | `scipy.signal.windows.gaussian` / `boxcar` (symmetric, `fftbins=False`), `filters.window.modified_hann`, `Window.make_circular` | `testWindowsMatchKikuchipy`, averaging tests | rtol 1e-12; circular exact | a 2D window is the outer product of the axes' 1D windows, as upstream; the other SciPy window names are not ported |
| `PatternFilters.fftFilter` / `...Values`, frequency (`shift` on and off) | `EBSD.fft_filter(function_domain="frequency")`, `pattern._pattern.fft_filter` | `testFFTFilter…`, `testFigureF4…` | values 1e-5 relative or 1e-3 grey levels (measured 7.4e-6 relative); uint8 within one grey level on at most 1 % of the pixels, D-SEM-18's rule (measured 0.005 % of all 4125 patterns with the guide's filter, pattern (0, 0) exact; at most 0.22 % with the asymmetric spatial kernel) | full complex FFT on ImagoKit's `FFT2DDouble`, one plan per pattern shape shared across patterns (#624); with `shift` the transfer function's centre multiplies the zero frequency |
| `PatternFilters.fftFilter` / `...Values`, spatial | `EBSD.fft_filter(function_domain="spatial")`, `filters.fft_barnes._fft_filter` (Barnes et al. 2016) | `testFFTFilter…` | as frequency (measured 0.004 % of all patterns with the 5 x 5 Gaussian) | padded to pattern + kernel − 1 per axis, not SciPy's `next_fast_len` (the crop never reads the extra zeros); a 3 x 4 asymmetric kernel pins the flip and the even-size offsets |
| `AdaptiveHistogramEqualization.equalize` / `equalizedUnit` | `EBSD.adaptive_histogram_equalization`, `skimage.exposure.equalize_adapthist` (Zuiderveld 1994) | `testCLAHE…` | exact (uint8) | 2¹⁴-level quantisation rounded half to even, reflect padding, clip-limit redistribution, mappings interpolated in float32 in scikit-image's order; default kernel `(columns / 4, rows / 4)` as (rows, columns), upstream's order |
| `NeighbourAveraging.average` / `averageValues`, `windowSums` | `EBSD.average_neighbour_patterns`, `pattern.chunk._average_neighbour_patterns` (Wright et al. 2015) | `testNeighbourAveraging…` | window sums exact; values 1e-5 relative or 1e-4 grey levels; uint8 within one grey level on at most 0.2 % (Gaussian) or 2 % (integer-weight windows) of the pixels (measured on all patterns: 0.002 %, 0.14 %) | map borders read zeros; each sum divided by the in-map window weights truncated to an integer (SciPy's integer correlate); a 1 x 1 window changes nothing |

### Known limits and decisions

- D-SEM-67 (2026-11-06): the ports' choices — F4's input is the raw pattern; CLAHE keeps scikit-image's float32 accumulation; the
  spatial FFT filter pads to the exact size; windows are 2D (`n x 1` for upstream's 1D shape); the averaging bound for integer
  windows is 2 % of a pattern set. Full text in docs/decisions.md.
- Figure F4 (docs/sem/north-star.md): `tools/parity/sem/filter_figure.py` draws kikuchipy's filtered pattern (0, 0) beside the one the unit test
  `testFigureF4PatternZeroAfterFFTFilter` writes to `$TMPDIR/macTEM-F4-ours.u8` (and prints as base64).

## Hough indexing (figure F8)

References: `tools/parity/sem/hough_cases.py` (pyEBSDindex 0.3.10.1 through kikuchipy 0.13.1, CPU path: pyopencl is not
in the lock), bundles `m4/hough-library`, `m4/hough-nickel-block` and `m4/hough-indexing-nickel-large`, tests in
`SEMHoughIndexingParityTests`. pyEBSDindex has no stated tolerance (its tests check that patterns index); it computes the
Radon transform, the convolution, the votes and the trial rotations in float32 under numba fastmath, the reflector library
and the QUEST fit in float64. TEMCore computes everything in float64 (D16); the line plan uses pyEBSDindex's float32
angles so every Radon line holds the same pixels (exact counts). Methods: Krieger Lassen 1994 (Radon, band normals),
Wright & Adams 1992 and Lassen 1994 (triplet voting), Shuster & Oh 1981 (QUEST), Rowenhorst et al. 2024 (pyEBSDindex).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `HoughReflectorLibrary` (pole families, variants, Cartesian normals, angle table, family pairs, triplet table; Laue codes and rotations) | `tripletvote.addphase`, `BandIndexer.build_trip_lib`, `crystal_sym`, `crystallometry.Crystal` | `testReflectorLibraries…`, `testLaueCodes…` | indices exact; poles and normals rtol 1e-7 (poles atol 1e-12); angles atol 1e-5° | triplet table ordered by (family key, angles), D-SEM-70 |
| `HoughBandDetector` plan, mask, kernel, `radon`, `convolve` | `radon_fast.Radon.radon_plan_setup`, `radon_faster`; `band_detect.BandDetect.band_detect_setup`, `rdn_conv` | `testRadonPlanKernelAndTransform…` | counts, bins, mask exact; Radon rtol 1e-5 (atol 1e-4), convolution rtol 1e-5 (atol 2e-3); a flipped plan pixel (below) may move up to 6 lines and 1 % of the convolution, each within 5 grey levels | the stats window keeps pyEBSDindex's row bound (`shprdn[1]`), D-SEM-70 |
| `HoughBandDetector.detect`, `normals` | `find_bands`, `rdn_local_max`, `band_label_numba`, `Radon.radon2pole` ("KIKUCHIPY") | `testBandsOfTheBlock…` | peak cells exact; sub-pixel peaks and rho 1e-3 px; theta and normals 1e-4; peak values rtol 1e-5; the bands of a pattern with a flipped plan pixel within 1 px and 1° | brief bound 1 px / 1° |
| `HoughIndexer.tripletVote` | `BandIndexer._tripvote_numba` | `testTripletVote…` | counts and families exact; weighted votes and ranks rtol 1e-5 (atol 1e-3) | fed the reference normals |
| `HoughIndexer.index` (`assignBands`, `quest`, confidence) | `bandindex`, `_assign_bands_nb2`, `_calc_quest_weights`, `_orientation_quest_nb`, `_calc_cm`, `EBSDIndexer._indexbandsphase` | `testBlockIsIndexed…` | matched bands, phase, total votes exact; fit atol 2e-3° (float32 arccos near 1), CM, PQ rtol 1e-5, IQ 1e-4 (one flipped-pixel pattern within 0.01 / 1 / 0.01); orientation < 0.01° (m-3m) | the matched variant compared by family, D-SEM-70 |
| `HoughIndexer.crystalMap` | kikuchipy `_hough_indexing.xmap_from_hough_indexing_data` | `testCrystalMapOfTheIndexedScan…` | grid, steps, unit, phase list, property names exact; rotations and properties at the bundle's tolerances | D-SEM-81 |
| F8 end to end: `HoughIndexer.indexMap` on the app's corrected demo scan | `EBSD.hough_indexing` on kikuchipy's corrected scan | `testFigureF8…` | indexed count within 1; 99 % of points under 1°; matched-band count equal on 95 % | a float64 replica on kikuchipy's exact patterns: 4124 of 4124 within 1.3e-5°, every matched-band count equal |
| F8 through the Indexing room: `IndexingSession.index` (the file's phase, the Patterns room's default stages applied per pattern as each is read, the file's mean PC, row by row) | `EBSD.hough_indexing` on kikuchipy's corrected scan | `IndexingRoomTests.testFigureF8ThroughTheRoom` | as F8 end to end: indexed count within 1; 99 % of points under 1°; matched-band count equal on 95 % | the per-pattern stages are `Process`'s numbers (F2 within one grey level); the map's IPF-Z colours are `IPFColorKeyTSL`'s within 1/255; the run's crystal map is `HoughIndexer.crystalMap`'s (D-SEM-81) and its .ang and .ctf read back to the written precision (F18's bounds), D-SEM-83, D-SEM-84 |
| `IndexedBand.segment` (a detected band's centre line on the pattern, for the overlay) | `Radon.radon2pole`'s frame ("KIKUCHIPY": the line x cos θ + y sin θ = ρ about the pattern centre, y up) | `testBandLinesSitWhereTheRadonFramePutsThem`, `testDetectedStripesAreDrawnOnTheirStripes` | analytic lines 1e-9 px; a detected 3 px stripe within 0.75 px of its middle | display only; no number leaves it |

### Known limits and decisions

- D-SEM-70 (2026-11-07): the port is float64 and orders ties stably where pyEBSDindex's float32 or quicksort order is
  arbitrary; symmetry-equivalent trial rotations score equally, so the matched library variant may be another member of
  the same family and the orientation another symmetry-equivalent quaternion: the tests hold families and
  symmetry-reduced misorientations, not variant indices or raw quaternions. The vendor is fixed to "KIKUCHIPY" (Bruker
  PCs in, the orix frame out), the one kikuchipy's `hough_indexing` uses; the rho mask fraction is limited to [0, 1)
  (pyEBSDindex's erosion and circle modes above 1 and below 0 are refused, not ported).
- The line plan rounds float32 sin and cos of the angle grid as pyEBSDindex does, but numpy's SIMD float32 sin/cos and
  Apple's differ in the last ulp, so a line whose pixel rounding sits on a half takes the neighbouring pixel (2 of 16200
  lines of the first block pattern on the CI Mac; counts stay exact). The tests allow these lines and what follows from
  them within the brief's 1 px and 1°.
- D-SEM-81 (2026-11-07): `HoughIndexer.crystalMap(_:steps:scanUnit:)` turns the scan's `HoughIndexer.Map` (which keeps
  the per-band detail) into the `CrystalMap` kikuchipy's `hough_indexing` returns; supersedes D-SEM-71's interim.
- Speed: the CPU path indexes in parallel over a scan row; the F8 test prints the time of the 4125 patterns. The brief's
  Metal path for the Radon transform is due only if a release build takes over 5 s on the 55 x 75 scan.
- Figure F8: `tools/parity/sem/hough_figure.py` draws the reference IPF-Z map beside the one
  `testFigureF8HoughIndexedMapOfTheDemoScan` prints (`F8 ours euler …` in the test log, passed with `--ours`) and their
  misorientation.

## Refinement of orientations and projection centres (figure F10)

References: `tools/parity/sem/refinement_cases.py` (kikuchipy 0.13.1's `EBSD.refine_orientation`,
`refine_projection_center` and `refine_orientation_projection_center` with their default solver, SciPy 1.18.1's
`minimize(method="Nelder-Mead")`), bundles `m4/nelder-mead` and `m4/refine-nickel-block` (a 10 x 10 block of the
corrected Ni scan, rows 20 to 29 and columns 30 to 39, from kikuchipy's Hough orientations against the Ni 20 kV master
pattern at 20 kV), tests in `SEMRefinementParityTests`. kikuchipy states no tolerance; the brief's bounds are 0.1° for
orientations and rtol 1e-4 for PCs and scores. Methods: Nelder & Mead 1965 (simplex), Winkelmann et al. 2020 and Ånes et
al. 2020 (pattern matching refinement), the NCC as kikuchipy computes it.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `NelderMead.minimize` | `scipy.optimize._optimize._minimize_neldermead` | `testNelderMeadFollowsSciPyStepForStep` | x, fun, final simplex rtol 1e-12; nfev, nit, status exact | unbounded, bounded, zero start, start at a bound, maxfev, maxiter |
| `EBSDRefinement.refineOrientations` (trust region, none, signal mask, pseudo-symmetry operators) | `EBSD.refine_orientation` | `testOrientationRefinement…`, `testPseudoSymmetry…` | every point within 0.1° (m-3m); scores rtol 1e-4; operator index exact; operator starts atol 1e-10 | a float64-NCC replica of kikuchipy: 0.005° and 4e-6 |
| `EBSDRefinement.refineProjectionCenters` | `EBSD.refine_projection_center` | `testProjectionCentreRefinement…` | scores rtol 1e-4; PCs rtol 1e-4 on 95 % of values, all within 1e-3 | replica: median 0, largest 5e-4 |
| `EBSDRefinement.refineOrientationsAndProjectionCenters` | `EBSD.refine_orientation_projection_center` | `testOrientationAndProjectionCentreRefinement…` | 90 % of points within 0.1°, all within 1°; 90 % of scores rtol 1e-4, all 1e-2, mean 1e-4; 90 % of PC values rtol 2e-3, all 5e-2 | D-SEM-87 |
| `EBSDRefinement.refineOrientations(map:)` and the PC twin | `compute_refine_*_results` | `testCrystalMapInAndOut` | grid, unit, phase list, −1 and identity at points not indexed, `scores` and `num_evals` | the master pattern's phase at the refined id |
| `refineOrientations(map:)` on a dictionary-indexed map (`DictionaryIndexing.Result.crystalMap`) | `dictionary_indexing` then `refine_orientation` (from `rotations[:, 0]`, the best match) | `testRefiningADictionaryIndexedMapMatchesKikuchipy` (`m4/refine-dictionary-nickel-block`) | under 0.1° (m-3m), scores rtol 1e-4; `is_in_data` and phase ids exact | F9's 6 x 6 corrected block, keep_n 5, two points masked out, F15 detector, trust region 1° (macTEM#213) |
| `IndexingRefinement.refine` (the Indexing room's row blocks) and a refinement's `IndexingResult.crystalMap` | `refine_orientation` on the run's map | `testRefiningInBlocksEqualsOneCall` (`m4/refine-dictionary-nickel-block`) | exact to one `refineOrientations` call over every indexed point; the map within the row above's bounds | two blocks of 3 rows (D-SEM-109) |

### Known limits and decisions

- D-SEM-86 (2026-11-07): only kikuchipy's default solver is ported, SciPy's local Nelder-Mead with its default options;
  NLopt's `LN_NELDERMEAD` and SciPy's global optimisers (basin hopping, differential evolution, dual annealing, SHGO)
  are not. The refinement runs on the CPU, one pattern per core: each evaluation projects one pattern (3600 pixels for
  the 60 x 60 detector), below the size at which the Metal projection pays (D16).
- D-SEM-87 (2026-11-07): the NCC takes kikuchipy's float32 patterns and sums in float64 where kikuchipy sums in float32
  under numba fastmath, so the simplex walks a slightly different path. Three-variable runs stay within the brief's
  bounds on every point. The six-variable joint run is ill-conditioned (a PC shift mimics a small rotation): a few
  points settle in a neighbouring optimum in either implementation, so it is held by the spread in the table, with the
  north star's 1° on every point. The evaluation counts are stored for the record, not compared.
- The orientation similarity map and the merging of crystal maps (kikuchipy's `_orientation_similarity_map`,
  `_merge_crystal_maps`) need dictionary indexing's best matches per point; they follow when dictionary indexing (P4-02)
  is on main, in its own PR (macTEM#213).

## TEM rooms (the app's own numbers)

The TEM rooms compute through the kits (their `docs/parity.md`). What the app computes itself is held by the six harnesses of
`tools/run-tests.sh`'s `scientific` array (nightly in CI and by hand, never per PR), each against a reference it computes from
`tools/lib/references-lock.txt` (CPython 3.14), and by the unit tests in the table. Each harness's README states its clauses,
tolerances and negative controls.

- `metadata-parity`: `AcquisitionMetadata.tiff(data:)`, `.mrc(data:)`, `.dm(numbers:strings:)` and `.read(path:)` (what the
  Image room shows of a file's acquisition) against ncempy 1.16, RosettaSciIO `049e7d70`, tifffile 2026.9.20 and mrcfile 1.5.4.
- `profile-parity`: `ImageMeasurement.distance` and `.angle` against their closed forms, `LineProfile.sample` against
  scikit-image 0.26.0's `measure.profile_line` (scipy 1.18.1, numpy 2.5.4).
- `export-parity`: the Image room's export (`ImageExport.render`, `ProfileCSV.text`, `ExportFile`) read back with Pillow 12.3.0,
  numpy 2.5.4 and Python's `float`.
- `fft-export-parity`: the FFT room's export (`FFTExport`, `RadialProfileCSV`, `SpotsCSV`, `ImageExport`'s provenance and spot
  marks) read back the same way.
- `sidecar-parity`: the session sidecar (`SessionSidecarFile`, `SessionLineage`) written by Swift and read by h5py 3.16.0, and
  the reverse; h5py ships its own HDF5, so neither side reads what it wrote itself.
- `diffraction-room-parity`: the Diffraction room's core (`Sources/TEMCore/Diffraction/`, on DiffractoKit) against numpy and
  planted truth (clauses R1 to R9).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `PatternIndexing.findSpots`, `.q`, `.index` (the Diffraction room's Index, #783) | DiffractoKit's `PatternSpots.find` (py4DSTEM `find_Bragg_disks` / get_maxima_2D, the kit's P41) and `PatternOrientation.index` (template match, zone-axis solver and tilt refinement, the kit's P45 against py4DSTEM 0.14.19 `match_single_pattern`); the room maps each spot to q (qx down the rows, \|q\| the readout's q of its radius, the inverse of the overlay's map), drops the direct beam (nearer than half the crystal's shortest g, at least 5 px) and indexes the spots within 1.5 Å⁻¹. Found spots become the room's spot marks (#784); with spots marked, Index reads those, and a clicked spot among them (no intensity) sends the marks to `ZoneAxisSolver.solve(clicked: true)` (the kit's P43): the zone axis and turn only, no tilt. The Spots table and its CSV (#785) list each spot's R (px from the centre Index ran about), q, d = 1/q, its hkl's d in the cell (`UnitCell.d`) and Δd/d, and R in mm as R px times the camera's pixel pitch (#907), the kit's numbers unrounded in the CSV (`%.9g`). A Simulation document's Spots table (#907) lists the simulated spots instead, with R in mm = λ L \|g\| (λ DiffractoKit's `RingCalibration.wavelengthAngstroms`, L the Microscope section's camera length; `SimulationSpotsTableTests`, 1e-9) | `DiffractionIndexTests` (a planted Al [0 1 1] pattern tilted (0.8°, −0.5°): within 0.5°, the best or a flagged alternative; the q map exact; every verdict's words) | 0.5° (the kit's own bound is its P45 regression, medians about 0.1°); the q map 1e-12 | the verdicts are the kit's: tied when it returns alternatives, scale at its limit within 0.001 of its 3 % window, found but poor when it flags the tilt spread or the positions' F_β is under its 0.7; misfit is the rms Δd/d of the explained spots under the room's scale |
| `ZoneAxisOverlay.spots` (the Diffraction room's simulated spots of a typed zone axis, #782) | DiffractoKit's `SpotPatternSimulator` at `CrystalOrientation(zoneAxis:inPlaneAngle:cell:)` (py4DSTEM's zone-axis frame and kinematical spot pattern, the kit's P42); placed by the room's scale and centre: row = centre + qx/Δq, column = centre + qy/Δq (py4DSTEM's qx down the rows), the radius the inverse of the readout's q (`RingScale.radius`) | `DiffractionSimulationTests` (hand-worked Au (2 0 0) and (1 1 1̄) positions at Δq 0.01 Å⁻¹/px, the zone law on every spot, a 90° turn) | 1e-9 px | the kit's numbers are its own parity; the room adds only the map, exact; spots past the image are left out |
| `ZoneAxisOverlay.tilted`, `.turned`, `DiffractionAnalysis.flip`, `.tilt(down:across:)`, `PatternIndexing.solverSettings(fitScale:)` (#787: the Tilt tool, ⌥ drag and its keys, Flip, Fit scale, the solutions) | DiffractoKit's `CrystalOrientation.tilted(by:)` and `rotatedInPlane(by:)`; `ZoneAxisSolver.Settings(scaleWindow:)` (0.03 on, 0 off) | `DiffractionSimulationTests.testFlipTiltAndTurnByHand` (Au (2 0 0) flipped to row 78.9588, a quarter turn to column 177.0412, a 40-point drag 2.0° off [001]), `testATiltOfOneDegreeLeavesTheZoneAxisByOneDegree`, `testFitScaleAndTheSolutionLimit`, `DiffractionIndexTests.testFitScaleOffHoldsTheRoomsScale` | 1e-6 px, 1e-6° | the kit's rotations; the room adds the drag's rate (0.05° per point) and the pointer's swept angle; at most five solutions, the best first |
| `ZoneAxisOverlay.spots` with Double diffraction and the excitation error (#786) | DiffractoKit's `DoubleDiffraction.spots(simulator:orientation:volts:settings:)` (g₁ + g₂ within one crystal on a forbidden reflection: Gjønnes and Moodie, Acta Cryst. 19 (1965) 65; Williams and Carter 2009) and `SpotPatternSimulator.Settings(sigmaExcitationError:)` (py4DSTEM's envelope, |s| ≤ 3σ kept) | `DiffractionSimulationTests.testDoubleDiffractionAddsSilicons002DownOneOneZero` (Si [1 1 0]: 002 only with the switch on, at 2 / 5.4309 / 0.01 px), `testTheExcitationErrorSetsWhichSpotsAreKept` (Au [0 0 1], σ 0.002: {2 0 0} kept, {2 2 0} not, by λg²/2) | 1e-6 px; hkl sets exact | the kit's numbers are its own parity (no Python package computes double diffraction; the kit checks a brute-force sum); an added spot has no intensity (kinematical theory gives none) and is drawn as a dashed ring; only routes within the one crystal; the Spots table names an unexplained spot within the solver's window (1 % of |q|, at least 0.004 Å⁻¹) of an added spot at Index's fitted scale (`testTheSpotsTableNamesASpotOfDoubleDiffraction`, exact) |
| `EELSCompositionSigma.percentSigmas`, `sigmas` (1σ on at% and wt%) | SpectroKit's `EDXQuantification.quantifyWithSigma`, the same first-order propagation of independent amounts (Ku 1966, J. Res. Natl. Bur. Stand. 70C, 263) | `EELSFitQualityTests.testCompositionSigmaIsTheKitsFirstOrderRule`, `testTheRegionRowsCarryTheSigmaOfTheComposition` | rtol 1e-6 against the kit on hand amounts, 1e-5 on a fitted room | interim, delete at the SpectroKit version whose `EELSCompositionPixel` carries its σ; the amounts' covariance is left out (the kit gives the diagonal only), so the σ of a ratio can read low under MLLS or shared windows; none on a deconvolved core loss |
| `EELSFitQuality.pearsonReduced`, `of` (RSS and reduced χ²) | the kit's residual sum of squares (`EELSModelResult.residualSumOfSquares`, `EELSMLLSPixel.residualSumOfSquares`); Pearson's χ² (Pearson 1900, Philos. Mag. 50, 157) over the fitted channels, divided by the degrees of freedom | `EELSFitQualityTests.testPearsonReducedChiSquared`, `testTheExactFitQualityIsTheKitsResidual` | 1e-15 on a hand case; RSS equal to the kit's; χ² 1e-12 relative | refused where the model is not positive on a fitted channel or no degree of freedom is left; the exact fit's χ² reads above 1 by construction (each background is fitted on its own window) and is not comparable with MLLS's |

## HRTEM simulation (2.5)

The numbers are SimulatoKit's (`from: "0.6.0"`), whose own `docs/parity.md` pins each to abTEM 1.0.10 (the slab builder,
the Lobato potential with infinite projection, the multislice, the contrast transfer function, frozen phonons). The app adds
only the plumbing below: which slab, which grid, which planes are stored, how an image is tiled and drawn, and how
configurations are averaged. Methods: the multislice of Cowley and Moodie (Acta Cryst. 10 (1957) 609) as in Kirkland,
*Advanced Computing in Electron Microscopy*, 3rd ed. (2020), ch. 6; the transfer function and Scherzer defocus as in Williams
and Carter (2009), ch. 28, with abTEM's sign (positive is underfocus, which Williams and Carter write negative); frozen phonons as
in Loane, Xu and Silcox (Acta Cryst. A47 (1991) 267). Rows for the Crystal pane's slab (MA5) and Place Beside (MA6) are added by
their PRs.

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `SimulationSpecimen.cell(of:)`, `build` (#893) | SimulatoKit `SlabBuilder.slab(of:zoneAxis:…)` (abTEM `orthogonalize_cell`) on the phase's cell (ASE `cellpar_to_cell`) and every site | `SimulationSpecimenTests.testSiliconAlong110ReadsItsBoxAtomsAndStrain` (Si [1 1 0]: 5.4309 × 7.6805 Å, 16 atoms a period, strain 0) | 1e-9 Å; counts exact | a partly occupied site is refused by name; a strain over 0.1 % asks (Build with Strain) |
| `SimulationSpecimen.inPlaneAngle` | DiffractoKit `CrystalOrientation(zoneAxis:inPlaneAngle:cell:)` against the slab's orientation | `SimulationSpecimenTests.testTheSlabsRotationEqualsThePatternsOrientation` | 1e-12 on every matrix element | the pattern and the slab show the same crystal |
| `HRTEMImage.grid`, `thermalGrid`, `squareGrid`, `planePeriods`, `exitWaves` (#894, #1006) | SimulatoKit `SimulationPlan.sampling(largestAngle:energy:)` (abTEM's min(0.05 Å, λ / 3β)); abTEM 1.0.10's grid rule, gpts = ⌈extent / sampling⌉ per axis on its own (`abtem.core.grid.Grid`), so its pixels are square within one point in a length; `Potential(...).build().tiled(repetitionsZ:)` of one period | `HRTEMImageTests.testThePixelsAreSquareWithinHalfAPercent` (Si [1 1 0] 125 × 176, Mg [0 0 0 1], Si [0 0 1] 120 × 120), `testTheExitWavesAreStoredAtEveryPeriodOnTheKitsGrid`, `testOnePeriodRepeatedEqualsTheWholeSlab`, `testStoredPlanesAreTieredAndAnOversizedRunIsRefused` | grid exact; pixel sides within 0.5 %; one period repeated equals the whole slab's run within 1e-12 | each length is at least abTEM's ⌈extent / sampling⌉, and the pair is the one of fewest points whose pixel sides agree within 0.5 %, of factors 2, 3 and 5 when one exists, else of factors up to 11 (SciPy's `next_fast_len` set); until #1006 each length was raised to factors 2, 3, 5 on its own, which stretched Si [1 1 0] by 6 % (120 × 160). CBED keeps its own square box (`CBEDPattern.squareRepeats`, the pattern's 0.192 mrad pixel is λ / box) and STEM's image pixel is the scan step, so neither changed. The stored waves are capped at 256 MiB by storing every n-th period and always the last; a run the kit's plan refuses for this Mac is refused before it starts |
| `HRTEMImage.image` (#894, #931) | SimulatoKit `ContrastTransferFunction.images(of:defocus:tile:)` (abTEM `Waves.apply_ctf(...).intensity()`), tiled to the field of view | `HRTEMImageTests.testTheImageIsTheKitsImageDrawnInThePatternsLabFrame`, `testTheImagesFringesLineUpWithTheSimulatedPattern`, `HRTEMControlsTests.testTheFieldOfViewSetsTheTiles` | pixels 1e-6 of the largest; calibration 1e-15 nm | drawn in the pattern's lab frame (x down the rows, y along the columns, the kit's storage order, no flip), so its FFT lines up with the simulated pattern |
| `HRTEMOptics.scherzerDefocusNM`, `HRTEMPreset` (#894, #895) | SimulatoKit `ContrastTransferFunction.scherzerDefocus(Cs:energy:)`, √(3/2 Cs λ) | `HRTEMImageTests.testScherzerIsTheDefaultAndTheMethodLineNamesEverySetting` (61.33 nm at 200 kV, Cs 1 mm), `HRTEMControlsTests.testThePresetsAreTheBriefsAndRoundTrip` | 1e-12 relative; presets exact | Uncorrected (Cs 1 mm, focal spread 5 nm), Cs Corrected (Cs −10 µm, 3 nm); the focal spread is the 1/e half-width |
| `HRTEMTransferCurve.of` (#895) | SimulatoKit `ContrastTransferFunction.profiles(energy:points:)` and `pointResolution(energy:)` | `HRTEMControlsTests.testTheTransferStripIsTheKitsProfilesInPerNanometre` | 1e-12 relative | Å⁻¹ to nm⁻¹ only; the aperture edge at β / λ |
| `HRTEMImage.table` (#895) | `HRTEMImage.image` at each defocus and stored thickness, 2 nm cells | `HRTEMControlsTests.testEveryCellIsTheSectionsImage` | exact (the same function) | columns centred on the defocus shown; rows from the first stored thickness |
| `HRTEMImage.configuration`, `addingConfiguration`, the ensemble mean (#896) | SimulatoKit `FrozenPhonons(structure:sigmas:configurations:seed:)` (abTEM `FrozenPhonons`, Einstein model, σ per element, seeded per configuration) | `HRTEMThermalTests.testOneConfigurationIsTheKitsDraw`, `testAStoppedRunContinuedEqualsOneUninterrupted` | positions exact; a continued run's image bit-equal to an uninterrupted one | the mean of the configurations' intensities on one supercell unit, tiled once (abTEM's ensemble mean); a supercell of whole units to at least 20 Å across |
| `HRTEMImage.convergence` (#896) | the app's own readout: RMS(mean of n − mean of n − 1) / RMS(mean of n) | `HRTEMThermalTests.testConvergenceNeedsTwoConfigurations` | 1e-12 (0 for a repeated configuration) | no Python package states one; it says how much the last configuration moved the image, read at the defocus and thickness it names |
| `AbTEMScript.text` (#915) | abTEM 1.0.10 and ASE 3.29.0: `Potential(gpts, slice_thickness, parametrization="lobato", projection="infinite", exit_planes)`, `PlaneWave`, `CTF`, `FrozenPhonons` | `AbTEMScriptTests.testAStaticRunWritesTheAppsUnitGridSlicesAndLens`, `testFrozenPhononsWriteTheSupercellAndSayTheDrawDiffers` | every number written in Swift's round-trip form (exact) | the specimen is written atom for atom from the app's slab, not rebuilt; a static script is written to reproduce the image at the kit's pin (nothing runs it yet); frozen phonons agree as ensembles only (NumPy's generator there, the kit's here), which the script says |
| `SlabDrawing.drawn`, `SlabDrawing.columns` (#897) | SimulatoKit `SlabBuilder` positions (abTEM `orthogonalize_cell`), projected along the beam; no computation of their own | `SlabDrawingTests.testSiliconOneOneZeroColumnsAreTheDumbbells`, `testTheColumnsSitOnTheImagesPixelsOfTheirPositions`, `testALargeSlabIsCappedAtWholePeriodsAndSaysSo`, `testTheDrawnSlabIsTheSlabInTheCrystalsFrame`, `testTheDrawnSlabKeepsTheCrystalsDepthOrder`, `testTheDrawnSlabIsNoDeeperThanItIsWide` | positions 1e-9 Å; marks on the pixel of their position, 1e-9 px | the pane draws at most 20 000 atoms (whole periods from the entrance face), no deeper than the slab's widest side across (at least one period, #1020), and names the count; columns merge atoms within 0.01 Å across the beam; the rings are drawn only on the image of the specimen shown, and not on Place Beside's pair |

## CBED, STEM and atom models (2.6)

The numbers are SimulatoKit's (CBED, STEM, the beams of a run, the slab of an atom model) and DiffractoKit's (the two-beam
thickness fit, the atom model readers), each pinned in that kit's own `docs/parity.md`: abTEM 1.0.10 (Madsen and Susi, Open
Research Europe 1 (2021) 24) and ASE 3.29.0 (Larsen et al., J. Phys.: Condens. Matter 29 (2017) 273002). The app adds the
plumbing below: which slab and probe position, which edge a pattern is cut at, how a scan is tiled and banded, and how a file
built elsewhere becomes a specimen. Methods: the probe through the multislice and the annular detectors as in Kirkland,
*Advanced Computing in Electron Microscopy*, 3rd ed. (2020); frozen phonons as in Loane, Xu and Silcox (Acta Cryst. A47
(1991) 267); the two-beam thickness from CBED fringes as in Kelly et al. (Phys. Status Solidi A 31 (1975) 771) and Allen
(Phil. Mag. A 43 (1981) 325).

| Function | Reference | Test | Tolerance | Notes |
|---|---|---|---|---|
| `DynamicalSpots`, `DynamicalBeams` (#911) | SimulatoKit `BeamIntensities(exitWaves:of:exitPlanes:)` (abTEM 1.0.10 `index_diffraction_spots`) of the HRTEM run's exit waves at whole periods | `DynamicalSpotsTests.testTheBeamsAreTheKitsAtEveryStoredPeriod`, `testSilicons002HasDynamicalIntensity`, `testTheOverlayDrawsTheBeamsWith002AsARing` | exact (the kit's numbers, renamed by hkl) | static lattice only (no beams for a frozen-phonon ensemble); the exact zone axis only, so a tilted overlay draws the kinematical spots |
| `CBEDRun.run`, `CBEDPattern` (#912) | SimulatoKit `Probe(semiangleCutoff:)` at the box's middle through the tiled one-period potential, `diffractionPattern(maxAngle: .cutoff)` (abTEM 1.0.10 `Probe(...).multislice(...).diffraction_patterns(max_angle="cutoff")`), cropped to the edge | `CBEDPatternTests.testASmallRunIsTheKitsPatternInTheDisplayFrame`, `testThePlanNamesTheBoxForTheAngularStep`, `testAnEdgeThatCutsTheDiscsIsRefused` | the kit's numbers (its CBED pins); Σ of a pattern 1 ± 0.05 inside the edge | the box is square within 0.5 %; static lattice only; the edge must hold twice the semiangle and the first ring; a pattern kept about every 2 nm, one stretch between stored planes in memory at a time; Fit Discs sets the semiangle to half the angle of the zone's shortest reflection in the kinematic list; a hand tilt is the probe's tilt (next row) |
| `CBEDTilt`, `CBEDRun.run(tiltMrad:)` (#1013) | SimulatoKit `Probe(…, tilt:)` (abTEM 1.0.10 `Probe(semiangle_cutoff, tilt=(tx, ty))`: e^{−2πi (kx tan tx + ky tan ty) Δz} on every propagator); the tilt is the beam of the orientation drawn by hand written in the slab's box, tan t = −(b_x, b_y) / b_z (b toward the source; the kit's slab mirrors crystal and beam to depth) | `CBEDTiltTests.testTheTiltedRunIsAbTEMsAndLightsTheDiscTheOverlayExcites` against `EMStudioTests/Fixtures/cbed-tilt.json` (`tools/parity/cbed-tilt/cbed_tilt.py`: abTEM's run of the same slab, box, grid and probe, float64), `testTheSlabsBoxIsTheScriptsFrame`, `testTheTiltDrawnByHandIsTheKitsTiltAndBack`, `testATiltPastTheRangeIsRefusedAndTheKeyCarriesIt` | each disc's share of the probe within 1 % (plus 1e−4 of the probe); the tilt read back to 1e−9 mrad; the brightest diffracted disc is abTEM's and the one on the overlay's Laue circle | Si [1 1 0], 200 kV, 3.9 mrad, tilt (45, 6.53) mrad: 2 2̄ 0 at its Bragg condition, 45 mrad at right angles to it taking the beam off the 1 1 1 discs; tilts up to 50 mrad (2.86°), past abTEM's "generally not more than one degree" because a two-beam condition off a low-index zone needs 2 to 3° (the slices' projection walks 0.05 Å per 1 Å slice there); a tilt is kept to 0.01 mrad; Index's orientation and a typed zone axis run untilted |
| `CBEDThickness.measure` (#916) | DiffractoKit `TwoBeamThickness.fit` (Kelly et al. 1975 whole-profile fit, Allen 1981 fringe line; DiffractoKit's own pins, no Python reference package) on the profile the app reads across the diffracted disc | `CBEDThicknessTests.testATwoBeamDiscGivesItsThickness`, `testNoScaleOrNoDiscIsRefused`; `CBEDTiltTests.testMeasureThicknessClosesOnATiltedSimulatedPattern` | 3 % on a synthetic Si 2 2 0 disc of 250 nm, and on the app's own tilted multislice CBED of Si [1 1 0] (2 2̄ 0 two-beam, 250 nm stored, Metal) | the disc is found on the phase's first six rings by its mean; a two-beam tilt is assumed; ambiguous fits give no number; a simulated pattern measures once its run is tilted to one strong reflection (#1013) |
| `STEMImage.prepare`, `STEMScan.image`, `radialProfile` (#913) | SimulatoKit `STEMRun` with `FlexibleAnnularDetector` (abTEM 1.0.10 `Probe(...).scan(..., detectors=FlexibleAnnularDetector())`) and `ScanMeasurement.integrateRadial` (abTEM `integrate_radial`) | `STEMImageTests.testTheBandsAreSumsOfTheKitsRings`, `testARunInSlicesEqualsOneUninterrupted` | the kit's numbers (its STEM and flexible annular pins); bands add to 1e-12; a sliced run equals one run exactly on the CPU | one projected unit scanned and tiled; the slab at least 20 Å across; bands on 1 mrad rings |
| `AtomModelSpecimen` (#914) | DiffractoKit `AtomModel.read` (ASE 3.29.0's extxyz, xyz and vasp readers) and `CrystalLoading`; SimulatoKit `SlabBuilder.slab(ofModel:beamAlong:…)` (abTEM `orthogonalize_cell` on the model's cell, ASE `center(vacuum=5)` for a model without one) | `AtomModelSpecimenTests.testAnExtendedXYZModelIsTheSlabAlongItsC`, `testAModelWithoutACellGetsFiveAngstromsOfVacuum`, `testWrappedAndCloseAtomsAreCounted`, `testCloseAtomsAreCountedAcrossTheCellsFaces`, `testTheDesignsRefusalsAreItsSentences` | 1e-9 Å; counts exact | the model's own thickness is the slab's (one period); at most 1 000 000 atoms and a 4096 grid at 0.05 Å; a cell that is not rectangular within 0.1 % is refused with its angle; atoms outside the cell are wrapped and counted, pairs closer than 0.5 Å counted, neither changed |

