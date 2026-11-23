//
//  AgentDoorEELSTests.swift
//  The agent door's EELS room tools (#558), through a real door over MCP on the generated demo spectrum image opened as Help > Open Demo
//  Data opens it (a 16 × 16 low loss, no core loss): get_eels reads the room, set_eels, set_eels_edges and set_eels_region go through the
//  session calls the controls make and leave "An agent" Output lines, run_room presses Run, get_eels_spectrum and get_eels_maps give
//  the spectrum and the maps.
//

import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorEELSTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-eels-tests-\(UUID().uuidString)"
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

    /// A window with the demo spectrum image open in the EELS room, its first pass ended.
    @MainActor private func eelsWindow() async throws -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.eels)?.value
        await state.eels.settled()
        try await waitUntil("the demo spectrum image to open", seconds: 60) { state.eels.hasImage && !state.eels.isBusy }
        XCTAssertEqual(state.navigation.workspaceArea, .eels)
        return state
    }

    /// Mutation: get_eels reading the spectra wrong, set_eels not reaching the mean free path, run_room not pressing Run, or the spectrum
    /// and the maps not given - red.
    @MainActor func testGetEELSRunAndTheMaps() async throws {
        let state = try await eelsWindow()
        let room = try json(try await call("get_eels").text)
        XCTAssertEqual(room["low_loss"] as? Bool, true)
        XCTAssertEqual(room["core_loss"] as? Bool, false, "the demo holds a low loss only")
        XCTAssertEqual((room["map_size"] as? [String: Any])?["width"] as? Int, state.eels.source?.image.nx)
        XCTAssertNotNil(room["processing"] as? [String: Any])

        let mfp = try await call("set_eels", ["mfp": "given", "lambda_nm": 100])
        XCTAssertFalse(mfp.refused, mfp.text)
        XCTAssertEqual(state.eels.meanFreePath, .given(nanometres: 100))
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used EELS room settings (lambda_nm 100; mfp given).") },
                      "\(state.activityLog.messages)")

        let ran = try await call("run_room")
        XCTAssertFalse(ran.refused, ran.text)
        XCTAssertEqual(try json(ran.text)["started"] as? String, "Run")
        await state.eels.settled()
        try await waitUntil("Run to land", seconds: 120) { !state.eels.isBusy && state.eels.map != nil }
        XCTAssertEqual(MacTEMAgentDoor.stateWord(state.eels.thicknessState), "current")

        let maps = try await call("get_eels_maps")
        XCTAssertTrue(maps.image, maps.text)
        let spectrum = try json(try await call("get_eels_spectrum").text)
        XCTAssertEqual(spectrum["spectrum_csv"] as? String, state.eels.spectrumCSV, "the export's own text")
    }

    /// Mutation: set_eels taking a backward signal range, maps the file cannot make, or iterations without Richardson-Lucy; set_eels_edges
    /// picking an edge the file has no core loss for - red; the Richardson-Lucy pick reaching the session - green.
    @MainActor func testSettingsAndTheirRefusals() async throws {
        let state = try await eelsWindow()
        let backward = try await call("set_eels", ["align_from": 5, "align_to": -5])
        XCTAssertTrue(backward.refused)
        let atomic = try await call("set_eels", ["maps": "atomicPercent"])
        XCTAssertTrue(atomic.refused, "no fit, no at% maps")
        XCTAssertNotEqual(state.eelsRoom.maps, .atomicPercent)
        let lone = try await call("set_eels", ["iterations": 20])
        XCTAssertTrue(lone.refused, "iterations are Richardson-Lucy's")

        let rl = try await call("set_eels", ["deconvolution": "richardsonLucy", "iterations": 20])
        XCTAssertFalse(rl.refused, rl.text)
        XCTAssertEqual(state.eels.deconvolutionChoice, .richardsonLucy(iterations: 20))

        let edge = try await call("set_eels_edges", ["add": "Fe"])
        XCTAssertTrue(edge.refused, "the demo holds no core loss")
        XCTAssertTrue(edge.text.contains("Fe: "), edge.text)
        if EELSEdgeChoices.live.contains("Fe") { XCTAssertTrue(edge.text.contains("no core loss"), edge.text) }
        XCTAssertTrue(state.eels.pickedEdges.isEmpty)
    }

    /// Mutation: set_eels_region going around drawRegion, selectPin or removePin, or taking a backward rectangle - red.
    @MainActor func testRegions() async throws {
        let state = try await eelsWindow()
        let before = state.eels.pins.count
        let drawn = try await call("set_eels_region", ["region": "rectangle", "x0": 1, "y0": 1, "x1": 5, "y1": 4])
        XCTAssertFalse(drawn.refused, drawn.text)
        XCTAssertEqual(state.eels.pins.count, before + 1)
        let pin = try XCTUnwrap(state.eels.selectedPin)
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasPrefix("An agent used EELS region (region rectangle;") })

        let whole = try await call("set_eels_region", ["region": "whole"])
        XCTAssertFalse(whole.refused, whole.text)
        XCTAssertNil(state.eels.selectedPinID)
        let picked = try await call("set_eels_region", ["region": "pin", "pin": pin.name])
        XCTAssertFalse(picked.refused, picked.text)
        XCTAssertEqual(state.eels.selectedPinID, pin.id)
        let backward = try await call("set_eels_region", ["region": "ellipse", "x0": 5, "y0": 1, "x1": 2, "y1": 4])
        XCTAssertTrue(backward.refused)
        let removed = try await call("set_eels_region", ["region": "remove", "pin": pin.name])
        XCTAssertFalse(removed.refused, removed.text)
        XCTAssertFalse(state.eels.pins.contains { $0.id == pin.id })
        let gone = try await call("set_eels_region", ["region": "pin", "pin": pin.name])
        XCTAssertTrue(gone.refused)
    }
}
