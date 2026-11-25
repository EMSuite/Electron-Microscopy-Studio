//
//  DiffractionTableHeadingsTests.swift
//  The Diffraction room's two tables in one heading style (#1041, HIG Lists and tables: nouns with title-style capitalization):
//  words capitalized, symbols in their own case, the unit in parentheses; an empty table shows its hint on the plain background (no
//  stripes under it); the table shows eight rows (a pane of the shell's bottom area since #1094, at the area's ideal height in a
//  1400 × 876 window).
//  Red before: the Readout table read "R px · family · d listed · odds · verdict" beside the Spots table's "Spot · d expected · Phase";
//  an empty table drew its stripes under the hint; the strip was 170 pt, four and a half rows.
//

import ShellLayout
import XCTest
@testable import macTEM

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
        let room = try source("macTEM/UI/DiffractionRoom.swift")
        let stripes = ".alternatingRowBackgrounds(TableStripes.shown(rowCount: rows.count) ? .automatic : .disabled)"
        XCTAssertEqual(room.components(separatedBy: stripes).count - 1, 2, "the Readout and the Spots table")
    }

    /// The table is a pane of the bottom area with no header of its own (the infobar's toggle names it), so the area at its ideal
    /// share of a 1400 × 876 window's column (the toolbar, 52 pt, and the infobar off) holds the table's header and eight rows.
    /// Mutation: a header row over the table, or the area at its floor (140 pt, four and a half rows).
    @MainActor func testTheTableShowsEightRows() throws {
        XCTAssertGreaterThanOrEqual(LayoutPolicy.diffractionTableRows, 8)
        let eight = LayoutPolicy.diffractionTableHeaderHeight + 8 * LayoutPolicy.diffractionTableRowHeight
        let column: CGFloat = 876 - 52 - LayoutPolicy.statusStripHeight
        let area = ProcessAreaLayout.heights(fraction: LayoutPolicy.processAreaIdealFraction, available: column).process
        XCTAssertGreaterThanOrEqual(area, eight, "the bottom area: \(area) pt")
        XCTAssertLessThan(LayoutPolicy.processAreaMinimumHeight, eight, "at its floor the area shows fewer: the ideal is what holds eight")
        let room = try source("macTEM/UI/DiffractionRoom.swift")
        XCTAssertFalse(room.contains("ProcessPaneHeader("), "no header row over a table")
        XCTAssertFalse(room.contains("diffractionReadoutHeight"), "no fixed strip")
    }
}
