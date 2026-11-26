//
//  DemoPatternLandingTests.swift
//  #1025: Help > Open Demo Data > Au Diffraction Pattern opened in the Image room. It lands in the Diffraction room, ready for
//  Calibrate on Ring: the annulus on Au {111}, the standard and ring at their defaults, and the fit at those settings gives the
//  pattern's planted Δq. Red before: the Open had no landing for the demo pattern and the annulus stayed at 28 to 40 px (it reaches
//  Au {200} at 39.24 px). The nanowire spot pattern lands there too, with its file's scale (2026-11-26).
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

    /// #1086: the nanowire spot pattern opened in the Image room of a new tab. Opened from the Image room, it lands in Diffraction.
    /// Red before: the Open had no landing for it and the room stayed Image.
    @MainActor func testTheNanowireDemoLandsInTheDiffractionRoom() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let url = try XCTUnwrap(DemoDocuments.Shipped.nanowirePattern.url)
        state.navigation.workspaceArea = .image
        await state.open(urls: [url])?.value
        try await waitUntil("the spot pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        XCTAssertEqual(state.openItems.selected?.url, url)
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
    }

    /// 2026-11-26: the nanowire demo carries its scale in the file (`DemoDocuments.Shipped.nanowirePatternDeltaQ`, 0.0285 Å⁻¹ per pixel,
    /// calibrated on the frame's GaAs {111}), so it opens with the scale marked as the file's and Index is not held for want of a
    /// scale or a beam energy. Red before: the frame's axes were in pixels and the room said "Index needs a scale".
    @MainActor func testTheNanowireDemoOpensWithTheFilesScaleSoIndexIsNotBlockedOnIt() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.spotPattern)?.value
        try await waitUntil("the spot pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        let calibration = try XCTUnwrap(analysis.calibration(for: image), "the demo opens with a scale")
        XCTAssertEqual(calibration.source, .fileAxis)
        XCTAssertEqual(calibration.sourceText, "the file's axis")
        XCTAssertEqual(calibration.deltaQ, DemoDocuments.Shipped.nanowirePatternDeltaQ)
        XCTAssertEqual(analysis.volts(for: image), 300_000)
        let blocker = analysis.indexBlocker(image: image)
        XCTAssertFalse(blocker?.contains("scale") ?? false, blocker ?? "")
        XCTAssertFalse(blocker?.contains("beam energy") ?? false, blocker ?? "")
        XCTAssertFalse(blocker?.contains("centre") ?? false, blocker ?? "")
    }
}
