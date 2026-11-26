//
//  TiltPlanningTests.swift
//  The tilt planner core of plan rows R15 and R16 (#814, #815): the zone-axis map's poles and traces are the kit's (S12), the
//  tilts to each pole are the kit's holder's and bring it on the beam, the reach outline lies where the limits are, the axis is
//  calibrated from a second planted pattern with its β sense (a reversed-β holder, and the ambiguous one-tilt pair, #932),
//  and uncalibrated the room says so and gives no α or β. Planted: aluminium down
//  [0 0 1] at zero tilt. Red before: the app had no tilt planner.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import TEMCore

nonisolated final class TiltPlanningTests: XCTestCase {

    private func aluminiumDown001() throws -> CrystalOrientation {
        try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell)
    }

    /// Uncalibrated: the map's poles are the kit's, nearest first, and no pole has α or β; every sentence says why.
    func testUncalibratedMapHasAnglesButNoTilts() throws {
        let o = try aluminiumDown001()
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: HolderSettings(),
                                     wavelengthAngstroms: 0.025079)
        let kit = ZoneAxisMap.poles(structure: CrystalPresets.aluminum, orientation: o, maxIndex: 3, withinDeg: 60)
        XCTAssertEqual(plan.rows.map(\.uvw), kit.map(\.uvw))
        XCTAssertEqual(plan.rows.map(\.angleFromBeamDeg), kit.map(\.angleFromBeamDeg))
        XCTAssertEqual(plan.rows.first?.uvw, SIMD3(0, 0, 1))
        XCTAssertEqual(try XCTUnwrap(plan.rows.dropFirst().first).angleFromBeamDeg, 18.4349, accuracy: 1e-4)
        XCTAssertTrue(plan.rows.allSatisfy { $0.target == nil && $0.reachable == nil })
        XCTAssertTrue(plan.reach.isEmpty)
        XCTAssertEqual(plan.traces.count, 13, "{111}, {200} and {220}: 4 + 3 + 6 traces")
        let row = try XCTUnwrap(plan.row(SIMD3(1, 0, 2)))
        let sentence = plan.sentence(for: row)
        XCTAssertTrue(sentence.hasPrefix("[1 0 2] is 26.6° from the beam. The tilt axis is not calibrated."), sentence)
        XCTAssertFalse(sentence.contains("α +") || sentence.contains("α −"), sentence)
        XCTAssertEqual(plan.calibrationSentence, TiltPlanning.uncalibratedSentence)
        let csv = plan.csv().split(separator: "\n").map(String.init)
        XCTAssertTrue(csv.contains("# tilt axis: not calibrated"))
        let row102 = try XCTUnwrap(csv.first { $0.hasPrefix("\"[1 0 2]\",") || $0.hasPrefix("[1 0 2],") }, "\(csv.prefix(12))")
        let cells = row102.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(try XCTUnwrap(Double(cells[1])), atan(0.5) * 180 / .pi, accuracy: 1e-9, "26.5651°, written exact")
        XCTAssertEqual(Array(cells.dropFirst(2)), ["", "", ""], "uncalibrated: no α, β or reach")
    }

    /// Calibrated: each pole's tilts are the kit holder's, moving there puts the pole on the beam, and the sentence says α, β
    /// and whether the holder reaches them.
    func testCalibratedTiltsBringThePoleOnTheBeam() throws {
        let o = try aluminiumDown001()
        var holder = HolderSettings()
        holder.axisAngleDeg = 23
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: holder,
                                     wavelengthAngstroms: nil)
        let cell = CrystalPresets.aluminum.cell
        for row in plan.rows {
            let kit = try XCTUnwrap(holder.holder.tilts(toZoneAxis: row.uvw, cell: cell, orientation: o, at: .zero))
            XCTAssertEqual(row.target, kit.tilts)
            XCTAssertEqual(row.reachable, kit.reachable)
            let moved = try XCTUnwrap(holder.holder.orientation(o, at: .zero, movedTo: kit.tilts))
            let d = Double(row.uvw.x) * cell.realLattice[0] + Double(row.uvw.y) * cell.realLattice[1] + Double(row.uvw.z) * cell.realLattice[2]
            let lab = moved.labCoordinates(of: d)
            let n = (lab.x * lab.x + lab.y * lab.y + lab.z * lab.z).squareRoot()
            XCTAssertEqual(lab.z / n, 1, accuracy: 1e-9, "\(row.uvw) not on the beam")
        }
        let reachable = try XCTUnwrap(plan.rows.first { $0.reachable == true && $0.angleFromBeamDeg > 10 })
        XCTAssertTrue(plan.sentence(for: reachable).hasSuffix(": inside the holder's range."), plan.sentence(for: reachable))
        XCTAssertTrue(plan.sentence(for: reachable).contains("Set α "))
        let far = try XCTUnwrap(plan.rows.first { $0.reachable == false })
        XCTAssertTrue(plan.sentence(for: far).hasSuffix(": outside the holder's range of ±30°."), plan.sentence(for: far))
        // the reach outline: 4 × 45 points, each at most the larger limit's worth of tilt from the beam's centre
        XCTAssertEqual(plan.reach.count, 180)
        XCTAssertTrue(plan.reach.allSatisfy { DiffractoGeometry.StereographicProjection.angleFromCentreDeg($0) <= 43 }, "√(30² + 30²) ≈ 42.4°")
    }

    /// A second planted pattern at other tilts calibrates the axis it was planted with; too small a tilt change is refused in the
    /// kit's words; the sentence says the tilt change, the axis and the β sense. This small mixed pair (−5°, 3° to 7°, −4°) fits
    /// the other β sense within 0.25° too, so with no sense set it is refused as ambiguous (#932) and calibrates with the sense
    /// set by hand.
    func testCalibrationFromASecondPattern() throws {
        let o = try aluminiumDown001()
        var start = HolderSettings()
        start.alphaDeg = -5; start.betaDeg = 3
        let truth = DoubleTiltHolder(axisAngleDeg: 37)
        let otherTilts = DoubleTiltHolder.Tilts(alpha: 7, beta: -4)
        let other = try XCTUnwrap(truth.orientation(o, at: start.tilts, movedTo: otherTilts))
        let found = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                           otherTilts: otherTilts, otherName: "pattern B")
        guard case .failure(let ambiguous) = found, case .ambiguousSense = ambiguous else {
            return XCTFail("a pair both senses fit calibrated: \(found)")
        }
        XCTAssertTrue(ambiguous.description.contains("set the β sense by hand"), ambiguous.description)
        start.betaSenseSetting = .positive
        let result = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                            otherTilts: otherTilts, otherName: "pattern B")
        let calibrated = try result.get()
        XCTAssertEqual(try XCTUnwrap(calibrated.axisAngleDeg), 37, accuracy: 1e-4)
        XCTAssertEqual(calibrated.calibration?.otherPattern, "pattern B")
        XCTAssertEqual(calibrated.calibration?.betaSense, .positive)
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: calibrated,
                                     wavelengthAngstroms: nil)
        XCTAssertTrue(plan.calibrationSentence.hasPrefix("Calibrated from two patterns 14° apart: tilt axis at 37° in the pattern"),
                      plan.calibrationSentence)
        XCTAssertTrue(plan.calibrationSentence.hasSuffix("β turns the positive way, set by hand."), plan.calibrationSentence)
        let tooClose = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: o,
                                              otherTilts: DoubleTiltHolder.Tilts(alpha: -4.5, beta: 3), otherName: "pattern C")
        guard case .failure(let why) = tooClose else { return XCTFail("a 0.5° change calibrated") }
        XCTAssertTrue(why.description.hasPrefix("The two patterns are only 0.5° apart"), why.description)
    }

    /// A holder whose β reads the other way (#932): a pair that changes both tilts by 10° finds the reversed sense, and the
    /// tilts the plan gives bring each pole onto the beam on that holder. The positive model alone refuses the pair, and its
    /// tilts would be off by degrees. Mutation: the plan's holder ignoring the found sense, or calibrate always passing
    /// .positive - red.
    func testFlippedBetaHolderGivesTheRightTilts() throws {
        let o = try aluminiumDown001()
        let start = HolderSettings()
        let truth = DoubleTiltHolder(axisAngleDeg: 37, betaSense: .negative)
        let otherTilts = DoubleTiltHolder.Tilts(alpha: 10, beta: 10)
        let other = try XCTUnwrap(truth.orientation(o, at: start.tilts, movedTo: otherTilts))
        let calibrated = try TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                                    otherTilts: otherTilts, otherName: "pattern B").get()
        XCTAssertEqual(try XCTUnwrap(calibrated.axisAngleDeg), 37, accuracy: 1e-4)
        XCTAssertEqual(calibrated.calibration?.betaSense, .negative)
        XCTAssertEqual(calibrated.betaSense, .negative)
        XCTAssertEqual(calibrated.betaSenseSource, .calibration)
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: calibrated,
                                     wavelengthAngstroms: nil)
        XCTAssertTrue(plan.calibrationSentence.hasSuffix("β turns the reversed way, found from the pair."), plan.calibrationSentence)
        XCTAssertTrue(plan.csv().contains("# beta sense: reversed (calibration)\n"))
        let cell = CrystalPresets.aluminum.cell
        var worstPositiveError = 0.0
        for row in plan.rows where row.angleFromBeamDeg > 5 && row.angleFromBeamDeg < 30 {
            let target = try XCTUnwrap(row.target)
            let moved = try XCTUnwrap(truth.orientation(o, at: .zero, movedTo: target))
            let d = Double(row.uvw.x) * cell.realLattice[0] + Double(row.uvw.y) * cell.realLattice[1] + Double(row.uvw.z) * cell.realLattice[2]
            let lab = moved.labCoordinates(of: d)
            let n = (lab.x * lab.x + lab.y * lab.y + lab.z * lab.z).squareRoot()
            XCTAssertEqual(lab.z / n, 1, accuracy: 1e-8, "\(row.uvw) not on the beam of the reversed holder")
            let positive = try XCTUnwrap(DoubleTiltHolder(axisAngleDeg: 37).tilts(toZoneAxis: row.uvw, cell: cell, orientation: o, at: .zero))
            worstPositiveError = max(worstPositiveError, abs(positive.tilts.alpha - target.alpha), abs(positive.tilts.beta - target.beta))
        }
        XCTAssertGreaterThan(worstPositiveError, 1, "the positive model's tilts are off by degrees on this holder")
        var positiveOnly = start
        positiveOnly.betaSenseSetting = .positive
        let refused = TiltPlanning.calibrate(positiveOnly, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                             otherTilts: otherTilts, otherName: "pattern B")
        guard case .failure = refused else { return XCTFail("the positive model fitted a reversed holder: \(refused)") }
    }

    /// A pair that changes α only cannot tell the β sense: the kit's ambiguous refusal, and the holder stays uncalibrated, so
    /// no α or β is said (#932).
    func testOneTiltPairIsAmbiguous() throws {
        let o = try aluminiumDown001()
        let start = HolderSettings()
        let otherTilts = DoubleTiltHolder.Tilts(alpha: 10, beta: 0)
        let other = try XCTUnwrap(DoubleTiltHolder(axisAngleDeg: 37).orientation(o, at: start.tilts, movedTo: otherTilts))
        let result = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                            otherTilts: otherTilts, otherName: "pattern B")
        guard case .failure(let why) = result, case .ambiguousSense = why else { return XCTFail("one tilt told the β sense: \(result)") }
        XCTAssertTrue(why.description.hasPrefix("Both senses of β fit these two patterns"), why.description)
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: start,
                                     wavelengthAngstroms: nil)
        XCTAssertTrue(plan.rows.allSatisfy { $0.target == nil }, "uncalibrated after the refusal: no α or β")
        XCTAssertTrue(plan.csv().contains("# beta sense: positive (assumed)\n"))
    }

    /// The file's stage tilts are read when it has both; one alone leaves the typed ones.
    func testStageTiltsFromTheFile() {
        var h = HolderSettings()
        h.readStage(alphaDeg: 12.5, betaDeg: nil)
        XCTAssertEqual(h.source, .typed)
        XCTAssertEqual(h.alphaDeg, 0)
        h.readStage(alphaDeg: 12.5, betaDeg: -3)
        XCTAssertEqual(h.source, .file)
        XCTAssertEqual(h.alphaDeg, 12.5)
        XCTAssertEqual(h.betaDeg, -3)
    }

    /// Signs and limits in words.
    func testWords() {
        XCTAssertEqual(TiltPlanning.signed(24.1), "+24.1°")
        XCTAssertEqual(TiltPlanning.signed(-26.6), "−26.6°")
        XCTAssertEqual(TiltPlanning.signed(-0.01), "+0.0°")
        var h = HolderSettings()
        XCTAssertEqual(TiltPlanning.limitsText(h), "±30°")
        h.betaLimitDeg = 20
        XCTAssertEqual(TiltPlanning.limitsText(h), "α ±30°, β ±20°")
    }
}
