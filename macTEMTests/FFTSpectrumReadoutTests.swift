//
//  FFTSpectrumReadoutTests.swift
//  The FFT room's status-line readout over the power spectrum (#862): the frequency of the bin under the pointer in a spot row's words,
//  and its azimuth counter-clockwise from +x as drawn; nothing off the spectrum or when the axes cannot give one |q|.
//

import TEMCore
import XCTest
@testable import macTEM

nonisolated final class FFTSpectrumReadoutTests: XCTestCase {

    private let point = Locale(identifier: "en_US_POSIX")

    private func readout(row: Int, col: Int, unitsY: String = "1/nm") -> String? {
        FFTSpectrumReadout.text(row: row, col: col, width: 8, height: 8, spacingX: 0.25, spacingY: 0.25, unitsX: "1/nm", unitsY: unitsY,
                                locale: point)
    }

    /// Two bins right of the centre of an 8 × 8 spectrum at 0.25 nm⁻¹ a bin: |q| 0.5 nm⁻¹, d 2 nm, at 0°; two bins up (row 2): 90°, as the
    /// picture shows it; one bin left and one down: 225°. Red under: no readout over the spectrum (before #862), or the angle measured
    /// clockwise.
    func testTheBinUnderThePointerReadsItsSpacingAndAzimuth() {
        let spacing = FFTRoomFormat.spotValue(d: 2, q: 0.5, unit: "nm", locale: point)
        XCTAssertEqual(readout(row: 4, col: 6), spacing + " · 0.0°")
        XCTAssertEqual(readout(row: 2, col: 4), spacing + " · 90.0°")
        let diagonal = 0.25 * 2.0.squareRoot()
        XCTAssertEqual(readout(row: 5, col: 3), FFTRoomFormat.spotValue(d: 1 / diagonal, q: diagonal, unit: "nm", locale: point) + " · 225.0°")
    }

    /// The centre bin is the DC; a point off the spectrum and axes in two units read nothing.
    func testTheDCAndWhatReadsNothing() {
        XCTAssertEqual(readout(row: 4, col: 4), FFTSpectrumReadout.dc)
        XCTAssertNil(readout(row: -1, col: 4))
        XCTAssertNil(readout(row: 4, col: 8))
        XCTAssertNil(readout(row: 4, col: 6, unitsY: "1/px"))
    }

    /// The pane and the status line are wired: the FFT room's cursor readout is the spectrum's.
    func testTheStatusLineShowsTheSpectrumReadoutInTheFFTRoom() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let workspace = try String(contentsOf: root.appendingPathComponent("macTEM/UI/WorkspaceView.swift"), encoding: .utf8)
        XCTAssertTrue(workspace.contains("case .fft: appState.imageRoomTools.spectrumReadout"))
        let pane = try String(contentsOf: root.appendingPathComponent("macTEM/UI/FFTSpectrumImagePane.swift"), encoding: .utf8)
        XCTAssertTrue(pane.contains("appState.imageRoomTools.spectrumReadout = FFTSpectrumReadout.text(spectrum, at: p, in: geometry)"))
    }
}
