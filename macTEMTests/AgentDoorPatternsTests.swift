//
//  AgentDoorPatternsTests.swift
//  The agent door's toolbar verb and Patterns room tools (#558), through a real door over MCP on kikuchipy's nickel scan opened as Help >
//  Open Demo Data opens it: get_patterns reads the room, select_scan_position picks as a click on the map does, set_patterns and
//  set_pattern_processing go through the session calls the controls make and leave "An agent" Output lines, get_patterns_picture draws
//  both panes, run_room presses Process as ⌘R does and stop_run refuses when nothing runs; the Simulation section's overlay and
//  get_session's SEM session rows.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorPatternsTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-patterns-tests-\(UUID().uuidString)"
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

    /// A window with the nickel scan open in the Patterns room, its passes ended.
    @MainActor private func nickelWindow() async throws -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.ebsd)?.value
        try await waitUntil("the nickel scan's passes to end", seconds: 60) { state.ebsd.dataset != nil && !state.ebsd.isBusy }
        XCTAssertEqual(state.navigation.workspaceArea, .patterns)
        return state
    }

    /// Mutation: get_patterns reading the scan's sizes wrong, or select_scan_position going around `pin` or taking a point off the scan - red.
    @MainActor func testGetPatternsAndPickAPosition() async throws {
        let state = try await nickelWindow()
        let room = try json(try await call("get_patterns").text)
        let scan = try XCTUnwrap(room["scan"] as? [String: Any])
        XCTAssertEqual(scan["columns"] as? Int, DemoDocuments.Shipped.nickelEBSDColumns)
        XCTAssertEqual(scan["rows"] as? Int, DemoDocuments.Shipped.nickelEBSDRows)
        XCTAssertEqual((room["pattern_size"] as? [String: Any])?["columns"] as? Int, DemoDocuments.Shipped.nickelEBSDPatternWidth)
        XCTAssertNotNil((room["processing"] as? [String: Any])?["dynamic_std"], "every setting under its set_pattern_processing name")

        let picked = try await call("select_scan_position", ["x": 10, "y": 5])
        XCTAssertFalse(picked.refused, picked.text)
        XCTAssertTrue(state.ebsd.pinned == EBSDPosition(row: 5, column: 10))
        XCTAssertTrue(state.activityLog.messages.contains("An agent used Patterns room position (x 10; y 5)."), "\(state.activityLog.messages)")
        let off = try await call("select_scan_position", ["x": DemoDocuments.Shipped.nickelEBSDColumns, "y": 0])
        XCTAssertTrue(off.refused, "a column past the scan is refused, not clamped")
        XCTAssertTrue(state.ebsd.pinned == EBSDPosition(row: 5, column: 10))
    }

    /// Mutation: set_pattern_processing not reaching the pipeline, changing a setting it was not given, or taking a low percentile above the
    /// high one - red.
    @MainActor func testSetPatternProcessingEditsThePipeline() async throws {
        let state = try await nickelWindow()
        let before = state.ebsd.pipeline
        let set = try await call("set_pattern_processing", ["binning": "2", "dynamic_std": 5, "nlpar_on": true])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.ebsd.pipeline.binning, 2)
        XCTAssertEqual(state.ebsd.pipeline.dynamicStage.std, 5)
        XCTAssertTrue(state.ebsd.pipeline.nlpar.isOn)
        XCTAssertTrue(state.ebsd.pipeline.staticStage == before.staticStage, "a stage not named stays as it was")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasPrefix("An agent used Pattern processing") })

        let crossed = try await call("set_pattern_processing", ["intensity_low": 90, "intensity_high": 10])
        XCTAssertTrue(crossed.refused)
        XCTAssertEqual(state.ebsd.pipeline.intensity.lowPercentile, before.intensity.lowPercentile)
    }

    /// Mutation: set_patterns' grid or tile map not reaching the session, a moved map going unsaid, or the pictures not drawn - red.
    @MainActor func testSetPatternsAndThePictures() async throws {
        let state = try await nickelWindow()
        let grid = try await call("set_patterns", ["grid": "3"])
        XCTAssertFalse(grid.refused, grid.text)
        XCTAssertEqual(state.ebsd.virtualGrid.rows, 3)
        try await waitUntil("the 3 × 3 pass to land", seconds: 60) { state.ebsd.virtualImages != nil && !state.ebsd.isBusy }

        let tile = try await call("set_patterns", ["map": "tile", "tile": "r1 c1"])
        XCTAssertFalse(tile.refused, tile.text)
        XCTAssertTrue(state.ebsd.mapChoice == .tile(VirtualBSETile(row: 1, column: 1)))
        let again = try await call("set_patterns", ["grid": "5"])
        XCTAssertFalse(again.refused, again.text)
        XCTAssertEqual(try json(again.text)["also_changed"] as? [String], ["map tile r1 c1 → mean"], "a new grid drops the tile map, and says so")
        XCTAssertTrue(state.statusText.contains("It also changed: map tile r1 c1 → mean."), state.statusText)
        try await waitUntil("the 5 × 5 pass to land", seconds: 60) { state.ebsd.virtualImages != nil && !state.ebsd.isBusy }

        let map = try await call("get_patterns_picture", ["which": "map"])
        XCTAssertTrue(map.image, map.text)
        try await waitUntil("the pattern to be on screen", seconds: 30) { state.ebsd.patternPresentation.canvas != nil }
        let pattern = try await call("get_patterns_picture", ["which": "pattern", "scale": 2])
        XCTAssertTrue(pattern.image, pattern.text)
    }

    /// The Simulation section through set_patterns, and the SEM session's rows through get_session (#558's last gaps).
    /// Mutation: simulation not reaching setOverlayOn or setOverlaySettings, get_patterns not reading the overlay the pane draws,
    /// or get_session not listing the ledger's rows - red.
    @MainActor func testTheSimulationOverlayAndTheSessionRows() async throws {
        let state = try await nickelWindow()
        try await waitUntil("the pattern to be on screen", seconds: 30) { state.ebsd.patternPosition != nil }
        let off = try XCTUnwrap(try json(try await call("get_patterns").text)["simulation"] as? [String: Any])
        XCTAssertEqual(off["mode"] as? String, "off")
        XCTAssertEqual(off["can_overlay"] as? Bool, true, "the nickel scan stores orientations")

        let on = try await call("set_patterns", ["simulation": "geometrical", "simulation_min_d": 1.5, "simulation_labels": false])
        XCTAssertFalse(on.refused, on.text)
        XCTAssertTrue(state.ebsd.overlayOn)
        XCTAssertEqual(state.ebsd.overlaySettings.minDSpacing, 1.5)
        XCTAssertFalse(state.ebsd.overlaySettings.labels)
        XCTAssertFalse(state.ebsd.overlaySettings.kinematical)
        let drawn = try XCTUnwrap(try json(on.text)["simulation"] as? [String: Any])
        XCTAssertEqual(drawn["mode"] as? String, "geometrical")
        guard case .success(let pattern)? = state.ebsd.overlay else { return XCTFail("no overlay: \(String(describing: state.ebsd.overlay))") }
        XCTAssertEqual(drawn["drawn"] as? String, "\(pattern.phase): \(pattern.drawnWords)", "the words the Simulation section says")
        let offAgain = try await call("set_patterns", ["simulation": "off"])
        XCTAssertFalse(offAgain.refused, offAgain.text)
        XCTAssertFalse(state.ebsd.overlayOn)

        let sem = try json(try await call("get_session").text)
        let rows = try XCTUnwrap(sem["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["id"] as? String }, SEMSessionLedger.rows(of: state).map(\.id))
        let dataset = try XCTUnwrap(rows.first { $0["id"] as? String == "dataset" }, "the open scan is the session's first row")
        XCTAssertEqual(dataset["result"] as? String, state.ebsd.document?.fileName)
        XCTAssertFalse((dataset["fields"] as? [[String: Any]] ?? []).isEmpty, "its Calibration rows")
        XCTAssertTrue(sem["sem_conditions"] is NSNull, "no SEM spectrum is open")
    }

    /// Mutation: run_room going around the toolbar's verb, or stop_run not refusing when nothing runs - red.
    @MainActor func testRunRoomPressesProcessAndStopRunRefusesWhenIdle() async throws {
        let state = try await nickelWindow()
        let idle = try await call("stop_run")
        XCTAssertTrue(idle.refused, "nothing runs")

        let ran = try await call("run_room")
        XCTAssertFalse(ran.refused, ran.text)
        XCTAssertEqual(try json(ran.text)["started"] as? String, "Process")
        XCTAssertTrue(state.activityLog.messages.contains("An agent pressed Process in the Patterns room."))
        try await waitUntil("Process to land", seconds: 120) { state.ebsd.processed != nil && !state.ebsd.isBusy }
        XCTAssertEqual(MacTEMAgentDoor.stateWord(state.ebsd.stageState(.dynamicBackground)), "current")
    }

    /// The Image room has no verb: run_room says so and nothing runs.
    @MainActor func testRunRoomRefusesARoomWithoutAVerb() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        let refused = try await call("run_room")
        XCTAssertTrue(refused.refused)
        XCTAssertTrue(refused.text.contains("Image room has nothing to run"), refused.text)
    }
}
