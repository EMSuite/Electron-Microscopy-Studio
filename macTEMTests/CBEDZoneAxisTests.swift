//
//  CBEDZoneAxisTests.swift
//  A Simulation document's CBED pattern is the exact zone axis (#1004): the probe goes down it untilted (`CBEDRun.run`), so no
//  reflection meets its Bragg condition inside its disc and Measure Thickness has no two-beam fringes to fit at any stored
//  thickness. The measurement says that instead of "fewer than two fringes … a thicker area", and Show CBED Pattern says a tilt set
//  by hand is not simulated (its run key holds the zone axis only, so nothing runs again).
//

import DiffractoCore
import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class CBEDZoneAxisTests: XCTestCase {
    /// Measure Thickness on a CBED item refuses with the zone-axis reason before any fit. Red before: the placeholder pattern's
    /// inputs refused for no phase, and a computed pattern went to the fit, which answered "Fewer than two fringes … a thicker area".
    @MainActor func testMeasureThicknessOnASimulatedCBEDPatternSaysItIsTheZoneAxis() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let url = DemoDocuments.cbedURL(of: URL(fileURLWithPath: "/macTEM-demo/Simulation 1"))
        await state.open(urls: [url])?.value
        try await waitUntil("the CBED item to open", seconds: 30) { state.openItems.selected?.session.image != nil }
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertTrue(DemoDocuments.isCBED(item.url))
        item.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        item.diffraction.setZoneAxis(SIMD3(1, 1, 0))
        let sentence = CBEDThicknessModel.zoneAxisPatternSentence(SIMD3(1, 1, 0))
        XCTAssertTrue(sentence.contains("[1 1 0]"), sentence)
        guard case .failure(let refusal) = item.thicknessInputs else { return XCTFail("a zone-axis pattern is measured") }
        XCTAssertEqual(refusal.sentence, sentence)
        await item.thickness.measure(item.thicknessInputs)
        guard case .failure(let shown)? = item.thickness.outcome else { return XCTFail("no refusal shown") }
        XCTAssertEqual(shown.sentence, sentence, "the section shows the reason")
    }

    /// A tilt set by hand off the zone axis is named as not simulated; on the axis, with a Parallel beam or after typing the axis
    /// again there is no note. Red before: there was no note, and run_cbed after a hand tilt silently kept the zone-axis pattern.
    @MainActor func testAHandTiltIsNamedAsNotSimulated() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let simulation = try XCTUnwrap(state.openItems.items.first { DemoDocuments.isSimulation($0.url) })
        let analysis = simulation.diffraction
        analysis.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        analysis.setZoneAxis(SIMD3(1, 1, 0))
        simulation.cbed.setConvergent(true)
        XCTAssertNil(state.cbedTiltNote(of: simulation), "on the zone axis")

        XCTAssertTrue(analysis.tilt(down: 0, across: 0.37))
        XCTAssertTrue(analysis.isTurnedByHand)
        let note = try XCTUnwrap(state.cbedTiltNote(of: simulation))
        XCTAssertTrue(note.hasPrefix("CBED is simulated on the exact zone axis [1 1 0]"), note)

        simulation.cbed.setConvergent(false)
        XCTAssertNil(state.cbedTiltNote(of: simulation), "a Parallel beam has no CBED run")
        simulation.cbed.setConvergent(true)
        analysis.setZoneAxis(SIMD3(1, 1, 0))
        XCTAssertNil(state.cbedTiltNote(of: simulation), "typing the axis again drops the hand tilt")
    }
}
