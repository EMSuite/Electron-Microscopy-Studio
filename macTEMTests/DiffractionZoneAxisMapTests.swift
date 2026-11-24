//
//  DiffractionZoneAxisMapTests.swift
//  The zone-axis map in the Holder section (#814): the plan of Al indexed down [0 0 1] holds the zone axes to index 3 within 60°
//  of the beam at their stereographic positions (the kit's `ZoneAxisMap.poles`), [0 0 1] on the beam at the centre and [0 1 1]
//  45° off at tan(22.5°); three plane families; and the map says how many it shows and which is picked. Red before: no map.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import TEMCore
@testable import macTEM

nonisolated final class DiffractionZoneAxisMapTests: XCTestCase {

    private func down001() throws -> CrystalOrientation {
        try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell)
    }

    private func plan() throws -> TiltPlan {
        TiltPlanning.plan(phase: "Al", structure: CrystalPresets.aluminum, orientation: try down001(),
                          holder: HolderSettings(), wavelengthAngstroms: 0.025079)
    }

    private func length(_ p: SIMD2<Double>) -> Double { (p.x * p.x + p.y * p.y).squareRoot() }

    func testThePolesSitWhereTheKitProjectsThem() throws {
        let plan = try plan()
        let poles = ZoneAxisMap.poles(structure: CrystalPresets.aluminum, orientation: try down001(), maxIndex: 3, withinDeg: 60)
        XCTAssertEqual(plan.rows.map(\.uvw), poles.map(\.uvw))
        XCTAssertEqual(plan.rows.map(\.position), poles.map(\.position))
        let beam = try XCTUnwrap(plan.row(SIMD3(0, 0, 1)))
        XCTAssertEqual(beam.angleFromBeamDeg, 0, accuracy: 1e-9)
        XCTAssertEqual(length(beam.position), 0, accuracy: 1e-12)
        let off = try XCTUnwrap(plan.row(SIMD3(0, 1, 1)))
        XCTAssertEqual(off.angleFromBeamDeg, 45, accuracy: 1e-9)
        XCTAssertEqual(length(off.position), tan(22.5 * Double.pi / 180), accuracy: 1e-12)
        XCTAssertEqual(plan.traces.count, 3)
    }

    func testTheMapSaysWhatItShows() throws {
        let plan = try plan()
        let families = DiffractionZoneAxisMapText.families(plan)
        XCTAssertEqual(families.count, 3, "13 traces, one a ±(hkl) pair, of three families: \(plan.traces.map(\.family))")
        let named = families.joined(separator: ", ")
        XCTAssertEqual(DiffractionZoneAxisMapText.spoken(plan, selected: nil),
                       "\(plan.rows.count) zone axes and 3 plane families (\(named))")
        XCTAssertEqual(DiffractionZoneAxisMapText.spoken(plan, selected: SIMD3(0, 1, 1)),
                       "\(plan.rows.count) zone axes and 3 plane families (\(named)); [0 1 1] picked, 45.0° from the beam")
    }
}
