//
//  EdgeTextTests.swift
//  #1090: text at an edge is never cut mid-word. A ring's label near the pattern's right edge sits to the ring's left; the
//  Diffraction header drops its least needed parts whole (the camera length, "(file)", the size, Δq) and keeps the beam energy and
//  the scale's source; an agent's step names the tool on the infobar and keeps its parameters for the Output line. Red before: the
//  label always sat to the right, the header was one tail-truncated line ("scale: th…"), and the infobar read the raw parameters.
//

import CoreGraphics
import ShellLayout
import Foundation
import SwiftUI
import TEMCore
import XCTest
@testable import macTEM

nonisolated final class EdgeTextTests: XCTestCase {
    func testARingLabelNearTheRightEdgeSitsInside() {
        let inside = DiffractionHalo.beside(CGPoint(x: 100, y: 50), width: 80, within: 400)
        XCTAssertEqual(inside.point, CGPoint(x: 106, y: 42))
        XCTAssertEqual(inside.anchor, .leading)
        let atEdge = DiffractionHalo.beside(CGPoint(x: 380, y: 50), width: 80, within: 400)
        XCTAssertEqual(atEdge.point, CGPoint(x: 374, y: 42))
        XCTAssertEqual(atEdge.anchor, .trailing, "a label that would run past the edge ends at the ring")
    }

    func testTheDiffractionHeaderDropsWholePartsLeastNeededFirst() {
        let calibration = DiffractionCalibration(source: .fileAxis, deltaQ: 0.01, ring: nil)
        let levels = DiffractionHeaderText.levels(width: 219, height: 219, volts: 200_000, voltsFromFile: true, calibration: calibration)
        XCTAssertTrue(levels[0].hasPrefix("219 × 219 px · 200 kV (file) · scale: the file's axis · Δq "), levels[0])
        XCTAssertEqual(levels.last, "200 kV · scale: the file's axis", "the beam energy and the scale's source stay")
        XCTAssertEqual(Set(levels).count, levels.count, "no level repeats")
        for (a, b) in zip(levels, levels.dropFirst()) { XCTAssertGreaterThan(a.count, b.count) }
        XCTAssertEqual(DiffractionHeaderText.levels(width: 8, height: 8, volts: nil, voltsFromFile: false, calibration: nil),
                       ["8 × 8 px · no scale yet", "no scale yet"])
    }

    @MainActor func testAnAgentStepNamesTheToolOnTheInfobarAndKeepsItsParametersInTheOutput() {
        let state = AppState()
        state.setAgentStatus(MacTEMAgentDoor.agentLine("Diffraction room settings", [:]),
                             record: MacTEMAgentDoor.agentLine("Diffraction room settings", ["inner": "37", "calibrate": "true"]))
        XCTAssertEqual(state.statusText, "An agent used Diffraction room settings.")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Diffraction room settings (calibrate true; inner 37).") })
        XCTAssertFalse(state.activityLog.messages.contains { $0.hasSuffix("An agent used Diffraction room settings.") }, "one Output line, not two")
    }
}
