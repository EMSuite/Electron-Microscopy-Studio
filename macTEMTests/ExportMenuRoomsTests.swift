//
//  ExportMenuRoomsTests.swift
//  The File menu lists only the room on screen's exports (#631, Paul's pick: flat, current room only, as mac4DSTEM's File menu
//  does): `FixedExports.listed(in:)` names the fixed groups each room lists, and `ExportCommands` draws each group behind it.
//

import XCTest
@testable import macTEM

nonisolated final class ExportMenuRoomsTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// Each room lists its own fixed group and no other; no window lists none. Red under: the Image items listed in every room (the
    /// menu before #631); the Session Report missing from a room that feeds it.
    func testEachRoomListsOnlyItsOwnFixedExports() {
        XCTAssertEqual(FixedExports.listed(in: nil), [])
        let expected: [WorkspaceArea: Set<FixedExports>] = [
            .image: [.image], .fft: [.fft], .results: [.results, .sessionReport],
            .edx: [.sessionReport], .patterns: [.sessionReport], .indexing: [.sessionReport], .maps: [.sessionReport],
            .diffraction: [], .eels: [],
        ]
        for area in WorkspaceArea.allCases {
            XCTAssertEqual(FixedExports.listed(in: area), expected[area], "\(area)")
        }
    }

    /// Every fixed item sits behind its group's check, keeps its key and its disabled rule. Red under: an item drawn outside its
    /// `if` (listed in every room again); a key or `.disabled` dropped in the move.
    func testEveryFixedItemIsDrawnBehindItsRoom() throws {
        let commands = squeezed(try source("macTEM/App/ExportCommands.swift"))
        XCTAssertTrue(commands.contains("let fixed = FixedExports.listed(in: appState?.navigation.workspaceArea)"))
        XCTAssertTrue(commands.contains("if fixed.contains(.image) { Divider() Button(\"Export Image…\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"e\", modifiers: [.command, .shift]) .disabled(availability?.image != true)"))
        XCTAssertTrue(commands.contains("if fixed.contains(.fft) { Divider() Button(\"Export Transform…\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"e\", modifiers: [.command, .option]) .disabled(fft?.transform != true)"))
        XCTAssertTrue(commands.contains(".disabled(fft?.spots != true) }"), "Export Spots… closes the FFT group")
        XCTAssertTrue(commands.contains("if fixed.contains(.results) { Button(\"Export Results…\")"))
        XCTAssertTrue(commands.contains("if fixed.contains(.sessionReport) { Button(\"Export Session Report…\")"))
        XCTAssertTrue(commands.contains(".disabled(session != true) }"))
        for title in ["Export Image…", "Export Profile…", "Export Transform…", "Export Radial Profile…", "Export Spots…",
                      "Export Results…", "Export Session Report…"] {
            XCTAssertEqual(commands.components(separatedBy: "Button(\"\(title)\")").count - 1, 1, "\(title) drawn once")
        }
    }
}
