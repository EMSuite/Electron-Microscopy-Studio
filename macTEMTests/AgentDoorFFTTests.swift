//
//  AgentDoorFFTTests.swift
//  The agent door's FFT room tools (#558), through a real door over MCP on the demo lattice (Help > Open Demo Data: 512 × 512 at
//  0.0123 nm/px, a square lattice of 0.235 nm): get_fft reads the room once the transform is current, set_fft_spots finds the
//  lattice's spots and their spacing, get_fft_data and get_fft_picture give the exports' numbers and picture, set_fft refuses a
//  region the room cannot transform and a setting without its mode.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorFFTTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-fft-tests-\(UUID().uuidString)"
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

    /// A window with the demo lattice open, moved to the FFT room, its transform current.
    @MainActor private func fftWindow() async throws -> (AppState, OpenItem) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.lattice)?.value
        try await waitUntil("the demo lattice to open", seconds: 60) {
            state.openItems.selected?.session.image != nil && state.openItems.selected?.presentation.canvas != nil
        }
        let outside = try await call("get_fft")
        XCTAssertTrue(outside.refused, "the window shows the Image room")
        let moved = try await call("select_room", ["room": "fft"])
        XCTAssertFalse(moved.refused, moved.text)
        let item = try XCTUnwrap(state.openItems.selected)
        _ = try await call("get_fft")
        try await waitUntil("the transform", seconds: 60) { item.fft.isSpectrumCurrent }
        return (state, item)
    }

    @MainActor private func spotsSettled(_ item: OpenItem) -> Bool {
        !item.fft.isFindingSpots && item.fft.spots.allSatisfy { spot in
            if case .measuring = spot.outcome { return false }
            return true
        }
    }

    /// Mutation: find not reaching Find Spots, the spot rows not the estimator's d, or the exports' numbers not the snapshots' - red.
    @MainActor func testFindSpotsMeasuresTheLatticeSpacing() async throws {
        let (_, item) = try await fftWindow()
        let room = try json(try await call("get_fft").text)
        XCTAssertEqual(room["current"] as? Bool, true)
        XCTAssertNotNil(room["spectrum"] as? [String: Any])

        let found = try await call("set_fft_spots", ["find": true])
        XCTAssertFalse(found.refused, found.text)
        try await waitUntil("the spots to be found and measured", seconds: 60) { item.fft.spots.count > 0 && self.spotsSettled(item) }
        let spots = try XCTUnwrap((try json(try await call("get_fft").text)["spots"] as? [String: Any])?["list"] as? [[String: Any]])
        let lattice = spots.filter { ($0["d"] as? Double).map { abs($0 - 0.235) < 0.01 } ?? false }
        XCTAssertFalse(lattice.isEmpty, "a spot at the planted 0.235 nm: \(spots.map { $0["d"] ?? "-" })")
        XCTAssertEqual(lattice.first?["d_unit"] as? String, "nm")

        let csv = try json(try await call("get_fft_data", ["which": "spots"]).text)
        XCTAssertEqual(csv["spots"] as? Int, item.fft.spots.filter { $0.measured != nil }.count)
        let profile = try await call("get_fft_data", ["which": "radial_profile"])
        XCTAssertFalse(profile.refused, profile.text)
        XCTAssertTrue((try json(profile.text)["csv"] as? String)?.isEmpty == false)
        let picture = try await call("get_fft_picture", ["which": "transform"])
        XCTAssertTrue(picture.image, picture.text)

        let first = try XCTUnwrap(item.fft.spots.first?.number)
        let out = try await call("set_fft_spots", ["out_of_mask": "\(first)"])
        XCTAssertFalse(out.refused, out.text)
        XCTAssertEqual(item.fft.spots.first?.inMask, false)
        let removed = try await call("set_fft_spots", ["remove": "all"])
        XCTAssertFalse(removed.refused, removed.text)
        XCTAssertTrue(item.fft.spots.isEmpty)
    }

    /// Mutation: set_fft taking a region the room cannot transform, a σ without Gaussian smoothing, or a view with nothing to show;
    /// a window not reaching setPreprocess - red.
    @MainActor func testSettingsAndTheirRefusals() async throws {
        let (state, item) = try await fftWindow()
        let odd = try await call("set_fft", ["region": "0 0 31"])
        XCTAssertTrue(odd.refused, "under 32 px and odd")
        XCTAssertNil(item.fft.region)
        let sigma = try await call("set_fft", ["sigma": 2])
        XCTAssertTrue(sigma.refused, "sigma is the Gaussian smoothing's")
        let absf = try await call("set_fft", ["view": "absf"])
        XCTAssertTrue(absf.refused, "no Filter run yet")

        let window = try await call("set_fft", ["window": "hann"])
        XCTAssertFalse(window.refused, window.text)
        XCTAssertEqual(item.fft.preprocess.window, .hann)
        XCTAssertTrue(state.activityLog.messages.contains("An agent used FFT room settings (window hann)."), "\(state.activityLog.messages)")
        let centred = try await call("set_fft", ["region": "128 128 256"])
        XCTAssertFalse(centred.refused, centred.text)
        XCTAssertEqual(item.fft.region?.width, 256)
        let whole = try await call("set_fft", ["region": "whole"])
        XCTAssertFalse(whole.refused, whole.text)
        XCTAssertNil(item.fft.region)
        let finder = try await call("set_fft", ["finder_count": 4, "finder_distance": 10])
        XCTAssertFalse(finder.refused, finder.text)
        XCTAssertEqual(item.fft.spotFinder.count, 4)
        XCTAssertEqual(item.fft.spotFinder.minDistance, 10)
    }
}
