//
//  AgentDoorFolderTests.swift
//  The agent door's folder tools (#739) through a real door over MCP, as an agent calls them: list_agent_folder lists the Agent folder
//  and nothing outside it; open_file opens a file of the folder as File > Open does and leaves an "An agent" Output line; a path
//  outside the folder, an absolute one, a missing file and a folder are refused; with "Let agents run analyses" off nothing opens.
//

import Foundation
import ShellAgentDoor
import XCTest
@testable import macTEM

nonisolated final class AgentDoorFolderTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    @MainActor private var root: URL!
    @MainActor private var outside: URL!
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-folder-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "macEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(MacTEMAgentDoor.allTools)
        door.runsAllowed = true
        door.setEnabled(true)
        try await waitUntil("the door to open", seconds: 5) { self.isListening }

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agent-folder-\(UUID().uuidString)")
        root = base.appendingPathComponent("folder")
        outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let map = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ebsd-edax-map.ang")
        try FileManager.default.copyItem(at: map, to: root.appendingPathComponent("sub/map.ang"))
        try Data("x".utf8).write(to: outside.appendingPathComponent("secret.ang"))
        // A link inside that leads out is neither listed nor opened.
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("out"), withDestinationURL: outside)
    }

    @MainActor override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        keep = []
        MacTEMAgentDoor.folder.use(folder: nil)
        if let root { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
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
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? false, text)
    }

    @MainActor private func window() -> AppState {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        return state
    }

    /// Mutation: the listing walks out through a link, or no folder is not refused - red.
    @MainActor func testTheListingHoldsTheFolderAndNothingElse() async throws {
        let none = try await call("list_agent_folder")
        XCTAssertTrue(none.refused)
        XCTAssertTrue(none.text.contains("No Agent folder"), none.text)

        MacTEMAgentDoor.folder.use(folder: root)
        let listed = try await call("list_agent_folder")
        XCTAssertFalse(listed.refused, listed.text)
        let files = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(listed.text.utf8)) as? [String: Any])?["files"] as? [[String: Any]])
        XCTAssertEqual(files.compactMap { $0["path"] as? String }, ["sub/map.ang"])
    }

    /// Mutation: open_file going around the folder check, or not through the app's Open, or leaving no Output line - red.
    @MainActor func testOpenFileOpensAFileOfTheFolderAsFileOpenDoes() async throws {
        let state = window()
        MacTEMAgentDoor.folder.use(folder: root)
        let opened = try await call("open_file", ["path": "sub/map.ang"])
        XCTAssertFalse(opened.refused, opened.text)
        XCTAssertTrue(opened.text.contains("sub/map.ang"), opened.text)
        await state.lastOpen?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps, "the orientation map lands in the Maps room, as File > Open puts it")
        XCTAssertTrue(state.activityLog.lines.contains { $0.text == "An agent opened map.ang." }, "the Output line")
    }

    /// Mutation: a path outside the folder, an absolute one, a link out, a missing file or a folder opening - red.
    @MainActor func testPathsOutsideTheFolderAndNonFilesAreRefused() async throws {
        let state = window()
        MacTEMAgentDoor.folder.use(folder: root)
        for path in ["../outside/secret.ang", outside.appendingPathComponent("secret.ang").path, "out/secret.ang", "missing.ang", "sub", ""] {
            let refused = try await call("open_file", ["path": path])
            XCTAssertTrue(refused.refused, "\(path): \(refused.text)")
        }
        XCTAssertNil(state.lastOpen, "nothing opened")
        XCTAssertTrue(state.openItems.items.isEmpty)
    }

    /// With "Let agents run analyses" off, open_file is refused and nothing opens. Mutation: open_file not marked acts - red.
    @MainActor func testOpenFileWaitsForTheSecondSwitch() async throws {
        door.runsAllowed = false
        let state = window()
        MacTEMAgentDoor.folder.use(folder: root)
        let refused = try await call("open_file", ["path": "sub/map.ang"])
        XCTAssertTrue(refused.refused)
        XCTAssertNil(state.lastOpen)
        let listed = try await call("list_agent_folder")
        XCTAssertFalse(listed.refused, "listing only looks: \(listed.text)")
    }
}
