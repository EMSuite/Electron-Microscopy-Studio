//
//  EBSDRoomPolishTests.swift
//  The EBSD rooms after the pass of 25 Nov 2026 (#1061, Ni demo at 1280 × 800): a pane heading names its pane (progress is the toolbar's
//  busy line alone, the long facts the line under it), every switch in the EBSD inspectors is one size, and the Bands table shows every
//  column at the opening window size. Red before: the map heading held a progress bar and "675 of 4125 reac…", the Results heading ran
//  to "PC (0,4…", nine Patterns switches were `.controlSize(.small)`, and the tables' columns took their default widths.
//

import ShellLayout
import XCTest
@testable import macTEM

nonisolated final class EBSDRoomPolishTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The EBSD rooms' inspector and pane sources.
    private let ebsdFiles = ["PatternsRoom.swift", "PatternsRoomInspector.swift", "PatternsProcessingInspector.swift", "PatternsSimulationOverlay.swift",
                             "IndexingRoom.swift", "IndexingRoomInspector.swift", "IndexingCompare.swift", "IndexingSimulationOverlay.swift",
                             "MapsRoom.swift", "MapsRoomInspector.swift", "MapsRoomAnalysis.swift"]

    /// A heading names its pane: the Results heading is the run alone, short enough for the pane at the opening size, with no count and
    /// no PC; no EBSD heading draws a progress bar.
    func testAPaneHeadingNamesItsPane() throws {
        for run in ["Hough", "Dictionary", "Dictionary · Refined"] {
            let heading = IndexingInfoFormat.resultsHeading(run: run)
            XCTAssertLessThanOrEqual(heading.count, 32, heading)
            XCTAssertFalse(heading.contains(where: \.isNumber), "\(heading): no count or PC in the heading")
        }
        let indexing = try ui("IndexingRoom.swift")
        XCTAssertFalse(indexing.contains("ProgressView(value: session.progress)"), "the map heading's progress bar is the toolbar's")
        XCTAssertFalse(indexing.contains("reached\""), "the map shows no running count")
        XCTAssertTrue(indexing.contains("guard let result = session.result, !session.isIndexing, !session.isRefining else { return nil }"))
        let patterns = try ui("PatternsRoom.swift")
        XCTAssertFalse(patterns.contains("ProgressView(value: session.mapProgress)"))
        XCTAssertFalse(patterns.contains("ProgressView(value: session.qualityProgress)"))
    }

    /// One switch size in the EBSD inspectors: every on/off a regular switch with its label hidden, none made small (EMSuiteUI's
    /// histogram footer keeps its own Log y-axis switch until EMSuiteUI#253).
    func testEverySwitchIsOneSize() throws {
        for file in ebsdFiles {
            let text = try ui(file)
            XCTAssertFalse(text.contains(".toggleStyle(.switch).controlSize(.small)"), file)
            XCTAssertFalse(text.contains(".labelsHidden().toggleStyle(.switch)"), "\(file): one spelling, .toggleStyle(.switch).labelsHidden()")
            for range in text.ranges(of: ".controlSize(.small)") {
                let start = text.index(range.lowerBound, offsetBy: -160, limitedBy: text.startIndex) ?? text.startIndex
                let before = text[start..<range.lowerBound]
                XCTAssertTrue(before.contains("ProgressView"), "\(file): only a spinner is small")
            }
        }
    }

    /// The Bands table's seven columns fit the Bands pane in a 1280 pt window (less the sidebar and the inspector, halved, less the pane's
    /// padding), with the table's spacing between columns; every column of both tables has its width. 1280 pt was the opening width
    /// until a new window opened at 1440 pt (2026-11-26); the narrower window is kept, so the columns fit at both.
    @MainActor func testTheBandsTableShowsEveryColumn() throws {
        let pane: CGFloat = (1280 - 220 - 310) / 2 - 16
        let columns = [LayoutPolicy.ebsdIndexColumn] + Array(repeating: LayoutPolicy.ebsdNumberColumn, count: 5) + [LayoutPolicy.ebsdFamilyColumn]
        let spacing: CGFloat = 8
        XCTAssertLessThanOrEqual(columns.map { $0.ideal }.reduce(0, +) + spacing * CGFloat(columns.count), pane)
        for column in columns { XCTAssertLessThan(column.min, column.ideal) }
        let room = try ui("IndexingRoom.swift")
        let bands = try XCTUnwrap(room.components(separatedBy: "Table(session.detectedBands, selection: $selection) {").last?
            .components(separatedBy: ".focused($tableFocused)").first)
        XCTAssertEqual(bands.components(separatedBy: "TableColumn(").count, bands.components(separatedBy: ".width(min: LayoutPolicy.ebsd").count,
                       "every Bands column has its width")
        XCTAssertEqual(bands.components(separatedBy: "TableColumn(").count - 1, 7)
        XCTAssertEqual(room.components(separatedBy: ".width(min: LayoutPolicy.ebsd").count - 1, 9 + 10 + 7, "every Results and Bands column")
    }
}
