//
//  AgentDoorCoverageTests.swift
//  The agent door's coverage table (EMStudio/App/AgentDoorCoverage.swift, #558): every control in the app's sources has a row, every
//  tool a row names is one the door registers, and no row outlives its control. A new control fails here until someone decides how an
//  agent reaches it (a tool, already seen, left to the person, or a gap with its issue).
//
//  The menu bar's items have their own table (`AgentDoorCoverage.menuItems`, #847): every Button and Toggle in a `Commands` source has
//  a row, every tool it names is registered, and no row outlives its item. Last, every tool that acts is in docs/agent-door.md's
//  "Tools that act", and that table lists no tool the door does not register as acting.
//

import Foundation
import ShellAgentDoor
import XCTest
@testable import EMStudio

nonisolated final class AgentDoorCoverageTests: XCTestCase {
    /// The `accessibilityIdentifier("…")` literals in EMStudio/ (UI and App), as written.
    private func appIdentifiers() throws -> Set<String> {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("EMStudio")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        let files = walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no app sources at \(app.path)")
        let pattern = try NSRegularExpression(pattern: #"accessibilityIdentifier\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)"#)
        var found = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { found.insert(String(text[range])) }
            }
        }
        return found
    }

    /// Mutation: a control is added to the UI without a row - red.
    func testEveryControlHasARow() throws {
        let identifiers = try appIdentifiers()
        XCTAssertGreaterThan(identifiers.count, 300, "the scan found too few controls to be the real UI")
        let missing = identifiers.subtracting(AgentDoorCoverage.controls.keys).sorted()
        XCTAssert(missing.isEmpty, "controls with no row in AgentDoorCoverage (say how an agent reaches each): \(missing)")
    }

    /// Mutation: a row names a tool the door does not register - red.
    @MainActor func testEveryNamedToolExists() {
        let names = Set(MacTEMAgentDoor.allTools.map(\.name))
        for (control, reach) in AgentDoorCoverage.controls {
            if case .tool(let name) = reach { XCTAssert(names.contains(name), "\(control) names \(name), which the door does not have") }
        }
    }

    /// A row whose control is gone is stale.
    func testNoRowOutlivesItsControl() throws {
        let stale = Set(AgentDoorCoverage.controls.keys).subtracting(try appIdentifiers()).sorted()
        XCTAssert(stale.isEmpty, "rows for controls that no longer exist: \(stale)")
    }

    /// A gap names this repo's open issue for the door; a reason left to the person says something.
    func testGapsAndReasonsSaySomething() {
        for (control, reach) in AgentDoorCoverage.controls {
            switch reach {
            case .gap(let issue): XCTAssertGreaterThan(issue, 0, "\(control): a gap names its issue")
            case .personOnly(let reason): XCTAssertGreaterThan(reason.count, 20, "\(control): say why it stays the person's")
            case .tool, .seen: break
            }
        }
    }

    // MARK: - The menu bar (#847)

    private static var root: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The end of a string literal that starts at `start` (just after its opening quote): the index after its closing quote. An
    /// interpolation `\(…)` is skipped whole, with its parentheses balanced.
    private static func endOfLiteral(_ chars: [Character], from start: Int) -> Int {
        var i = start
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
                var depth = 1; i += 2
                while i < chars.count, depth > 0 {
                    if chars[i] == "\"" { i = endOfLiteral(chars, from: i + 1); continue }
                    if chars[i] == "(" { depth += 1 } else if chars[i] == ")" { depth -= 1 }
                    i += 1
                }
                continue
            }
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "\"" { return i + 1 }
            i += 1
        }
        return i
    }

    /// The title argument of every `Button(` and `Toggle(` in `text`, as written: a literal's text without its quotes, or the
    /// expression up to the first comma or closing parenthesis outside brackets and literals, its whitespace squeezed.
    static func menuTitles(in text: String) -> [String] {
        let chars = Array(text)
        let pattern = try! NSRegularExpression(pattern: #"\b(Button|Toggle)\("#)
        var titles: [String] = []
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let start = text.distance(from: text.startIndex, to: range.upperBound)
            var i = start
            var depth = 0
            while i < chars.count {
                let c = chars[i]
                if c == "\"" { i = endOfLiteral(chars, from: i + 1); continue }
                if "([{".contains(c) { depth += 1 } else if ")]}".contains(c) {
                    if depth == 0 { break }
                    depth -= 1
                } else if c == ",", depth == 0 { break }
                i += 1
            }
            var title = String(chars[start..<i]).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if title.count >= 2, title.first == "\"", title.last == "\"", endOfLiteral(Array(title), from: 1) == title.count {
                title = String(title.dropFirst().dropLast())
            }
            if !title.isEmpty { titles.append(title) }
        }
        return titles
    }

    /// The titles of the menu bar's items: every Button and Toggle in a EMStudio/ source that builds `some Commands`.
    private func menuItemTitles() throws -> Set<String> {
        let app = Self.root.appendingPathComponent("EMStudio")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var found = Set<String>()
        var files = 0
        for case let file as URL in walk where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("some Commands") else { continue }
            files += 1
            found.formUnion(Self.menuTitles(in: text))
        }
        XCTAssertGreaterThanOrEqual(files, 3, "the Commands sources (EMStudioApp, ExportCommands, SessionCommands)")
        return found
    }

    /// The reader takes literals, interpolations and expressions as written.
    func testTheMenuReaderReadsTitlesAsWritten() {
        let text = #"""
        Button("Open…") { perform(.openImage) }
        Button("Go to \(group.title)") { x() }
        Button(recents.title(of: entry)) { y() }
        Toggle(tool.title, isOn: Binding(get: { a }, set: { b }))
        Button(appState.map { RoomPrimaryAction.stopTitle($0) } ?? "Stop") { z() }
        CheckForUpdatesButton(update: update)
        """#
        XCTAssertEqual(Self.menuTitles(in: text), [
            "Open…", #"Go to \(group.title)"#, "recents.title(of: entry)", "tool.title",
            #"appState.map { RoomPrimaryAction.stopTitle($0) } ?? "Stop""#,
        ])
    }

    /// Mutation: a menu item is added (a new export, a new room verb) without a row - red.
    func testEveryMenuItemHasARow() throws {
        let titles = try menuItemTitles()
        XCTAssertGreaterThan(titles.count, 30, "the scan found too few menu items to be the real menu bar: \(titles.sorted())")
        let missing = titles.subtracting(AgentDoorCoverage.menuItems.keys).sorted()
        XCTAssert(missing.isEmpty, "menu items with no row in AgentDoorCoverage.menuItems (say how an agent does each): \(missing)")
    }

    /// A row whose menu item is gone is stale.
    func testNoMenuRowOutlivesItsItem() throws {
        let stale = Set(AgentDoorCoverage.menuItems.keys).subtracting(try menuItemTitles()).sorted()
        XCTAssert(stale.isEmpty, "menu rows for items that no longer exist: \(stale)")
    }

    /// Mutation: a menu row names a tool the door does not register - red. A gap names its issue; a reason says something.
    @MainActor func testEveryMenuRowNamesARegisteredToolOrAReason() {
        let names = Set(MacTEMAgentDoor.allTools.map(\.name))
        for (item, reach) in AgentDoorCoverage.menuItems {
            switch reach {
            case .tool(let name): XCTAssert(names.contains(name), "\(item) names \(name), which the door does not have")
            case .gap(let issue): XCTAssertGreaterThan(issue, 0, "\(item): a gap names its issue")
            case .personOnly(let reason): XCTAssertGreaterThan(reason.count, 20, "\(item): say why it stays the person's")
            case .seen: break
            }
        }
    }

    /// Mutation: a tool that acts is registered and not written into docs/agent-door.md's "Tools that act" - red; so is a row there
    /// for a tool the door does not register as acting.
    @MainActor func testEveryActingToolIsInTheGuide() throws {
        let guide = try String(contentsOf: Self.root.appendingPathComponent("docs/agent-door.md"), encoding: .utf8)
        let start = try XCTUnwrap(guide.range(of: "\n## Tools that act\n"), "the guide's Tools that act section")
        let rest = guide[start.upperBound...]
        let section = rest.range(of: "\n## ").map { rest[..<$0.lowerBound] } ?? rest
        let row = try NSRegularExpression(pattern: #"(?m)^\| `([a-z_]+)` \|"#)
        let text = String(section)
        let listed = Set(row.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
        let acting = Set(MacTEMAgentDoor.allTools.filter(\.acts).map(\.name))
        XCTAssertGreaterThan(acting.count, 10)
        XCTAssertEqual(acting.subtracting(listed).sorted(), [], "tools that act and are not in docs/agent-door.md's Tools that act")
        XCTAssertEqual(listed.subtracting(acting).sorted(), [], "rows in Tools that act for tools the door does not register as acting")
    }
    /// The EDS room's Polygon Region Tool, Line Tool and Pin Region reach the door through set_eds (#885, EMSuiteUI 0.16.0).
    /// Red before: set_eds took no vertices, keep or line, and the three menu rows were gaps.
    @MainActor func testTheEDSRegionToolsReachTheDoor() throws {
        let tool = try XCTUnwrap(MacTEMAgentDoor.allTools.first { $0.name == "set_eds" })
        XCTAssertTrue(Set(tool.parameters.map(\.name)).isSuperset(of: ["vertices", "keep", "name", "line"]))
        for item in ["Polygon Region Tool", "Line Tool", "Pin Region"] {
            XCTAssertEqual(AgentDoorCoverage.menuItems[item], .tool("set_eds"), item)
        }
    }
}
