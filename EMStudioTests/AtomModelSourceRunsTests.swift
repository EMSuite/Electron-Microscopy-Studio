//
//  AtomModelSourceRunsTests.swift
//  An atom model as the specimen in CBED, STEM and Dynamical (#953): while a model is the source, Dynamical, Fit Discs, the CBED
//  pattern's overlay labels and Use in Simulation refuse with one sentence each, in the section and through the door tools of #918;
//  CBED and STEM run on the model (the scan on its supercell without frozen phonons); and the CBED, STEM and Dynamical run keys carry the model's identity and beam axis, so a new model
//  or axis is a new run. Red before: the keys held the phase's identity alone (a new model reused the last run's patterns), Dynamical
//  ran the phase's multislice beside a model, and Fit Discs read the phase's reflections for the model's discs.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class AtomModelSourceRunsTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    /// Two fcc Al cells stacked along c (4.05 × 4.05 × 8.1 Å, 8 atoms), as extended XYZ.
    private static let stacked = """
    8
    Lattice="4.05 0 0 0 4.05 0 0 0 8.1" Properties=species:S:1:pos:R:3 pbc="T T T"
    Al 0 0 0
    Al 0 2.025 2.025
    Al 2.025 0 2.025
    Al 2.025 2.025 0
    Al 0 0 4.05
    Al 0 2.025 6.075
    Al 2.025 0 6.075
    Al 2.025 2.025 4.05
    """

    @MainActor override func setUp() async throws {
        defaultsSuite = "atom-model-source-runs-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "macEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(MacTEMAgentDoor.allTools)
        door.runsAllowed = true
        door.setEnabled(true)
        try await waitUntil("the door to open", seconds: 5) { self.isListening }
    }

    @MainActor override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        keep = []
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    @MainActor private var isListening: Bool {
        if case .listening = door.status { return true }
        return false
    }

    @MainActor private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any], String(decoding: data, as: UTF8.self))
        let content = (result["content"] as? [[String: Any]])?.first
        return (result["isError"] as? Bool ?? false, (content?["text"] as? String) ?? "")
    }

    @MainActor private func read(_ tool: String) async throws -> [String: Any] {
        let answer = try await call(tool)
        XCTAssertFalse(answer.refused, answer.text)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(answer.text.utf8)) as? [String: Any], answer.text)
    }

    private static func model(_ name: String) throws -> AtomModelSpecimen {
        try AtomModelSpecimen(bytes: Data(stacked.utf8), fileName: name)
    }

    /// A Simulation document with Si down [1 1 0] at 200 kV, enrolled in the door, with the Al stack open as its specimen.
    @MainActor private func documentWithModel() async throws -> (AppState, OpenItem) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.newSimulation()?.value
        try await waitUntil("the Simulation document to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSimulation($0.url) } ?? false
        }
        let simulation = try XCTUnwrap(state.openItems.selected)
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        let set = try await call("set_simulation", ["zone_axis": "1 1 0", "voltage_kv": 200])
        XCTAssertFalse(set.refused, set.text)
        simulation.multislice.useAtomModel(try Self.model("Al stack.xyz"))
        await simulation.multislice.buildModelSlabs()
        return (state, simulation)
    }

    /// Each refusal in the section's words, the door's the same. Mutation: Dynamical kept on with a model, set_dynamical running
    /// the phase's multislice, Fit Discs reading the phase's reflections, the CBED overlay keeping the phase's labels, Use in
    /// Simulation setting a thickness the model does not have - red.
    @MainActor func testDynamicalFitDiscsLabelsAndUseInSimulationRefuseWhileAModelIsTheSource() async throws {
        let (state, simulation) = try await documentWithModel()

        // Dynamical.
        let dynamical = try await call("set_dynamical", ["dynamical": true])
        XCTAssertTrue(dynamical.refused)
        XCTAssertTrue(dynamical.text.contains(SimulationModel.modelDynamicalSentence), dynamical.text)
        XCTAssertFalse(simulation.multislice.isDynamical)
        XCTAssertNil(simulation.dynamicalBeams)
        let readDynamical = try await read("read_dynamical")
        XCTAssertEqual(readDynamical["model_refusal"] as? String, SimulationModel.modelDynamicalSentence)

        // Fit Discs: the section's blocker and the door's set_cbed.
        let convergent = try await call("set_cbed", ["beam": "Convergent"])
        XCTAssertFalse(convergent.refused, convergent.text)
        XCTAssertNil(state.cbedShortestG(of: simulation), "a model has no reflection list")
        XCTAssertEqual(state.cbedBlocker(of: simulation), SimulationModel.modelFitDiscsSentence)
        let fit = try await call("set_cbed", ["fit_discs": true])
        XCTAssertTrue(fit.refused)
        XCTAssertTrue(fit.text.contains(SimulationModel.modelFitDiscsSentence), fit.text)
        let cbed = try await read("read_cbed")
        XCTAssertEqual(cbed["fit_discs_refusal"] as? String, SimulationModel.modelFitDiscsSentence)
        XCTAssertEqual(cbed["blocker"] as? String, SimulationModel.modelFitDiscsSentence)

        // The overlay's labels on the CBED pattern.
        XCTAssertEqual(cbed["labels_refusal"] as? String, SimulationModel.modelLabelsSentence)

        // Use in Simulation.
        XCTAssertEqual(state.useInSimulationRefusal(of: simulation), SimulationModel.modelThicknessSentence)
        let thickness = simulation.multislice.thicknessNM
        let use = try await call("use_measured_thickness")
        XCTAssertTrue(use.refused)
        XCTAssertTrue(use.text.contains(SimulationModel.modelThicknessSentence), use.text)
        XCTAssertEqual(simulation.multislice.thicknessNM, thickness)

        // Back to the phase: none of them refuse for the model.
        simulation.multislice.useAtomModel(nil)
        XCTAssertNil(state.useInSimulationRefusal(of: simulation))
        XCTAssertNotEqual(state.cbedBlocker(of: simulation), SimulationModel.modelFitDiscsSentence)
        XCTAssertNotNil(state.cbedShortestG(of: simulation))
    }

    /// CBED and STEM run on the model, named after it, with a typed semiangle. Mutation: the phase guard kept (no phase, no run),
    /// the specimen named after the phase, the STEM supercell built only with frozen phonons on - red.
    @MainActor func testCBEDAndSTEMRunOnTheModel() async throws {
        let (state, simulation) = try await documentWithModel()
        let typed = try await call("set_cbed", ["beam": "Convergent", "semiangle_mrad": 5])
        XCTAssertFalse(typed.refused, typed.text)
        XCTAssertNil(state.cbedBlocker(of: simulation))
        guard case .success(let cbed) = state.cbedRun(of: simulation) else { return XCTFail("CBED refused on the model") }
        XCTAssertEqual(cbed.specimen, "Al stack along c")
        XCTAssertNil(cbed.shortestG)
        guard case .success(let stem) = state.stemRun(of: simulation) else { return XCTFail("STEM refused on the model") }
        XCTAssertEqual(stem.specimen, "Al stack along c")
        XCTAssertGreaterThanOrEqual(stem.built.slabBox.x, HRTEMThermal.lateralSize.x - 1e-9, "the supercell a scan runs on")
        XCTAssertGreaterThanOrEqual(stem.built.slabBox.y, HRTEMThermal.lateralSize.y - 1e-9, "the supercell a scan runs on")
        XCTAssertNil(simulation.multislice.thermal, "built without frozen phonons")
    }

    /// Each run key changes with the model and with its beam axis. Mutation: a key built from the phase's identity alone, or
    /// without the beam axis - red.
    @MainActor func testEachRunKeyChangesWithTheModel() async throws {
        let (state, simulation) = try await documentWithModel()
        let typed = try await call("set_cbed", ["beam": "Convergent", "semiangle_mrad": 5])
        XCTAssertFalse(typed.refused, typed.text)
        let model = simulation.multislice

        func keys() throws -> (cbed: CBEDModel.RunKey, stem: STEMModel.RunKey, dynamical: DynamicalRunKey) {
            (try state.cbedRun(of: simulation).get().key, try state.stemRun(of: simulation).get().key, simulation.dynamicalRunKey)
        }

        let first = try keys()
        model.useAtomModel(try Self.model("Al stack.xyz"))
        await model.buildModelSlabs()
        let second = try keys()
        XCTAssertNotEqual(first.cbed, second.cbed, "a new model is a new CBED run")
        XCTAssertNotEqual(first.stem, second.stem, "a new model is a new STEM run")
        XCTAssertNotEqual(first.dynamical, second.dynamical, "a new model is a new Dynamical run")

        model.setBeamAxis(.a)
        await model.buildModelSlabs()
        let alongA = try keys()
        XCTAssertNotEqual(second.cbed, alongA.cbed)
        XCTAssertNotEqual(second.stem, alongA.stem)
        XCTAssertNotEqual(second.dynamical, alongA.dynamical)

        model.useAtomModel(nil)
        let phase = try keys()
        XCTAssertNotEqual(alongA.cbed, phase.cbed, "the phase is another specimen")
        XCTAssertNotEqual(alongA.stem, phase.stem)
        XCTAssertNotEqual(alongA.dynamical, phase.dynamical)
    }
}
