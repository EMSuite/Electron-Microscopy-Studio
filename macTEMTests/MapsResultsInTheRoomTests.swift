//
//  MapsResultsInTheRoomTests.swift
//  The Maps room's results live in the room, its settings in the inspector (#1066, approved 25 Nov 2026): the Grains tab's heading carries
//  the five grain statistics and the settings they were made with, the picked grain's slip planes sit under the Grains table with their
//  trace's colour, and the inspector's Grains and Slip sections hold no result rows. Red before: the inspector listed Grains, Mean ECD,
//  Area-weighted, Mean intercept, ASTM E112 and Made with, and the picked grain's planes; the tab's line had three of the five.
//

import TEMCore
import XCTest
@testable import macTEM

nonisolated final class MapsResultsInTheRoomTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The source between `start` and `end`.
    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        try XCTUnwrap(text.components(separatedBy: start).dropFirst().first?.components(separatedBy: end).first, start)
    }

    func testTheInspectorHoldsNoResultRows() throws {
        let analysis = try ui("MapsRoomAnalysis.swift")
        let grains = try slice(analysis, from: "struct MapsGrainsSection: View {", to: "struct MapsSlipSection: View {")
        let slip = try slice(analysis, from: "struct MapsSlipSection: View {", to: "struct MapsTextureSection: View {")
        for section in [grains, slip] {
            XCTAssertFalse(section.contains("InspectorValueRow("), "no result row in the inspector")
            XCTAssertFalse(section.contains("grainRows("))
            XCTAssertFalse(section.contains("planeText("))
        }
        for setting in ["maps.boundaryAngle", "maps.minimumSize", "maps.showBoundaries"] { XCTAssertTrue(grains.contains(setting), setting) }
        for setting in ["maps.slip.load", "maps.slip.phase.", "maps.slip.traces"] { XCTAssertTrue(slip.contains(setting), setting) }
        XCTAssertTrue(grains.contains("InspectorWarning(\"The settings changed: Segment again to apply them.\")"), "the stale warning is about the settings")
    }

    /// The Grains table's heading carries the five statistics, the secondary line the settings; the picked grain's planes are the Slip
    /// table's (#1095: under the Grains table they pushed it to three rows), each in its trace's colour, in `planeText`'s formats.
    func testTheGrainsTabCarriesTheStatisticsAndTheSlip() throws {
        let analysis = try ui("MapsRoomAnalysis.swift")
        let table = try slice(analysis, from: "struct MapsGrainsTable: View {", to: "private func refresh()")
        XCTAssertTrue(table.contains("Text(verbatim: MapsRoomFormat.grainHeadline(analysis))"))
        XCTAssertTrue(table.contains("Text(verbatim: \"Made with \" + MapsRoomFormat.madeWith(analysis.settings))"))
        XCTAssertFalse(table.contains("MapsGrainSlipRows("), "no planes under the Grains table")
        XCTAssertFalse(analysis.contains("struct MapsGrainSlipRows"), "no slip rows as text")
        let rows = try slice(analysis, from: "struct MapsSlipTable: View {", to: "extension GrainRow {")
        XCTAssertTrue(rows.contains(".fill(MapsAnalysisOverlay.traceColour(plane.colour))"), "each plane in its trace's colour")
        XCTAssertTrue(rows.contains("Text(MapsRoomFormat.fraction($0.schmid))"), "the Schmid factor as planeText writes it")
        XCTAssertTrue(rows.contains("Text(MapsRoomFormat.angle($0.inclinationDegrees, digits: 0))"), "the inclination as planeText writes it")
        XCTAssertTrue(rows.contains("Text($0.traceText()).monospacedDigit()"))
        XCTAssertTrue(rows.contains("Text(verbatim: \"Slip in grain \\(row.id) · \\(row.phaseName)\")"), "the grain it is for")
        XCTAssertEqual(AgentDoorCoverage.controls["maps.grains.slip"], .tool("get_maps"))
        XCTAssertEqual(AgentDoorCoverage.controls["maps.slip.table"], .tool("get_maps"))
        XCTAssertEqual(AgentDoorCoverage.controls["maps.grains.madeWith"], .tool("get_maps"))
    }

    /// The five statistics in the heading's words, in the inspector's old order, each as the analysis has it; the settings in the
    /// ledger's words. One Ni grain of 16 µm² (a 4 × 4 map at a 1 µm step): ECD 2√(16/π) = 4.51 µm by number and by area.
    func testTheHeadlineNamesTheFiveStatistics() throws {
        let grid = CrystalMap.coordinates(shape: (rows: 4, columns: 4), steps: (dy: 1, dx: 1))
        let ni = CrystalPhase(name: "Ni", spaceGroup: 225, pointGroup: "m-3m", lattice: [3.524, 3.524, 3.524, 90, 90, 90])
        let map = try CrystalMap(euler: Array(repeating: SIMD3<Double>(0.1, 0.2, 0.3), count: 16), phaseIDs: Array(repeating: 0, count: 16),
                                 x: grid.x, y: grid.y, phaseList: PhaseList([(0, ni)]), scanUnit: "um")
        let analysis = try MapAnalysis.run(map, settings: MapAnalysisSettings(boundaryDegrees: 5, minimumSize: 1, kamMaxDegrees: 5))
        let en = Locale(identifier: "en_US")
        var expected = ["1 grain", "mean ECD 4.51 µm", "area-weighted 4.51 µm"]
        if let intercept = analysis.meanLinealIntercept { expected.append("mean intercept \(MapsRoomFormat.length(intercept, locale: en)) µm") }
        if let g = analysis.astmGrainSizeNumber { expected.append("ASTM E112 \(MapsRoomFormat.angle(g, locale: en))") }
        XCTAssertEqual(MapsRoomFormat.grainHeadline(analysis, locale: en), expected.joined(separator: " · "))
        XCTAssertEqual(MapsRoomFormat.madeWith(analysis.settings, locale: en), "5° · ≥ 1 point · KAM ≤ 5°")
        let made = try XCTUnwrap(MapsRoomFormat.grainRows(analysis, locale: en).first { $0.label == "Made with" })
        XCTAssertEqual(made.value, MapsRoomFormat.madeWith(analysis.settings, locale: en), "the ledger's words")
    }
}
