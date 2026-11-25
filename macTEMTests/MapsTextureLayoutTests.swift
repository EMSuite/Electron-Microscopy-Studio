//
//  MapsTextureLayoutTests.swift
//  The Maps room's results fit their pane (#1060, seen on the Ni demo at 1280 × 800 on 25 Nov 2026): the pole figures and the ODF
//  sections take the pane's size with their aspect kept and the caption wraps under them, and the tab row is the tabs alone, so it
//  keeps its width whichever tab is chosen. Red before: the figures were a fixed 150 pt (the ODF 240 pt) in a horizontal scroller that
//  the strip cut at a third of their height, the caption a 150 pt column at the right cut mid-word, and choosing Histogram put a
//  "Histogram of" pop-up in the tab row.
//

import CoreGraphics
import XCTest
@testable import macTEM

nonisolated final class MapsTextureLayoutTests: XCTestCase {
    /// The trailing pane at the opening window size: 1280 pt less the sidebar (220) and the inspector (310), halved, by 800 pt less the
    /// toolbar (52) and the tab row (34).
    private let openingPane = CGSize(width: (1280 - 220 - 310) / 2, height: 800 - 52 - 34)
    /// Three pole figures and the IPF-Z density, square; a cubic phase's three ODF sections, four times wider than tall.
    private let poles = (count: 4, aspect: CGFloat(1))
    private let odf = (count: 3, aspect: CGFloat(0.25))

    @discardableResult private func assertFits(_ figures: (count: Int, aspect: CGFloat), in pane: CGSize, file: StaticString = #filePath, line: UInt = #line) -> MapsTextureLayout.Arrangement {
        let arrangement = MapsTextureLayout.arrangement(count: figures.count, aspect: figures.aspect, in: pane)
        let content = MapsTextureLayout.contentSize(count: figures.count, aspect: figures.aspect, arrangement: arrangement)
        XCTAssertLessThanOrEqual(content.width, pane.width + 0.001, "\(arrangement) fits across", file: file, line: line)
        XCTAssertLessThanOrEqual(content.height, pane.height + 0.001, "\(arrangement) fits down", file: file, line: line)
        return arrangement
    }

    /// At the opening size every figure and the caption fit the pane, each figure at least as wide as the fixed size it had.
    func testTheFiguresFitThePaneAtTheOpeningSize() {
        let p = assertFits(poles, in: openingPane)
        XCTAssertGreaterThanOrEqual(p.side, 150, "a pole figure no smaller than before")
        XCTAssertEqual(p.columns, 2, "two by two in the tall pane")
        let o = assertFits(odf, in: openingPane)
        XCTAssertGreaterThanOrEqual(o.side, 240, "an ODF section no narrower than before")
        XCTAssertEqual(o.columns, 1, "one section a row")
    }

    /// A short pane (the old strip's height) or a wide one still fits everything, the figures in more columns; a pane too small for a figure
    /// to be read keeps the smallest side, and the pane scrolls.
    func testTheFiguresFollowThePaneShape() {
        let shortPane = CGSize(width: 375, height: 260)
        XCTAssertEqual(assertFits(poles, in: shortPane).columns, 4)
        XCTAssertEqual(assertFits(odf, in: shortPane).columns, 2)
        let wide = assertFits(poles, in: CGSize(width: 1200, height: 400))
        XCTAssertEqual(wide.columns, 4)
        XCTAssertLessThanOrEqual(wide.side, MapsTextureLayout.maximumSide)
        let tiny = MapsTextureLayout.arrangement(count: poles.count, aspect: poles.aspect, in: CGSize(width: 120, height: 120))
        XCTAssertEqual(tiny.side, MapsTextureLayout.minimumSide)
        XCTAssertEqual(MapsTextureLayout.arrangement(count: 0, aspect: 1, in: openingPane).columns, 1)
    }

    /// The figures view sizes its cells from the layout, without a horizontal scroller or a fixed side, and the caption wraps under them.
    func testTheFiguresViewUsesTheLayout() throws {
        let analysis = try FFTRoomWiringTests.squeezedUI("MapsRoomAnalysis.swift")
        let figures = try XCTUnwrap(analysis.components(separatedBy: "struct MapsTextureFigures: View {").dropFirst().first?
            .components(separatedBy: "nonisolated enum MapsTextureLayout {").first)
        XCTAssertFalse(figures.contains("ScrollView(.horizontal)"))
        XCTAssertTrue(figures.contains("let arrangement = MapsTextureLayout.arrangement(count: figures.count, aspect: aspect, in: proxy.size)"))
        XCTAssertTrue(figures.contains("MapsTextureFigureCell(figure: figures[index], odf: odf, side: arrangement.side,"))
        XCTAssertTrue(figures.contains("Text(verbatim: MapsRoomFormat.textureCaption(texture, odf: odf)) .font(.caption).foregroundStyle(.secondary) .fixedSize(horizontal: false, vertical: true)"),
                      "the caption wraps")
        XCTAssertFalse(analysis.contains("LayoutPolicy.mapsTextureFigureSide"))
        XCTAssertFalse(analysis.contains("LayoutPolicy.mapsODFSectionWidth"))
    }

    /// The tab row is the tabs alone: nothing in it depends on the tab chosen, so its width is the same with and without Histogram; the
    /// histogram's kind and the texture's phase are on their tabs' own header lines.
    func testTheTabRowKeepsItsWidth() throws {
        let analysis = try FFTRoomWiringTests.squeezedUI("MapsRoomAnalysis.swift")
        // The Detail panel's tab row (#1095; the results pane's before).
        let pane = try XCTUnwrap(analysis.components(separatedBy: "struct MapsDetailPane: View {").dropFirst().first?
            .components(separatedBy: "struct MapsTexturePhasePicker: View {").first)
        let row = try XCTUnwrap(pane.components(separatedBy: "HStack {").dropFirst().first?.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").first)
        XCTAssertTrue(row.contains("SegmentedControl(label: \"Detail\""))
        XCTAssertFalse(row.contains("Picker("), "no pop-up in the tab row")
        XCTAssertFalse(row.contains("MapsTexturePhasePicker("))
        XCTAssertFalse(row.contains("state.detailTab =="), "nothing in the row depends on the tab")
        let histogram = try XCTUnwrap(analysis.components(separatedBy: "struct MapsHistogramPane: View {").dropFirst().first)
        XCTAssertTrue(histogram.contains("Picker(\"Histogram of\", selection: $state.histogramKind)"))
        let figures = try XCTUnwrap(analysis.components(separatedBy: "struct MapsTextureFigures: View {").dropFirst().first)
        XCTAssertTrue(figures.contains("MapsTexturePhasePicker(session: session)"))
    }
}
