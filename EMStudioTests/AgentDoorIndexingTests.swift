//
//  AgentDoorIndexingTests.swift
//  The agent door's Indexing room tools (#558), through a real door over MCP on kikuchipy's nickel scan opened as Help > Open Demo Data
//  opens it: get_indexing reads the room, set_indexing and set_indexing_phase go through the session calls the controls make and leave
//  "An agent" Output lines, run_room presses Index, select_scan_position follows the Indexing room, get_indexing_picture draws its
//  panes, and open_in_maps hands the run to the Maps room.
//

import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class AgentDoorIndexingTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-indexing-tests-\(UUID().uuidString)"
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

    @MainActor private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// A window with the nickel scan open and the Indexing room shown, its passes ended.
    @MainActor private func nickelInIndexing() async throws -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.ebsd)?.value
        try await waitUntil("the nickel scan's passes to end", seconds: 60) { state.ebsd.dataset != nil && !state.ebsd.isBusy }
        let moved = try await call("select_room", ["room": "indexing"])
        XCTAssertFalse(moved.refused, moved.text)
        XCTAssertEqual(state.navigation.workspaceArea, .indexing)
        return state
    }

    /// Mutation: get_indexing reading the method or the phases wrong, set_indexing not reaching the Hough settings or ignoring reset, or
    /// taking a layer the method has not - red.
    @MainActor func testGetIndexingAndSetIndexing() async throws {
        let state = try await nickelInIndexing()
        let room = try json(try await call("get_indexing").text)
        XCTAssertEqual(room["method"] as? String, "hough")
        let phases = try XCTUnwrap(room["phases"] as? [[String: Any]])
        XCTAssertEqual(phases.map { $0["name"] as? String }, state.indexing.phases.map(\.name))
        XCTAssertFalse(phases.isEmpty, "the demo scan carries its phase")
        XCTAssertTrue(room["run"] is NSNull, "nothing indexed yet")
        XCTAssertEqual(room["can_index"] as? Bool, state.indexing.canIndex)
        XCTAssertNotNil((room["hough"] as? [String: Any])?["rho_mask_percent"], "every setting under its set_indexing name")

        let set = try await call("set_indexing", ["hough_bands": 8, "rho_mask_percent": 10])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.indexing.settings.bands, 8)
        XCTAssertEqual(state.indexing.settings.rhoMaskFraction, 0.1, accuracy: 1e-12)
        XCTAssertEqual(state.indexing.settings.rhoBins, HoughIndexingSettings.roomDefault.rhoBins, "a setting not named stays as it was")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Indexing room settings (hough_bands 8; rho_mask_percent 10).") },
                      "\(state.activityLog.messages)")

        let reset = try await call("set_indexing", ["reset": "hough"])
        XCTAssertFalse(reset.refused, reset.text)
        XCTAssertTrue(state.indexing.settings == HoughIndexingSettings.roomDefault)

        let score = try await call("set_indexing", ["layer": "score"])
        XCTAssertTrue(score.refused, "Hough has no score layer")
        XCTAssertTrue(score.text.contains("confidence"), score.text)
        XCTAssertEqual(state.indexing.layer, .ipfZ)
    }

    /// Mutation: set_indexing_phase not adding the preset, not switching or removing the named phase, taking an HCP list for a cubic
    /// phase, or a master pattern that is not open - red.
    @MainActor func testSetIndexingPhase() async throws {
        let state = try await nickelInIndexing()
        let added = try await call("set_indexing_phase", ["add": "Al"])
        XCTAssertFalse(added.refused, added.text)
        XCTAssertTrue(state.indexing.phases.contains { $0.name == "Al" })
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Indexing phase (add Al).") }, "\(state.activityLog.messages)")

        let off = try await call("set_indexing_phase", ["phase": "Al", "on": false])
        XCTAssertFalse(off.refused, off.text)
        XCTAssertEqual(state.indexing.phases.first { $0.name == "Al" }?.isOn, false)

        let hcp = try await call("set_indexing_phase", ["phase": "Al", "reflectors": "hcp"])
        XCTAssertTrue(hcp.refused, "aluminium is cubic (225)")
        XCTAssertEqual(state.indexing.phases.first { $0.name == "Al" }?.reflectors, .fcc)

        let master = try await call("set_indexing_phase", ["phase": "Al", "master": "none-such.h5"])
        XCTAssertTrue(master.refused, "only an open master pattern is picked")
        let unknown = try await call("set_indexing_phase", ["phase": "Zz", "on": true])
        XCTAssertTrue(unknown.refused)

        let removed = try await call("set_indexing_phase", ["phase": "Al", "remove": true])
        XCTAssertFalse(removed.refused, removed.text)
        XCTAssertFalse(state.indexing.phases.contains { $0.name == "Al" })
    }

    /// Mutation: run_room not pressing Index in the Indexing room, get_indexing's run not following the result, select_scan_position
    /// going around the Indexing room's pin, a pane not drawn, the best match drawn for a Hough run, or open_in_maps going around
    /// AppState.openIndexingInMaps - red.
    @MainActor func testIndexPicturesAndOpenInMaps() async throws {
        let state = try await nickelInIndexing()
        let early = try await call("open_in_maps")
        XCTAssertTrue(early.refused, "nothing indexed yet")

        let ran = try await call("run_room")
        XCTAssertFalse(ran.refused, ran.text)
        XCTAssertEqual(try json(ran.text)["started"] as? String, "Index")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent pressed Index in the Indexing room.") })
        try await waitUntil("Index to end", seconds: 120) { !state.indexing.isIndexing && state.indexing.result?.isComplete == true }

        let room = try json(try await call("get_indexing").text)
        let run = try XCTUnwrap(room["run"] as? [String: Any])
        let result = try XCTUnwrap(state.indexing.result)
        XCTAssertEqual(run["indexed"] as? Int, result.indexedCount)
        XCTAssertEqual(run["points"] as? Int, result.pointCount)
        XCTAssertEqual(run["state"] as? String, "Current")
        XCTAssertGreaterThan(result.indexedCount, 0)

        let picked = try await call("select_scan_position", ["x": 3, "y": 2])
        XCTAssertFalse(picked.refused, picked.text)
        XCTAssertTrue(state.ebsd.pinned == EBSDPosition(row: 2, column: 3))
        try await waitUntil("the pattern as indexed to be on screen", seconds: 30) {
            state.indexing.patternPosition == EBSDPosition(row: 2, column: 3) && state.indexing.patternPresentation.canvas != nil
        }
        let indexingText = try await call("get_indexing").text
        let point = try XCTUnwrap((try json(indexingText)["run"] as? [String: Any])?["picked_point"] as? [String: Any])
        XCTAssertNotNil(point["confidence"], "a Hough point's confidence index")

        let map = try await call("get_indexing_picture", ["which": "map"])
        XCTAssertTrue(map.image, map.text)
        let pattern = try await call("get_indexing_picture", ["which": "pattern"])
        XCTAssertTrue(pattern.image, pattern.text)
        let best = try await call("get_indexing_picture", ["which": "best_match"])
        XCTAssertTrue(best.refused, "a Hough run has no best match")

        let layer = try await call("set_indexing", ["layer": "confidence"])
        XCTAssertFalse(layer.refused, layer.text)
        try await waitUntil("the confidence layer to land", seconds: 30) { state.indexing.mapPresentation.canvas != nil }
        let scalar = try await call("get_indexing_picture", ["which": "map"])
        XCTAssertTrue(scalar.image, scalar.text)

        let handed = try await call("open_in_maps")
        XCTAssertFalse(handed.refused, handed.text)
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent opened the Indexing room's run in the Maps room.") })
    }
}
