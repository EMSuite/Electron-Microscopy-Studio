//
//  DiffractionPowderTests.swift
//  The Diffraction room's powder pattern (#810) on the room's crystal: Al with Cu Kα gives pymatgen's five peaks from 10° to 90°,
//  111 at 38.51° (PowderTableTests' kit numbers, to 1e-4°); Au to compare with marks overlaps and a diagnostic peak as the kit
//  does; rings take the pattern's beam energy; the range and reach refuse what is out of bounds. Red before: the room had no powder.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class DiffractionPowderTests: XCTestCase {

    @MainActor private func aluminium() -> DiffractionCrystal {
        .preset(StandardCrystals.all.first { $0.name == "Al" }!)
    }

    @MainActor private func gold() -> PowderPhase {
        let au = StandardCrystals.all.first { $0.name == "Au" }!
        return PowderPhase(name: au.name, structure: au.structure)
    }

    @MainActor func testAluminiumWithCopperKAlphaHasFivePeaksAnd111At38_51() {
        let powder = DiffractionPowder()
        let table = powder.table(phases: powder.phases(crystal: aluminium(), others: []), volts: nil)
        XCTAssertEqual(table.rows.count, 5)
        let strongest = table.rows.max { $0.intensity < $1.intensity }
        XCTAssertEqual(strongest?.hkl, "111")
        XCTAssertEqual(strongest?.position ?? 0, 38.5057, accuracy: 1e-4)
        XCTAssertEqual(table.headline(phase: 0), "Al · Cu Kα · 5 peaks from 10° to 90° · strongest 111 at 38.51°")
        XCTAssertNil(table.marksSentence(phase: 0), "one phase has no marks")
    }

    @MainActor func testASecondPhaseIsMarkedAsTheKitMarksIt() {
        let powder = DiffractionPowder()
        powder.setCompareWith("Au")
        let phases = powder.phases(crystal: aluminium(), others: [gold()])
        XCTAssertEqual(phases.map(\.name), ["Al", "Au"])
        let table = powder.table(phases: phases, volts: nil)
        XCTAssertEqual(table, PowderTable.make(phases: phases, settings: powder.settings), "the room's table is the core's")
        XCTAssertNotNil(table.marksSentence(phase: 0))
        XCTAssertNotNil(table.marksSentence(phase: 1))
        powder.setMarkOverlaps(false)
        XCTAssertNil(powder.table(phases: phases, volts: nil).marksSentence(phase: 0))
        powder.setCompareWith("Al")
        XCTAssertEqual(powder.phases(crystal: aluminium(), others: [gold()]).map(\.name), ["Al"], "the crystal is not compared with itself")
    }

    @MainActor func testRingsTakeThePatternsBeamEnergy() {
        let powder = DiffractionPowder()
        powder.setKind(.rings)
        let phases = powder.phases(crystal: aluminium(), others: [])
        XCTAssertEqual(powder.table(phases: phases, volts: 300_000).settings.volts, 300_000)
        XCTAssertEqual(powder.table(phases: phases, volts: nil).settings.volts, 200_000)
        XCTAssertTrue(powder.table(phases: phases, volts: nil).headline(phase: 0).hasPrefix("Al · 200 kV · "))
    }

    @MainActor func testTheRangeAndReachAreBounded() {
        let powder = DiffractionPowder()
        powder.setTwoTheta(from: 0, to: 90)
        powder.setTwoTheta(from: 20, to: 20)
        XCTAssertEqual(powder.settings.twoThetaFrom, 10)
        powder.setTwoTheta(from: 120, to: 30)
        XCTAssertEqual(powder.settings.twoThetaFrom, 30)
        XCTAssertEqual(powder.settings.twoThetaTo, 120)
        powder.setReach(9)
        XCTAssertEqual(powder.settings.ringReach, 4)
    }

    @MainActor func testAPeakLineSaysWhatTheTableSays() throws {
        let powder = DiffractionPowder()
        let table = powder.table(phases: powder.phases(crystal: aluminium(), others: []), volts: nil)
        let row = try XCTUnwrap(table.rows.first { $0.hkl == "111" })
        XCTAssertEqual(DiffractionPowderText.line(row, table: table), "Al 111  d 2.338 Å  38.51°  100  ◆")
    }
}
