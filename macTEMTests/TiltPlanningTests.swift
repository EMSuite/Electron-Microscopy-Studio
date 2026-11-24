//
//  TiltPlanningTests.swift
//  The tilt planner core of plan rows R15 and R16 (#814, #815): the zone-axis map's poles and traces are the kit's (S12), the
//  tilts to each pole are the kit's holder's and bring it on the beam, the reach outline lies where the limits are, the axis is
//  calibrated from a second planted pattern, and uncalibrated the room says so and gives no α or β. Planted: aluminium down
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
        XCTAssertTrue(csv.contains("\"[1 0 2]\",26.5651,,,") || csv.contains("[1 0 2],26.5651,,,"), "\(csv.prefix(12))")
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
    /// kit's words; the sentence says the tilt change and the axis.
    func testCalibrationFromASecondPattern() throws {
        let o = try aluminiumDown001()
        var start = HolderSettings()
        start.alphaDeg = -5; start.betaDeg = 3
        let truth = DoubleTiltHolder(axisAngleDeg: 37)
        let otherTilts = DoubleTiltHolder.Tilts(alpha: 7, beta: -4)
        let other = try XCTUnwrap(truth.orientation(o, at: start.tilts, movedTo: otherTilts))
        let result = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: other,
                                            otherTilts: otherTilts, otherName: "pattern B")
        let calibrated = try result.get()
        XCTAssertEqual(try XCTUnwrap(calibrated.axisAngleDeg), 37, accuracy: 1e-4)
        XCTAssertEqual(calibrated.calibration?.otherPattern, "pattern B")
        let plan = TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: o, holder: calibrated,
                                     wavelengthAngstroms: nil)
        XCTAssertTrue(plan.calibrationSentence.hasPrefix("Calibrated from two patterns 14° apart: tilt axis at 37° in the pattern"),
                      plan.calibrationSentence)
        let tooClose = TiltPlanning.calibrate(start, structure: CrystalPresets.aluminum, orientation: o, other: o,
                                              otherTilts: DoubleTiltHolder.Tilts(alpha: -4.5, beta: 3), otherName: "pattern C")
        guard case .failure(let why) = tooClose else { return XCTFail("a 0.5° change calibrated") }
        XCTAssertTrue(why.description.hasPrefix("The two patterns are only 0.5° apart"), why.description)
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
