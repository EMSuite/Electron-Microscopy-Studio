//
//  DemoPatternLandingTests.swift
//  #1025: Help > Open Demo Data > Au Diffraction Pattern opened in the Image room. It lands in the Diffraction room, ready for
//  Calibrate on Ring: the annulus on Au {111}, the standard and ring at their defaults, and the fit at those settings gives the
//  pattern's planted Δq. Red before: the Open had no landing for the demo pattern and the annulus stayed at 28 to 40 px (it reaches
//  Au {200} at 39.24 px).
//

import XCTest
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DemoPatternLandingTests: XCTestCase {

    @MainActor func testTheAuDemoLandsInTheDiffractionRoomReadyToCalibrate() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.diffraction)?.value
        try await waitUntil("the demo pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertEqual(item.url, DemoDocuments.patternURL)
        XCTAssertEqual(item.diffractionView.annulusInner, 29)
        XCTAssertEqual(item.diffractionView.annulusOuter, 37)

        // Calibrate on Ring's own call, at the settings the demo opens with.
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        let families = analysis.standardFamilies()
        XCTAssertEqual(analysis.standard.name, "Au")
        XCTAssertEqual(families[analysis.familyIndex].name, "{111}")
        await analysis.fitRing(image: image, inner: item.diffractionView.annulusInner, outer: item.diffractionView.annulusOuter,
                               calibrateOn: families[analysis.familyIndex].family)?.value
        XCTAssertTrue(analysis.ringCalibrationExists, analysis.failure ?? "no calibration")
        let deltaQ = try XCTUnwrap(analysis.calibration(for: image)?.deltaQ)
        XCTAssertEqual(deltaQ, DemoDocuments.Truth.patternDeltaQ, accuracy: 0.005 * DemoDocuments.Truth.patternDeltaQ)
    }
}
