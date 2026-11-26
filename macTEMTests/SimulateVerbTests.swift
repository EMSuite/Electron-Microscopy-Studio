//
//  SimulateVerbTests.swift
//  The toolbar's verb per computed document (#1047, design-dna 3: one verb per room in the toolbar, Stop in its place, disabled with
//  the blocker as its help): a STEM image's Simulate, Continue while a scan of the settings is held and incomplete, off when the
//  image is complete; a CBED pattern of a Simulation document's Simulate, on only while the stored patterns are not those of the
//  settings now; a Simulation document has no verb and no Index. Read as data from `SimulateVerb` and from `RoomPrimaryAction.current`
//  on a window's state. Red before: no `SimulateVerb`; a Simulation document and its CBED pattern showed Index, a STEM image no verb
//  (its Simulate was a button in the STEM section), so Workspace > Run read "Index" or "Run" in them.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class SimulateVerbTests: XCTestCase {
    // MARK: As data

    /// Mutation: Continue on a complete image, Simulate enabled with a refusal, a complete image runnable again.
    func testTheSTEMVerbPerState() {
        let fresh = SimulateVerb.stem(refusal: nil, holdsRun: false, isComplete: false)
        XCTAssertEqual(fresh.title, "Simulate")
        XCTAssertTrue(fresh.isEnabled)

        let stopped = SimulateVerb.stem(refusal: nil, holdsRun: true, isComplete: false)
        XCTAssertEqual(stopped.title, "Continue", "a scan of these settings is held and incomplete")
        XCTAssertTrue(stopped.isEnabled)

        let complete = SimulateVerb.stem(refusal: nil, holdsRun: true, isComplete: true)
        XCTAssertEqual(complete.title, "Simulate")
        XCTAssertFalse(complete.isEnabled, "a complete image is not run again")
        XCTAssertTrue(complete.help.contains("complete"), complete.help)

        let refused = SimulateVerb.stem(refusal: "Add a phase to simulate.", holdsRun: false, isComplete: false)
        XCTAssertFalse(refused.isEnabled)
        XCTAssertEqual(refused.help, "Add a phase to simulate.", "the blocker is the help")
    }

    /// Mutation: Simulate enabled while the stored patterns are current, or with a refusal.
    func testTheCBEDVerbIsOnOnlyWhileStale() {
        let none = SimulateVerb.cbed(refusal: nil, isCurrent: false)
        XCTAssertEqual(none.title, "Simulate")
        XCTAssertTrue(none.isEnabled, "no pattern yet, or the settings changed since the one shown")

        let current = SimulateVerb.cbed(refusal: nil, isCurrent: true)
        XCTAssertFalse(current.isEnabled, "the pattern shown is the one for these settings")

        let refused = SimulateVerb.cbed(refusal: SimulateVerb.cbedParallelSentence, isCurrent: false)
        XCTAssertFalse(refused.isEnabled)
        XCTAssertEqual(refused.help, SimulateVerb.cbedParallelSentence)
    }

    // MARK: On a window's state

    /// A Simulation document has no verb (and so no Index); its CBED pattern's verb is Simulate, off with the beam Parallel and the
    /// reason as help; its STEM image's verb is Simulate, off with the run's refusal as help; Workspace > Run follows.
    /// Mutation: Index on the Simulation document or the CBED pattern; no verb on the STEM image.
    @MainActor func testEachComputedDocumentHasItsVerb() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        try await waitUntil("the Simulation document to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSimulation($0.url) } ?? false
        }
        let simulation = try XCTUnwrap(state.openItems.selected)
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        XCTAssertNil(RoomPrimaryAction.current(state)?.title, "a Simulation document is live: no verb, no Index")
        XCTAssertEqual(RoomPrimaryAction.runTitle(state), "Run")
        XCTAssertFalse(RoomPrimaryAction.canRun(RoomPrimaryAction.current(state)))

        // The CBED pattern, with the beam Parallel: opening it runs nothing, and its verb says why.
        XCTAssertFalse(simulation.cbed.isConvergent)
        await state.open(urls: [DemoDocuments.cbedURL(of: simulation.url)])?.value
        try await waitUntil("the CBED pattern to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isCBED($0.url) } ?? false
        }
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        let cbed = try XCTUnwrap(RoomPrimaryAction.current(state))
        XCTAssertEqual(cbed.title, "Simulate")
        XCTAssertFalse(cbed.isEnabled)
        XCTAssertEqual(cbed.help, SimulateVerb.cbedParallelSentence)
        XCTAssertFalse(simulation.cbed.isComputing, "a refused verb runs nothing on open")
        XCTAssertEqual(RoomPrimaryAction.runTitle(state), "Simulate")

        // The STEM image: Simulate, off with the run's own refusal as help when it has one.
        await state.open(urls: [DemoDocuments.stemURL(of: simulation.url)])?.value
        try await waitUntil("the STEM image to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSTEM($0.url) } ?? false
        }
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        let stem = try XCTUnwrap(RoomPrimaryAction.current(state))
        XCTAssertEqual(stem.title, "Simulate")
        switch state.stemRun(of: simulation) {
        case .failure(let refusal):
            XCTAssertFalse(stem.isEnabled)
            XCTAssertEqual(stem.help, refusal.sentence, "the run's refusal is the help")
        case .success:
            XCTAssertEqual(stem.isEnabled, simulation.stem.blocker == nil)
        }
        XCTAssertFalse(stem.isRunning, "opening the image starts no scan")
        XCTAssertEqual(RoomPrimaryAction.runTitle(state), "Simulate")
    }

    /// Show STEM Image computes on Show, as Show HRTEM Image and Show CBED Pattern do (review 2026-11-26: it opened a black tab that waited
    /// for the toolbar's Simulate): the image opens in the Image room and its scan starts, its Stop the toolbar's; with the verb refused
    /// (no phase yet) Show opens the image and runs nothing. Mutation: Show STEM Image opening the image only; Show running past a refusal.
    @MainActor func testShowSTEMImageRunsTheScan() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let simulation = try XCTUnwrap(state.openItems.selected)
        XCTAssertTrue(DemoDocuments.isSimulation(simulation.url))
        XCTAssertNotNil(state.stemVerbRefusal(of: simulation), "no phase yet")
        await state.showSTEMImage(of: simulation)?.value
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        XCTAssertEqual(state.openItems.selected.map { DemoDocuments.isSTEM($0.url) }, true)
        XCTAssertNil(simulation.stem.scan, "a refused verb runs nothing on Show")

        // A small run (Si [1 1 0], 0.5 nm, a 20 mrad probe at 1 Å steps): Show again starts it; Stop keeps what it did.
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        simulation.diffraction.setZoneAxis(SIMD3(1, 1, 0))
        simulation.multislice.setThickness(nm: 0.5)
        simulation.stem.changeSettings {
            $0.semiangleMrad = 20
            $0.scanStepAngstrom = 1
            $0.collectMrad = 100
            $0.defocusNM = 0
        }
        XCTAssertNil(state.stemVerbRefusal(of: simulation), "the run can go")
        let shown = state.showSTEMImage(of: simulation)
        try await waitUntil("the scan to start", seconds: 60) { simulation.stem.isRunning || simulation.stem.scan != nil }
        simulation.stem.stop()
        await shown?.value
        XCTAssertNotNil(simulation.stem.scan, "Show STEM Image ran the scan")
        XCTAssertFalse(simulation.stem.isRunning, "the toolbar's Stop ended it")
    }

    /// The STEM section keeps its plan line and loses the button and its progress bar; the CBED rows lose Stop and the progress bar
    /// (the toolbar's now), and Show CBED Pattern is never disabled. Mutation: a Simulate or Stop button back in the section.
    func testTheSectionsLeaveTheRunToTheToolbar() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let stem = try String(contentsOf: root.appendingPathComponent("macTEM/UI/SimulationSTEMSection.swift"), encoding: .utf8)
        XCTAssertTrue(stem.contains("simulation.stem.plan"))
        for gone in ["simulation.stem.simulate", "simulation.stem.stop", "simulation.stem.progress", "ProgressView("] {
            XCTAssertFalse(stem.contains(gone), gone)
        }
        let cbed = try String(contentsOf: root.appendingPathComponent("macTEM/UI/SimulationCBEDRows.swift"), encoding: .utf8)
        for gone in ["diffraction.simulation.cbed.stop", "diffraction.simulation.cbed.progress", "ProgressView("] {
            XCTAssertFalse(cbed.contains(gone), gone)
        }
        XCTAssertTrue(cbed.contains("diffraction.simulation.cbed.show"))
    }

    /// Every document with a toolbar verb names the door tool that runs the same code path. Mutation: a verb's row names a tool the
    /// door does not have.
    @MainActor func testTheDoorRunsEachVerb() {
        let names = Set(MacTEMAgentDoor.allTools.map(\.name))
        for (verb, reach) in AgentDoorCoverage.toolbarVerbs {
            guard case .tool(let name) = reach else { XCTFail("\(verb): a verb is reached by a tool"); continue }
            XCTAssertTrue(names.contains(name), "\(verb) names \(name), which the door does not have")
        }
        for verb in ["Image · STEM image · Simulate", "Diffraction · CBED pattern · Simulate"] {
            XCTAssertNotNil(AgentDoorCoverage.toolbarVerbs[verb], verb)
        }
        XCTAssertEqual(AgentDoorCoverage.toolbarVerbs["Image · STEM image · Simulate"], .tool("run_stem"))
        XCTAssertEqual(AgentDoorCoverage.toolbarVerbs["Diffraction · CBED pattern · Simulate"], .tool("run_cbed"))
    }
}
