//
//  AgentDoorDiffractionScienceTests.swift
//  The agent door's 2.4 Diffraction tools (#816), through a real door over MCP on the demo Au pattern (Help > Open Demo Data, as
//  AgentDoorDiffractionTests): powder_pattern answers the Powder section's table and refuses a bad range or comparing the crystal
//  with itself without changing a setting; plan_tilt before Index gives the refusal the Holder section shows and no α or β, and sets the β sense (#932);
//  set_relationship refuses a malformed pair and the matrix as its own precipitate; find_phases refuses Rank before a ring and
//  ranks Au on a fitted {111} ring. Red before: none of the four tools existed.
//

import DiffractoGeometry
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorDiffractionScienceTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-diffraction-science-tests-\(UUID().uuidString)"
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

    /// A window with the demo Au pattern open, moved to the Diffraction room.
    @MainActor private func diffractionWindow() async throws -> (AppState, OpenItem) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        await state.openDemo(.diffraction)?.value
        try await waitUntil("the demo pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        if state.navigation.workspaceArea != .diffraction {
            let outside = try await call("get_diffraction")
            XCTAssertTrue(outside.refused, "the window shows another room")
            let moved = try await call("select_room", ["room": "diffraction"])
            XCTAssertFalse(moved.refused, moved.text)
        }
        return (state, try XCTUnwrap(state.openItems.selected))
    }

    /// Mutation: the answer not the section's table, or a refused call changing the kind given beside it - red.
    @MainActor func testPowderPatternIsTheSectionsTable() async throws {
        let (state, item) = try await diffractionWindow()
        let answer = try await call("powder_pattern", ["kind": "xray", "compare": "Al"])
        XCTAssertFalse(answer.refused, answer.text)
        let powder = try json(answer.text)
        XCTAssertEqual(powder["phases"] as? [String], ["Au", "Al"])
        let image = try XCTUnwrap(item.session.image)
        let table = MacTEMAgentDoor.powderTable(item, image: image, others: [])
        XCTAssertEqual((powder["peaks"] as? [[String: Any]])?.count, table.rows.count)
        XCTAssertEqual(powder["headlines"] as? [String], table.phases.indices.map { table.headline(phase: $0) })
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Diffraction powder pattern (compare Al; kind xray).") },
                      "\(state.activityLog.messages)")

        let backwards = try await call("powder_pattern", ["kind": "rings", "two_theta_from": 80, "two_theta_to": 20])
        XCTAssertTrue(backwards.refused, "the range runs backwards")
        XCTAssertEqual(item.diffractionPowder.settings.kind, .xray, "a refused call changes nothing")
        let itself = try await call("powder_pattern", ["compare": "Au"])
        XCTAssertTrue(itself.refused, "the crystal is not compared with itself")
        XCTAssertEqual(item.diffractionPowder.compareWith, "Al")
    }

    /// Mutation: plan_tilt giving tilts or a pick before Index, or set_relationship taking a malformed pair - red.
    @MainActor func testHolderAndRelationshipBeforeIndex() async throws {
        let (_, item) = try await diffractionWindow()
        let holder = try json(try await call("plan_tilt", ["alpha": 5]).text)
        XCTAssertNotNil(holder["refusal"] as? String, "\(holder)")
        XCTAssertNil(holder["zone_axes"], "no orientation, no zone axes")
        XCTAssertEqual(try XCTUnwrap(holder["alpha_deg"] as? Double), 5, accuracy: 1e-9)
        XCTAssertEqual(holder["beta_sense"] as? String, "positive")
        XCTAssertEqual(holder["beta_sense_from"] as? String, "assumed")
        let reversed = try json(try await call("plan_tilt", ["beta_sense": "reversed"]).text)
        XCTAssertEqual(reversed["beta_sense"] as? String, "reversed", "\(reversed)")
        XCTAssertEqual(reversed["beta_sense_from"] as? String, "hand")
        XCTAssertEqual(item.diffractionHolder.settings.betaSenseSetting, .negative, "the section's own setting")
        let badSense = try await call("plan_tilt", ["beta_sense": "sideways", "alpha": 9])
        XCTAssertTrue(badSense.refused)
        XCTAssertEqual(item.diffractionHolder.settings.alphaDeg, 5, "a refused call changes nothing")
        let pick = try await call("plan_tilt", ["zone_axis": "[1 1 0]"])
        XCTAssertTrue(pick.refused, "nothing to pick before Index")
        XCTAssertNil(item.diffractionHolder.selected)
        let write = try await call("plan_tilt", ["write": true])
        XCTAssertTrue(write.refused, "no tilt list before Index")

        let before = item.diffractionVariants.relationship
        let bad = try await call("set_relationship", ["first": "[1 0 0] [3 2 0]", "show": true])
        XCTAssertTrue(bad.refused, "a pair needs ||")
        XCTAssertEqual(item.diffractionVariants.relationship, before)
        XCTAssertFalse(item.diffractionVariants.isShown, "a refused call changes nothing")
        let matrix = try await call("set_relationship", ["precipitate": "Au"])
        XCTAssertTrue(matrix.refused, "the matrix is not its own precipitate")
        let empty = try json(try await call("set_relationship", [:]).text)
        XCTAssertEqual(empty["precipitate"] as? String, "none", "nothing chosen by default (#1137)")
        XCTAssertEqual(empty["relationship"] as? String, "none")
        let half = try await call("set_relationship", ["precipitate": "Al", "second": "(0 0 1) ∥ (1 -3 0)"])
        XCTAssertTrue(half.refused, "one pair is not a relationship")
        XCTAssertNil(item.diffractionVariants.precipitate, "a refused call changes nothing")
        let example = try json(try await call("set_relationship", ["example": "beta_double_prime_in_al"]).text)
        XCTAssertEqual(example["precipitate"] as? String, "β″")
        XCTAssertNotNil(example["warning"] as? String, "the paper states it for Al, the crystal is Au: \(example)")
        let precipitate = try json(try await call("set_relationship", ["precipitate": "Al", "first": "[1 0 0] || [3 2 0]",
                                                                       "second": "(0 0 1) ∥ (1 -3 0)"]).text)
        XCTAssertEqual(precipitate["precipitate"] as? String, "Al")
        XCTAssertNil(precipitate["example"], "a new precipitate leaves the example")
        XCTAssertNil(precipitate["warning"])
        XCTAssertEqual(item.diffractionVariants.relationship?.secondMatrix, RelationshipVector(.plane, 1, -3, 0))
        XCTAssertNotNil(precipitate["refusal"] as? String, "no matrix orientation before Index: \(precipitate)")
        let hideNone = try await call("set_relationship", ["precipitate": "Si", "hide": "1"])
        XCTAssertTrue(hideNone.refused, "no variant is placed to hide")
        XCTAssertEqual(item.diffractionVariants.precipitate?.name, "Al", "a refused call changes nothing, the precipitate given beside it too")
    }

    /// Mutation: Rank going ahead without a ring, use taking an unranked name, or the rows not the finder's - red.
    @MainActor func testFindPhasesRanksOnAFittedRing() async throws {
        let (_, item) = try await diffractionWindow()
        let early = try await call("find_phases", ["rank": true])
        XCTAssertTrue(early.refused, "no ring yet")
        let unranked = try await call("find_phases", ["use": "Al"])
        XCTAssertTrue(unranked.refused, "nothing ranked yet")
        XCTAssertEqual(item.diffraction.crystal.name, "Au")

        let room = try json(try await call("get_diffraction").text)
        let families = try XCTUnwrap(room["families"] as? [[String: Any]])
        let index111 = try XCTUnwrap(families.first { $0["name"] as? String == "{111}" }?["index"] as? Int, "\(families)")
        let calibrate = try await call("set_diffraction", ["inner": 29, "outer": 37, "family": index111, "calibrate": true])
        XCTAssertFalse(calibrate.refused, calibrate.text)
        try await waitUntil("the ring fit to land", seconds: 60) { !item.diffraction.isFitting && !item.diffraction.rings.isEmpty }

        let ranked = try await call("find_phases", ["rank": true])
        XCTAssertFalse(ranked.refused, ranked.text)
        try await waitUntil("the ranking to land", seconds: 60) { !item.diffractionPhases.isRunning && item.diffractionPhases.result != nil }
        let answer = try json(try await call("find_phases").text)
        let rows = try XCTUnwrap(answer["rows"] as? [[String: Any]], "\(answer)")
        XCTAssertEqual(rows.map { $0["name"] as? String }, item.diffractionPhases.result?.rows.map(\.name))
        let au = try XCTUnwrap(rows.first { $0["name"] as? String == "Au" })
        XCTAssertEqual(au["explains"] as? Int, 1)
        XCTAssertEqual(au["measured"] as? Int, 1)
        let used = try await call("find_phases", ["use": "Au"])
        XCTAssertFalse(used.refused, used.text)
        XCTAssertEqual(item.diffraction.crystal.name, "Au")
    }

    /// Mutation: ∥ not read as ||, or a side not parsed as a plane or a direction - red.
    @MainActor func testAPairReadsBothSides() {
        let p = MacTEMAgentDoor.pair("[1 0 0] ∥ (3 2 0)")
        XCTAssertEqual(p?.0, RelationshipVector(.direction, 1, 0, 0))
        XCTAssertEqual(p?.1, RelationshipVector(.plane, 3, 2, 0))
        XCTAssertNotNil(MacTEMAgentDoor.pair("[0 0 1] || [1 -3 0]"))
        XCTAssertNil(MacTEMAgentDoor.pair("[1 0 0]"))
        XCTAssertNil(MacTEMAgentDoor.pair("[1 0 0] || nope"))
    }
}
