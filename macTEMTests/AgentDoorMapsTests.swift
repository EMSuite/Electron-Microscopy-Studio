//
//  AgentDoorMapsTests.swift
//  The agent door's Maps room tools (#558), through a real door over MCP on orix's duplex steel map opened as Help > Open Demo Data
//  opens it: get_maps reads the room, set_maps goes through the session calls the inspector makes and leaves "An agent" Output lines,
//  run_room presses Segment, get_grains and select_grains work the grain table, select_scan_position follows the Maps room, and
//  get_maps_picture draws the map and texture figures.
//

import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorMapsTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-maps-tests-\(UUID().uuidString)"
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

    /// A window with the duplex steel map open in the Maps room, its picture drawn.
    @MainActor private func steelWindow() async throws -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.orientationMap)?.value
        try await waitUntil("the steel map to be drawn", seconds: 60) { state.maps.raster != nil && !state.maps.isBusy }
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        return state
    }

    /// Segment through the toolbar verb, and its end.
    @MainActor private func segmented(_ state: AppState) async throws {
        let ran = try await call("run_room")
        XCTAssertFalse(ran.refused, ran.text)
        XCTAssertEqual(try json(ran.text)["started"] as? String, "Segment")
        try await waitUntil("Segment to land", seconds: 120) { state.maps.analysis != nil && !state.maps.isBusy }
    }

    /// Mutation: get_maps reading the grid or the phases wrong, set_maps not reaching the layer or the Segment settings, or taking a
    /// derived layer before Segment or a source the room does not hold - red.
    @MainActor func testGetMapsAndSetMaps() async throws {
        let state = try await steelWindow()
        let document = try XCTUnwrap(state.maps.document)
        let room = try json(try await call("get_maps").text)
        let grid = try XCTUnwrap(room["grid"] as? [String: Any])
        XCTAssertEqual(grid["rows"] as? Int, document.rows)
        XCTAssertEqual(grid["columns"] as? Int, document.columns)
        XCTAssertEqual((room["phases"] as? [[String: Any]])?.count, MapsRoomFormat.indexedPhases(document.map).count)
        XCTAssertEqual(room["layer"] as? String, "ipf-z")
        XCTAssertEqual(room["layers"] as? [String], state.maps.layers.map(\.id))

        let phase = try await call("set_maps", ["layer": "phase", "boundary_angle": 10])
        XCTAssertFalse(phase.refused, phase.text)
        XCTAssertTrue(state.maps.layer == .phase)
        XCTAssertEqual(state.maps.analysisSettings.boundaryDegrees, 10)
        XCTAssertEqual(state.maps.analysisSettings.minimumSize, MapAnalysisSettings().minimumSize, "a setting not named stays as it was")
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Maps room settings (boundary_angle 10; layer phase).") },
                      "\(state.activityLog.messages)")

        let kam = try await call("set_maps", ["layer": "derived-kam"])
        XCTAssertTrue(kam.refused, "KAM comes with Segment")
        XCTAssertTrue(state.maps.layer == .phase)
        let source = try await call("set_maps", ["source": 5])
        XCTAssertTrue(source.refused, "the room holds one result")
    }

    /// Mutation: run_room not pressing Segment, get_grains' page or order wrong, select_grains going around the table's selection or
    /// taking a grain that is not there, select_scan_position going around the Maps room's pin, or the map figure not drawn - red.
    @MainActor func testSegmentGrainsAndTheMap() async throws {
        let state = try await steelWindow()
        let early = try await call("get_grains")
        XCTAssertTrue(early.refused, "no grains before Segment")
        try await segmented(state)
        let analysis = try XCTUnwrap(state.maps.analysis)
        XCTAssertGreaterThan(analysis.table.count, 1)

        let page = try json(try await call("get_grains", ["sort": "size", "count": 5, "histogram": "kam"]).text)
        XCTAssertEqual(page["grains"] as? Int, analysis.table.count)
        let rows = try XCTUnwrap(page["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, min(5, analysis.table.count))
        XCTAssertEqual(rows.first?["points"] as? Int, analysis.table.map(\.points).max(), "largest first")
        let histogram = try XCTUnwrap(page["histogram"] as? [String: Any])
        XCTAssertEqual(histogram["counts"] as? [Int], state.maps.histogram(.kam)?.counts)

        let one = try await call("select_grains", ["grains": "1"])
        XCTAssertFalse(one.refused, one.text)
        XCTAssertEqual(state.maps.selectedGrain, 1)
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Maps room grain selection (grains 1).") }, "\(state.activityLog.messages)")
        let missing = try await call("select_grains", ["grains": "\(analysis.table.count + 1)"])
        XCTAssertTrue(missing.refused)
        XCTAssertEqual(state.maps.selectedGrain, 1)
        let cleared = try await call("select_grains", ["grains": "none"])
        XCTAssertFalse(cleared.refused, cleared.text)
        XCTAssertTrue(state.maps.selectedGrains.isEmpty)

        let picked = try await call("select_scan_position", ["x": 2, "y": 3])
        XCTAssertFalse(picked.refused, picked.text)
        XCTAssertTrue(state.maps.pinned == EBSDPosition(row: 3, column: 2))
        XCTAssertNotNil(try json(picked.text)["segment"], "the Maps room's get tool answers")
        let off = try await call("select_scan_position", ["x": state.maps.gridShape.columns, "y": 0])
        XCTAssertTrue(off.refused, "a column past the map is refused, not clamped")

        let map = try await call("get_maps_picture", ["which": "map"])
        XCTAssertTrue(map.image, map.text)
    }

    /// Mutation: set_maps' slip systems not reaching the phase or taking a file that does not fit it, texture_phase not computing, or
    /// the texture figure not drawn - red.
    @MainActor func testSlipAndTexture() async throws {
        let state = try await steelWindow()
        let map = try XCTUnwrap(state.maps.map)
        let entry = try XCTUnwrap(MapsRoomFormat.indexedPhases(map).first { !MapsRoomFormat.slipChoices($0.phase).isEmpty })
        let file = try XCTUnwrap(MapsRoomFormat.slipChoices(entry.phase).first)
        let slip = try await call("set_maps", ["slip_phase": entry.id, "slip_systems": file.rawValue, "load": "y"])
        XCTAssertFalse(slip.refused, slip.text)
        XCTAssertEqual(state.maps.slipFiles[entry.id], file)
        XCTAssertEqual(state.maps.loadDirection, .y)
        let unfit = SlipSystemFile.allCases.first { !MapsRoomFormat.slipChoices(entry.phase).contains($0) }
        if let unfit {
            let refused = try await call("set_maps", ["slip_phase": entry.id, "slip_systems": unfit.rawValue])
            XCTAssertTrue(refused.refused, "\(unfit.rawValue) does not fit \(entry.phase.name)")
            XCTAssertEqual(state.maps.slipFiles[entry.id], file)
        }

        let early = try await call("get_maps_picture", ["which": "texture"])
        XCTAssertTrue(early.refused, "no texture yet")
        let phaseID = try XCTUnwrap(state.maps.texturePhases.first?.id)
        let texture = try await call("set_maps", ["texture_phase": phaseID])
        XCTAssertFalse(texture.refused, texture.text)
        try await waitUntil("the texture to land", seconds: 120) { state.maps.texture != nil && !state.maps.isTexturing }
        let figure = try await call("get_maps_picture", ["which": "texture"])
        XCTAssertTrue(figure.image, figure.text)
        let mapsText = try await call("get_maps").text
        let landed = try XCTUnwrap((try json(mapsText)["texture"] as? [String: Any])?["landed"] as? [String: Any])
        XCTAssertEqual(landed["points"] as? Int, state.maps.texture?.points)
    }
}
