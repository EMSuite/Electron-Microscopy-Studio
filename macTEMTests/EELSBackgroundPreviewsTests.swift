//
//  EELSBackgroundPreviewsTests.swift
//  The background previews under the EELS edges are fitted once per core spectrum and windows (#623): a zoom or a pan redraws the plot
//  without fitting again; a window drag or another spectrum fits anew. The curve is the kit's preview (`EELSBackgroundFit.extrapolation`).
//

import XCTest
import TEMCore
@testable import macTEM

nonisolated final class EELSBackgroundPreviewsTests: XCTestCase {

    /// A power law A·E^−r from 300 to 700 eV, 1 eV a channel.
    private static func core(scale: Double = 1e9) -> EELSPlotCurve {
        EELSPlotCurve(origin: 300, step: 1, counts: (0..<400).map { scale * pow(300 + Double($0), -3) })
    }

    /// Ten frames with the same spectrum and windows fit once; the curve is the kit's; moved windows and another spectrum fit again.
    /// Red under: the plot fitting every frame; the memo handing one edge's curve to another's windows.
    @MainActor func testThePreviewIsFittedOncePerSpectrumAndWindows() throws {
        let previews = EELSBackgroundPreviews()
        let core = Self.core()
        let windows = EELSEdgeWindows(background: 400...450, signal: 460...520)
        let first = previews.curve(of: core, windows: windows)
        for _ in 0..<10 { _ = previews.curve(of: core, windows: windows) }
        XCTAssertEqual(previews.fits, 1, "a zoom or a pan frame fits nothing")
        // Bit patterns, so the NaN outside the windows compares equal to itself.
        XCTAssertEqual(first?.map(\.bitPattern),
                       EELSBackgroundFit.extrapolation(of: core, windows: windows, over: 400...520)?.map(\.bitPattern))
        XCTAssertNotNil(first)
        let moved = EELSEdgeWindows(background: 405...450, signal: 460...520)
        _ = previews.curve(of: core, windows: moved)
        XCTAssertEqual(previews.fits, 2, "a window drag fits again")
        _ = previews.curve(of: core, windows: windows)
        XCTAssertEqual(previews.fits, 2, "back to the first windows: kept")
        _ = previews.curve(of: Self.core(scale: 2e9), windows: windows)
        XCTAssertEqual(previews.fits, 3, "another spectrum fits again")
    }
}
