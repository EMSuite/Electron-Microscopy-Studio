//
//  DiffractionTableHeadingsTests.swift
//  The Diffraction room's two tables in one heading style (#1041, HIG Lists and tables: nouns with title-style capitalization):
//  words capitalized, symbols in their own case, the unit in parentheses; an empty table shows its hint on the plain background (no
//  stripes under it); the table shows seven rows (a tab of the shell's bottom area since #1094 and #1112, under the area's tab
//  header, at the area's ideal height in a 1400 × 876 window; eight before the header of #1112).
//  Red before: the Readout table read "R px · family · d listed · odds · verdict" beside the Spots table's "Spot · d expected · Phase";
//  an empty table drew its stripes under the hint; the strip was 170 pt, four and a half rows.
//

import ShellLayout
import XCTest
@testable import EMStudio

nonisolated final class DiffractionTableHeadingsTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testBothTablesHaveOneHeadingStyle() {
        XCTAssertEqual(DiffractionReadoutFormat.Column.allCases.map(\.title),
                       ["", "R (px)", "q (Å⁻¹)", "d (Å)", "Family", "d Listed", "Σ|F|² Listed", "Δd/d (%)", "Odds", "Verdict"])
        XCTAssertEqual(DiffractionSpotFormat.Column.allCases.map(\.title),
                       ["Spot", "hkl", "R (px)", "R (mm)", "q (Å⁻¹)", "d (Å)", "d Expected", "Δd/d (%)", "Phase", "I dyn (%)"])
        // A heading's first word is capitalized unless it is a symbol (hkl, q, d, R, Δd/d, Σ|F|², I dyn).
        let symbols: Set<String> = ["hkl", "q", "d", "R", "Δd/d", "Σ|F|²", "I", "dyn"]
        let titles = DiffractionReadoutFormat.Column.allCases.map(\.title) + DiffractionSpotFormat.Column.allCases.map(\.title)
        for title in titles where !title.isEmpty {
            for word in title.split(separator: " ") where !word.hasPrefix("(") && !symbols.contains(String(word)) {
                XCTAssertTrue(word.first?.isUppercase ?? false, "\(title): \(word)")
            }
        }
    }

    func testAnEmptyTableDrawsNoStripes() throws {
        XCTAssertFalse(TableStripes.shown(rowCount: 0))
        XCTAssertTrue(TableStripes.shown(rowCount: 1))
        let room = try source("EMStudio/UI/DiffractionRoom.swift")
        let stripes = ".alternatingRowBackgrounds(TableStripes.shown(rowCount: rows.count) ? .automatic : .disabled)"
        XCTAssertEqual(room.components(separatedBy: stripes).count - 1, 2, "the Readout and the Spots table")
    }

    /// The table is a tab of the bottom area with no header of its own (the area's tab header names it, #1112), so the area at its
    /// ideal share of a 1400 × 876 window's column (the toolbar, 52 pt, and the infobar off), less that tab header and its divider,
    /// holds the table's header and seven rows. Mutation: a header row of the room's over the table, or the area at its floor (140 pt).
    @MainActor func testTheTableShowsSevenRows() throws {
        XCTAssertGreaterThanOrEqual(LayoutPolicy.diffractionTableRows, 7)
        let rows = LayoutPolicy.diffractionTableHeaderHeight + CGFloat(LayoutPolicy.diffractionTableRows) * LayoutPolicy.diffractionTableRowHeight
        let column: CGFloat = 876 - 52 - LayoutPolicy.statusStripHeight
        let area = ProcessAreaLayout.heights(fraction: LayoutPolicy.processAreaIdealFraction, available: column).process
        let tab = area - LayoutPolicy.paneHeaderHeight - 1   // the area's tab header and the divider under it
        XCTAssertGreaterThanOrEqual(tab, rows, "the bottom area's tab: \(tab) pt")
        XCTAssertLessThan(LayoutPolicy.processAreaMinimumHeight - LayoutPolicy.paneHeaderHeight - 1, rows,
                          "at its floor the area shows fewer: the ideal is what holds them")
        let room = try source("EMStudio/UI/DiffractionRoom.swift")
        XCTAssertFalse(room.contains("ProcessPaneHeader("), "no header row over a table")
        XCTAssertFalse(room.contains("diffractionReadoutHeight"), "no fixed strip")
    }
}
