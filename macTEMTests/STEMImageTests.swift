//
//  STEMImageTests.swift
//  A Simulation document's STEM image (#913, plan row MA10): the scan step at Nyquist, the detector presets, one small run on the CPU
//  float64 path whose bands are sums of the kit's rings (abTEM's FlexibleAnnularDetector and integrate_radial), a run advanced in
//  slices equal to one run uninterrupted (Stop and Continue), and the model's band edits. The kit is pinned to abTEM 1.0.10
//  (SimulatoKit's STEM and flexible annular pins); this file pins the app's use of it. Red before: there was no STEM image.
//
//  At 200 kV λ = 0.025079 Å, so Nyquist for a 10 mrad probe is λ / 4α = 0.627 Å, the design's 0.63.
//

import XCTest
import DiffractoCore
import ImagoCore
import SimulatoCore
import TEMCore
import TEMSession

nonisolated final class STEMImageTests: XCTestCase {

    func testTheScanStepIsNyquistForTheProbe() throws {
        XCTAssertEqual(try STEMImage.nyquistStep(semiangleMrad: 10, volts: 200_000), 0.025079 / 0.04, accuracy: 1e-5)
    }

    /// The design's presets at α = 20 mrad (Paul, 23 Nov): BF 0 to 10, ABF 10 to 20, ADF 30 to 60, HAADF 60 to 200; BF, ABF and ADF
    /// follow the probe. Mutation: ADF fixed; HAADF relative.
    func testThePresetsAreTheDesigns() {
        XCTAssertEqual(STEMDetector.bf.band(semiangleMrad: 20), STEMBand(inner: 0, outer: 10))
        XCTAssertEqual(STEMDetector.abf.band(semiangleMrad: 20), STEMBand(inner: 10, outer: 20))
        XCTAssertEqual(STEMDetector.adf.band(semiangleMrad: 20), STEMBand(inner: 30, outer: 60))
        XCTAssertEqual(STEMDetector.haadf.band(semiangleMrad: 20), STEMBand(inner: 60, outer: 200))
        XCTAssertEqual(STEMDetector.adf.band(semiangleMrad: 10), STEMBand(inner: 15, outer: 30))
        XCTAssertEqual(STEMDetector.haadf.band(semiangleMrad: 10), STEMBand(inner: 60, outer: 200))
        XCTAssertEqual(STEMDetector.matching(STEMBand(inner: 30, outer: 60), semiangleMrad: 20), .adf)
        XCTAssertNil(STEMDetector.matching(STEMBand(inner: 31, outer: 60), semiangleMrad: 20))
    }

    /// A small static run: Si [1 1 0], 2 nm, 20 Å across, a 20 mrad probe, 1 Å steps, rings to 100 mrad.
    private func smallScan() throws -> STEMScan {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2,
                                                 lateralSize: HRTEMThermal.lateralSize).get()
        var settings = STEMSettings()
        settings.semiangleMrad = 20
        settings.scanStepAngstrom = 1
        settings.collectMrad = 100
        settings.defocusNM = 0
        return try STEMImage.prepare(built, settings: settings, csMM: 0, volts: 200_000, thermal: nil, specimen: "Si [1 1 0]",
                                     reference: true)
    }

    /// Advances `scan` from slices of `slice`, grown as the model grows them (`STEMImage.nextSlice`), until it is complete.
    private func finish(_ scan: STEMScan, slice: Duration) async throws -> STEMScan {
        var current = scan, step = slice
        while !current.isComplete {
            let before = (current.completedConfigurations, current.completedPositions)
            current = try await STEMImage.advance(current, slice: step)
            step = STEMImage.nextSlice(after: step, progressed: before != (current.completedConfigurations, current.completedPositions))
        }
        return current
    }

    /// A slice that made progress is never shortened and grows to ten seconds; one that made none doubles past it. Mutation: the
    /// slice reset to one second after progress (every resume sets its configuration up again).
    func testTheSliceGrowsAndNeverResets() {
        XCTAssertEqual(STEMImage.nextSlice(after: .seconds(1), progressed: true), .seconds(2))
        XCTAssertEqual(STEMImage.nextSlice(after: .seconds(8), progressed: true), .seconds(10))
        XCTAssertEqual(STEMImage.nextSlice(after: .seconds(16), progressed: true), .seconds(16))
        XCTAssertEqual(STEMImage.nextSlice(after: .seconds(16), progressed: false), .seconds(32))
    }

    /// The band stated is the band summed: edges snap to whole rings (BF at 15 mrad is 0 to 7.5, summed 0 to 8), and a preset still
    /// names a snapped band. Mutation: the fields keeping 7.5 while the kit truncates to 7.
    @MainActor func testTheBandSnapsToTheRings() {
        XCTAssertEqual(STEMBand(inner: 0, outer: 7.5).snapped(), STEMBand(inner: 0, outer: 8))
        XCTAssertEqual(STEMBand(inner: 22.4, outer: 45).snapped(), STEMBand(inner: 22, outer: 45))
        XCTAssertEqual(STEMDetector.abf.band(semiangleMrad: 1).snapped(), STEMBand(inner: 1, outer: 2), "never an empty band")
        XCTAssertEqual(STEMDetector.matching(STEMBand(inner: 0, outer: 8), semiangleMrad: 15), .bf)
        let model = STEMModel()
        XCTAssertTrue(model.changeSettings { $0.semiangleMrad = 15 })
        model.setDetector(.bf)
        XCTAssertEqual(model.band, STEMBand(inner: 0, outer: 8))
        XCTAssertTrue(model.setBand(STEMBand(inner: 10.4, outer: 20.6)))
        XCTAssertEqual(model.band, STEMBand(inner: 10, outer: 21))
        XCTAssertTrue(model.changeSettings { $0.collectMrad = 150.5 })
        XCTAssertEqual(model.settings.collectMrad, 151, "Collect to is whole rings")
    }

    /// A preset past the angles collected is not kept, and one left past them after Collect to is lowered says why. Mutation: the
    /// HAADF band kept with 100 mrad collected, giving no image and no sentence.
    @MainActor func testABandPastTheCollectedAnglesSaysWhy() {
        let model = STEMModel()
        XCTAssertNil(model.bandRefusal)
        XCTAssertTrue(model.changeSettings { $0.collectMrad = 100 })
        XCTAssertEqual(model.bandRefusal, "HAADF runs to 200 mrad, past the 100 mrad collected: choose a band inside it, or raise Collect to and simulate again.")
        XCTAssertTrue(model.setDetector(.adf))
        XCTAssertNil(model.bandRefusal)
        XCTAssertFalse(model.setDetector(.haadf), "HAADF does not fit 100 mrad")
        XCTAssertEqual(model.detector, .adf)
    }

    /// The probe wraps when its cone through the specimen and its own width pass the box: at 10 mrad and 200 kV, 100 nm spreads
    /// past a 20 Å box and 2 nm does not. Mutation: no check (the probe wraps with no word).
    func testAProbeThatWrapsIsNamed() throws {
        let sentence = try XCTUnwrap(STEMImage.wrapSentence(thicknessNM: 100, boxAngstrom: 20, semiangleMrad: 10, volts: 200_000))
        XCTAssertTrue(sentence.contains("Å through 100 nm, past the 20 Å box: it wraps onto its own copies"), sentence)
        XCTAssertNil(STEMImage.wrapSentence(thicknessNM: 2, boxAngstrom: 20, semiangleMrad: 10, volts: 200_000))
    }

    /// The bands are sums of the rings: BF and the rest add up to the whole collected range at every position; the bright field
    /// carries more per ring than the dark field; the unit image is the scan's shape; the HAADF band on the static lattice carries
    /// the chip, BF does not; the method line names every setting. Mutation: a band summed over the wrong rings; the image
    /// transposed (row = lab y); the chip on every band.
    func testTheBandsAreSumsOfTheKitsRings() async throws {
        let scan = try await finish(try smallScan(), slice: .seconds(600))
        XCTAssertTrue(scan.isComplete)
        let bf = try scan.unitImage(band: STEMBand(inner: 0, outer: 20))
        let rest = try scan.unitImage(band: STEMBand(inner: 20, outer: 100))
        let all = try scan.unitImage(band: STEMBand(inner: 0, outer: 100))
        XCTAssertEqual(bf.nx, Int((scan.unit.x / 1).rounded(.up)), "rows run along lab x")
        XCTAssertEqual(bf.ny, Int((scan.unit.y / 1).rounded(.up)))
        for i in all.values.indices { XCTAssertEqual(bf.values[i] + rest.values[i], all.values[i], accuracy: 1e-12) }
        let profile = scan.radialProfile()
        XCTAssertEqual(profile.angles.count, 100)
        XCTAssertGreaterThan(profile.intensities[5], 10 * profile.intensities[80], "the bright field disc outshines 80 mrad")
        XCTAssertEqual(scan.notQuantitative(band: STEMDetector.haadf.band(semiangleMrad: 20)), STEMImage.notQuantitative)
        XCTAssertNil(scan.notQuantitative(band: STEMDetector.bf.band(semiangleMrad: 20)))
        let image = try scan.image(band: STEMBand(inner: 0, outer: 20), fieldOfViewNM: 2, name: "STEM of Simulation 1")
        XCTAssertGreaterThanOrEqual(Double(image.height) * (image.y?.scale ?? 0), 2 - 1e-9)
        XCTAssertTrue(scan.methodLine(band: STEMBand(inner: 0, outer: 10)).hasPrefix("STEM · Si [1 1 0] · 200 kV · 20 mrad · defocus 0 nm · Cs 0 mm · BF 0 to 10 mrad"),
                      scan.methodLine(band: STEMBand(inner: 0, outer: 10)))
        XCTAssertTrue(scan.methodLine(band: STEMBand(inner: 0, outer: 10)).hasSuffix("static lattice · exact (float64)"))
    }

    /// A run advanced in short slices (Stop, then Continue, many times) equals the run uninterrupted. Mutation: a slice restarting
    /// its configuration; finished positions dropped at a stop.
    func testARunInSlicesEqualsOneUninterrupted() async throws {
        let whole = try await finish(try smallScan(), slice: .seconds(600))
        let sliced = try await finish(try smallScan(), slice: .milliseconds(20))
        let a = try whole.unitImage(band: STEMBand(inner: 0, outer: 100)), b = try sliced.unitImage(band: STEMBand(inner: 0, outer: 100))
        XCTAssertEqual(a.values, b.values)
    }

    /// The kit's count of positions in the configuration under way starts again at 0 when a configuration ends, the last included:
    /// a finished run, however it was stopped and continued, reports every position done, not 0 (#1005). Mutation: `positionsDone`
    /// back to the kit's count - red.
    func testAFinishedRunReportsEveryPositionDone() async throws {
        let fresh = try smallScan()
        XCTAssertEqual(fresh.positionsDone, 0)
        let count = fresh.positionCount
        XCTAssertGreaterThan(count, 1)
        var sliced = fresh
        while !sliced.isComplete { sliced = try await STEMImage.advance(sliced, slice: .milliseconds(20)) }   // Stop, Continue, ...
        XCTAssertTrue(sliced.isComplete)
        XCTAssertEqual(sliced.completedPositions, 0, "the kit's own count restarts when the last configuration ends")
        XCTAssertEqual(sliced.positionsDone, count)
    }

    /// The model keeps only valid settings and bands; Custom keeps the band shown; a preset band follows the semiangle. Mutation: a
    /// band past the collection angle kept; Custom resetting the band.
    @MainActor func testTheModelKeepsValidSettingsAndBands() {
        let model = STEMModel()
        XCTAssertEqual(model.detector, .haadf)
        XCTAssertFalse(model.changeSettings { $0.semiangleMrad = 0 })
        XCTAssertFalse(model.changeSettings { $0.collectMrad = 1000 })
        XCTAssertTrue(model.changeSettings { $0.semiangleMrad = 20 })
        model.setDetector(.adf)
        XCTAssertEqual(model.band, STEMBand(inner: 30, outer: 60))
        model.setDetector(nil)
        XCTAssertEqual(model.band, STEMBand(inner: 30, outer: 60), "Custom starts from the band shown")
        XCTAssertFalse(model.setBand(STEMBand(inner: 50, outer: 300)), "past the 200 mrad collected")
        XCTAssertFalse(model.setBand(STEMBand(inner: 50, outer: 40)))
        XCTAssertTrue(model.setBand(STEMBand(inner: 10, outer: 20)))
        XCTAssertEqual(model.detector, .abf, "a band equal to a preset names it")
        XCTAssertNil(model.scan)
    }
}
