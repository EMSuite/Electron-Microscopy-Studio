//
//  AgentDoorPhasesTests.swift
//  #781: the phase library's door tools through a real door over MCP. add_phase adds a Materials Project entry by its id through
//  the Add Phase sheet's own model and shows it in the Diffraction room; list_phases reads the library; set_phase_lattice edits a
//  free parameter through the kit and the room takes the edit; no tool sends a key, and none answers one. The Materials Project
//  is a stub transport: the entry is DiffractoKit's recorded OPTIMADE answer for mp-134 (Al, served as the primitive fcc cell),
//  as EMSuiteUI's AddPhaseModelTests use it. Red before #781: none of the three tools existed.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import ShellPhaseLibrary
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

/// Answers every request with `answer`, and keeps what was sent.
private final class DoorStubTransport: PhaseTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    let answer: @Sendable (URLRequest) -> (Data, Int)
    init(answer: @escaping @Sendable (URLRequest) -> (Data, Int)) { self.answer = answer }
    var sent: [URLRequest] { lock.withLock { _sent } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _sent.append(request) }
        let (data, status) = answer(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }
}

private final class NoKeyStore: APIKeyStore, @unchecked Sendable {
    var key: String?
    init(_ key: String? = nil) { self.key = key }
    func load() throws -> String? { key }
    func save(_ key: String) throws { self.key = key }
    func delete() throws { key = nil }
}

nonisolated final class AgentDoorPhasesTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []
    @MainActor private var folder: URL!
    @MainActor private var saved: (any APIKeyStore, MaterialsProjectClient, PhaseLibrary, Bool)!

    static let entry = Data(#"{"data":{"id":"mp-134","type":"structures","attributes":{"immutable_id":"645d313cbcd30f748b49304e","last_modified":"2023-03-11T22:01:11.232000","elements":["Al"],"nelements":1,"elements_ratios":[1.0],"chemical_formula_descriptive":"Al","chemical_formula_reduced":"Al","chemical_formula_hill":"Al","chemical_formula_anonymous":"A","dimension_types":[1,1,1],"nperiodic_dimensions":3,"lattice_vectors":[[2.473329,0.0,1.427977],[0.824443,2.331877,1.427977],[0.0,0.0,2.855955]],"space_group_symmetry_operations_xyz":null,"space_group_symbol_hall":null,"space_group_symbol_hermann_mauguin":null,"space_group_symbol_hermann_mauguin_extended":null,"space_group_it_number":null,"cartesian_site_positions":[[0.0,0.0,0.0]],"nsites":1,"species":[{"name":"Al","chemical_symbols":["Al"],"concentration":[1.0],"mass":null,"original_name":null,"attached":null,"nattached":null}],"species_at_sites":["Al"],"assemblies":null,"structure_features":[],"_mp_chemical_system":"Al","_mp_stability":{"r2scan":{"thermo_id":"mp-134_R2SCAN","energy_above_hull":0.0,"formation_energy_per_atom":0.0,"last_updated_thermo":"2023-04-27T01:10:08.750000"},"gga_gga+u_r2scan":{"thermo_id":"mp-134_GGA_GGA+U_R2SCAN","energy_above_hull":0.0,"formation_energy_per_atom":0.0,"last_updated_thermo":"2023-04-27T01:10:08.910000"},"gga_gga+u":{"thermo_id":"mp-134_GGA_GGA+U","energy_above_hull":0.0,"formation_energy_per_atom":0.0,"last_updated_thermo":"2023-04-27T01:10:09.479000"}}}},"meta":{"query":{"representation":"/structures/mp-134?"},"api_version":"1.2.0","more_data_available":false,"schema":"https://schemas.optimade.org/openapi/v1.2.0/optimade.json","time_stamp":"2026-11-24T01:20:32.935041","data_returned":1,"provider":{"name":"Materials Project - OPTIMADE","description":"The Materials Project OPTIMADE endpoint","prefix":"mp","homepage":"https://materialsproject.org/"},"data_available":154387,"implementation":{"name":"OPTIMADE Python Tools","version":"1.5.0","source_url":"https://github.com/Materials-Consortia/optimade-python-tools","maintainer":{"email":"dev@optimade.org"},"issue_tracker":"https://github.com/Materials-Consortia/optimade-python-tools/issues"}},"included":[],"links":{"next":null}}"#.utf8)

    @MainActor override func setUp() async throws {
        saved = (PhaseServices.keyStore, PhaseServices.client, PhaseServices.library, PhaseServices.isLoaded)
        folder = FileManager.default.temporaryDirectory.appending(path: "AgentDoorPhasesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        PhaseServices.library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        PhaseServices.isLoaded = true
        defaultsSuite = "agent-door-phases-tests-\(UUID().uuidString)"
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
        (PhaseServices.keyStore, PhaseServices.client, PhaseServices.library, PhaseServices.isLoaded) = saved
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor private func use(_ transport: DoorStubTransport, key: String?) {
        PhaseServices.client = MaterialsProjectClient(transport: transport, now: Date.init, sleep: { _ in })
        PhaseServices.keyStore = NoKeyStore(key)
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

    @MainActor private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// A window with the demo Au pattern open, in the Diffraction room.
    @MainActor private func diffractionWindow() async throws -> (AppState, OpenItem) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.diffraction)?.value
        try await waitUntil("the demo pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        if state.navigation.workspaceArea != .diffraction {
            let moved = try await call("select_room", ["room": "diffraction"])
            XCTAssertFalse(moved.refused, moved.text)
        }
        return (state, try XCTUnwrap(state.openItems.selected))
    }

    /// Mutation: add_phase not going through the sheet's model (no conventional cell, no record), show not reaching the room,
    /// set_phase_lattice not writing the library or the room's copy, or a refused edit changing the phase - red.
    @MainActor func testAddShowAndEditAPhaseThroughTheDoor() async throws {
        let stub = DoorStubTransport { request in
            request.url!.path.hasSuffix("/structures/mp-134") ? (AgentDoorPhasesTests.entry, 200) : (Data("{}".utf8), 404)
        }
        use(stub, key: nil)
        let (state, item) = try await diffractionWindow()
        PhaseServices.isLoaded = false
        let loading = try await call("list_phases")
        XCTAssertTrue(loading.refused, "no answer from a library not yet read")
        PhaseServices.isLoaded = true
        let empty = try json(try await call("list_phases").text)
        XCTAssertEqual((empty["phases"] as? [Any])?.count, 0)

        let bad = try await call("add_phase", ["material_id": "aluminium"])
        XCTAssertTrue(bad.refused, "not a Materials Project id")
        let started = try await call("add_phase", ["material_id": "mp-134", "show": true])
        XCTAssertFalse(started.refused, started.text)
        XCTAssertEqual(try json(started.text)["adding"] as? String, "mp-134")
        await MacTEMAgentDoor.PhaseAdds.shared.task?.value

        let listed = try json(try await call("list_phases").text)
        XCTAssertTrue(listed["adding"] is NSNull)
        XCTAssertEqual((listed["last_add"] as? [String: Any])?["added"] as? Bool, true, "\(listed)")
        let phases = try XCTUnwrap(listed["phases"] as? [[String: Any]])
        XCTAssertEqual(phases.map { $0["id"] as? String }, ["mp-134"])
        XCTAssertEqual(phases[0]["credit"] as? String, "Materials Project · mp-134 · CC BY 4.0")
        XCTAssertEqual(phases[0]["free_parameters"] as? [String], ["a"], "cubic: a alone")
        let a = try XCTUnwrap((phases[0]["lattice"] as? [String: Any])?["a"] as? Double)
        XCTAssertEqual(a, 2.855955 * 2.0.squareRoot(), accuracy: 1e-3, "the conventional fcc cell, as the sheet adds it")
        XCTAssertEqual(item.diffraction.crystal.phaseID, "mp-134", "show put it in the room")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Add phase (material_id mp-134; show true).") },
                      "\(state.activityLog.messages)")
        XCTAssertTrue(stub.sent.allSatisfy { $0.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader) == nil }, "no key without one")

        let again = try json(try await call("add_phase", ["material_id": "mp-134"]).text)
        XCTAssertEqual(again["already_in_library"] as? Bool, true)
        XCTAssertEqual(PhaseServices.library.phases.count, 1)

        let fixed = try await call("set_phase_lattice", ["id": "mp-134", "c": 4.2])
        XCTAssertTrue(fixed.refused, "c is tied to a in a cubic phase")
        XCTAssertEqual(PhaseServices.library.phases.first?.isEdited, false, "a refused edit changes nothing")
        let edited = try await call("set_phase_lattice", ["id": "mp-134", "a": 4.10])
        XCTAssertFalse(edited.refused, edited.text)
        let phase = try XCTUnwrap(try json(edited.text)["phase"] as? [String: Any])
        XCTAssertEqual(phase["edited"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap((phase["lattice"] as? [String: Any])?["c"] as? Double), 4.10, accuracy: 1e-12, "c follows a")
        XCTAssertEqual(item.diffraction.crystal.structure.cell.a, 4.10, accuracy: 1e-12, "the room takes the edit of the phase it shows")
        let room = try json(try await call("get_diffraction").text)
        XCTAssertEqual(room["crystal_phase"] as? String, "mp-134")
        XCTAssertEqual(room["crystal_lattice"] as? String, "a 4.1000 Å")
    }

    /// The key stays in the Keychain: a download with a key sends it to the Materials Project only, and no answer holds it.
    @MainActor func testTheKeyNeverPassesTheDoor() async throws {
        let stub = DoorStubTransport { _ in (Data(#"{"data":[],"errors":[]}"#.utf8), 200) }
        use(stub, key: "secret-key-123")
        _ = try await diffractionWindow()
        let started = try await call("add_phase", ["material_id": "mp-134"])
        XCTAssertFalse(started.refused, started.text)
        await MacTEMAgentDoor.PhaseAdds.shared.task?.value
        let listed = try await call("list_phases")
        XCTAssertFalse(listed.text.contains("secret-key-123"))
        XCTAssertEqual((try json(listed.text)["last_add"] as? [String: Any])?["added"] as? Bool, false, "the stub has no such entry")
        XCTAssertEqual(stub.sent.first?.url?.host, "api.materialsproject.org")
        for tool in MacTEMAgentDoor.phaseTools {
            XCTAssertFalse(tool.parameters.contains { $0.name.localizedCaseInsensitiveContains("key") }, "\(tool.name) takes no key")
        }
    }
}
