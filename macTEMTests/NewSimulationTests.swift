//
//  NewSimulationTests.swift
//  File > New Simulation (#788, plan row R6): the simulation opens through the app's own Open as an item of its own, the window goes
//  to the Diffraction room, and the simulated spots are shown at once, placed by the canvas's scale (0.0125 Å⁻¹/px) and a typed
//  200 kV the person can change. Au (2 0 0) at [0 0 1] is |q| = 2 / 4.0782 Å⁻¹, 39.2330 px down the rows from the centre
//  (256, 256). Red before that change: the app had no New Simulation.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class NewSimulationTests: XCTestCase {
    @MainActor func testNewSimulationOpensTheSimulatedSpotsInTheDiffractionRoom() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertTrue(DemoDocuments.isSimulation(item.url), item.url.path)
        XCTAssertTrue(item.url.lastPathComponent.hasPrefix("Simulation "))
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)

        let image = try XCTUnwrap(item.session.image)
        XCTAssertEqual(image.width, 512)
        let analysis = item.diffraction
        XCTAssertNil(image.voltage, "the beam energy is the room's typed one, which the Calibration section changes")
        XCTAssertEqual(analysis.volts(for: image), 200_000)
        analysis.typedBeamKV = 300
        XCTAssertEqual(analysis.volts(for: image), 300_000)
        analysis.typedBeamKV = 200
        XCTAssertTrue(analysis.simulation.isShown)
        XCTAssertEqual(try XCTUnwrap(analysis.fileDeltaQ(image)), 0.0125, accuracy: 1e-12)

        analysis.bind(image)   // the room's view binds it on screen
        // The canvas's corner is 4.5 Å⁻¹ out, past the kit's k_max cap of 4: the simulator stops at the cap rather than refusing.
        let simulated = try XCTUnwrap(analysis.simulatedSpots(image: image))
        guard case .success(let spots) = simulated else {
            if case .failure(let absence) = simulated { XCTFail("no simulated spots on a new simulation: \(absence.sentence)") }
            return
        }
        let s200 = try XCTUnwrap(spots.first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(s200.row, 256 + 2 / 4.0782 / 0.0125, accuracy: 1e-9)
        XCTAssertEqual(s200.column, 256, accuracy: 1e-9)
    }

    /// #1111: with no phase yet the crystal pane draws no cell and the header names no crystal, as the pattern's empty state says: the
    /// room's standard (Au) is no specimen in a Simulation document. A phase shown fills both; a measured pattern keeps its standard.
    /// Red before: the pane drew an Au cell beside "No phase yet" and the header read "Au [001]".
    @MainActor func testASimulationWithNoPhaseNamesNoCrystal() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let analysis = try XCTUnwrap(state.openItems.selected).diffraction
        XCTAssertTrue(analysis.simulation.isShown)
        XCTAssertTrue(analysis.awaitsPhase)
        XCTAssertNil(DiffractionCrystalScenes.shown(analysis), "no Au cell in the crystal pane")
        XCTAssertEqual(DiffractionCrystalScenes.emptySentence(analysis), SimulationEmptyState.sentence)
        XCTAssertNil(analysis.orientationLine, "no \"Au [001]\" in the header")

        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        analysis.setCrystal(.phase(PhaseCrystal(id: "test-al", name: "Al", structure: al.structure)))
        XCTAssertFalse(analysis.awaitsPhase)
        XCTAssertNotNil(DiffractionCrystalScenes.shown(analysis))
        XCTAssertEqual(analysis.orientationLine, "Al [001]")

        let measured = DiffractionAnalysis()
        measured.simulation.isShown = true
        XCTAssertFalse(measured.awaitsPhase, "a measured pattern's standard is its specimen")
    }

    /// A second New Simulation is a document of its own, never the first one brought forward; a measured pattern is no simulation.
    @MainActor func testEachNewSimulationIsADocumentOfItsOwn() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        await state.newSimulation()?.value
        let simulations = state.openItems.items.filter { DemoDocuments.isSimulation($0.url) }
        XCTAssertEqual(simulations.count, 2)
        XCTAssertNotEqual(simulations[0].url, simulations[1].url)
        XCTAssertFalse(DemoDocuments.isSimulation(DemoDocuments.patternURL))
        XCTAssertFalse(DemoDocuments.isSimulation(URL(fileURLWithPath: "/Users/someone/Simulation 1.dm4")))
    }
}
