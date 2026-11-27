//
//  HistogramCaptionTests.swift
//  Role: the FFT and Diffraction rooms' histograms read the same words (#1097, EMSuiteUI#253): both draw the app's one
//        `IntensityHistogramView` on EMSuiteUI's `HistogramChart`, whose captions are the data's min · mean · max with the
//        window's edges on a line of their own. Red under: a room drawing its own chart, or the shared chart's captions
//        switching words with the window again.
//

import ShellControls
import XCTest

nonisolated final class HistogramCaptionTests: XCTestCase {
    private func ui(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("EMStudio/UI/\(name)"), encoding: .utf8)
    }

    func testTheFFTAndDiffractionHistogramsAreTheOneSharedChart() throws {
        XCTAssertTrue(try ui("FFTRoomInspector.swift").contains("IntensityHistogramView(histogram:"), "the FFT room draws the shared histogram")
        XCTAssertTrue(try ui("DiffractionRoomInspector.swift").contains("ImageRoomDisplaySection("), "the Diffraction room draws the shared display section")
        XCTAssertTrue(try ui("ImageRoomDisplay.swift").contains("IntensityHistogramView(histogram:"), "the display section draws the shared histogram")
        XCTAssertTrue(try ui("ImageRoomDisplay.swift").contains("HistogramChart("), "the shared histogram is EMSuiteUI's chart")
        XCTAssertEqual(HistogramWindowRules.statisticsCaptions, ["min", "mean", "max"])
        XCTAssertEqual(HistogramWindowRules.windowCaption, "window")
    }
}
