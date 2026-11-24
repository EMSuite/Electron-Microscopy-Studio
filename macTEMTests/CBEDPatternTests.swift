//
//  CBEDPatternTests.swift
//  A Simulation document's CBED pattern with a thickness series (#912, plan row MA9): the semiangle that keeps the discs apart, the
//  box the angular step needs with square pixels, the stored thicknesses, and one small run on the CPU float64 path whose patterns
//  are the kit's (`Probe` through the tiled potential, `diffractionPattern(maxAngle: .cutoff)`) in the display frame, calibrated on
//  the direct beam. The kit is pinned to abTEM 1.0.10 (SimulatoKit's CBED pins); this file pins the app's use of it. Red before:
//  there was no convergent beam.
//
//  Si a = 5.4309 Å. Down [1 1 1] the shortest reflection of the zone is 2 2̄ 0, |g| = √8 / a = 0.5208 Å⁻¹; at 200 kV λ = 0.025079 Å,
//  so the discs touch at λ|g| / 2 = 6.53 mrad: 6.5, the design's number.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoMultislice
import TEMCore
import TEMSession

nonisolated final class CBEDPatternTests: XCTestCase {

    func testFitDiscsIsHalfTheShortestReflectionsAngle() throws {
        XCTAssertEqual(try CBEDRun.separatedSemiangle(shortestG: 8.0.squareRoot() / 5.4309, volts: 200_000), 6.5)
        XCTAssertNil(CBEDRun.overlapSentence(semiangleMrad: 6.5, separatedMrad: 6.5))
        XCTAssertEqual(CBEDRun.overlapSentence(semiangleMrad: 9, separatedMrad: 6.5), "At 9 mrad the discs overlap.")
    }

    /// The box reaches λ / step on both sides and its two sides agree within 0.5 % (square pixels: Si [1 1 1]'s √3 cell needs
    /// repeats that are not 2-3-5 smooth); the planes step about 2 nm to the largest thickness, ascending, the last the whole slab,
    /// and the default run fits an 8 GB budget. Mutation: repeats from one side only; smooth repeats only; a plane at 0; the last
    /// thickness dropped; the 0.05 Å grid's cutoff as the default edge.
    func testThePlanNamesTheBoxForTheAngularStep() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 1), thicknessNM: 2).get()
        let plan = try CBEDRun.plan(built, settings: CBEDSettings(), volts: 200_000)
        let reach = 0.025079 / 0.00025
        XCTAssertGreaterThanOrEqual(plan.box.x, reach * 0.999)
        XCTAssertGreaterThanOrEqual(plan.box.y, reach * 0.999)
        XCTAssertLessThanOrEqual(abs(plan.box.x - plan.box.y) / max(plan.box.x, plan.box.y), CBEDRun.squareTolerance)
        XCTAssertLessThanOrEqual(max(plan.stepMrad.x, plan.stepMrad.y), 0.25 + 1e-9)
        XCTAssertEqual(plan.planePeriods, plan.planePeriods.sorted())
        XCTAssertEqual(Set(plan.planePeriods).count, plan.planePeriods.count)
        XCTAssertEqual(plan.planePeriods.last, plan.periods)
        XCTAssertGreaterThanOrEqual(plan.planePeriods.first ?? 0, 1)
        let periodNM = built.box.z / 10
        XCTAssertEqual(Double(plan.periods) * periodNM, 100, accuracy: periodNM / 2)
        XCTAssertGreaterThan(plan.planePeriods.count, 40, "about every 2 nm to 100 nm")
        XCTAssertTrue(plan.sentence.hasPrefix("Box "), plan.sentence)
        XCTAssertNil(plan.smallBoxSentence)
        XCTAssertNoThrow(try CBEDRun.checkPlan(plan, built: built, settings: CBEDSettings(), volts: 200_000,
                                               limits: SimulationLimits(memoryBudget: 8 << 30, largestBuffer: 8 << 30)))
    }

    /// Of the pairs within 0.5 %, the smallest box: a 1 × √2 unit to at least 10 Å. Mutation: the first pair found kept; the
    /// closest pair kept over a smaller one within tolerance.
    func testTheSquareBoxIsTheSmallestWithinTolerance() {
        let unit = SIMD2(1.0, 2.0.squareRoot())
        let r = CBEDRun.squareRepeats(unit: unit, reach: 10)
        let side = SIMD2(Double(r.x) * unit.x, Double(r.y) * unit.y)
        XCTAssertGreaterThanOrEqual(min(side.x, side.y), 10 - 1e-9)
        XCTAssertLessThanOrEqual(abs(side.x - side.y) / max(side.x, side.y), CBEDRun.squareTolerance)
        for nx in 10 ... 20 {
            for ny in 8 ... 16 {
                let a = Double(nx) * unit.x, b = Double(ny) * unit.y
                guard abs(a - b) / max(a, b) <= CBEDRun.squareTolerance else { continue }
                XCTAssertGreaterThanOrEqual(a * b, side.x * side.y - 1e-9, "\(nx) × \(ny) is smaller")
            }
        }
    }

    /// The edge must hold twice the semiangle and the first ring (Si [1 1 1] at 200 kV: 2 × 6.5 + 13.06 mrad), else the run is
    /// refused before it starts. Mutation: the semiangle counted once; the ring left out.
    func testAnEdgeThatCutsTheDiscsIsRefused() throws {
        let g = 8.0.squareRoot() / 5.4309
        XCTAssertEqual(CBEDRun.edgeSentence(edgeMrad: 20, semiangleMrad: 6.5, shortestG: g, volts: 200_000),
                       "A 20 mrad edge cuts the discs off: this probe and the first ring need 27 mrad.")
        XCTAssertNil(CBEDRun.edgeSentence(edgeMrad: 27, semiangleMrad: 6.5, shortestG: g, volts: 200_000))
        XCTAssertNil(CBEDRun.edgeSentence(edgeMrad: CBEDSettings().edgeMrad, semiangleMrad: 6.5, shortestG: g, volts: 200_000),
                     "the default edge holds Fit Discs' probe")
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 1), thicknessNM: 2).get()
        var settings = CBEDSettings()
        settings.edgeMrad = 20
        XCTAssertThrowsError(try CBEDRun.run(built, settings: settings, semiangleMrad: 6.5, volts: 200_000, specimen: "Si [1 1 1]",
                                             shortestG: g, reference: true)) { XCTAssertTrue($0 is CBEDRun.EdgeRefusal, "\($0)") }
    }

    /// One small run (a 1 mrad step, so a 25 Å box; 4 nm in steps of 2; a 2 mrad probe) on the CPU float64 path: one pattern a stored thickness,
    /// odd-sized about the direct beam, the probe's intensity kept to the edge, the bright field disc of the semiangle around the
    /// centre and dark beyond it before any Bragg disc, calibrated in 1/nm on the direct beam with the method line. Mutation: the
    /// pattern transposed (row = lab y); the calibration off the centre; the intensity left unnormalised.
    func testASmallRunIsTheKitsPatternInTheDisplayFrame() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2).get()
        var settings = CBEDSettings()
        settings.angularStepMrad = 1
        settings.largestThicknessNM = 4
        settings.edgeMrad = 40
        let pattern = try CBEDRun.run(built, settings: settings, semiangleMrad: 2, volts: 200_000, specimen: "Si [1 1 0]", reference: true)
        XCTAssertFalse(pattern.onMetal)
        XCTAssertFalse(pattern.beyondRegisteredDepth)
        XCTAssertEqual(pattern.patterns.count, pattern.thicknessesNM.count)
        XCTAssertGreaterThanOrEqual(pattern.patterns.count, 2)
        XCTAssertEqual(pattern.rows % 2, 1)
        XCTAssertEqual(pattern.columns % 2, 1)
        let rows = pattern.rows, columns = pattern.columns
        for p in pattern.patterns {
            XCTAssertEqual(p.count, rows * columns)
            let total = p.reduce(0) { $0 + Double($1) }
            XCTAssertEqual(total, 1, accuracy: 0.05, "the probe's intensity, Σ|Ψ(k)|² = 1, nearly all inside 40 mrad")
        }
        // The direct beam's disc (2 mrad) is bright at the centre; at 4 mrad, between it and any Bragg disc (111 is 8 mrad out, so
        // its disc starts at 6), it is dark.
        let first = pattern.patterns[0]
        let centre = Double(first[(rows / 2) * columns + columns / 2])
        let outside = Int((4 / pattern.rowStepMrad).rounded())
        XCTAssertGreaterThan(centre, 20 * Double(first[(rows / 2 + outside) * columns + columns / 2]))
        // The image of a pattern: rows down lab x, calibrated in 1/nm, origin on the direct beam, the method line in its notes.
        let image = pattern.image(at: 1, name: "CBED of Simulation 1")
        XCTAssertEqual(image.height, rows)
        XCTAssertEqual(image.width, columns)
        XCTAssertEqual(image.y?.scale ?? 0, pattern.rowDeltaQ * 10, accuracy: 1e-12)
        XCTAssertEqual(image.x?.origin, Double(columns / 2))
        XCTAssertEqual(image.voltage, 200_000)
        XCTAssertTrue(image.notes.contains { $0.hasPrefix("CBED · Si [1 1 0] · 200 kV · 2 mrad · ") }, "\(image.notes)")
        XCTAssertTrue(image.notes.contains { $0.hasSuffix("static lattice · exact (float64)") })
        XCTAssertEqual(pattern.index(nearest: 3.9), pattern.thicknessesNM.count - 1)
    }

    /// Under 20 Å across, the plan carries the design's chip.
    func testASmallBoxSaysTheProbeOverlapsItsCopies() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2).get()
        var settings = CBEDSettings()
        settings.angularStepMrad = 2
        let plan = try CBEDRun.plan(built, settings: settings, volts: 200_000)
        XCTAssertEqual(plan.smallBoxSentence?.hasSuffix("Å wide and repeats; the probe overlaps its own copies."), true)
    }

    /// The settings keep only valid edits; Fit Discs goes back to the separated semiangle. Mutation: a negative thickness kept; Fit
    /// Discs keeping the typed angle.
    @MainActor func testTheModelKeepsValidSettingsAndFitDiscs() {
        let model = CBEDModel()
        XCTAssertFalse(model.changeSettings { $0.largestThicknessNM = -1 })
        XCTAssertFalse(model.changeSettings { $0.angularStepMrad = 0 })
        XCTAssertFalse(model.changeSettings { $0.semiangleMrad = 80 })
        XCTAssertEqual(model.settings, CBEDSettings())
        XCTAssertTrue(model.changeSettings { $0.semiangleMrad = 9 })
        XCTAssertEqual(model.semiangle(shortestG: 8.0.squareRoot() / 5.4309, volts: 200_000), 9)
        model.fitDiscs()
        XCTAssertEqual(model.semiangle(shortestG: 8.0.squareRoot() / 5.4309, volts: 200_000), 6.5)
        XCTAssertNil(model.semiangle(shortestG: nil, volts: 200_000))
        XCTAssertNil(model.shownIndex, "no run yet")
    }
}
