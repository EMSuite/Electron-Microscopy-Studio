//
//  FFTStrainTests.swift
//  The FFT room's strain maps (MA16, #917). Two halves, as FFTAnalysisTests. The LANE, with an injected strain run whose jobs
//  park until the test finishes them: Map Strain takes the first two measured spots, refuses without two, lands on εxx, and a
//  region change, a new reference or a release takes the maps away. The PRODUCT, with `FFTStrainWork.live` on the planted image:
//  each map is ImagoKit's GPA called directly on the same crop, with εxx its column-column strain and εyy its row-row one, so the
//  room adds no arithmetic to the kit's numbers.
//  Every test names, in its comment, the change to the production code that turns it red.
//

import XCTest
import TEMCore
import TEMSession
import ImagoCore
import ImagoFFT
import ImagoFilters

nonisolated final class FFTStrainTests: XCTestCase {

    /// The plant's two lattices on region A's centred spectrum: (kx, ky) = (8, 5) at bin (37, 40) and (12, −3) at (29, 44).
    nonisolated static let first = (row: 37, col: 40)
    nonisolated static let second = (row: 29, col: 44)

    // MARK: - The reflections

    /// A measured spot's centroid becomes g in cycles per pixel about the centred spectrum's zero frequency, ⌊n / 2⌋: the plant's
    /// lattices are g = (5, 8) / 64 and (−3, 12) / 64. Red under: the centre taken as n / 2 − 1 or (n − 1) / 2 as a Double; the
    /// row and column swapped; g in bins instead of cycles per pixel.
    func testAMeasuredSpotIsItsLatticesReflection() throws {
        let a = FFTStrainReflection(try FFTAnalysisTests.measured(row: Self.first.row, col: Self.first.col), spot: 1)
        let b = FFTStrainReflection(try FFTAnalysisTests.measured(row: Self.second.row, col: Self.second.col), spot: 2)
        XCTAssertEqual(a.row, 5.0 / 64, accuracy: 0.05 / 64)
        XCTAssertEqual(a.column, 8.0 / 64, accuracy: 0.05 / 64)
        XCTAssertEqual(b.row, -3.0 / 64, accuracy: 0.05 / 64)
        XCTAssertEqual(b.column, 12.0 / 64, accuracy: 0.05 / 64)
        XCTAssertEqual(a.spot, 1)
    }

    /// The pair is the first two MEASURED spots on the spectrum asked at an angle to each other: a refused spot, one still
    /// measuring, one on another spectrum and the first's Friedel partner are passed over. Red under: the first two spots whatever
    /// their outcome; spots of another region taken; a collinear partner taken as g₂ (the kit would refuse the run).
    func testTheReflectionsAreTheFirstTwoMeasuredSpotsOfThisSpectrum() throws {
        let key = FFTSpectrumKey(contentVersion: 1, crop: FFTAnalysisTests.regionA)
        let other = FFTSpectrumKey(contentVersion: 1, crop: FFTAnalysisTests.regionB)
        let m1 = try FFTAnalysisTests.measured(row: Self.first.row, col: Self.first.col)
        let m2 = try FFTAnalysisTests.measured(row: Self.second.row, col: Self.second.col)
        let friedel = try FFTAnalysisTests.measured(row: 64 - Self.first.row, col: 64 - Self.first.col)
        let spots = [
            FFTSpot(number: 1, row: 1, col: 1, spectrumKey: key, outcome: .refused(.noPower)),
            FFTSpot(number: 2, row: 37, col: 40, spectrumKey: other, outcome: .measured(m1)),
            FFTSpot(number: 3, row: 37, col: 40, spectrumKey: key, outcome: .measured(m1)),
            FFTSpot(number: 4, row: 2, col: 2, spectrumKey: key),
            FFTSpot(number: 5, row: 27, col: 24, spectrumKey: key, outcome: .measured(friedel)),
            FFTSpot(number: 6, row: 29, col: 44, spectrumKey: key, outcome: .measured(m2)),
        ]
        let pair = try XCTUnwrap(FFTStrainReflection.firstTwo(of: spots, on: key))
        XCTAssertEqual([pair.0.spot, pair.1.spot], [3, 6])
        XCTAssertNil(FFTStrainReflection.firstTwo(of: Array(spots.prefix(5)), on: key), "the first and its Friedel partner only")
    }

    /// The reference windows: the whole of the pixels, or the centred half on each axis. Red under: the quarter off centre or
    /// a quarter of the side instead of half.
    func testTheReferenceWindows() {
        let whole = FFTStrainReference.whole.window(rows: 64, columns: 96)
        XCTAssertEqual(whole.rows, 0..<64)
        XCTAssertEqual(whole.columns, 0..<96)
        let quarter = FFTStrainReference.centredQuarter.window(rows: 64, columns: 96)
        XCTAssertEqual(quarter.rows, 16..<48)
        XCTAssertEqual(quarter.columns, 24..<72)
    }

    // MARK: - The product

    /// Each map is the kit's GPA of the same crop with the same reflections and window, εxx its column-column strain, εyy its
    /// row-row, εxy its row-column, drawn by `FFTStrainWork.drawn`. Red under: εxx and εyy swapped; the window not passed; the crop
    /// not taken.
    func testEachMapIsTheKitsOnTheSameCrop() async throws {
        let image = FFTAnalysisTests.plant()
        let g1 = FFTStrainReflection(try FFTAnalysisTests.measured(row: Self.first.row, col: Self.first.col), spot: 1)
        let g2 = FFTStrainReflection(try FFTAnalysisTests.measured(row: Self.second.row, col: Self.second.col), spot: 2)
        let key = FFTStrainKey(spectrum: FFTSpectrumKey(contentVersion: 1, crop: FFTAnalysisTests.regionA), g1: g1, g2: g2,
                               reference: .centredQuarter)
        let product = try await FFTStrainWork.live(image, key)
        let crop = try XCTUnwrap(image.micrograph.cropped(FFTAnalysisTests.regionA))
        let kit = try GeometricPhaseAnalysis.analyze(crop.pixels.map(Double.init), rows: 64, columns: 64,
                                                     g1: (g1.row, g1.column), g2: (g2.row, g2.column),
                                                     reference: .init(rows: 16..<48, columns: 16..<48))
        let maps: [(FFTStrainProduct.Component, [Double])] = [(.exx, kit.strainCC), (.eyy, kit.strainRR), (.exy, kit.strainRC),
                                                              (.rotation, kit.rotation)]
        for (component, values) in maps {
            let canvas = product.canvas(component)
            let expected = FFTStrainWork.drawn(values, width: 64, height: 64)
            XCTAssertEqual(canvas.width, 64)
            XCTAssertEqual(canvas.height, 64)
            XCTAssertEqual(canvas.normalized, expected.normalized, "\(component)")
            XCTAssertEqual(canvas.rawRange, expected.rawRange, "\(component)")
        }
        XCTAssertNotEqual(product.exx.normalized, product.eyy.normalized, "the plant's two strains differ, so a swap shows")
        XCTAssertEqual(product.unmeasured, kit.strainRR.filter { !$0.isFinite }.count)
    }

    /// A map is drawn over the 99th percentile of its magnitudes, symmetric, clipped past it, a NaN masked: one wild pixel at a
    /// frame edge does not wash out the rest. Red under: the largest magnitude as the range; values past it not clipped; NaN drawn.
    func testAMapIsDrawnOverItsNinetyNinthPercentile() {
        var values = (0 ..< 200).map { Double($0 % 2 == 0 ? 1 : -1) * 0.01 * Double($0) / 199 }
        values[7] = 5                                   // one wild pixel
        values[8] = .nan
        let canvas = FFTStrainWork.drawn(values, width: 20, height: 10)
        let extent = canvas.rawRange?.upperBound ?? 1
        XCTAssertLessThan(extent, 0.011, "the wild pixel is not the range")
        XCTAssertEqual(canvas.rawRange?.lowerBound, -extent)
        XCTAssertEqual(canvas.normalized[7], 1, "clipped to the top of the map")
        XCTAssertLessThan(canvas.normalized[8], 0, "masked")
        XCTAssertEqual(FFTStrainWork.drawn([0, 0, 0, 0], width: 2, height: 2).normalized, [0.5, 0.5, 0.5, 0.5], "no strain is the middle")
        XCTAssertNil(FFTStrainWork.drawn([.nan], width: 1, height: 1).rawRange)
    }

    /// Two collinear spots are the kit's refusal, thrown to the owner. Red under: the run answering maps of a singular basis.
    func testCollinearSpotsAreRefused() async throws {
        let g = FFTStrainReflection(row: 5.0 / 64, column: 8.0 / 64, spot: 1)
        let twice = FFTStrainReflection(row: 10.0 / 64, column: 16.0 / 64, spot: 2)
        let key = FFTStrainKey(spectrum: FFTSpectrumKey(contentVersion: 1, crop: FFTAnalysisTests.regionA), g1: g, g2: twice,
                               reference: .whole)
        do {
            _ = try await FFTStrainWork.live(FFTAnalysisTests.plant(), key)
            XCTFail("collinear reflections are refused")
        } catch let error as GeometricPhaseAnalysisError {
            XCTAssertEqual(error, .collinearReflections)
        }
    }

    // MARK: - The lane

    /// A run above 2048 × 2048 px is refused before it starts, saying to draw a region: never a hidden crop, never gigabytes. Red
    /// under: the size not checked (the job is asked for the whole image).
    @MainActor func testALargeImageIsRefusedBeforeTheRun() async throws {
        let rig = Rig()
        addTeardownBlock { await rig.drain() }
        rig.owner.show(FFTAnalysisTests.flat(width: 2050, height: 2048), contentVersion: 1)
        rig.owner.runStrain()
        let failure = try XCTUnwrap(rig.owner.strainFailure)
        XCTAssertTrue(failure.contains("2050 × 2048 px"), failure)
        XCTAssertTrue(failure.contains("Draw a region"), failure)
        XCTAssertFalse(rig.owner.isComputingStrain)
        try await Task.sleep(for: .milliseconds(80))
        let asked = await rig.strains.asked.count
        XCTAssertEqual(asked, 0)
    }

    /// An owner whose spectra, spots and strain runs park until the test finishes them.
    @MainActor final class Rig {
        let spectra: FFTAnalysisTests.ParkedJobs<FFTSpectrumKey, FFTSpectrumProduct>
        let spotJobs: FFTAnalysisTests.ParkedJobs<FFTAnalysisTests.SpotAsk, FFTSpot.Outcome>
        let strains: FFTAnalysisTests.ParkedJobs<FFTStrainKey, FFTStrainProduct>
        let owner: FFTAnalysis

        init() {
            let spectra = FFTAnalysisTests.ParkedJobs<FFTSpectrumKey, FFTSpectrumProduct>()
            let spotJobs = FFTAnalysisTests.ParkedJobs<FFTAnalysisTests.SpotAsk, FFTSpot.Outcome>()
            let strains = FFTAnalysisTests.ParkedJobs<FFTStrainKey, FFTStrainProduct>()
            self.spectra = spectra
            self.spotJobs = spotJobs
            self.strains = strains
            owner = FFTAnalysis(
                compute: FFTCompute(
                    spectrum: { _, key in try await spectra.run(key) },
                    spot: { _, crop, row, col in
                        (try? await spotJobs.run(FFTAnalysisTests.SpotAsk(crop: crop, row: row, col: col))) ?? .measuring
                    },
                    maskedInverse: { _, _ in throw CancellationError() },
                    filter: { _, _ in throw CancellationError() }),
                strain: { _, key in try await strains.run(key) })
        }

        func drain() async {
            await spectra.failAll()
            await spotJobs.failAll()
            await strains.failAll()
        }

        func finishStrain(_ n: Int) async {
            let key = await strains.asked[n]
            let canvas = FFTAnalysisTests.fakeCanvas()
            await strains.finish(n, .success(FFTStrainProduct(key: key, exx: canvas, eyy: canvas, exy: canvas, rotation: canvas,
                                                              unmeasured: 0)))
        }
    }

    /// A rig showing the plant's region A with its spectrum landed and `spots` of the two lattices measured.
    @MainActor private func landed(spots: Int = 2) async throws -> Rig {
        let rig = Rig()
        addTeardownBlock { await rig.drain() }
        rig.owner.setRegion(FFTAnalysisTests.regionA, committed: true)
        rig.owner.show(FFTAnalysisTests.plant(), contentVersion: 1)
        try await waitUntil("the spectrum is asked for", seconds: 8) { await rig.spectra.asked.count == 1 }
        let key = await rig.spectra.asked[0]
        await rig.spectra.finish(0, .success(FFTAnalysisTests.fakeSpectrum(key)))
        try await waitUntil("the spectrum lands", seconds: 8) { rig.owner.isSpectrumCurrent }
        for (n, bin) in [Self.first, Self.second].prefix(spots).enumerated() {
            rig.owner.measureSpot(row: bin.row, col: bin.col)
            try await waitUntil("the spot job starts", seconds: 8) { await rig.spotJobs.asked.count == n + 1 }
            let measurement = try FFTAnalysisTests.measured(row: bin.row, col: bin.col)
            await rig.spotJobs.finish(n, .success(.measured(measurement)))
            try await waitUntil("the spot lands", seconds: 8) { rig.owner.spots.count == n + 1 && rig.owner.spots[n].measured != nil }
        }
        return rig
    }

    /// Map Strain with one measured spot says why and asks nothing; the strain views stay unavailable. Red under: a run with a
    /// missing reflection; the failure left empty (the button does nothing visible).
    @MainActor func testMapStrainNeedsTwoMeasuredSpots() async throws {
        let rig = try await landed(spots: 1)
        rig.owner.runStrain()
        XCTAssertNotNil(rig.owner.strainFailure)
        XCTAssertFalse(rig.owner.isComputingStrain)
        let asked = await rig.strains.asked.count
        XCTAssertEqual(asked, 0)
        rig.owner.setSourceView(.strainXX)
        XCTAssertEqual(rig.owner.sourceView, .original, "no maps yet")
    }

    /// Map Strain asks for the spectrum's crop, the two spots' reflections and the reference chosen, and the pane shows εxx when
    /// the maps land. Red under: the key built from another spectrum, spots or reference; the pane not switched.
    @MainActor func testMapStrainRunsOnTheFirstTwoSpotsAndShowsExx() async throws {
        let rig = try await landed()
        rig.owner.setStrainReference(.centredQuarter)
        rig.owner.runStrain()
        XCTAssertTrue(rig.owner.isComputingStrain)
        try await waitUntil("the run starts", seconds: 8) { await rig.strains.asked.count == 1 }
        let key = await rig.strains.asked[0]
        XCTAssertEqual(key.spectrum, rig.owner.wantedSpectrumKey)
        XCTAssertEqual([key.g1.spot, key.g2.spot], [1, 2])
        XCTAssertEqual(key.reference, .centredQuarter)
        await rig.finishStrain(0)
        try await waitUntil("the maps land", seconds: 8) { rig.owner.strain != nil }
        XCTAssertEqual(rig.owner.sourceView, .strainXX)
        XCTAssertFalse(rig.owner.isComputingStrain)
        rig.owner.setSourceView(.rotation)
        XCTAssertEqual(rig.owner.sourceView, .rotation)
    }

    /// The maps belong to the crop and the reference they were made of: a region's drag sample, a new reference and a release
    /// each take them away, and the pane falls back to the file. Red under: `dropStrainResult` missing from `setRegion`,
    /// `setStrainReference` or `release`.
    @MainActor func testTheMapsGoWithTheirRegionAndReference() async throws {
        for change in ["region", "reference", "release"] {
            let rig = try await landed()
            rig.owner.runStrain()
            try await waitUntil("the run starts", seconds: 8) { await rig.strains.asked.count == 1 }
            await rig.finishStrain(0)
            try await waitUntil("the maps land", seconds: 8) { rig.owner.strain != nil }
            switch change {
            case "region": rig.owner.setRegion(FFTAnalysisTests.regionB, committed: false)
            case "reference": rig.owner.setStrainReference(.centredQuarter)
            default: rig.owner.release()
            }
            XCTAssertNil(rig.owner.strain, change)
            XCTAssertEqual(rig.owner.sourceView, .original, change)
        }
    }

    /// An answer for region A that lands while region B is transformed is dropped (R2). Red under: the strain lane's wanted key
    /// left as the stored one.
    @MainActor func testMapsAnsweredForAnOldRegionAreNotPublished() async throws {
        let rig = try await landed()
        rig.owner.runStrain()
        try await waitUntil("the run starts", seconds: 8) { await rig.strains.asked.count == 1 }
        rig.owner.setRegion(FFTAnalysisTests.regionB, committed: false)
        XCTAssertFalse(rig.owner.isComputingStrain)
        await rig.finishStrain(0)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(rig.owner.strain)
        XCTAssertEqual(rig.owner.sourceView, .original)
    }
}
