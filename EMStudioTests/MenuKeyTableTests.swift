//
//  MenuKeyTableTests.swift
//  The menu bar's key table (2.3 plan row Q10): no two items that can be in the menu bar at the same time share a key, and every
//  room's toolbar verb has a menu item with a key. The keys are read from the menu sources as written (`.keyboardShortcut("k",
//  modifiers: …)`), plus the two derived sets: Go to <workspace> (⌘1…⌘5, `WorkspaceGroup.shortcutDigit`) and the Image room's tools
//  (⌃⌘1…4, `ImageRoomTools.Tool.shortcutDigit`). The Image room's tools and the EDS room's region tools share ⌃⌘0…4 on purpose: each
//  set is in the menu bar only in its own room, which the test reads from the source too. Red under: a new item given a key another
//  item has; a tool key given outside its room; the Run item no longer titled with the room's verb.
//

import XCTest
@testable import EMStudio

nonisolated final class MenuKeyTableTests: XCTestCase {

    private static let menuFiles = ["EMStudio/App/EMStudioApp.swift", "EMStudio/App/ExportCommands.swift", "EMStudio/App/SessionCommands.swift"]

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// A key as the menu shows it, modifiers in the system's order (⌃⌥⇧⌘) then the key, so two spellings of one key compare equal.
    private static func key(_ character: String, modifiers: String) -> String {
        let names: [(String, String)] = [("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘")]
        return names.filter { modifiers.contains(".\($0.0)") }.map(\.1).joined() + character.uppercased()
    }

    /// Every literal key in `text`: `.keyboardShortcut("k", modifiers: .command)` or `modifiers: [.command, .shift]`.
    private static func literalKeys(in text: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #"\.keyboardShortcut\("(.)", modifiers: (\.[a-z]+|\[[^\]]*\])\)"#)
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let character = Range(match.range(at: 1), in: text), let modifiers = Range(match.range(at: 2), in: text) else { return nil }
            return key(String(text[character]), modifiers: String(text[modifiers]))
        }
    }

    /// The EDS room's region tools: the literal keys between the room's `if` and the end of the Workspace menu.
    private func edsToolKeys() throws -> [String] {
        let text = try source("EMStudio/App/EMStudioApp.swift")
        let start = try XCTUnwrap(text.range(of: "appState.navigation.workspaceArea == .edx, appState.edx.hasImage"), "the EDS tools' guard")
        let end = try XCTUnwrap(text.range(of: "Pin Region", range: start.upperBound..<text.endIndex), "Pin Region after the tools")
        return try Self.literalKeys(in: String(text[start.lowerBound..<end.lowerBound]))
    }

    @MainActor func testNoTwoMenuItemsShareAKey() throws {
        var literal: [String] = []
        for file in Self.menuFiles { literal += try Self.literalKeys(in: try source(file)) }
        XCTAssertGreaterThan(literal.count, 15, "the reader finds the menus' keys: \(literal)")
        // Show Next Room and Show Previous Room (#837), the only way between the rooms of a workspace from the keyboard.
        XCTAssertTrue(literal.contains("⇧⌘]") && literal.contains("⇧⌘["), "the room keys: \(literal)")
        let eds = try edsToolKeys()
        XCTAssertEqual(eds, ["⌃⌘0", "⌃⌘1", "⌃⌘2", "⌃⌘3", "⌃⌘4"], "the EDS room's region tools")

        let workspaces = WorkspaceGroup.allCases.map { "⌘\($0.shortcutDigit)" }
        let imageTools = ImageRoomTools.Tool.allCases.map { "⌃⌘\($0.shortcutDigit)" }
        // In the menu bar together: every literal key but the EDS tools, the workspace keys, and either room's tools.
        let always = literal.filter { !eds.contains($0) } + workspaces
        for roomKeys in [eds, imageTools] {
            let table = always + roomKeys
            let shared = Dictionary(grouping: table, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            XCTAssertEqual(shared, [], "keys given to two menu items: \(shared); the table: \(table.sorted())")
        }
    }

    /// Each room's tool keys are in the menu bar only in that room: the Image menu sets its tools' key only `inImageRoom`, and the
    /// EDS tools are listed only while the EDS room shows a spectrum image.
    func testTheSharedToolKeysAreEachInTheirOwnRoomOnly() throws {
        let app = squeezed(try source("EMStudio/App/EMStudioApp.swift"))
        XCTAssertTrue(app.contains("let inImageRoom = appState?.navigation.workspaceArea == .image"))
        XCTAssertTrue(app.contains(".keyboardShortcut(inImageRoom ? KeyboardShortcut(KeyEquivalent(tool.shortcutDigit), modifiers: [.command, .control]) : nil)"))
        XCTAssertTrue(app.contains("if let appState, appState.navigation.workspaceArea == .edx, appState.edx.hasImage {"))
    }

    /// Every toolbar verb (Quantify, Run, Process, Index, Segment, and the Diffraction parts' Calibrate and Measure) has a menu item with a key: Workspace › Run (⌘R) takes the shown
    /// room's verb as its title and runs it (RoomRunMenuTests runs it), and Workspace › Stop (⌘.) stops it.
    func testEveryToolbarVerbHasTheRunItem() throws {
        let verbs = squeezed(try source("EMStudio/UI/RoomPrimaryAction.swift"))
        for verb in ["Quantify", "Run", "Process", "Index", "Segment", "Calibrate", "Measure"] {
            XCTAssertTrue(verbs.contains("title: \"\(verb)\""), "\(verb) is a room's toolbar verb")
        }
        XCTAssertTrue(verbs.contains("static func runTitle(_ appState: AppState?) -> String { appState.flatMap { current($0)?.title } ?? \"Run\" }"))
        let app = squeezed(try source("EMStudio/App/EMStudioApp.swift"))
        XCTAssertTrue(app.contains("Button(RoomPrimaryAction.runTitle(appState)) { if let appState { RoomPrimaryAction.runActive(appState) } } .keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(app.contains(".keyboardShortcut(\".\", modifiers: .command)"))
    }

    /// The reader itself, on planted lines: both spellings of the modifiers, and one key spelled two ways compares equal.
    func testTheReaderReadsBothSpellings() throws {
        let planted = """
            .keyboardShortcut("w", modifiers: .command)
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .keyboardShortcut("E", modifiers: [.shift, .option, .command])
            .keyboardShortcut(.cancelAction)
            """
        XCTAssertEqual(try Self.literalKeys(in: planted), ["⌘W", "⌥⇧⌘E", "⌥⇧⌘E"])
    }
}
