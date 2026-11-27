//
//  AgentDoorFolderTests.swift
//  The agent door's folder tools (#739) through a real door over MCP, as an agent calls them: list_agent_folder lists the Agent folder
//  and nothing outside it; open_file opens a file of the folder as File > Open does and leaves an "An agent" Output line; a path
//  outside the folder, an absolute one, a missing file and a folder are refused; with "Let agents run analyses" off nothing opens.
//

import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

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

    /// A truncated listing holds the first files by path, not the first the walk met, and a tree past the visit limit says so
    /// (#926). Mutation: truncating before the sort, or no visit limit - red.
    @MainActor func testATruncatedListingHoldsTheFirstFilesByPath() throws {
        for name in ["c.txt", "a.txt", "e.txt", "b.txt", "d.txt"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        MacTEMAgentDoor.folder.use(folder: root)
        let short = try XCTUnwrap(MacTEMAgentDoor.folder.listing(limit: 3))
        XCTAssertEqual(short.files.compactMap { $0["path"] as? String }, ["a.txt", "b.txt", "c.txt"])
        XCTAssertTrue(short.truncated)
        let whole = try XCTUnwrap(MacTEMAgentDoor.folder.listing())
        XCTAssertEqual(whole.files.compactMap { $0["path"] as? String }, ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt", "sub/map.ang"])
        XCTAssertFalse(whole.truncated)
        XCTAssertEqual(whole.files.first?["bytes"] as? Int, 5)
        let capped = try XCTUnwrap(MacTEMAgentDoor.folder.listing(visitLimit: 2))
        XCTAssertTrue(capped.truncated, "the walk stopped early")
        XCTAssertLessThanOrEqual(capped.files.count, 2)
    }

    /// The walk runs from a background thread and lists what the door lists, so a folder on a share is not walked on the main
    /// actor once the door can wait (#926). Mutation: the walk reading the object's state, or listing another way - red.
    @MainActor func testTheWalkRunsOffTheMainActor() async throws {
        for name in ["b.txt", "a.txt"] { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        let folder: URL = root
        let walked = await offMainActor { () -> [String]? in
            XCTAssertFalse(Thread.isMainThread)
            return AgentFolder.listing(of: folder)?.files.compactMap { $0["path"] as? String }
        }
        XCTAssertEqual(walked, ["a.txt", "b.txt", "sub/map.ang"], "the link out is not listed")
        MacTEMAgentDoor.folder.use(folder: root)
        XCTAssertEqual(MacTEMAgentDoor.folder.listing()?.files.compactMap { $0["path"] as? String }, walked)
    }

    /// Settings > Agents shows the folder's path resolved off the main actor, once per bookmark, not in its view body (#926).
    /// Mutation: resolving on the main thread, or a bookmark that does not resolve showing a path - red.
    @MainActor func testTheShownPathResolvesOffTheMainThread() async throws {
        let none = await AgentFolder.shownPath(bookmark: nil)
        XCTAssertNil(none)
        let junk = await AgentFolder.shownPath(bookmark: Data("not a bookmark".utf8))
        XCTAssertNil(junk)
        guard let bookmark = AgentFolder.bookmark(for: root) else {
            throw XCTSkip("this build cannot make a security-scoped bookmark of a temporary folder")
        }
        let offMain = await offMainActor { () -> String? in
            XCTAssertFalse(Thread.isMainThread)
            return AgentFolder.displayPath(bookmark: bookmark)
        }
        let shown = await AgentFolder.shownPath(bookmark: bookmark)
        XCTAssertEqual(shown, offMain)
        XCTAssertEqual(shown.map { ($0 as NSString).expandingTildeInPath }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       root.resolvingSymlinksInPath().path)
    }

    /// Mutation: open_file going around the folder check, or not through the app's Open, or leaving no Output line - red.
    @MainActor func testOpenFileOpensAFileOfTheFolderAsFileOpenDoes() async throws {
        let state = window()
        MacTEMAgentDoor.folder.use(folder: root)
        let opened = try await call("open_file", ["path": "sub/map.ang"])
        XCTAssertFalse(opened.refused, opened.text)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(opened.text.utf8)) as? [String: Any], opened.text)
        XCTAssertEqual(answer["opening"] as? String, "sub/map.ang", opened.text)
        await state.lastOpen?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps, "the orientation map lands in the Maps room, as File > Open puts it")
        // An Output line is "HH:mm:ss  <message>" (ActivityLog.record).
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("  An agent opened map.ang.") }, "\(state.activityLog.messages)")
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
