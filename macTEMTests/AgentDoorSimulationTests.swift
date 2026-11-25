//
//  AgentDoorSimulationTests.swift
//  The agent door's Simulation tools (#846, plan row R8b), through a real door over MCP: new_simulation opens File > New
//  Simulation's document in the Diffraction room, and get_crystal_view reads the crystal pane beside it: the phase, the zone axis,
//  the orientation as the simulated spots' matrix (at [0 0 1] and no turn the kit's lab frame is the crystal's: the identity), the
//  scene (Au: 14 atoms, no bond), and the words for an empty pane. Red before: the door had neither tool.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorSimulationTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-simulation-tests-\(UUID().uuidString)"
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

    @MainActor private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    @MainActor func testNewSimulationAndTheCrystalView() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }

        let opened = try await call("new_simulation")
        XCTAssertFalse(opened.refused, opened.text)
        XCTAssertEqual(try json(opened.text)["opens_in_new_window"] as? Bool, false, "an empty window takes the simulation itself")
        try await waitUntil("the simulation to open", seconds: 30) { state.openItems.selected?.session.image != nil }
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)

        let view = try await call("get_crystal_view")
        XCTAssertFalse(view.refused, view.text)
        let answer = try json(view.text)
        XCTAssertEqual(answer["shown"] as? Bool, true)
        XCTAssertEqual(answer["phase"] as? String, "Au")
        XCTAssertEqual(answer["place"] as? String, "Au, zone axis [001]")
        XCTAssertEqual(answer["shows_unit_cell"] as? Bool, true)
        let rows = try XCTUnwrap(answer["orientation"] as? [[Double]])
        for i in 0..<3 { for j in 0..<3 { XCTAssertEqual(rows[i][j], i == j ? 1 : 0, accuracy: 1e-12, "\(rows)") } }
        let crystal = try XCTUnwrap(answer["crystal"] as? [String: Any])
        XCTAssertEqual(crystal["atoms"] as? Int, 14)

        // The pane follows the spots: another zone axis is the answer's at once.
        let item = try XCTUnwrap(state.openItems.selected)
        item.diffraction.setZoneAxis(SIMD3(1, 1, 0))
        let turned = try await call("get_crystal_view")
        XCTAssertEqual(try json(turned.text)["place"] as? String, "Au, zone axis [110]")

        // Spots off: the pane is empty, said in words.
        item.diffraction.simulation.isShown = false
        let empty = try await call("get_crystal_view")
        XCTAssertTrue(empty.refused)
        XCTAssertTrue(empty.text.contains("crystal pane is empty"), empty.text)
    }
}
