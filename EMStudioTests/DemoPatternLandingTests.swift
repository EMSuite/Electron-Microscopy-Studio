//
//  DemoPatternLandingTests.swift
//  #1025: Help > Open Demo Data > Au Diffraction Pattern opened in the Image room. It lands in the Diffraction room, ready for
//  Calibrate on Ring: the annulus on Au {111}, the standard and ring at their defaults, and the fit at those settings gives the
//  pattern's planted Δq. Red before: the Open had no landing for the demo pattern and the annulus stayed at 28 to 40 px (it reaches
//  Au {200} at 39.24 px). The nanowire spot pattern lands there too, with its file's scale (2026-11-26).
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import EMStudio

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

    /// 2026-11-26: the nanowire demo carries its scale in the file (`DemoDocuments.Shipped.nanowirePatternDeltaQ`, 0.0283 Å⁻¹ per pixel,
    /// calibrated on the pattern's GaAs {111}), so it opens with the scale marked as the file's and Index is not held for want of a
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
        // The wire's crystal, not the room's Au standard (walk of 26 Nov 2026), and the person's phase library untouched.
        XCTAssertEqual(analysis.crystal.structure.spaceGroupNumber, 216, analysis.crystal.name)
        XCTAssertEqual(analysis.crystal.structure.cell.a, 5.6533)
    }

    /// #1133: Index on the nanowire demo as it lands (GaAs, the file's scale, the room's defaults) finds the wire's ⟨110⟩ zone, the
    /// zone pyxem's tutorial names for it. Red before: the room's Au standard answered, and with GaAs the 1 % window on {111} about
    /// 11 px out (a tenth of a pixel) left the single frame "found but poor", 7.5° from [230].
    @MainActor func testIndexOnTheNanowireDemoFindsGaAs110() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.spotPattern)?.value
        try await waitUntil("the spot pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        XCTAssertNil(analysis.indexBlocker(image: image))
        await analysis.index(image: image)?.value
        let outcome = try XCTUnwrap(analysis.indexOutcome)
        let header = PatternIndexing.header(outcome)
        XCTAssertNotNil(outcome.orientation, header)
        XCTAssertEqual(outcome.zoneAxis.map { [abs($0.x), abs($0.y), abs($0.z)].sorted() }, [0, 1, 1], header)
        XCTAssertLessThan(try XCTUnwrap(outcome.zoneAxisAngle, header) * 180 / .pi, 3, header)
        XCTAssertGreaterThanOrEqual(outcome.indexed, 8, header)
    }
}
