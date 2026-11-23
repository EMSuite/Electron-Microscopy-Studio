//
//  AgentDoorRoomsTests.swift
//  macEM's first tools that act (#558), through a real door over MCP as an agent calls them: select_room moves the window as the room
//  bar does and refuses a room the files do not fill with the room bar's reason; the EDS room's tools (MacEMUI's EDXAgentTools) pick an
//  element on the demo spectrum image and get_eds_maps draws the maps as the export does; each acting call leaves an "An agent" Output
//  line; open_demo opens a demo document in its room as Help > Open Demo Data does; with the second switch off an acting tool is refused.
//

import Foundation
import ShellAgentDoor
import ShellEDXModel
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorRoomsTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-rooms-tests-\(UUID().uuidString)"
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

    @MainActor private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String, image: Bool) {
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
        return (result["isError"] as? Bool ?? false, (content?["text"] as? String) ?? "", content?["type"] as? String == "image")
    }

    @MainActor private func window() -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        return state
    }

    /// Mutation: select_room going around `roomUnavailableReason`, or leaving no Output line - red.
    @MainActor func testSelectRoomMovesTheWindowOrSaysWhyNot() async throws {
        let state = window()
        // With nothing open every room is enterable; an orientation map alone leaves the EDS room without data.
        let map = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ebsd-sdss-ferrite-austenite.ang")
        await state.open(urls: [map])?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        let refused = try await call("select_room", ["room": "edx"])
        XCTAssertTrue(refused.refused, "a window holding only a map has no spectrum image for the EDS room")
        let reason = try XCTUnwrap(state.roomUnavailableReason(.edx))
        XCTAssertTrue(refused.text.contains(reason), "the room bar's reason: \(refused.text)")
        XCTAssertEqual(state.navigation.workspaceArea, .maps)

        await state.edx.bind(DemoDocuments.edx()).value
        let moved = try await call("select_room", ["room": "edx"])
        XCTAssertFalse(moved.refused, moved.text)
        XCTAssertEqual(state.navigation.workspaceArea, .edx)
        XCTAssertEqual(state.statusText, "An agent selected the EDS room.")
    }

    /// Mutation: the EDS tools not registered, their acting calls leaving no Output line, or get_eds_maps drawing nothing - red.
    @MainActor func testTheEDSToolsPickAndTheMapsAreDrawn() async throws {
        let state = window()
        await state.edx.bind(DemoDocuments.edx()).value
        try await waitUntil("the EDS room to settle", seconds: 60) { !state.edx.isBusy }
        await state.edx.settled()

        let picked = try await call("set_eds", ["add": "Fe"])
        XCTAssertFalse(picked.refused, picked.text)
        XCTAssertTrue(state.edx.picks.contains { $0.symbol == "Fe" })
        XCTAssertEqual(state.statusText, "An agent used EDS room settings (add Fe).")

        let maps = try await call("get_eds_maps")
        XCTAssertFalse(maps.refused, maps.text)
        XCTAssertTrue(maps.image, "get_eds_maps answers a picture")
    }

    /// Mutation: open_demo going around `openDemo`, leaving the window in another room, or leaving no Output line - red.
    @MainActor func testOpenDemoOpensTheDocumentInItsRoom() async throws {
        let state = window()
        let opened = try await call("open_demo", ["demo": "lattice"])
        XCTAssertFalse(opened.refused, opened.text)
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        XCTAssertTrue(state.activityLog.messages.contains("An agent opened the demo Lattice Image."), "\(state.activityLog.messages)")
        try await waitUntil("the lattice image to be read", seconds: 30) { state.openItems.selected?.session.image != nil }

        let unknown = try await call("open_demo", ["demo": "gold"])
        XCTAssertTrue(unknown.refused, "a demo the menu does not have is refused by its schema")
        XCTAssertEqual(state.openItems.items.count, 1)
    }

    /// With Settings > Agents' second switch off, an acting tool is refused and nothing moves. Mutation: select_room not marked acts - red.
    @MainActor func testActingToolsWaitForTheSecondSwitch() async throws {
        door.runsAllowed = false
        let state = window()
        await state.edx.bind(DemoDocuments.edx()).value
        let refused = try await call("select_room", ["room": "edx"])
        XCTAssertTrue(refused.refused)
        XCTAssertEqual(state.navigation.workspaceArea, .image)
    }

    func testTheAgentLineNamesTheToolAndItsArguments() {
        XCTAssertEqual(MacTEMAgentDoor.agentLine("EDS room action", ["action": "quantify"]), "An agent used EDS room action (action quantify).")
        XCTAssertEqual(MacTEMAgentDoor.agentLine("EDS room settings", ["region": "whole", "add": "Fe, Ni"]),
                       "An agent used EDS room settings (add Fe, Ni; region whole).")
        XCTAssertEqual(MacTEMAgentDoor.agentLine("Stop", [:]), "An agent used Stop.")
    }
}
