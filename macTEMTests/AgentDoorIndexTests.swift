//
//  AgentDoorIndexTests.swift
//  The agent door's Index tools (#791, plan row R8), through a real door over MCP on the demo Au pattern (Help > Open Demo Data:
//  512 × 512, centre (256, 256), {220} as six spots at R 55.48 px at 45° + k·60°, the file's axis written 1 % large): six spots
//  clicked through set_diffraction_marks, index_pattern presses Index and get_spot_table reads its answer (the six {220} of Au
//  [111], the zone axis only, as clicks carry no intensity), the Spots CSV is Export Spots CSV…'s, set_zone_axis and
//  simulate_pattern set the Index and Simulation sections through the room's intents, and get_diffraction_picture draws the
//  pattern. Red before: the door had none of these tools.
//

import Foundation
import ShellAgentDoor
import ShellLayout
import DiffractoCore
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorIndexTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-index-tests-\(UUID().uuidString)"
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

    /// Mutation: index_pattern not pressing the room's Index, get_spot_table not reading `indexOutcome` and `indexSpotRows`, the
    /// CSV not Export Spots CSV…'s, or set_zone_axis and simulate_pattern not reaching the analysis' intents - red.
    @MainActor func testIndexSixClickedSpotsAndReadTheSpotTable() async throws {
        let (state, item) = try await diffractionWindow()
        let before = try json(try await call("get_spot_table").text)
        XCTAssertTrue(before["answer"] is NSNull, "no answer before Index")
        XCTAssertEqual((before["rows"] as? [Any])?.count, 0)

        for k in 0..<6 {
            let a = (45.0 + 60.0 * Double(k)) * .pi / 180
            let added = try await call("set_diffraction_marks", ["add_spot": "\(256 + 55.48 * sin(a) + 0.7) \(256 + 55.48 * cos(a) - 0.6)"])
            XCTAssertFalse(added.refused, added.text)
        }
        XCTAssertEqual(item.diffraction.spots.count, 6)

        let pressed = try await call("index_pattern")
        XCTAssertFalse(pressed.refused, pressed.text)
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Index.") }, "\(state.activityLog.messages)")
        try await waitUntil("Index to land", seconds: 60) { !item.diffraction.isIndexing }
        let table = try json(try await call("get_spot_table").text)
        XCTAssertEqual(table["indexing"] as? Bool, false)
        let answer = try XCTUnwrap(table["answer"] as? [String: Any], "\(table)")
        XCTAssertEqual(answer["zone_axis_only"] as? Bool, true, "clicked spots carry no intensity")
        XCTAssertEqual(answer["line"] as? String, item.diffraction.indexLine)
        let solutions = try XCTUnwrap(answer["solutions"] as? [[String: Any]])
        let axis = try XCTUnwrap(solutions.first?["zone_axis"] as? [Int], "\(answer)")
        XCTAssertEqual(axis.map(abs).sorted(), [1, 1, 1], "six {220} at 60° are Au [111]")
        XCTAssertEqual(answer["explained"] as? Int, 6)
        let rows = try XCTUnwrap(table["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["spot"] as? Int }, [1, 2, 3, 4, 5, 6])
        for row in rows {
            let hkl = try XCTUnwrap(row["hkl"] as? [Int], "\(row)")
            XCTAssertEqual(hkl.map(abs).sorted(), [0, 2, 2], "\(row)")
            XCTAssertEqual(row["phase"] as? String, "Au")
        }
        let spots = try XCTUnwrap(table["spots"] as? [[String: Any]])
        XCTAssertTrue(spots.allSatisfy { $0["found"] as? Bool == false }, "the six are clicked")

        let image = try XCTUnwrap(item.session.image)
        let csv = try json(try await call("get_spot_table", ["csv": true]).text)["csv"] as? String
        XCTAssertEqual(csv, ExportSnapshot.diffractionSpotsCSV(item.diffraction, image: image, openItems: state.openItems))

        let typo = try await call("set_zone_axis", ["zone_axis": "1 a 0"])
        XCTAssertTrue(typo.refused, "not a zone axis")
        let typed = try await call("set_zone_axis", ["zone_axis": "[0 0 1]", "turn": 30])
        XCTAssertFalse(typed.refused, typed.text)
        XCTAssertEqual(item.diffraction.simulation.zoneAxis, SIMD3(0, 0, 1))
        XCTAssertEqual(item.diffraction.simulation.inPlaneDegrees, 30)
        XCTAssertNil(item.diffraction.simulation.indexed, "a typed zone axis takes the overlay off Index's orientation")

        let shown = try await call("simulate_pattern", ["overlay": true, "labels": false])
        XCTAssertFalse(shown.refused, shown.text)
        XCTAssertTrue(item.diffraction.simulation.isShown)
        XCTAssertFalse(item.diffraction.simulation.showsLabels)
        let simulation = try XCTUnwrap(try json(shown.text)["simulation"] as? [String: Any])
        XCTAssertFalse(try XCTUnwrap(simulation["spots"] as? [[String: Any]]).isEmpty, "\(simulation)")

        await item.diffractionView.show(image: image, analysis: item.diffraction)
        let picture = try await call("get_diffraction_picture")
        XCTAssertFalse(picture.refused, picture.text)
        XCTAssertTrue(picture.image)
    }

    /// Mutation: remove_spots not removing the spots first (Index would read the clicks again) - red.
    @MainActor func testIndexAfreshFindsTheSpots() async throws {
        let (_, item) = try await diffractionWindow()
        _ = try await call("set_diffraction_marks", ["add_spot": "\(256 + 55.48 * sin(Double.pi / 4)) \(256 + 55.48 * cos(Double.pi / 4))"])
        let pressed = try await call("index_pattern", ["remove_spots": true])
        XCTAssertFalse(pressed.refused, pressed.text)
        try await waitUntil("Index to land", seconds: 60) { !item.diffraction.isIndexing }
        XCTAssertGreaterThanOrEqual(item.diffraction.spots.count, 2)
        XCTAssertTrue(item.diffraction.spots.allSatisfy { $0.intensity != nil }, "Index found the spots afresh")
    }

    /// Fit scale, the solutions, the Tilt tool, Flip, double diffraction and the excitation error through the door (#787, #786): each
    /// reaches the analysis' own intent. Mutation: fit_scale not setting `fitScale`, tilt_down not tilting as the Tilt tool, flip not
    /// flipping, solution not `selectSolution`, or the Simulation section's two settings not reaching the analysis - red.
    @MainActor func testSolutionsTiltFlipAndTheSimulationSettings() async throws {
        let (_, item) = try await diffractionWindow()
        let analysis = item.diffraction
        let pressed = try await call("index_pattern", ["fit_scale": false])
        XCTAssertFalse(pressed.refused, pressed.text)
        XCTAssertFalse(analysis.fitScale)
        try await waitUntil("Index to land", seconds: 60) { !analysis.isIndexing }
        let table = try await call("get_spot_table")
        let answer = try XCTUnwrap(try json(table.text)["answer"] as? [String: Any])
        if analysis.indexOutcome?.orientation != nil {
            XCTAssertEqual(try XCTUnwrap(answer["scale"] as? Double), 1, accuracy: 1e-9, "Fit scale off holds the room's scale")
            XCTAssertEqual(answer["solution"] as? Int, 1)
        }

        let typed = try await call("set_zone_axis", ["zone_axis": "0 0 1", "tilt_down": 2])
        XCTAssertFalse(typed.refused, typed.text)
        XCTAssertTrue(analysis.isTurnedByHand)
        let simulation = try XCTUnwrap(try json(typed.text)["simulation"] as? [String: Any])
        XCTAssertEqual(simulation["place"] as? String, "Au · 2.0° from [001] · set by hand")
        let before = try XCTUnwrap(analysis.drawnOrientation)
        let flipped = try await call("set_zone_axis", ["flip": true])
        XCTAssertFalse(flipped.refused, flipped.text)
        XCTAssertEqual(analysis.drawnOrientation, before.rotatedInPlane(by: .pi))
        if !analysis.solutions.isEmpty {
            let first = try await call("set_zone_axis", ["solution": 1])
            XCTAssertFalse(first.refused, first.text)
            XCTAssertEqual(analysis.drawnOrientation, analysis.solutions.first)
            XCTAssertFalse(analysis.isTurnedByHand)
        }
        let beyond = try await call("set_zone_axis", ["solution": 9])
        XCTAssertTrue(beyond.refused, "at most five solutions")

        let settings = try await call("simulate_pattern", ["overlay": true, "double_diffraction": true, "excitation_error": 0.01])
        XCTAssertFalse(settings.refused, settings.text)
        XCTAssertTrue(analysis.simulation.doubleDiffraction)
        XCTAssertEqual(analysis.simulation.excitationError, 0.01)
        let refused = try await call("simulate_pattern", ["excitation_error": 5])
        XCTAssertTrue(refused.refused, "outside 0.001 to 1")
        XCTAssertEqual(analysis.simulation.excitationError, 0.01)
    }

    func testThePictureDrawsTheSimulatedSpotsUnderTheMarkedOnes() {
        let simulated = (0..<70).map { i in
            ZoneAxisOverlay.Spot(hkl: MillerIndex(i, 0, 0), row: Double(i), column: 10, intensity: Double(100 - i), relative: Double(100 - i) / 100)
        }
        let marked = [MeasuredSpot(clickRow: 5, clickColumn: 6, row: 5.2, column: 6.1, radius: nil, refusal: nil),
                      MeasuredSpot(clickRow: 9, clickColumn: 9, row: nil, column: nil, radius: nil, refusal: "no signal near the click")]
        let marks = DiffractionPicture.marks(spots: marked, simulated: simulated, labels: true)
        XCTAssertEqual(marks.count, 71, "70 simulated, the marked spot with a centre")
        XCTAssertEqual(marks.prefix(70).map(\.kind), Array(repeating: .simulatedSpot, count: 70))
        XCTAssertEqual(marks.prefix(70).filter { !$0.label.isEmpty }.count, ZoneAxisOverlay.labelledCount, "the room's labelled spots")
        XCTAssertEqual(marks.last?.kind, .spot)
        XCTAssertEqual(marks.last?.label, "1")
        XCTAssertEqual(marks.last?.points, [ImagePoint(x: 6.1, y: 5.2)])
        XCTAssertTrue(DiffractionPicture.marks(spots: [], simulated: simulated, labels: false).allSatisfy(\.label.isEmpty))
    }
}
