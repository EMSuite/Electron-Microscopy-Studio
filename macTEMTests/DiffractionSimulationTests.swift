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
import DiffractoGeometry
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

    // MARK: Double diffraction and the excitation error (#786)

    /// Silicon down [1 1 0] forbids 002 (diamond: h + k + l = 4n + 2 with all even), yet 1̄11 + 11̄1 lands there: the overlay draws it
    /// only with Double diffraction on, as a spot of no intensity at |q| = 2 / 5.4309 Å⁻¹, 36.8263 px out at Δq 0.01. Red before #786:
    /// the settings had no such switch and the overlay drew only the kinematical spots.
    @MainActor func testDoubleDiffractionAddsSilicons002DownOneOneZero() throws {
        let image = blankPattern()
        let analysis = shown(image, zone: SIMD3(1, 1, 0))
        analysis.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named("Si"))))
        let forbidden: Set<MillerIndex> = [MillerIndex(0, 0, 2), MillerIndex(0, 0, -2)]
        let kinematical = try spots(analysis, image)
        XCTAssertFalse(kinematical.contains { forbidden.contains($0.hkl) }, "002 is forbidden in silicon")
        XCTAssertFalse(kinematical.contains(where: \.isDoubleDiffraction))
        XCTAssertFalse(analysis.simulation.doubleDiffraction, "off by default")

        analysis.simulation.doubleDiffraction = true
        let both = try spots(analysis, image)
        let added = both.filter(\.isDoubleDiffraction)
        XCTAssertEqual(Set(added.map(\.hkl)).intersection(forbidden), forbidden, "both 002 and 002̄ are added")
        for s in added {
            XCTAssertEqual(s.relative, 0); XCTAssertEqual(s.intensity, 0)
            XCTAssertFalse(kinematical.contains { $0.hkl == s.hkl }, "\(s.hkl) is a kinematical spot too")
            XCTAssertEqual(s.hkl.h + s.hkl.k, 0, "\(s.hkl) is not in [1 1 0]")
        }
        let s002 = try XCTUnwrap(added.first { $0.hkl == MillerIndex(0, 0, 2) })
        XCTAssertEqual(hypot(s002.row - 128, s002.column - 128), 2 / 5.4309 / 0.01, accuracy: 1e-6)
        XCTAssertEqual(Array(both.prefix(kinematical.count)).map(\.hkl), kinematical.map(\.hkl), "the kinematical spots come first, as before")

        let result = analysis.simulatedSpots(image: image)
        XCTAssertEqual(DiffractionSimulationText.summary(result, crystal: "Si", zoneAxis: SIMD3(1, 1, 0)),
                       "Si [1 1 0]: \(both.count) spots on the pattern, \(added.count) of them by double diffraction.")
        XCTAssertEqual(DiffractionSimulationText.spoken(result, zoneAxis: SIMD3(1, 1, 0)),
                       ", \(both.count) simulated spots of [1 1 0], \(added.count) by double diffraction")
    }

    /// The excitation error is σ of the kit's envelope, 0.02 Å⁻¹ by default (py4DSTEM's), and spots with |s| ≤ 3σ are kept: down
    /// [0 0 1] at the exact zone |s| = λg²/2 (λ 0.02508 Å at 200 kV), so σ = 0.002 Å⁻¹ keeps |s| ≤ 0.006: {2 0 0} of Au (|s| 0.00302) is
    /// kept, {2 2 0} (0.00603) is not. A value outside 0.001...1 is not taken.
    @MainActor func testTheExcitationErrorSetsWhichSpotsAreKept() throws {
        XCTAssertEqual(ZoneAxisOverlay.Settings().excitationError, 0.02)
        let image = blankPattern()
        let analysis = shown(image)
        let wide = try spots(analysis, image)
        XCTAssertTrue(wide.contains { $0.hkl == MillerIndex(2, 2, 0) })
        XCTAssertTrue(analysis.setExcitationError(0.002))
        let narrow = try spots(analysis, image)
        XCTAssertLessThan(narrow.count, wide.count, "a narrower window keeps fewer spots")
        XCTAssertTrue(narrow.contains { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertFalse(narrow.contains { $0.hkl == MillerIndex(2, 2, 0) })
        for bad: Double in [0, -0.02, 0.0005, 2, .nan, .infinity] { XCTAssertFalse(analysis.setExcitationError(bad), "\(bad)") }
        XCTAssertEqual(analysis.simulation.excitationError, 0.002, "a refused value leaves the last one")
    }

    // MARK: Turning by hand, Flip and the solutions (#787)

    /// Flip turns the drawn orientation 180° about the beam: Au (2 0 0) at [0 0 1] goes from row 177.0412 to row 78.9588. A Tilt-tool
    /// drag of 40 points down the rows tilts 2° (0.05° per point) and the header names the zone axis and the angle; an ⌥ drag a
    /// quarter turn round the centre carries (2 0 0) under the pointer, to column 177.0412. Red before #787: none of these existed.
    @MainActor func testFlipTiltAndTurnByHand() throws {
        let image = blankPattern()
        let analysis = shown(image)
        XCTAssertEqual(analysis.orientationLine, "Au [001]", "no Index answer: the drawn zone axis is named")
        XCTAssertFalse(analysis.isTurnedByHand)

        analysis.flip()
        XCTAssertTrue(analysis.isTurnedByHand)
        let flipped = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(flipped.row, 128 - 2 / 4.0782 / 0.01, accuracy: 1e-6)
        XCTAssertEqual(flipped.column, 128, accuracy: 1e-6)
        XCTAssertEqual(analysis.orientationLine, "Au [001] · set by hand")

        let base = try XCTUnwrap(analysis.drawnOrientation)
        analysis.turnByHand(to: ZoneAxisOverlay.tilted(base, drag: SIMD2(40, 0)))
        XCTAssertEqual(analysis.orientationLine, "Au · 2.0° from [001] · set by hand")
        let tilted = try XCTUnwrap(analysis.drawnOrientation)
        let (t, b) = (tilted.beamDirection, base.beamDirection)
        XCTAssertEqual(acos(min(1, t.x * b.x + t.y * b.y + t.z * b.z)) * 180 / .pi, 2, accuracy: 1e-6)

        analysis.setZoneAxis(SIMD3(0, 0, 1))
        XCTAssertFalse(analysis.isTurnedByHand, "a typed zone axis is not by hand")
        let start = try XCTUnwrap(analysis.drawnOrientation)
        XCTAssertNil(ZoneAxisOverlay.turned(start, start: SIMD2(1, 0), now: SIMD2(0, 40)), "no angle at the centre")
        analysis.turnByHand(to: try XCTUnwrap(ZoneAxisOverlay.turned(start, start: SIMD2(49, 0), now: SIMD2(0, 49))))
        let turned = try XCTUnwrap(try spots(analysis, image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(turned.row, 128, accuracy: 1e-6)
        XCTAssertEqual(turned.column, 128 + 2 / 4.0782 / 0.01, accuracy: 1e-6)
        XCTAssertEqual(analysis.simulation.zoneAxis, SIMD3(0, 0, 1), "the zone axis field shows the nearest")
    }

    /// Fit scale is on by default with a 3 % window, and off holds the scale; the Index section steps through at most five solutions.
    func testFitScaleAndTheSolutionLimit() throws {
        XCTAssertEqual(PatternIndexing.scaleWindow, 0.03)
        XCTAssertEqual(PatternIndexing.solverSettings(fitScale: true).scaleWindow, 0.03)
        XCTAssertEqual(PatternIndexing.solverSettings(fitScale: false).scaleWindow, 0)
        let o = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: try XCTUnwrap(StandardCrystals.named("Al")).structure.cell)
        func outcome(_ alternatives: Int, found: Bool = true) -> PatternIndexing.Outcome {
            PatternIndexing.Outcome(phase: "Al", verdict: .tied(count: alternatives + 1), spots: [], explained: 0, indexed: 0,
                                    orientation: found ? o : nil, alternatives: Array(repeating: o.rotatedInPlane(by: 1), count: alternatives),
                                    zoneAxis: nil, zoneAxisAngle: nil, scale: 1, misfitPercent: nil)
        }
        XCTAssertEqual(PatternIndexing.solutions(outcome(0)).count, 1)
        XCTAssertEqual(PatternIndexing.solutions(outcome(2)).count, 3)
        XCTAssertEqual(PatternIndexing.solutions(outcome(7)).count, 5, "at most five")
        XCTAssertEqual(PatternIndexing.solutions(outcome(2, found: false)).count, 0)
        XCTAssertEqual(PatternIndexing.solutions(outcome(2)).first, o, "the best first")
    }

    @MainActor func testTheFitScaleIsOnByDefault() {
        XCTAssertTrue(DiffractionAnalysis().fitScale)
    }
}
