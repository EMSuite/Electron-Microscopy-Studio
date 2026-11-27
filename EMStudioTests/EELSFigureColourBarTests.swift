//
//  EELSFigureColourBarTests.swift
//  The EELS Maps PNG puts a colour bar under each map (#861): the tile's own colours over the window it shows, and the values at the window's
//  two ends with the unit. A flat map gets none.
//

import XCTest
import ShellMetal
import ShellSpectroscopy
import TEMCore
@testable import EMStudio

nonisolated final class EELSFigureColourBarTests: XCTestCase {

    private let point = Locale(identifier: "en_US_POSIX")

    /// A 0 to 2 nm map windowed to its middle half: the bar reads 0.5 to 1.5 nm, and its ends are the picture's colours at those values.
    /// Red under: no bar (before #861), or ends read off the whole scale instead of the window.
    func testTheBarReadsTheWindowItShowsInTheTilesColours() {
        let scale = EELSMapScale.scaled([0, 1, 2], mode: .minToMax)
        let coloring = MapColoring.colormap(.viridis)
        let window = MapAdjustment(low: 0.25, high: 0.75, gamma: 1)
        let bar = EELSFigureColourBar.bar(scale, coloring: coloring, adjustment: window, unit: "nm", locale: point)
        XCTAssertEqual(bar.low, "0.5")
        XCTAssertEqual(bar.high, "1.5 nm")
        XCTAssertEqual(bar.width, EELSFigureColourBar.steps)
        XCTAssertEqual(bar.rgba.count, 4 * EELSFigureColourBar.steps)
        let lowColour = MapRaster.rgba(values: [0.25], coloring: coloring, upper: 1, adjustment: window)
        let highColour = MapRaster.rgba(values: [0.75], coloring: coloring, upper: 1, adjustment: window)
        XCTAssertEqual(Array(bar.rgba.prefix(4)), lowColour)
        XCTAssertEqual(Array(bar.rgba.suffix(4)), highColour)
        XCTAssertNotEqual(lowColour, highColour, "precondition: the ramp runs from one colour to another")
    }

    /// A unitless map (t/λ) has no unit after its high end.
    func testAUnitlessMapHasNoUnit() {
        let bar = EELSFigureColourBar.bar(EELSMapScale.scaled([0.2, 0.8], mode: .minToMax), coloring: .colormap(.viridis), adjustment: MapAdjustment(),
                                          unit: "", locale: point)
        XCTAssertEqual(bar.low, "0.2")
        XCTAssertEqual(bar.high, "0.8")
    }

    /// The figure gives each map with a range its bar and a flat map none; the source keeps the wiring.
    func testTheFigurePassesTheBars() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let room = try String(contentsOf: root.appendingPathComponent("EMStudio/UI/EELSRoom.swift"), encoding: .utf8)
        XCTAssertTrue(room.contains("colourBar: scale.map { EELSFigureColourBar.bar($0, coloring: coloring, adjustment: adjustment, unit: tile.unit,"))
        XCTAssertTrue(room.contains("let scale = EELSMapScale.isFlat(tile.values) ? nil :"))
    }
}
