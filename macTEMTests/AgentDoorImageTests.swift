//
//  AgentDoorImageTests.swift
//  The agent door's Image room tools (#558), through a real door over MCP on the demo lattice (Help > Open Demo Data: 512 × 512 at
//  0.0123 nm/px with five planted discs) and the generated SEM image: get_image_room reads the room, set_marks measures as a drag does,
//  get_profile gives Export Profile…'s text, set_particles finds the five discs, set_image_room sets the tool and refuses a frame on
//  a single image.
//

import Foundation
import ImagoCore
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorImageTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-image-tests-\(UUID().uuidString)"
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

    /// A window with `demo` open in the Image room, its picture drawn (the canvas holds the raw range the Level slider spans).
    @MainActor private func imageWindow(_ demo: DemoDocument = .lattice) async throws -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(demo)?.value
        try await waitUntil("the demo image to open", seconds: 60) {
            state.openItems.selected?.session.image != nil && state.openItems.selected?.presentation.canvas != nil
        }
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        return state
    }

    /// Mutation: set_marks going around ImageMeasurements.add, numbering the marks off by one, or taking a wrong number of points;
    /// get_profile not giving ProfileCSV's text; width not reaching the profile - red.
    @MainActor func testMarksAndTheProfile() async throws {
        let state = try await imageWindow()
        let item = try XCTUnwrap(state.openItems.selected)
        let room = try json(try await call("get_image_room").text)
        XCTAssertEqual(room["width"] as? Int, 512)
        XCTAssertEqual((room["marks"] as? [Any])?.count, 0)
        XCTAssertTrue(room["stack"] is NSNull, "the lattice is one image")

        let added = try await call("set_marks", ["add": "distance", "points": "100 100 200 100"])
        XCTAssertFalse(added.refused, added.text)
        XCTAssertEqual(item.measurements.marks.count, 1)
        let mark = try XCTUnwrap((try json(added.text)["marks"] as? [[String: Any]])?.first)
        XCTAssertEqual(mark["number"] as? Int, 1)
        XCTAssertEqual(mark["selected"] as? Bool, true, "a new mark is selected, as after a drag")
        let value = try XCTUnwrap(mark["value"] as? String)
        XCTAssertTrue(value.contains("nm") && value.hasSuffix("100 px"), value)
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Image marks (add distance; points 100 100 200 100).") },
                      "\(state.activityLog.messages)")

        let short = try await call("set_marks", ["add": "angle", "points": "1 1 2 2"])
        XCTAssertTrue(short.refused, "an angle takes three points")
        XCTAssertEqual(item.measurements.marks.count, 1)

        let profile = try await call("set_marks", ["add": "profile", "points": "50 256 450 256", "width": 3])
        XCTAssertFalse(profile.refused, profile.text)
        XCTAssertEqual(item.measurements.marks.last?.kind, .profile)
        XCTAssertEqual(item.measurements.marks.last?.width, 3)
        let csv = try json(try await call("get_profile", ["mark": 2]).text)
        XCTAssertEqual(csv["mark"] as? Int, 2)
        XCTAssertGreaterThan(csv["samples"] as? Int ?? 0, 0)
        XCTAssertTrue((csv["csv"] as? String)?.contains("line profile") == true)
        let notProfile = try await call("get_profile", ["mark": 1])
        XCTAssertTrue(notProfile.refused, "mark 1 is a distance")

        let width = try await call("set_marks", ["select": 1, "width": 5])
        XCTAssertTrue(width.refused, "a distance has no width")
        let gone = try await call("set_marks", ["remove": "1"])
        XCTAssertFalse(gone.refused, gone.text)
        XCTAssertEqual(item.measurements.marks.map(\.kind), [.profile])
        let missing = try await call("set_marks", ["remove": "4"])
        XCTAssertTrue(missing.refused)
    }

    /// Mutation: set_particles' threshold not mapped onto the Level slider's fraction, show not pressing Show Objects, or the
    /// counts not the report's; a threshold taken under Otsu - red.
    @MainActor func testParticlesFindTheFivePlantedDiscs() async throws {
        let state = try await imageWindow()
        let item = try XCTUnwrap(state.openItems.selected)
        let range = try XCTUnwrap(item.presentation.canvas?.rawRange)
        let otsu = try await call("set_particles", ["method": "otsu", "threshold": 2500])
        XCTAssertTrue(otsu.refused, "Otsu chooses the level")
        XCTAssertEqual(item.particles.settings.method, .manual, "a refused call changes nothing")

        let shown = try await call("set_particles", ["polarity": "bright", "threshold": 2500, "show": true])
        XCTAssertFalse(shown.refused, shown.text)
        XCTAssertEqual(item.particles.settings.thresholdFraction,
                       (2500 - Double(range.lowerBound)) / Double(range.upperBound - range.lowerBound), accuracy: 1e-9)
        await item.particles.settled()
        try await waitUntil("Show Objects to land", seconds: 60) { item.particles.report != nil && !item.particles.isComputing }
        let room = try json(try await call("get_image_room").text)
        let result = try XCTUnwrap((room["particles"] as? [String: Any])?["result"] as? [String: Any])
        XCTAssertEqual(result["counted"] as? Int, 5, "the five planted discs")
        XCTAssertEqual(result["current"] as? Bool, true)

        let table = try json(try await call("get_particles", ["sort": "area"]).text)
        let objects = try XCTUnwrap(table["objects"] as? [[String: Any]])
        XCTAssertEqual(objects.count, 5)
        XCTAssertGreaterThan(objects.first?["area"] as? Double ?? 0, objects.last?["area"] as? Double ?? 0, "largest first")
        let csv = try json(try await call("get_particles", ["csv": true]).text)
        XCTAssertEqual(csv["csv"] as? String, ParticleFormat.csv(try XCTUnwrap(item.particles.report),
                                                                 scale: ParticleCompute.scale(of: try XCTUnwrap(item.session.image)),
                                                                 fileName: try XCTUnwrap(item.session.image).fileName))

        let region = try await call("set_particles", ["region": "0 0 300 300"])
        XCTAssertFalse(region.refused, region.text)
        XCTAssertEqual(item.particles.settings.region?.width, 300)
        XCTAssertFalse(item.particles.isCurrent, "a new region makes the objects stale")
        let whole = try await call("set_particles", ["whole_image": true])
        XCTAssertFalse(whole.refused, whole.text)
        XCTAssertNil(item.particles.settings.region)
        let unknown = try await call("set_particles", ["select": 99])
        XCTAssertTrue(unknown.refused)
    }

    /// Mutation: set_image_room not reaching the window's tool, or moving a frame on a single image - red.
    @MainActor func testToolAndFrames() async throws {
        let state = try await imageWindow()
        let tool = try await call("set_image_room", ["tool": "profile"])
        XCTAssertFalse(tool.refused, tool.text)
        XCTAssertTrue(state.imageRoomTools.tool == .profile)
        let frame = try await call("set_image_room", ["frame": 2])
        XCTAssertTrue(frame.refused, "the lattice is not a stack")
    }

    /// Mutation: get_image_room leaving out an SEM file's rows or its databar - red.
    @MainActor func testTheSEMRows() async throws {
        _ = try await imageWindow(.semImage)
        let room = try json(try await call("get_image_room").text)
        let rows = try XCTUnwrap((room["sem"] as? [String: Any])?["rows"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual((room["sem"] as? [String: Any])?["databar_rows"] as? Int, DemoDocuments.semDatabarRows)
    }
}
