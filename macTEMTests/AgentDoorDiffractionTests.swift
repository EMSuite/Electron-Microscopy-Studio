//
//  AgentDoorDiffractionTests.swift
//  The agent door's Diffraction room tools (#558), through a real door over MCP on the demo Au pattern (Help > Open Demo Data:
//  512 × 512, centre (256, 256), Δq 0.0125 Å⁻¹/px at 200 kV, {111} at R 33.98, {200} at 39.24, {220} as six spots at R 55.48, the
//  file's axis written 1 % large): set_diffraction calibrates on the Au {111} ring and get_diffraction reads the planted scale back,
//  set_diffraction_marks adds a {220} spot that the readout indexes, removes it, and the settings the file states are refused.
//  get_diffraction_figure draws the figure Copy Figure copies (#823).
//  The tolerances are DiffractionAnalysisTests' (the kit's): the door adds none of its own.
//

import Foundation
import ShellAgentDoor
import ShellExport
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorDiffractionTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-diffraction-tests-\(UUID().uuidString)"
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

    @MainActor private func readout(_ room: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(room["readout"] as? [[String: Any]], "\(room)")
    }

    /// Mutation: calibrate not reaching fitRing with the family, the scale not the analysis' calibration, add_spot not adding the
    /// spot as a click does, or remove not going through the room's undo - red.
    @MainActor func testCalibrateOnAuAndIndexASpot() async throws {
        let (state, item) = try await diffractionWindow()
        let room = try json(try await call("get_diffraction").text)
        XCTAssertEqual((room["scale"] as? [String: Any])?["source"] as? String, "the file's axis")
        XCTAssertEqual(room["standard"] as? String, "Au")
        let families = try XCTUnwrap(room["families"] as? [[String: Any]])
        let index111 = try XCTUnwrap(families.first { $0["name"] as? String == "{111}" }?["index"] as? Int, "\(families)")

        let calibrate = try await call("set_diffraction", ["inner": 29, "outer": 37, "family": index111, "calibrate": true])
        XCTAssertFalse(calibrate.refused, calibrate.text)
        try await waitUntil("the ring fit to land", seconds: 60) { !item.diffraction.isFitting && !item.diffraction.rings.isEmpty }
        XCTAssertTrue(state.activityLog.messages.contains { $0.hasSuffix("An agent used Diffraction room settings (calibrate true; family \(index111); inner 29; outer 37).") },
                      "\(state.activityLog.messages)")
        let after = try json(try await call("get_diffraction").text)
        let scale = try XCTUnwrap(after["scale"] as? [String: Any])
        XCTAssertEqual(scale["source"] as? String, "fit Au {111}")
        XCTAssertEqual(try XCTUnwrap(scale["delta_q_per_px"] as? Double), 0.0125, accuracy: 0.0125 * 0.01, "the planted scale")
        XCTAssertEqual(try XCTUnwrap(scale["fit_versus_file_percent"] as? Double), -1, accuracy: 0.3, "the file's axis is 1 % large")
        XCTAssertEqual(try readout(after).first?["family"] as? String, "{111}")
        XCTAssertEqual(try readout(after).first?["calibrating"] as? Bool, true)

        let spot = try await call("set_diffraction_marks", ["add_spot": "\(256 + 55.48 * sin(.pi / 4) + 1.0) \(256 + 55.48 * cos(.pi / 4) - 1.0)"])
        XCTAssertFalse(spot.refused, spot.text)
        let rows = try readout(try json(spot.text))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1]["kind"] as? String, "spot")
        XCTAssertEqual(rows[1]["family"] as? String, "{220}", "\(rows[1])")
        XCTAssertEqual(try XCTUnwrap(rows[1]["d_angstroms"] as? Double), 1.4419, accuracy: 3e-3)

        let csv = try json(try await call("get_diffraction", ["csv": true]).text)["csv"] as? String
        XCTAssertEqual(csv, item.diffraction.exportText(image: try XCTUnwrap(item.session.image)))

        let selected = try await call("set_diffraction_marks", ["select": "spot 1"])
        XCTAssertFalse(selected.refused, selected.text)
        XCTAssertEqual(item.diffractionView.selection, item.diffraction.spots.first?.id)
        let missing = try await call("set_diffraction_marks", ["remove": "spot 2"])
        XCTAssertTrue(missing.refused, "there is one spot")
        let removed = try await call("set_diffraction_marks", ["remove": "spot 1"])
        XCTAssertFalse(removed.refused, removed.text)
        XCTAssertTrue(item.diffraction.spots.isEmpty)
        XCTAssertNil(item.diffractionView.selection, "the removed spot is no longer selected")
        let all = try await call("set_diffraction_marks", ["remove": "all"])
        XCTAssertFalse(all.refused, all.text)
        XCTAssertTrue(item.diffraction.rings.isEmpty)
        XCTAssertFalse(item.diffraction.ringCalibrationExists, "removing the calibrating ring drops its scale")
    }

    /// Mutation: a typed Δq or beam energy taken over the file's own, a refused call changing a setting given beside the refused one
    /// (the centre and the standard before a ring the new standard lacks, #927), or a setting not reaching the analysis' intent - red.
    @MainActor func testSettingsAndTheirRefusals() async throws {
        let (_, item) = try await diffractionWindow()
        let typed = try await call("set_diffraction", ["delta_q": 0.02, "k_max": 2])
        XCTAssertTrue(typed.refused, "the demo file states its reciprocal axis")
        XCTAssertNil(item.diffraction.typedDeltaQ)
        XCTAssertNotEqual(item.diffraction.kMax, 2, "a refused call changes nothing")
        let kv = try await call("set_diffraction", ["beam_kv": 300])
        XCTAssertTrue(kv.refused, "the demo file states 200 kV")
        let annulus = try await call("set_diffraction", ["inner": 40, "outer": 30])
        XCTAssertTrue(annulus.refused, "inner above outer")
        let half = try await call("set_diffraction", ["centre_row": 250])
        XCTAssertTrue(half.refused, "a row without a column")

        let set = try await call("set_diffraction", ["centre_row": 255, "centre_column": 257, "crystal": "Si", "k_max": 2, "tolerance": 2,
                                                     "camera": "Thermo Ceta (14 µm)", "tool": "spot", "log": false])
        XCTAssertFalse(set.refused, set.text)
        let room = try json(set.text)
        XCTAssertEqual((room["centre"] as? [String: Any])?["source"] as? String, "typed")
        XCTAssertEqual(item.diffraction.centre?.row, 255)
        XCTAssertEqual(item.diffraction.centre?.column, 257)
        XCTAssertEqual(item.diffraction.crystal.name, "Si")
        XCTAssertEqual(item.diffraction.kMax, 2)
        XCTAssertEqual(item.diffraction.tolerancePercent, 2)
        XCTAssertEqual(item.diffraction.pitchMM, 0.014)
        XCTAssertEqual(room["camera"] as? String, "Thermo Ceta (14 µm)")
        XCTAssertTrue(item.diffractionView.tool == .spot)
        XCTAssertFalse(item.diffractionView.useLog)

        let standard = try await call("set_diffraction", ["standard": "Al", "camera": "none"])
        XCTAssertFalse(standard.refused, standard.text)
        XCTAssertEqual(item.diffraction.standard.name, "Al")
        XCTAssertNil(item.diffraction.pitchMM)
        // A ring the new standard does not list is refused before the centre or the standard moves (#927).
        let family = try await call("set_diffraction", ["standard": "Si", "family": 6, "centre_row": 10, "centre_column": 10])
        XCTAssertTrue(family.refused, "the standards list at most six rings")
        XCTAssertEqual(item.diffraction.standard.name, "Al", "a refused call keeps the standard")
        XCTAssertEqual(item.diffraction.centre?.row, 255, "a refused call keeps the centre")
        XCTAssertEqual(item.diffraction.centre?.column, 257)
        let noRing = try await call("set_diffraction", ["use_ring_centre": 1])
        XCTAssertTrue(noRing.refused, "no ring is fitted")
    }

    /// The methods record of the Au pattern (#818): refused before a ring or spot is measured, then the record and paragraph File >
    /// Export Methods Record… and Edit > Copy Methods Paragraph give, the ring fit's calibration among its steps, and the file's name
    /// left out on request. Mutation: the tool or the menu reading another record than `MethodsRecordExport.record(of:)`, the
    /// availability ignoring the readout, or leave_out_file_names not reaching the record - red.
    @MainActor func testTheMethodsRecordOfTheAuPattern() async throws {
        let (state, item) = try await diffractionWindow()
        XCTAssertFalse(MethodsRecordExport.isAvailable(in: state), "nothing measured yet")
        let none = try await call("get_methods_record")
        XCTAssertTrue(none.refused, "no result to record")

        let calibrate = try await call("set_diffraction", ["inner": 29, "outer": 37, "family": 0, "calibrate": true])
        XCTAssertFalse(calibrate.refused, calibrate.text)
        try await waitUntil("the ring fit to land", seconds: 60) { !item.diffraction.isFitting && !item.diffraction.rings.isEmpty }
        XCTAssertTrue(MethodsRecordExport.isAvailable(in: state))

        let answer = try json(try await call("get_methods_record").text)
        let record = try MethodsRecord.decode(try XCTUnwrap(answer["record"] as? String))
        XCTAssertEqual(record, MethodsRecordExport.record(of: state), "the menu's record")
        XCTAssertEqual(record.room, "diffraction")
        XCTAssertEqual(record.exportKind, "methods-record")
        XCTAssertEqual(record.steps.map(\.name), ["Centring", "Calibration", "Indexing"])
        XCTAssertTrue(record.steps[1].method.hasPrefix("a ring fit to the Au {"), record.steps[1].method)
        let name = DemoDocuments.patternURL.lastPathComponent
        XCTAssertEqual(record.sources.first?.fileName, name)
        let paragraph = try XCTUnwrap(answer["paragraph"] as? String)
        XCTAssertEqual(paragraph, record.paragraph)
        XCTAssertTrue(paragraph.contains("Calibration used a ring fit to the Au {"), paragraph)
        // The paragraph in the CI log, for reading it as a methods section.
        print("MACEM_METHODS_PARAGRAPH \(paragraph)")

        let copied = CopiedText()
        await MethodsRecordExport.copyParagraph(appState: state, writer: copied)?.value
        XCTAssertEqual(copied.texts, [paragraph], "Copy Methods Paragraph copies the same paragraph")

        let anonymous = try json(try await call("get_methods_record", ["leave_out_file_names": true]).text)
        let left = try MethodsRecord.decode(try XCTUnwrap(anonymous["record"] as? String))
        XCTAssertEqual(left.sources.first?.fileName, "source 1")
        XCTAssertFalse(try XCTUnwrap(anonymous["paragraph"] as? String).contains(name))
    }

    /// get_diffraction_figure (#823) answers the figure Copy Figure copies, as an image, once the pattern's display is built.
    /// Mutation: the tool missing, or answering text - red.
    @MainActor func testTheFigureToolDrawsThePattern() async throws {
        let (_, item) = try await diffractionWindow()
        let image = try XCTUnwrap(item.session.image)
        await item.diffractionView.show(image: image, analysis: item.diffraction)
        let figure = try await call("get_diffraction_figure")
        XCTAssertFalse(figure.refused, figure.text)
        XCTAssertTrue(figure.image, "the figure is a picture")
    }
}

/// A pasteboard that keeps what it is given.
@MainActor private final class CopiedText: PaneTextWriter {
    var texts: [String] = []
    func write(_ text: String) { texts.append(text) }
}
