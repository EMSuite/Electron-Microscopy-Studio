//
//  DiffractionSimulationTests.swift
//  The Diffraction room's simulated spots of a typed zone axis (#782, plan row R1): the zone axis as typed, the hkl labels, and
//  the spots DiffractoKit's `SpotPatternSimulator` gives placed on the image (`DiffractionAnalysis.simulatedSpots`). Red before
//  that change: the room had no simulation.
//
//  The pattern is a blank 256 × 256 image with no axis, centre (128, 128) and a typed Δq of 0.01 Å⁻¹/px at 200 kV, so every
//  position is worked by hand: Au (a 4.0782 Å, the room's standard) has (2 0 0) at |q| = 2 / 4.0782 = 0.490412 Å⁻¹, 49.0412 px from
//  the centre; at [0 0 1] and no turn the kit's lab x is the crystal's a axis (py4DSTEM's zone-axis frame), and lab x runs down the
//  rows, so (2 0 0) sits at row 177.0412, column 128. A 90° turn moves it to row 128, column 177.0412. (1 1 1̄) at [0 1 1] is
//  √3 / 4.0782 / 0.01 = 42.4709 px out.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionSimulationTests: XCTestCase {

    @MainActor private func blankPattern(voltage: Double? = 200_000) -> CalibratedImage {
        CalibratedImage(width: 256, height: 256, pixels: [Float](repeating: 1, count: 256 * 256), x: nil, y: nil,
                        fileName: "blank", source: "test", voltage: voltage)
    }

    @MainActor private func shown(_ image: CalibratedImage, zone: SIMD3<Int> = SIMD3(0, 0, 1), turn: Double = 0) -> DiffractionAnalysis {
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        analysis.typedDeltaQ = 0.01
        analysis.simulation.isShown = true
        analysis.simulation.zoneAxis = zone
        analysis.simulation.inPlaneDegrees = turn
        return analysis
    }

    @MainActor private func spots(_ analysis: DiffractionAnalysis, _ image: CalibratedImage) throws -> [ZoneAxisOverlay.Spot] {
        try XCTUnwrap(analysis.simulatedSpots(image: image)).get()
    }

    // MARK: The zone axis as typed

    func testAZoneAxisIsReadAsAPersonTypesIt() {
        let cases: [(String, SIMD3<Int>?)] = [
            ("[1 1 0]", SIMD3(1, 1, 0)), ("1 1 0", SIMD3(1, 1, 0)), ("110", SIMD3(1, 1, 0)), (" [0,0,1] ", SIMD3(0, 0, 1)),
            ("-1 1 0", SIMD3(-1, 1, 0)), ("−1 1 0", SIMD3(-1, 1, 0)), ("-110", SIMD3(-1, 1, 0)), ("1\u{0304}10", SIMD3(-1, 1, 0)),
            ("1 1\u{0304} 2", SIMD3(1, -1, 2)), ("<1 1 1>", SIMD3(1, 1, 1)), ("2 1 10", SIMD3(2, 1, 10)), ("[1 2 3]", SIMD3(1, 2, 3)),
            ("0 0 0", nil), ("000", nil), ("12", nil), ("1 1", nil), ("1 1 0 0", nil), ("abc", nil), ("", nil), ("1 a 0", nil),
            ("0\u{0304}01", nil), ("--110", nil), ("11-", nil), ("1 1 100", nil),
        ]
        for (text, uvw) in cases { XCTAssertEqual(ZoneAxisText.parse(text), uvw, "\"\(text)\"") }
        XCTAssertEqual(ZoneAxisText.text(SIMD3(-1, 1, 0)), "[-1 1 0]")
    }

    func testAnHKLLabelBarsItsNegativeIndices() {
        XCTAssertEqual(ZoneAxisText.label(MillerIndex(2, 0, 0)), "200")
        XCTAssertEqual(ZoneAxisText.label(MillerIndex(1, -1, 1)), "11\u{0304}1")
        XCTAssertEqual(ZoneAxisText.label(MillerIndex(-2, -2, 0)), "2\u{0304}2\u{0304}0")
        XCTAssertEqual(ZoneAxisText.label(MillerIndex(10, 0, -1)), "10 0 1\u{0304}")
    }

    // MARK: The spots on the pattern

    @MainActor func testThe001SpotsOfGoldLieWhereTheScaleAndCentrePutThem() throws {
        let image = blankPattern()
        let analysis = shown(image)
        XCTAssertEqual(analysis.crystal.name, "Au")
        let all = try spots(analysis, image)
        XCTAssertFalse(all.isEmpty)
        // Every spot is in the zone: h u + k v + l w = 0 (the first Laue zone of Au [001] lies past this image's reach).
        for s in all { XCTAssertEqual(s.hkl.l, 0, "\(s.hkl) is not in [0 0 1]") }
        let s200 = try XCTUnwrap(all.first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(s200.row, 128 + 2 / 4.0782 / 0.01, accuracy: 1e-9)
        XCTAssertEqual(s200.column, 128, accuracy: 1e-9)
        let s020 = try XCTUnwrap(all.first { $0.hkl == MillerIndex(0, 2, 0) })
        XCTAssertEqual(s020.row, 128, accuracy: 1e-9)
        XCTAssertEqual(s020.column, 128 + 2 / 4.0782 / 0.01, accuracy: 1e-9)
        XCTAssertNil(all.first { $0.hkl == MillerIndex(1, 0, 0) }, "fcc (1 0 0) is extinct")
        // Strongest first; the strongest is 1, the rest below.
        XCTAssertEqual(all.first?.relative, 1)
        XCTAssertTrue(zip(all, all.dropFirst()).allSatisfy { $0.intensity >= $1.intensity })
        // Every spot lands on the image.
        XCTAssertTrue(all.allSatisfy { $0.row >= -0.5 && $0.row <= 255.5 && $0.column >= -0.5 && $0.column <= 255.5 })
    }

    /// The overlay is drawn again on every change: a turn, another zone axis, another crystal and another centre each give the spots
    /// of the new settings at the next read.
    @MainActor func testEveryChangeGivesTheSpotsOfTheNewSettings() throws {
        let image = blankPattern()
        let analysis = shown(image)
        _ = try spots(analysis, image)
        let r = 2 / 4.0782 / 0.01

        analysis.simulation.inPlaneDegrees = 90
        let turned = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(turned.row, 128, accuracy: 1e-9)
        XCTAssertEqual(turned.column, 128 + r, accuracy: 1e-9)

        analysis.simulation.inPlaneDegrees = 0
        analysis.simulation.zoneAxis = SIMD3(0, 1, 1)
        let zone011 = try spots(analysis, image)
        for s in zone011 { XCTAssertEqual(s.hkl.k + s.hkl.l, 0, "\(s.hkl) is not in [0 1 1]") }
        let s111 = try XCTUnwrap(zone011.first { $0.hkl == MillerIndex(1, 1, -1) })
        XCTAssertEqual(hypot(s111.row - 128, s111.column - 128), 3.0.squareRoot() / 4.0782 / 0.01, accuracy: 1e-9)

        analysis.setCentre(row: 120, column: 130)
        let moved = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(1, 1, -1) })
        XCTAssertEqual(moved.row - 120, s111.row - 128, accuracy: 1e-9)
        XCTAssertEqual(moved.column - 130, s111.column - 128, accuracy: 1e-9)

        analysis.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named("Al"))))
        let aluminium = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(hypot(aluminium.row - 120, aluminium.column - 130), 2 / 4.0495 / 0.01, accuracy: 1e-9)

        analysis.typedDeltaQ = 0.02
        let rescaled = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(hypot(rescaled.row - 120, rescaled.column - 130), 2 / 4.0495 / 0.02, accuracy: 1e-9)
    }

    @MainActor func testTheOverlayNamesWhatItNeeds() throws {
        let image = blankPattern()
        let analysis = shown(image)
        analysis.simulation.isShown = false
        XCTAssertNil(analysis.simulatedSpots(image: image), "off: nothing drawn")
        XCTAssertNil(DiffractionSimulationText.summary(nil, crystal: "Au", zoneAxis: SIMD3(0, 0, 1)))
        XCTAssertEqual(DiffractionSimulationText.spoken(nil, zoneAxis: SIMD3(0, 0, 1)), "")

        analysis.simulation.isShown = true
        analysis.typedDeltaQ = nil
        guard case .failure(let noScale)? = analysis.simulatedSpots(image: image) else { return XCTFail("drawn without a scale") }
        XCTAssertTrue(noScale.sentence.hasPrefix("Needs a scale"), noScale.sentence)

        let noBeam = blankPattern(voltage: nil)
        let unpowered = shown(noBeam)
        guard case .failure(let why)? = unpowered.simulatedSpots(image: noBeam) else { return XCTFail("drawn without a beam energy") }
        XCTAssertTrue(why.sentence.hasPrefix("Needs the beam energy"), why.sentence)
        unpowered.typedBeamKV = 200
        XCTAssertNotNil(try? unpowered.simulatedSpots(image: noBeam)?.get(), "a typed beam energy is enough")

        analysis.typedDeltaQ = 0.01
        let result = analysis.simulatedSpots(image: image)
        let count = try XCTUnwrap(try? result?.get()).count
        XCTAssertEqual(DiffractionSimulationText.summary(result, crystal: "Au", zoneAxis: SIMD3(0, 0, 1)),
                       "Au [0 0 1]: \(count) spots on the pattern.")
        XCTAssertEqual(DiffractionSimulationText.spoken(result, zoneAxis: SIMD3(0, 0, 1)), ", \(count) simulated spots of [0 0 1]")
    }
}
