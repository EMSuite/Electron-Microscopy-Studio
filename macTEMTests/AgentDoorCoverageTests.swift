//
//  AgentDoorCoverageTests.swift
//  The agent door's coverage table (macTEM/App/AgentDoorCoverage.swift, #558): every control in the app's sources has a row, every
//  tool a row names is one the door registers, and no row outlives its control. A new control fails here until someone decides how an
//  agent reaches it (a tool, already seen, left to the person, or a gap with its issue).
//

import Foundation
import XCTest
@testable import macTEM

nonisolated final class AgentDoorCoverageTests: XCTestCase {
    /// The `accessibilityIdentifier("…")` literals in macTEM/ (UI and App), as written.
    private func appIdentifiers() throws -> Set<String> {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("macTEM")
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
}
