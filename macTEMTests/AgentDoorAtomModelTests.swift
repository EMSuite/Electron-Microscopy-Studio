//
//  AgentDoorAtomModelTests.swift
//  The agent door's atom model and abTEM script tools (#918, the last gaps of plan row MA17), through a real door over MCP, on a
//  document File > New Simulation opens: set_atom_model reads a model file of the Agent folder as the Specimen section's Atom
//  Model… does (off the main actor), refuses a path outside the folder, a missing file, a beam axis with no model and Phase with a
//  path, keeps a refused file's sentence for read_atom_model and changes nothing, turns the model with beam_axis (its thickness
//  then the model's own along that axis) and goes back to the phase; get_abtem_script is refused until the exit waves are current
//  and then answers the script Export abTEM Script… writes. Red before: the door had none of the three tools, and the coverage
//  rows of the Source picker, Open Another Model…, Beam along, the model's thickness and Export abTEM Script… were gaps.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorAtomModelTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    @MainActor private var root: URL!
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    /// Two fcc Al cells stacked along c (4.05 × 4.05 × 8.1 Å, 8 atoms), as extended XYZ (AtomModelSourceRunsTests' model).
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
        defaultsSuite = "agent-door-atom-model-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "macEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(MacTEMAgentDoor.allTools)
        door.runsAllowed = true
        door.setEnabled(true)
        try await waitUntil("the door to open", seconds: 5) { self.isListening }

        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("models"), withIntermediateDirectories: true)
        try Data(Self.stacked.utf8).write(to: root.appendingPathComponent("models/Al stack.xyz"))
        try Data("ATOM      1  AL   AL A   1       0.000   0.000   0.000\n".utf8).write(to: root.appendingPathComponent("models/model.pdb"))
        MacTEMAgentDoor.folder.use(folder: root)
    }

    @MainActor override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        keep = []
        MacTEMAgentDoor.folder.use(folder: nil)
        if let root { try? FileManager.default.removeItem(at: root) }
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

    /// A Simulation document with Si down [1 1 0] at 200 kV, 0.5 nm thick, enrolled in the door.
    @MainActor private func document() async throws -> (AppState, OpenItem) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.newSimulation()?.value
        try await waitUntil("the Simulation document to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSimulation($0.url) } ?? false
        }
        let simulation = try XCTUnwrap(state.openItems.selected)
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        let set = try await call("set_simulation", ["zone_axis": "1 1 0", "thickness_nm": 0.5, "voltage_kv": 200])
        XCTAssertFalse(set.refused, set.text)
        return (state, simulation)
    }

    /// Mutation: a row still a gap; the file read around the Agent folder or not through `AtomModelSpecimen(contentsOf:)`; a refused
    /// file turning the beam axis; a beam axis kept with no model; Phase not dropping the model - red.
    @MainActor func testAnAgentOpensTurnsAndDropsAnAtomModel() async throws {
        for control in ["simulation.specimen.source", "simulation.specimen.openModel", "simulation.specimen.beamAxis"] {
            XCTAssertEqual(AgentDoorCoverage.controls[control], .tool("set_atom_model"), control)
        }
        XCTAssertEqual(AgentDoorCoverage.controls["simulation.specimen.modelThickness"], .tool("read_atom_model"))
        XCTAssertEqual(AgentDoorCoverage.controls["simulation.hrtem.saveScript"], .tool("get_abtem_script"))

        let (state, simulation) = try await document()
        let model = simulation.multislice
        var now = try await read("read_atom_model")
        XCTAssertEqual(now["source"] as? String, "Phase")

        // Checked whole first: nothing changes on a refusal.
        for arguments: [String: Any] in [["beam_axis": "a"], ["source": "Atom Model"], ["path": "../outside.xyz"],
                                         ["path": "models/missing.xyz"], ["path": "models"],
                                         ["source": "Phase", "path": "models/Al stack.xyz"]] {
            let refused = try await call("set_atom_model", arguments)
            XCTAssertTrue(refused.refused, "\(arguments): \(refused.text)")
        }
        XCTAssertNil(model.atomModel)
        XCTAssertEqual(model.beamAxis, .c)

        // A format the section does not read: its sentence, and the beam axis given with it not set.
        let pdb = try await call("set_atom_model", ["path": "models/model.pdb", "beam_axis": "a"])
        XCTAssertFalse(pdb.refused, pdb.text)
        try await waitUntil("the file to be read", seconds: 30) { !AtomModelReads.isReading(simulation) }
        now = try await read("read_atom_model")
        XCTAssertEqual(now["refusal"] as? String, AtomModelSpecimen.Refusal.format(file: "model.pdb").sentence, "\(now)")
        XCTAssertEqual(now["source"] as? String, "Phase")
        XCTAssertNil(model.atomModel)
        XCTAssertEqual(model.beamAxis, .c, "a refused file changes nothing")

        // The model, along a: the beam runs along the model's 4.05 Å a, the model's own thickness.
        let opened = try await call("set_atom_model", ["path": "models/Al stack.xyz", "beam_axis": "a"])
        XCTAssertFalse(opened.refused, opened.text)
        try await waitUntil("the model to be in", seconds: 30) { !AtomModelReads.isReading(simulation) && model.atomModel != nil }
        await model.buildModelSlabs()
        now = try await read("read_atom_model")
        XCTAssertEqual(now["source"] as? String, "Atom Model")
        XCTAssertEqual(now["model"] as? String, "Al stack")
        XCTAssertEqual(now["atoms"] as? Int, 8)
        XCTAssertEqual(now["beam_axis"] as? String, "a")
        XCTAssertTrue(now["refusal"] is NSNull, "\(now)")
        XCTAssertEqual(try XCTUnwrap(now["thickness_nm"] as? Double, "\(now)"), 0.405, accuracy: 1e-6)
        XCTAssertTrue((now["summary"] as? String)?.hasSuffix("beam along a.") == true, "\(now)")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent used Atom model") }, "\(state.activityLog.messages)")

        // Beam along c: the stack's 8.1 Å.
        let turned = try await call("set_atom_model", ["beam_axis": "c"])
        XCTAssertFalse(turned.refused, turned.text)
        XCTAssertEqual(model.beamAxis, .c)
        await model.buildModelSlabs()
        now = try await read("read_atom_model")
        XCTAssertEqual(try XCTUnwrap(now["thickness_nm"] as? Double, "\(now)"), 0.81, accuracy: 1e-6)

        // Back to the phase, as the Source picker's Phase.
        let phase = try await call("set_atom_model", ["source": "Phase"])
        XCTAssertFalse(phase.refused, phase.text)
        XCTAssertNil(model.atomModel)
        now = try await read("read_atom_model")
        XCTAssertEqual(now["source"] as? String, "Phase")
    }

    /// Mutation: the script answered before the waves are current (the button is off then), or another text than the section's - red.
    @MainActor func testTheAbTEMScriptIsTheSectionsOnceTheWavesAreCurrent() async throws {
        let (_, simulation) = try await document()
        let early = try await call("get_abtem_script")
        XCTAssertTrue(early.refused, early.text)
        let ran = try await call("run_simulation")
        XCTAssertFalse(ran.refused, ran.text)
        let model = simulation.multislice, analysis = simulation.diffraction
        try await waitUntil("the exit waves", seconds: 120) {
            model.exitWavesAreCurrent(crystal: analysis.simulatedPhase, zoneAxis: SIMD3(1, 1, 0)) && !model.isComputing
        }
        let script = try await read("get_abtem_script")
        let expected = try XCTUnwrap(model.abTEMScript(crystal: analysis.simulatedPhase, zoneAxis: SIMD3(1, 1, 0),
                                                       appVersion: MacTEMAgentDoor.version()))
        XCTAssertEqual(script["name"] as? String, expected.name)
        XCTAssertEqual(script["text"] as? String, expected.text)
    }
}
