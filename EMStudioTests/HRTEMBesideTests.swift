//
//  HRTEMBesideTests.swift
//  Place Beside for a Simulation document's HRTEM image (#898, plan row MA6): the measured image's nanometres per pixel or its
//  refusal, and the one picture of the pair at that scale: the measured image unchanged, the simulation resampled so a fringe of
//  0.4 nm spans 0.4 nm at the measured scale, turned by the rotation, matched to the measured mean and spread, and inset at the
//  size in unit cells asked for. Planted images, so every number is known. Red before: there was no Place Beside.
//

import ImagoCore
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class HRTEMBesideTests: XCTestCase {

    /// A simulated image of fringes 0.4 nm apart across its columns, sampled every 0.01 nm: two whole periods, so it wraps.
    private let fringes: CalibratedImage = {
        let width = 80, height = 8
        var pixels = [Float]()
        for _ in 0 ..< height { for c in 0 ..< width { pixels.append(Float(1 + cos(2 * Double.pi * Double(c) / 40))) } }
        return CalibratedImage(width: width, height: height, pixels: pixels, x: AxisCalibration(scale: 0.01, unit: "nm"),
                               y: AxisCalibration(scale: 0.01, unit: "nm"), fileName: "HRTEM of Simulation 1",
                               source: "HRTEM of Simulation 1", voltage: 200_000, notes: ["simulated image, no measured data"])
    }()

    /// A measured image of 60 × 40 pixels at 0.2 Å (0.02 nm) per pixel, with values that are not flat.
    private func measured(unit: String? = "Å", scale: Double = 0.2) -> CalibratedImage {
        let width = 60, height = 40
        let pixels = (0 ..< width * height).map { Float(100 + 10 * sin(Double($0) * 0.37) + Double($0 % 7)) }
        let axis = unit.map { AxisCalibration(scale: scale, unit: $0) }
        return CalibratedImage(width: width, height: height, pixels: pixels, x: axis, y: axis, fileName: "Si110.dm4",
                               source: "Si110.dm4", voltage: 200_000)
    }

    private func stats(_ v: [Double]) -> (mean: Double, sd: Double) {
        let m = v.reduce(0, +) / Double(v.count)
        return (m, (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot())
    }

    /// Ångström and nanometre calibrations read in nanometres; an axis in pixels or none at all is the design's refusal, and the
    /// composite then throws it. Mutation: the scale taken without its unit, an uncalibrated image drawn at 1 nm per pixel.
    func testTheMeasuredScaleIsReadInNanometresOrRefused() throws {
        let scale = try XCTUnwrap(HRTEMBeside.nanometresPerPixel(measured()))
        XCTAssertEqual(scale.x, 0.02, accuracy: 1e-15)
        XCTAssertEqual(scale.y, 0.02, accuracy: 1e-15)
        XCTAssertNil(HRTEMBeside.nanometresPerPixel(measured(unit: nil)))
        XCTAssertNil(HRTEMBeside.nanometresPerPixel(measured(unit: "px")))
        XCTAssertNil(HRTEMBeside.nanometresPerPixel(measured(unit: "1/nm")))
        XCTAssertEqual(HRTEMBeside.sameScaleLine(measured()), "Both at 0.02 nm per pixel.")
        XCTAssertThrowsError(try HRTEMBeside(measured: URL(fileURLWithPath: "/m")).composite(
            simulated: fringes, measured: measured(unit: "px"), cellNM: SIMD2(0.4, 0.4))) { error in
            XCTAssertEqual(error as? HRTEMBeside.Refusal, .uncalibrated)
            XCTAssertEqual(error.localizedDescription, HRTEMBeside.uncalibrated)
        }
        XCTAssertTrue(HRTEMBeside.isCoarser(measured(), than: (0.01, 0.01)))
        XCTAssertFalse(HRTEMBeside.isCoarser(measured(), than: (0.02, 0.02)))
    }

    /// Beside: the measured image on the left as it is, the simulation on the right at the measured scale (the 0.4 nm fringe is 20
    /// measured pixels, half of it the opposite phase), with the measured mean and spread, the pair calibrated in nm.
    /// Mutation: the simulation drawn at its own pixels (a 40-pixel fringe), no contrast match, the measured image resampled.
    func testBesideDrawsBothAtTheMeasuredScale() throws {
        let m = measured()
        let pair = try HRTEMBeside(measured: URL(fileURLWithPath: "/m")).composite(simulated: fringes, measured: m, cellNM: SIMD2(0.4, 0.4))
        let gap = 2, width = 60
        XCTAssertEqual(pair.width, 2 * width + gap)
        XCTAssertEqual(pair.height, 40)
        XCTAssertEqual(try XCTUnwrap(pair.x?.scale), 0.02, accuracy: 1e-15)
        XCTAssertEqual(pair.x?.unit, "nm")
        let out = pair.pixels, source = m.pixels
        for row in 0 ..< 40 { for c in 0 ..< width { XCTAssertEqual(out[row * pair.width + c], source[row * width + c]) } }

        let panel = (0 ..< 40).flatMap { row in (0 ..< width).map { Double(out[row * pair.width + width + gap + $0]) } }
        let wanted = stats(source.map(Double.init)), got = stats(panel)
        XCTAssertEqual(got.mean, wanted.mean, accuracy: 1e-3)
        XCTAssertEqual(got.sd, wanted.sd, accuracy: 1e-3)
        for row in [0, 17, 39] {
            for c in 0 ..< 30 {
                let a = panel[row * width + c] - got.mean, b = panel[row * width + c + 20] - got.mean
                let half = panel[row * width + c + 10] - got.mean
                XCTAssertEqual(a, b, accuracy: 1e-3 * got.sd, "one period is 20 measured pixels")
                XCTAssertEqual(a, -half, accuracy: 1e-3 * got.sd, "half a period is the opposite phase")
            }
        }
        XCTAssertTrue(pair.notes.contains("Both at 0.02 nm per pixel."))
        XCTAssertTrue(pair.notes.contains("beside Si110.dm4, rotated 0°"), "\(pair.notes)")
        XCTAssertTrue(pair.notes.contains("measured at 200 kV"), "\(pair.notes)")
    }

    /// A rotation of 90° turns fringes across the columns into fringes down the rows. Mutation: the rotation ignored, or turned
    /// the wrong way for a quarter turn's period check (it is symmetric, so the sign is held by the formula's own comment).
    func testTheRotationTurnsTheSimulation() throws {
        var settings = HRTEMBeside(measured: URL(fileURLWithPath: "/m"))
        settings.rotationDegrees = 90
        let pair = try settings.composite(simulated: fringes, measured: measured(), cellNM: SIMD2(0.4, 0.4))
        let start = 62, out = pair.pixels.map(Double.init)
        let sd = stats(Array(out[start ..< start + 60])).sd + stats((0 ..< 40).map { out[$0 * pair.width + start] }).sd
        XCTAssertGreaterThan(sd, 1)
        for row in 0 ..< 20 {
            let line = (0 ..< 60).map { out[row * pair.width + start + $0] }
            XCTAssertLessThan(stats(line).sd, 1e-3 * sd, "constant along a row")
            XCTAssertEqual(out[row * pair.width + start], out[(row + 20) * pair.width + start], accuracy: 1e-3 * sd, "20 rows a period")
        }
    }

    /// Inset: the simulation fills 2 × 1 unit cells of 0.4 nm (40 × 20 measured pixels) in the top right corner inside a one-pixel
    /// frame at the measured extreme farthest from its mean; the rest is the measured image. Mutation: the size in simulated pixels, no frame, the inset
    /// at the wrong corner.
    func testTheInsetIsItsUnitCellsInTheTopRightCorner() throws {
        var settings = HRTEMBeside(measured: URL(fileURLWithPath: "/m"))
        settings.layout = .inset
        settings.insetCells = SIMD2(2, 1)
        let m = measured()
        let pair = try settings.composite(simulated: fringes, measured: m, cellNM: SIMD2(0.4, 0.4))
        XCTAssertEqual(pair.width, 60)
        XCTAssertEqual(pair.height, 40)
        let out = pair.pixels, source = m.pixels
        let low = try XCTUnwrap(source.min()), high = try XCTUnwrap(source.max()), mean = stats(source.map(Double.init)).mean
        let frame = Double(high) - mean >= mean - Double(low) ? high : low   // the extreme farthest from the mean
        let left = 60 - 2 - 40, top = 2
        XCTAssertEqual(out[(top - 1) * 60 + left], frame, "frame above")
        XCTAssertEqual(out[top * 60 + left - 1], frame, "frame to the left")
        XCTAssertEqual(out[(top + 20) * 60 + left], frame, "frame below: 20 rows of inset")
        XCTAssertEqual(out[0], source[0])
        XCTAssertEqual(out[39 * 60 + 59], source[39 * 60 + 59])
        let first = Double(out[top * 60 + left]), period = Double(out[top * 60 + left + 20])
        XCTAssertEqual(first, period, accuracy: 1e-3 * stats(source.map(Double.init)).sd, "one 0.4 nm cell is 20 pixels")
    }

    /// The model keeps Place Beside only with a finite rotation and an inset size in range. Mutation: no check.
    @MainActor func testTheSettingsAreKeptOnlyWhenValid() {
        let model = SimulationModel()
        var settings = HRTEMBeside(measured: URL(fileURLWithPath: "/m"))
        settings.rotationDegrees = .nan
        XCTAssertFalse(model.setBeside(settings))
        settings.rotationDegrees = 12
        settings.insetCells = SIMD2(0, 4)
        XCTAssertFalse(model.setBeside(settings))
        XCTAssertNil(model.beside)
        settings.insetCells = SIMD2(4, 4)
        XCTAssertTrue(model.setBeside(settings))
        XCTAssertEqual(model.beside, settings)
        XCTAssertTrue(model.setBeside(nil))
        XCTAssertNil(model.beside)
    }
}
