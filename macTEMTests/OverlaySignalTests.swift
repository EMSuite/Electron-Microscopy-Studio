//
//  OverlaySignalTests.swift
//  The rooms' overlays carry a second signal beside colour (#799, plan row Q9 of 2.3): every pair that differed in hue alone now
//  differs by a dash, a width or a word, and every overlay line thickens under Increase Contrast. Red before: the calibrating ring,
//  the phase boundaries, the EELS windows and a refused edge differed from their neighbours by colour only.
//

import XCTest
@testable import macTEM

nonisolated final class OverlaySignalTests: XCTestCase {

    func testIncreaseContrastThickensTheLines() {
        for base: CGFloat in [1, 1.5, 2.25] {
            XCTAssertGreaterThan(OverlaySignal.width(base, increasedContrast: true), OverlaySignal.width(base, increasedContrast: false))
            XCTAssertEqual(OverlaySignal.width(base, increasedContrast: false), base, "the standard width is unchanged")
        }
    }

    /// Diffraction: the ring a calibration runs on was orange against the others' yellow.
    func testTheCalibratingRingIsDashed() {
        XCTAssertNotEqual(OverlaySignal.diffractionRing(calibrating: true), OverlaySignal.diffractionRing(calibrating: false))
        XCTAssertTrue(OverlaySignal.diffractionRing(calibrating: false).dash.isEmpty, "a fitted ring stays solid")
    }

    /// EBSD: grain boundaries were white, phase boundaries black, at one width.
    func testPhaseBoundariesAreWiderThanGrainBoundaries() {
        XCTAssertGreaterThan(OverlaySignal.phaseBoundary.widthScale, OverlaySignal.grainBoundary.widthScale)
    }

    /// EELS: background (orange) and signal (accent) windows, and either one refused (red), were told apart by colour.
    func testEveryEELSWindowStateDiffersWithoutColour() {
        let states = [OverlaySignal.eelsWindow(.background, refused: false), OverlaySignal.eelsWindow(.signal, refused: false),
                      OverlaySignal.eelsWindow(.signal, refused: true)]
        for (i, a) in states.enumerated() {
            for b in states[(i + 1)...] { XCTAssertNotEqual(a, b, "\(a) and \(b) differ by colour alone") }
        }
        XCTAssertNotEqual(OverlaySignal.eelsWindow(.background, refused: true).dash, OverlaySignal.eelsWindow(.background, refused: false).dash)
        XCTAssertEqual(OverlaySignal.eelsWindow(.signal, refused: true).word, "refused")
        XCTAssertNotEqual(OverlaySignal.eelsBackground(refused: true), OverlaySignal.eelsBackground(refused: false))
    }
}
