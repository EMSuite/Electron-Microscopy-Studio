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

    // MARK: - The 2.4 overlays, charts and sheets (#923)

    /// Diffraction: a precipitate's variants were pink rings against the matrix's cyan rings.
    func testVariantSpotsAreDiamondsAgainstTheMatrixsRings() {
        XCTAssertEqual(OverlaySignal.simulatedSpot(variant: false), .ring)
        XCTAssertEqual(OverlaySignal.simulatedSpot(variant: true), .diamond)
        let centre = CGPoint(x: 10, y: 10)
        let ring = OverlaySignal.outline(.ring, centre: centre, radius: 4), diamond = OverlaySignal.outline(.diamond, centre: centre, radius: 4)
        for (a, b) in [(ring.boundingBoxOfPath.minX, diamond.boundingBoxOfPath.minX), (ring.boundingBoxOfPath.maxY, diamond.boundingBoxOfPath.maxY)] {
            XCTAssertEqual(a, b, accuracy: 1e-9, "the same reach, so a spot's size still reads its intensity")
        }
        XCTAssertFalse(diamond.contains(CGPoint(x: 13, y: 13)), "a diamond leaves the corners a ring covers")
        XCTAssertTrue(ring.contains(CGPoint(x: 12.5, y: 12.5)))
    }

    /// Zone-axis map: the three plane families were orange, green and purple, and the legend's swatches colour only.
    func testTheZoneAxisFamiliesDifferByDash() {
        let strokes = (0..<3).map(OverlaySignal.zoneAxisFamily)
        XCTAssertTrue(strokes[0].dash.isEmpty, "the first family solid")
        XCTAssertEqual(Set(strokes.map(\.dash)).count, 3, "solid, dashed, dotted: \(strokes)")
    }

    /// Powder: the compared phase's sticks were another colour only.
    func testThePowderPhasesDifferByDash() {
        XCTAssertTrue(OverlaySignal.powderPhase(0).dash.isEmpty)
        XCTAssertNotEqual(OverlaySignal.powderPhase(0), OverlaySignal.powderPhase(1))
    }

    /// The views draw what the signals say: the variants by their mark, the map and its legend by the family's dash, the powder chart
    /// and its key by the phase's dash; the transfer chart names its aperture rule and draws the spacings in the secondary colour; no
    /// label under `.caption`; and the Find Phases sheet's warnings are the glyph with primary text, never orange text.
    /// Red under: rings back for the variants, a colour-only trace or swatch, a `.caption2` label, an orange sentence in the sheet.
    func testTheViewsDrawTheSecondSignal() throws {
        let room = try FFTRoomWiringTests.squeezedUI("DiffractionRoom.swift")
        XCTAssertTrue(room.contains("let mark = OverlaySignal.simulatedSpot(variant: true)"))
        XCTAssertTrue(room.contains("ctx.stroke(Path(OverlaySignal.outline(mark, centre: p, radius: r)), with: .color(.pink),"))
        let map = try FFTRoomWiringTests.squeezedUI("DiffractionZoneAxisMap.swift")
        XCTAssertTrue(map.contains("style: Self.traceStyle(i, increasedContrast: increasedContrast))"))
        XCTAssertTrue(map.contains("dash: OverlaySignal.zoneAxisFamily(i).dash)"), "the legend's line has the family's dash")
        XCTAssertFalse(map.contains(".caption2") || map.contains("Rectangle().fill("), "no label under caption, no colour swatch")
        let powder = try FFTRoomWiringTests.squeezedUI("DiffractionPowderSection.swift")
        XCTAssertTrue(powder.contains(".lineStyle(StrokeStyle(lineWidth: 1.5, dash: OverlaySignal.powderPhase(stick.phaseIndex).dash))"))
        XCTAssertTrue(powder.contains("LegendLine(colour: Self.phaseColours[i % Self.phaseColours.count], dash: OverlaySignal.powderPhase(i).dash)"))
        XCTAssertFalse(powder.contains(".foregroundStyle(by:"), "the chart's own legend is colour swatches only")
        let transfer = try FFTRoomWiringTests.squeezedUI("SimulationHRTEMOptics.swift")
        XCTAssertTrue(transfer.contains("RuleMark(x: .value(\"Aperture\", edge)).foregroundStyle(.red).lineStyle(StrokeStyle(dash: [2, 2])) .annotation(position: .top, alignment: .trailing) { Text(\"aperture\")"))
        XCTAssertTrue(transfer.contains("yEnd: .value(\"Transfer\", -0.8)) .foregroundStyle(.secondary) .annotation(position: .bottom) { Text(spacings[i].label)"))
        let sheet = try FFTRoomWiringTests.squeezedUI("DiffractionFindPhasesSheet.swift")
        XCTAssertTrue(sheet.contains("if let refusal = finder.refusal { InspectorWarning(refusal, font: .callout) }"))
        XCTAssertTrue(sheet.contains("if let weak = result.weakSentence { InspectorWarning(weak, font: .callout) }"))
        XCTAssertFalse(sheet.contains(".foregroundStyle(.orange)") || sheet.contains(".foregroundStyle(.red)"), "no coloured sentence")
        let precipitate = try FFTRoomWiringTests.squeezedUI("DiffractionPrecipitateSection.swift")
        XCTAssertFalse(precipitate.contains("magenta"), "one word for the variants' colour, the one the code draws")
    }
}
