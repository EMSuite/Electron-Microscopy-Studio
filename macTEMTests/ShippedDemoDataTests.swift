//
//  ShippedDemoDataTests.swift
//  The real, licensed files the app bundle ships as demo data (`DemoDocuments.Shipped`, DemoData/, NOTICE): each is in the built bundle at
//  the size and md5 its source publishes, its contents read back to the truth h5py gave (readers are tested exact), and the SEM-EDS
//  spectrum opens through the app's own route into the EDS room; the recorded spot pattern is one image, and the silicon CIF is
//  silicon (#804). A replaced or truncated file, a lost folder reference in the Xcode
//  project, or a `.hspy` that no longer routes goes red here.
//

import XCTest
import DiffractoCore
import FormatoCore
import FormatoHDF5
import FormatoHSPY
import ImagoCore
import SpectroCore
import SpectroEDX
import TEMCore
import TEMSession
@testable import macTEM
import ShellEDXModel

nonisolated final class ShippedDemoDataTests: XCTestCase {

    /// Every shipped file is in the bundle (the `DemoData` folder reference copies the whole folder) at the pinned size and md5.
    /// Mutation: a file replaced, truncated or renamed; the folder reference dropped from the project.
    func testEveryShippedFileIsInTheBundleAtItsPinnedSizeAndMD5() throws {
        XCTAssertEqual(DemoDocuments.Shipped.all.count, 7)
        for file in DemoDocuments.Shipped.all {
            let url = try XCTUnwrap(file.url, "\(file.relativePath) is not in the bundle's DemoData/")
            let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            XCTAssertEqual(size, file.bytes, file.relativePath)
            XCTAssertEqual(try DemoDocuments.md5(of: url), file.md5, file.relativePath)
            XCTAssertEqual(url.lastPathComponent, file.fileName)
        }
    }

    /// The nickel patterns: 55 x 75 of 60 x 60 uint8 at kikuchipy's path, the header agreeing, the first pattern's pixel sum as h5py read it.
    func testTheNickelPatternsReadBackToTheirTruth() throws {
        let file = DemoDocuments.Shipped.nickelEBSD
        let url = try XCTUnwrap(file.url)
        let reader = try HDF5Reader(url: url)
        let info = try reader.datasetInfo(DemoDocuments.Shipped.nickelEBSDPatternsPath)
        XCTAssertEqual(info.shape, [DemoDocuments.Shipped.nickelEBSDRows * DemoDocuments.Shipped.nickelEBSDColumns,
                                    DemoDocuments.Shipped.nickelEBSDPatternHeight, DemoDocuments.Shipped.nickelEBSDPatternWidth])
        XCTAssertEqual(info.type, .numeric(.uint8))
        XCTAssertEqual(try reader.readDataset("/Scan 1/EBSD/Header/n_rows").doubles(), [Double(DemoDocuments.Shipped.nickelEBSDRows)])
        XCTAssertEqual(try reader.readDataset("/Scan 1/EBSD/Header/n_columns").doubles(), [Double(DemoDocuments.Shipped.nickelEBSDColumns)])
        let first = try reader.readDataset(DemoDocuments.Shipped.nickelEBSDPatternsPath, start: [0, 0, 0], count: [1, 60, 60]).doubles()
        XCTAssertEqual(first.count, 3600)
        XCTAssertEqual(UInt64(first.reduce(0, +)), DemoDocuments.Shipped.nickelEBSDFirstPatternSum)
        let all = try reader.readDataset(DemoDocuments.Shipped.nickelEBSDPatternsPath).doubles()
        XCTAssertEqual(all.count, 4125 * 3600)
        XCTAssertEqual(UInt64(all.reduce(0, +)), DemoDocuments.Shipped.nickelEBSDPixelSum)
    }

    /// The nickel file's crystal map is in µm, as its `header/scan_unit` says and orix reads it: the Maps room's scale bar and grain sizes
    /// are lengths, not pixels. Mutation: the reader ignores `scan_unit` (the map falls back to orix's "px").
    func testTheNickelCrystalMapReadsItsScanUnit() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelEBSD.url)
        let map = try XCTUnwrap(try EBSDH5Reader.read(url: url).crystalMap)
        XCTAssertEqual(map.scanUnit, "um")
        XCTAssertEqual(map.dx, 1.5, accuracy: 1e-12)
        XCTAssertEqual(EBSDBrowsing.unitLabel(map.scanUnit), "µm")
    }

    /// The Ni master pattern through the EMsoft reader: an EBSD master pattern of nickel (space group 225) at 20 kV, 401 x 401 px in
    /// both hemispheres, each Lambert hemisphere's sum as h5py read it; projectable (Lambert, both hemispheres).
    func testTheNickelMasterPatternReadsBackToItsTruth() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelMasterPattern.url)
        XCTAssertEqual(EMsoftMasterPatternReader.sniff(url: url), .ebsd)
        let mp = try EMsoftMasterPatternReader.read(url: url, type: .ebsd, projection: .lambert, hemisphere: .both)
        XCTAssertEqual(mp.side, DemoDocuments.Shipped.nickelMasterPatternSide)
        XCTAssertEqual(mp.energies, [20])
        XCTAssertEqual(mp.phase.name, "ni")
        XCTAssertEqual(mp.phase.spaceGroup, 225)
        for h in 0 ..< 2 {
            XCTAssertEqual(mp.pattern(hemisphere: h, energy: 0).reduce(UInt64(0)) { $0 + UInt64($1) }, DemoDocuments.Shipped.nickelMasterPatternLambertSum)
        }
        XCTAssertNoThrow(try MasterPatternProjection.checkSuitable(mp))
    }

    /// The recorded spot pattern (#804): a HyperSpy file of one 144 x 144 2D signal, which the Open route takes as an image (the Image,
    /// FFT and Diffraction rooms), with the scan's 300 kV. Mutation: the frame cut wrong (a 4D or 3D signal), the file replaced - red.
    func testTheSpotPatternIsOneImageOfTheNanowireScan() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nanowirePattern.url)
        let experiments = try HyperSpyOpening.experiments(path: url.path)
        XCTAssertEqual(experiments.count, 1)
        XCTAssertEqual(experiments.first?.shape, [DemoDocuments.Shipped.nanowirePatternSide, DemoDocuments.Shipped.nanowirePatternSide])
        XCTAssertEqual(HyperSpyOpening.contents(of: experiments).images.count, 1)
        XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(image: true))
    }

    /// The spot pattern is the distortion-corrected frame (pyxem tutorial 01's affine, x 0.99 and y 0.69 about the centre, order 1, uint8;
    /// tools/lib/extract-spot-pattern.py) and carries its scale (2026-11-26): both axes in Å⁻¹ at `nanowirePatternDeltaQ`, the zero at
    /// pixel 0 as the scan's axes had it, the scan's 300 kV. Pixels as h5py reads them: sum 174,088, maximum 254 at two pixels, the
    /// first at (row 72, column 71), and the 0.69 squeeze leaves rows 0 to 21 and 122 to 143 black.
    /// Mutation: the raw frame back (sum 264,228, max 255, no black rows), the axes in pixels again, the scale's unit in 1/nm - red.
    func testTheSpotPatternIsTheCorrectedFrameWithItsScale() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nanowirePattern.url)
        let image = try ImageOpening.openNow(path: url.path)
        let side = DemoDocuments.Shipped.nanowirePatternSide
        XCTAssertEqual(image.width, side)
        XCTAssertEqual(image.height, side)
        XCTAssertEqual(image.voltage, 300_000)
        for axis in [image.x, image.y] {
            XCTAssertEqual(axis?.unit, "Å⁻¹")
            XCTAssertEqual(axis?.scale, DemoDocuments.Shipped.nanowirePatternDeltaQ)
            XCTAssertEqual(axis?.origin, 0)
        }
        XCTAssertEqual(UnitDisplay.reciprocalAngstromsPerPixel(image.x), DemoDocuments.Shipped.nanowirePatternDeltaQ)
        guard case .uint8(let pixels) = image.stored else { return XCTFail("the frame is 8 bit") }
        XCTAssertEqual(pixels.reduce(0) { $0 + Int($1) }, 174_088)
        XCTAssertEqual(pixels.max(), 254)
        XCTAssertEqual(pixels.firstIndex(of: 254), 72 * side + 71)
        XCTAssertEqual(pixels.filter { $0 == 254 }.count, 2)
        let rowSums = (0..<side).map { row in pixels[(row * side)..<((row + 1) * side)].reduce(0) { $0 + Int($1) } }
        XCTAssertEqual(rowSums.indices.filter { rowSums[$0] > 0 }.first, 22)
        XCTAssertEqual(rowSums.indices.filter { rowSums[$0] > 0 }.last, 121)
    }

    /// The silicon CIF of the demo simulation (#804): Fd-3m, eight atoms in the cell, a = 5.4309 Å, as the kit reads it.
    func testTheSiliconCIFIsTheDiamondStructure() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.siliconCIF.url)
        let loaded = try CrystalLoading.load(bytes: Data(contentsOf: url), fileName: url.lastPathComponent)
        XCTAssertEqual(loaded.structure.sites.count, 8)
        XCTAssertTrue(loaded.structure.sites.allSatisfy { $0.z == 14 })
        XCTAssertEqual(loaded.structure.cell.a, 5.4309)
        XCTAssertEqual(loaded.structure.spaceGroupNumber, 227)
    }

    /// The GaAs CIF the nanowire demo lands with: F-43m, four Ga and four As in the cell, a = 5.6533 Å, as the kit reads it.
    func testTheGaAsCIFIsTheZincBlendeStructure() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.gaAsCIF.url)
        let loaded = try CrystalLoading.load(bytes: Data(contentsOf: url), fileName: url.lastPathComponent)
        XCTAssertEqual(loaded.structure.sites.count, 8)
        XCTAssertEqual(loaded.structure.sites.filter { $0.z == 31 }.count, 4)
        XCTAssertEqual(loaded.structure.sites.filter { $0.z == 33 }.count, 4)
        XCTAssertEqual(loaded.structure.cell.a, 5.6533)
        XCTAssertEqual(loaded.structure.spaceGroupNumber, 216)
    }

    /// The BAM TM002 spectrum through the HyperSpy reader: 1024 channels of 0.01 keV from -0.1 keV, 10 kV, the counts exact (their total,
    /// the peak channel), the microscope and the five elements the file names.
    func testTheSEMEDSSpectrumReadsBackToItsTruth() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        XCTAssertTrue(HyperSpySpectrumFile.isHyperSpyFile(path: url.path))
        let header = try HyperSpySpectrumFile.header(path: url.path)
        XCTAssertEqual(header.experiment, "/Experiments/EDS SEM Spectrum")
        XCTAssertEqual(header.title, "EDS SEM Spectrum")
        XCTAssertEqual(header.channels, DemoDocuments.Shipped.semEDSChannels)
        let spectrum = try HyperSpySpectrumFile.read(path: url.path)
        XCTAssertEqual(spectrum.counts.count, DemoDocuments.Shipped.semEDSChannels)
        XCTAssertEqual(spectrum.offset, DemoDocuments.Shipped.semEDSOffsetKeV, accuracy: 1e-12)
        XCTAssertEqual(spectrum.scale, DemoDocuments.Shipped.semEDSScaleKeV, accuracy: 1e-12)
        XCTAssertEqual(spectrum.units, "keV")
        XCTAssertEqual(spectrum.signalType, "EDS_SEM")
        XCTAssertEqual(spectrum.beamEnergyKeV, DemoDocuments.Shipped.semEDSBeamKeV)
        XCTAssertEqual(spectrum.microscope, "Nvision40 Carl Zeiss")
        XCTAssertEqual(spectrum.elements, DemoDocuments.Shipped.semEDSElements)
        XCTAssertEqual(UInt64(spectrum.counts.reduce(0, +)), DemoDocuments.Shipped.semEDSTotalCounts)
        let peak = try XCTUnwrap(spectrum.counts.indices.max { spectrum.counts[$0] < spectrum.counts[$1] })
        XCTAssertEqual(peak, DemoDocuments.Shipped.semEDSPeakChannel)
        XCTAssertEqual(UInt32(spectrum.counts[peak]), DemoDocuments.Shipped.semEDSPeakCounts)
    }

    /// The route: a `.hspy` of one spectrum is a single spectrum (the EDS room), opens as a one-pixel spectrum image with the file's axis,
    /// beam energy and instrument, and its extension is one the Open panel and Finder offer. A `.hspy` that is not HDF5 is refused in words.
    func testTheSpectrumRoutesToTheEDSRoomAsAOnePixelImage() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(singleSpectrum: true))
        XCTAssertTrue(FileRouting.isSingleSpectrum(path: url.path))
        XCTAssertTrue(EDXOpening.isSpectrumImage(at: url))
        let loaded = try FileRouting.spectrumFile(path: url.path)
        XCTAssertEqual(loaded.metadata.scanWidth, 1); XCTAssertEqual(loaded.metadata.scanHeight, 1)
        XCTAssertEqual(loaded.metadata.channelCount, 1024)
        XCTAssertEqual(loaded.metadata.beamEnergyKeV, 10)
        XCTAssertEqual(loaded.metadata.instrument, "Nvision40 Carl Zeiss")
        XCTAssertEqual(loaded.energyAxis.offset, -0.1, accuracy: 1e-9); XCTAssertEqual(loaded.energyAxis.scale, 0.01, accuracy: 1e-9)
        XCTAssertEqual(loaded.metadata.energyOffsetEV, -100, accuracy: 1e-6); XCTAssertEqual(loaded.metadata.energyDispersionEV, 10, accuracy: 1e-6)
        XCTAssertEqual(loaded.image.sum(mask: nil).reduce(0, +), DemoDocuments.Shipped.semEDSTotalCounts)
        XCTAssertTrue(FileRouting.openableExtensions.contains("hspy"))
        XCTAssertTrue(EDXOpening.readableExtensions.contains("hspy"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hspy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = dir.appendingPathComponent("fake.hspy")
        try Data("not an HDF5 file".utf8).write(to: fake)
        XCTAssertFalse(HyperSpySpectrumFile.isHyperSpyFile(path: fake.path))
        XCTAssertEqual(FileRouting.inventory(path: fake.path).refusal, "fake.hspy is not a format Electron Microscopy Studio opens (or its extension and its first bytes disagree).")
    }

    /// HyperSpy writes its layout under any extension it is given: the same spectrum saved as `.hdf5` routes and opens as the `.hspy`
    /// does (FormatoKit 0.19.0's sniff finds the layout). Red before: "spectrum.hdf5 is a 4D dataset or an HDF5 file that is neither ...".
    func testTheSpectrumSavedAsHDF5RoutesAsTheHSPYDoes() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hspy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("spectrum.hdf5")
        try FileManager.default.copyItem(at: url, to: copy)
        XCTAssertTrue(HyperSpySpectrumFile.isHyperSpyFile(path: copy.path))
        XCTAssertEqual(FileRouting.inventory(path: copy.path), FileInventory(singleSpectrum: true))
        let loaded = try FileRouting.spectrumFile(path: copy.path)
        XCTAssertEqual(loaded.metadata.channelCount, 1024)
        XCTAssertEqual(loaded.image.sum(mask: nil).reduce(0, +), DemoDocuments.Shipped.semEDSTotalCounts)
    }

    /// A 4D HyperSpy file (as a 4D-STEM .hspy is) is refused naming the file and what it holds, never HyperSpy's internal group name
    /// "__unnamed__" (real-file sweep, 12 Nov). Fixture: tools/parity/sem-readers/make_hspy_4d_fixture.py.
    /// Red before: "__unnamed__ in hyperspy-4d-unnamed.hspy is not one spectrum (4 dimensions, 4 axes): ...".
    func testAHyperSpyFileThatIsNotOneSpectrumIsRefusedWithoutItsGroupName() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/sem/hyperspy-4d-unnamed.hspy")
        XCTAssertTrue(HyperSpySpectrumFile.isHyperSpyFile(path: url.path))
        XCTAssertThrowsError(try HyperSpySpectrumFile.header(path: url.path)) { error in
            let text = (error as? HyperSpySpectrumFile.Refusal)?.text ?? "\(error)"
            XCTAssertEqual(text, "hyperspy-4d-unnamed.hspy holds a 4-dimensional signal (a 4D-STEM or EBSD dataset), not one spectrum: "
                           + "Electron Microscopy Studio opens single spectra from HyperSpy files.")
            XCTAssertFalse(text.contains("__unnamed__"))
        }
        // The Open route says the same and where such a file opens (#820).
        XCTAssertEqual(FileRouting.inventory(path: url.path).refusal,
                       "hyperspy-4d-unnamed.hspy holds a 4-dimensional signal (a 4D-STEM or EBSD dataset), which no room of Electron Microscopy Studio "
                       + "opens: it opens images, spectra and spectrum images from HyperSpy files. Open a 4D-STEM file in 4DSTEM Studio.")
    }

    /// Help > Open Demo Data and `--demo-sem-eds` open the shipped spectrum into the EDS room through the app's own Open.
    /// The shipped SEM spectrum is quantified by the shared EDS room (D-SEM-107): once the room has opened it and Auto ID has answered,
    /// the five elements the file names are picked, so the room's Quantify is offered; exspy's line table is read for Info. A second call
    /// adds nothing. Mutation: the elements are not picked (Quantify stays off, as before D-SEM-107 with no Auto ID pick at 10 kV).
    @MainActor func testTheSEMSpectrumOpensWithItsElementsPickedForTheRoomsQuantify() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        await state.edx.open(url: url).value
        await state.semEDS.load(path: state.edx.source?.metadata.filePath)
        XCTAssertTrue(state.semEDS.isSEMSpectrum)
        XCTAssertEqual(state.semEDS.rows.map(\.line), ["Al_Ka", "C_Ka", "Cu_La", "Mn_La", "Zr_La"])
        await state.semEDS.pickFileElements(in: state.edx)
        XCTAssertEqual(Set(state.edx.picks.map(\.symbol)), ["Al", "C", "Cu", "Mn", "Zr"])
        XCTAssertTrue(state.edx.canQuantify, state.edx.quantifyBlocker ?? "")
        await state.semEDS.pickFileElements(in: state.edx)
        XCTAssertEqual(state.edx.picks.count, 5)
    }

    /// The demo's Quantify gives the line intensities and no composition, as exspy does for an SEM spectrum (walk 2026-11-26): every file
    /// element is fitted and shown with its area and σ, Zr on Zr_La too, and the header says why there is no at%. Red before: thin-film
    /// Cliff-Lorimer at% with ± on a bulk 10 kV spectrum, Zr picked Fit only and left out of the table without a word.
    @MainActor func testTheSEMSpectrumsQuantifyGivesLineIntensitiesOnly() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        await state.edx.open(url: url).value
        await state.semEDS.load(path: state.edx.source?.metadata.filePath)
        await state.semEDS.pickFileElements(in: state.edx)
        XCTAssertEqual(state.edx.intensitiesOnly, SEMEDSState.intensitiesOnlyReason)
        XCTAssertTrue(state.edx.picks.allSatisfy { $0.role == .quantify }, "\(state.edx.picks.map { ($0.symbol, $0.role) })")
        await state.edx.quantify()?.value
        await state.edx.settled()
        let fit = try XCTUnwrap(state.edx.fit, state.edx.fitFailure ?? "no fit")
        XCTAssertFalse(fit.hasAbundance)
        XCTAssertEqual(fit.abundanceRefusal, SEMEDSState.intensitiesOnlyReason)
        XCTAssertTrue(fit.rows.allSatisfy { $0.atomicPercent == nil && $0.weightPercent == nil })
        XCTAssertEqual(Set(fit.rows.map(\.element)), ["Al", "C", "Cu", "Mn", "Zr"], "every file element is in the table")
        let zr = try XCTUnwrap(fit.rows.first { $0.element == "Zr" })
        XCTAssertGreaterThan(zr.net, 0, "Zr is fitted on its L line")
    }

    /// A TEM spectrum is quantified as before: opening one after the SEM demo clears the mark.
    @MainActor func testATEMSpectrumAfterTheSEMDemoIsQuantifiedAgain() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.edx.open(url: try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)).value
        await state.semEDS.load(path: state.edx.source?.metadata.filePath)
        await state.semEDS.pickFileElements(in: state.edx)
        XCTAssertNotNil(state.edx.intensitiesOnly)
        await state.edx.bind(DemoDocuments.edx()).value
        await state.semEDS.load(path: state.edx.source?.metadata.filePath)
        await state.semEDS.pickFileElements(in: state.edx)
        XCTAssertNil(state.edx.intensitiesOnly)
    }

    /// The Results room reports the SEM spectrum's lines as the EDS room shows them: once Quantify has run, the room's fitted areas with σ
    /// on the room's lines, under "SEM-EDS line intensities". Red before (walk 2026-11-26): Results kept exspy's window sums of open time
    /// (Cu Lα 83,885, Zr Lα 82,216 counts) under "SEM-EDS composition" beside the room's fit (Cu Kα 1,256), two answers for one spectrum.
    @MainActor func testResultsReportTheEDSRoomsFitOfTheSEMSpectrum() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let url = try XCTUnwrap(DemoDocuments.Shipped.semEDSSpectrum.url)
        await state.edx.open(url: url).value
        await state.semEDS.load(path: state.edx.source?.metadata.filePath)
        await state.semEDS.pickFileElements(in: state.edx)
        let before = SEMSessionLedger.rows(of: state).filter { $0.kind == .composition }
        XCTAssertEqual(before.map(\.methods), Array(repeating: [.edsLines], count: before.count), "exspy's windows before Quantify")
        await state.edx.quantify()?.value
        await state.edx.settled()
        let fit = try XCTUnwrap(state.edx.fit, state.edx.fitFailure ?? "no fit")
        let rows = SEMSessionLedger.rows(of: state, locale: Locale(identifier: "en_US_POSIX")).filter { $0.kind == .composition }
        let fitted = fit.rows.filter { $0.failure == nil && !$0.groupID.isEmpty }
        XCTAssertFalse(fitted.isEmpty)
        XCTAssertEqual(rows.map(\.label), fitted.map { ElementWindows.label(ofLineID: $0.groupID) })
        for (row, f) in zip(rows, fitted) {
            XCTAssertEqual(row.methods, [.edsModelFit])
            XCTAssertTrue(row.value.hasPrefix(SEMEDSFormat.counts(f.net, locale: Locale(identifier: "en_US_POSIX")) + " ± "), "\(row.value) for \(f.net)")
        }
        XCTAssertEqual(SEMSessionRow.Kind.composition.title, "SEM-EDS line intensities")
    }

    @MainActor func testTheSpectrumOpensFromTheMenuAndTheLaunchArgument() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.semSpectrum)?.value
        XCTAssertEqual(state.navigation.workspaceArea, .edx)
        XCTAssertTrue(state.edx.hasImage || state.edx.isOpening, "the EDS room holds the spectrum or is opening it")
        XCTAssertTrue(LaunchOptions(arguments: ["--demo-sem-eds"]).demoSEMSpectrum)
        XCTAssertFalse(LaunchOptions(arguments: []).demoSEMSpectrum)
    }
}
