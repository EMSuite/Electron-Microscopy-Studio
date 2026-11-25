//
//  AgentDoorSimulationTests.swift
//  The agent door's Simulation tools (#846, plan row R8b), through a real door over MCP: new_simulation opens File > New
//  Simulation's document in the Diffraction room, and get_crystal_view reads the crystal pane beside it: the phase, the zone axis,
//  the orientation as the simulated spots' matrix (at [0 0 1] and no turn the kit's lab frame is the crystal's: the identity), the
//  scene (Au: 14 atoms, no bond), and the words for an empty pane. Red before: the door had neither tool.
//
//  The Microscope section, the Unit cell switch and the Export section (#846's last gaps): set_simulation sets the voltage and the
//  camera length the Diffraction room's Microscope section types, and read_simulation and get_spot_table read the Spots table with R
//  in mm at it; set_diffraction unit_cell flips the crystal pane's switch, refused while the pane is hidden; save_diffraction writes
//  the Spots CSV (the simulated spots) and the pattern's PNG into the Agent folder, refused where the section's button is off. Red
//  before: the coverage rows were gaps and none of these arguments or tools existed.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorSimulationTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-simulation-tests-\(UUID().uuidString)"
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
        MacTEMAgentDoor.folder.use(folder: nil)
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
        let content = (result["content"] as? [[String: Any]])?.first
        return (result["isError"] as? Bool ?? false, (content?["text"] as? String) ?? "")
    }

    @MainActor private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    @MainActor func testNewSimulationAndTheCrystalView() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }

        let opened = try await call("new_simulation")
        XCTAssertFalse(opened.refused, opened.text)
        XCTAssertEqual(try json(opened.text)["opens_in_new_window"] as? Bool, false, "an empty window takes the simulation itself")
        // The image loads before the open lands the simulation in its room (`landSimulation`, after `settled()`): wait for both.
        try await waitUntil("the simulation to open", seconds: 30) {
            state.openItems.selected?.session.image != nil && state.navigation.workspaceArea == .diffraction
        }
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)

        let view = try await call("get_crystal_view")
        XCTAssertFalse(view.refused, view.text)
        let answer = try json(view.text)
        XCTAssertEqual(answer["shown"] as? Bool, true)
        XCTAssertEqual(answer["phase"] as? String, "Au")
        XCTAssertEqual(answer["place"] as? String, "Au, zone axis [001]")
        XCTAssertEqual(answer["shows_unit_cell"] as? Bool, true)
        let rows = try XCTUnwrap(answer["orientation"] as? [[Double]])
        for i in 0..<3 { for j in 0..<3 { XCTAssertEqual(rows[i][j], i == j ? 1 : 0, accuracy: 1e-12, "\(rows)") } }
        let crystal = try XCTUnwrap(answer["crystal"] as? [String: Any])
        XCTAssertEqual(crystal["atoms"] as? Int, 14)

        // The pane follows the spots: another zone axis is the answer's at once.
        let item = try XCTUnwrap(state.openItems.selected)
        item.diffraction.setZoneAxis(SIMD3(1, 1, 0))
        let turned = try await call("get_crystal_view")
        XCTAssertEqual(try json(turned.text)["place"] as? String, "Au, zone axis [110]")

        // Spots off: the pane is empty, said in words.
        item.diffraction.simulation.isShown = false
        let empty = try await call("get_crystal_view")
        XCTAssertTrue(empty.refused)
        XCTAssertTrue(empty.text.contains("crystal pane is empty"), empty.text)
    }

    /// Mutation: camera_length_mm not set through `setCameraLength`, the voltage not typed into the document, the Spots rows not the
    /// simulated ones, unit_cell kept while the pane is hidden, save_diffraction writing the Index spots for a Simulation document or
    /// writing a file while the button is off, or any of the five rows still a gap - red.
    @MainActor func testTheMicroscopeSectionTheUnitCellSwitchAndTheExportsReachTheDoor() async throws {
        for control in ["diffraction.microscope.voltage", "diffraction.microscope.cameraLength"] {
            XCTAssertEqual(AgentDoorCoverage.controls[control], .tool("set_simulation"), control)
        }
        XCTAssertEqual(AgentDoorCoverage.controls["diffraction.crystal.unitCell"], .tool("set_diffraction"))
        for control in ["diffraction.export", "diffraction.export.spots"] {
            XCTAssertEqual(AgentDoorCoverage.controls[control], .tool("save_diffraction"), control)
        }

        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        let opened = try await call("new_simulation")
        XCTAssertFalse(opened.refused, opened.text)
        try await waitUntil("the simulation to open", seconds: 30) {
            state.openItems.selected?.session.image != nil && state.navigation.workspaceArea == .diffraction
        }
        let item = try XCTUnwrap(state.openItems.selected)
        let analysis = item.diffraction

        // The Microscope section: a value out of range is refused whole, the rest of the call with it.
        let kV = analysis.typedBeamKV
        let wrong = try await call("set_simulation", ["voltage_kv": 300, "camera_length_mm": 0.5])
        XCTAssertTrue(wrong.refused, wrong.text)
        XCTAssertEqual(analysis.typedBeamKV, kV, "a refused call changes nothing")
        XCTAssertEqual(analysis.cameraLengthMM, DiffractionAnalysis.defaultCameraLengthMM)

        let before = try await call("get_spot_table")
        var table = try json(before.text)
        let rows = try XCTUnwrap(table["rows"] as? [[String: Any]], "\(table)")
        XCTAssertFalse(rows.isEmpty, "a Simulation document's table lists its simulated spots")
        let first = try XCTUnwrap(rows.first?["r_mm"] as? Double, "\(rows)")

        let set = try await call("set_simulation", ["voltage_kv": 300, "camera_length_mm": 1000])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(analysis.typedBeamKV, 300, "the document's voltage, as the Microscope section types it")
        XCTAssertEqual(analysis.cameraLengthMM, 1000)
        let simulationRead = try await call("read_simulation")
        let read = try json(simulationRead.text)
        XCTAssertEqual(read["camera_length_mm"] as? Double, 1000)
        XCTAssertEqual(read["voltage_kv"] as? Double ?? 0, 300, accuracy: 1e-9)
        let near = try XCTUnwrap(read["nearest_zone_axis"] as? [String: Any], "\(read)")
        XCTAssertEqual(near["zone_axis"] as? [Int], [0, 0, 1])
        XCTAssertEqual(near["degrees_off"] as? Double ?? 1, 0, accuracy: 1e-6)
        let spots = try XCTUnwrap(read["spots"] as? [[String: Any]], "\(read)")
        let spotTable = try await call("get_spot_table")
        table = try json(spotTable.text)
        let after = try XCTUnwrap(table["rows"] as? [[String: Any]])
        XCTAssertEqual(spots.count, after.count, "read_simulation and get_spot_table read the one Spots table")
        // R in mm = λ L |g|: twice L at a shorter λ (300 kV against 200 kV), as the table computes it.
        let image = try XCTUnwrap(item.session.image)
        let expected = try XCTUnwrap(analysis.simulatedSpotRows(image: image).first?.radiusMM)
        XCTAssertEqual(try XCTUnwrap(spots.first?["r_mm"] as? Double), expected, accuracy: expected * 1e-9)
        XCTAssertNotEqual(expected, first)

        // The Unit cell switch, and off limits while the pane is hidden.
        let off = try await call("set_diffraction", ["unit_cell": false])
        XCTAssertFalse(off.refused, off.text)
        XCTAssertFalse(item.diffractionView.showsUnitCell)
        let pane = try await call("get_crystal_view")
        XCTAssertEqual(try json(pane.text)["shows_unit_cell"] as? Bool, false)
        item.diffractionView.showsCrystal = false
        let log = item.diffractionView.useLog
        let hidden = try await call("set_diffraction", ["unit_cell": true, "log": !log])
        XCTAssertTrue(hidden.refused, hidden.text)
        XCTAssertFalse(item.diffractionView.showsUnitCell)
        XCTAssertEqual(item.diffractionView.useLog, log, "a refused call changes nothing")
        item.diffractionView.showsCrystal = true

        // The Export section into the Agent folder.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        MacTEMAgentDoor.folder.use(folder: root)
        let csv = try await call("save_diffraction", ["which": "spots_csv", "file": "spots.csv"])
        XCTAssertFalse(csv.refused, csv.text)
        XCTAssertEqual(try json(csv.text)["written"] as? String, "spots.csv")
        let written = try String(contentsOf: root.appendingPathComponent("spots.csv"), encoding: .utf8)
        let csvAnswer = try await call("get_spot_table", ["csv": true])
        let shown = try XCTUnwrap(try json(csvAnswer.text)["csv"] as? String)
        XCTAssertEqual(written, shown, "the file the section's button writes, and get_spot_table's csv")
        XCTAssertTrue(written.contains("# simulation: "), written)
        let readout = try await call("save_diffraction", ["which": "readout_csv", "file": "readout.csv"])
        XCTAssertTrue(readout.refused, "no rings or spots: the button is off")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("readout.csv").path))
        let outside = try await call("save_diffraction", ["which": "spots_csv", "file": "../outside.csv"])
        XCTAssertTrue(outside.refused, outside.text)
        await item.diffractionView.show(image: image, generation: item.session.generation, analysis: analysis)
        let png = try await call("save_diffraction", ["which": "png", "file": "pattern.png"])
        XCTAssertFalse(png.refused, png.text)
        let bytes = try Data(contentsOf: root.appendingPathComponent("pattern.png"))
        XCTAssertEqual(Array(bytes.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "a PNG")
    }
}
