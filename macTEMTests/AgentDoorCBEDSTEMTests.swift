//
//  AgentDoorCBEDSTEMTests.swift
//  The agent door's tools for release 2.6's simulations (#918, plan row MA17), through a real door over MCP, on a document File >
//  New Simulation opens: set_dynamical switches the Intensities to Dynamical and runs the multislice as the section does, and
//  read_dynamical reads the beams and the method line; set_cbed refuses a value the section does not keep (changing nothing),
//  run_cbed refuses a Parallel beam and runs Show CBED Pattern, read_cbed reads the stored patterns; measure_thickness and
//  use_measured_thickness refuse with the section's sentences on a pattern with no discs; set_stem refuses a preset with a band
//  and a band past the angles collected, run_stem scans a small Si [1 1 0] slab to the end, read_stem reads the band, the profile
//  and the method line, and a complete image is not run again. Red before: the door had none of these tools. The numbers are the
//  kits' (DynamicalSpotsTests, CBEDPatternTests, CBEDThicknessTests, STEMImageTests); the door adds none of its own.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorCBEDSTEMTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-cbed-stem-tests-\(UUID().uuidString)"
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

    @MainActor private func read(_ tool: String) async throws -> [String: Any] {
        let answer = try await call(tool)
        XCTAssertFalse(answer.refused, answer.text)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(answer.text.utf8)) as? [String: Any], answer.text)
    }

    /// The walk an agent makes through the four sections. Mutation: a tool missing; set_dynamical not running the multislice;
    /// set_cbed applying the good values of a refused call; run_cbed past a Parallel beam; run_stem running a complete image again;
    /// a band past the collected angles kept.
    @MainActor func testAnAgentDrivesDynamicalCBEDThicknessAndSTEM() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        let before = try await call("read_stem")
        XCTAssertTrue(before.refused, "no Simulation document yet")

        await state.newSimulation()?.value
        try await waitUntil("the Simulation document to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSimulation($0.url) } ?? false
        }
        let simulation = try XCTUnwrap(state.openItems.selected)
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        let set = try await call("set_simulation", ["zone_axis": "1 1 0", "thickness_nm": 0.5, "voltage_kv": 200])
        XCTAssertFalse(set.refused, set.text)

        // Dynamical (MA8).
        let early = try await call("set_dynamical", ["thickness_index": 0])
        XCTAssertTrue(early.refused, "the index needs Dynamical on")
        let dynamical = try await call("set_dynamical", ["dynamical": true])
        XCTAssertFalse(dynamical.refused, dynamical.text)
        try await waitUntil("the exit waves", seconds: 120) {
            simulation.multislice.exitWavesAreCurrent(crystal: simulation.diffraction.simulatedPhase, zoneAxis: SIMD3(1, 1, 0))
        }
        var now = try await read("read_dynamical")
        XCTAssertEqual(now["dynamical"] as? Bool, true)
        XCTAssertTrue((now["method"] as? String)?.hasPrefix("Dynamical · Si [1 1 0]") == true, "\(now)")
        let beams = try XCTUnwrap(now["beams"] as? [[String: Any]], "\(now)")
        XCTAssertFalse(beams.isEmpty)
        let count = try XCTUnwrap(now["thicknesses_nm"] as? [Double], "\(now)").count
        let past = try await call("set_dynamical", ["thickness_index": count])
        XCTAssertTrue(past.refused, past.text)

        // CBED (MA9).
        let parallel = try await call("run_cbed")
        XCTAssertTrue(parallel.refused, "the beam is Parallel")
        // In every parameter's range, but a largest thickness below the 2 nm step: the section's own check refuses it.
        let mixed = try await call("set_cbed", ["beam": "Convergent", "angular_step_mrad": 2, "largest_thickness_nm": 1])
        XCTAssertTrue(mixed.refused, mixed.text)
        XCTAssertFalse(simulation.cbed.isConvergent, "a refused call changes nothing")
        XCTAssertTrue(mixed.text.hasPrefix("Those settings are not kept"), mixed.text)
        XCTAssertEqual(simulation.cbed.settings.angularStepMrad, CBEDSettings().angularStepMrad)
        let cbed = try await call("set_cbed", ["beam": "Convergent", "largest_thickness_nm": 2, "angular_step_mrad": 2, "edge_mrad": 20,
                                               "fit_discs": true])
        XCTAssertFalse(cbed.refused, cbed.text)
        now = try await read("read_cbed")
        XCTAssertEqual(now["beam"] as? String, "Convergent")
        XCTAssertNotNil(now["plan"] as? String, "\(now)")
        XCTAssertNotNil(now["semiangle_mrad"] as? Double, "\(now)")
        let ran = try await call("run_cbed")
        XCTAssertFalse(ran.refused, ran.text)
        try await waitUntil("the CBED patterns", seconds: 180) { simulation.cbed.pattern != nil && !simulation.cbed.isComputing }
        now = try await read("read_cbed")
        XCTAssertEqual(now["pattern_shown"] as? Bool, true)
        XCTAssertTrue((now["method"] as? String)?.isEmpty == false, "\(now)")
        XCTAssertFalse(try XCTUnwrap(now["thicknesses_nm"] as? [Double], "\(now)").isEmpty)

        // Two-beam thickness (MA15) on the Simulation document's own spot pattern: no discs, so the section's refusal.
        state.openItems.select(simulation.id)
        let measured = try await call("measure_thickness")
        if case .failure(let refusal) = simulation.thicknessInputs {
            XCTAssertTrue(measured.refused)
            XCTAssertEqual(measured.text, refusal.sentence)
        }
        try await waitUntil("the measurement to end", seconds: 60) { !simulation.thickness.isMeasuring }
        let use = try await call("use_measured_thickness")
        XCTAssertTrue(use.refused, use.text)
        now = try await read("read_thickness")
        XCTAssertEqual(now["use_in_simulation"] as? Bool, false)

        // STEM (MA10).
        let presetBand = try await call("set_stem", ["detector": "HAADF", "inner_mrad": 10])
        XCTAssertTrue(presetBand.refused, presetBand.text)
        let pastCollected = try await call("set_stem", ["collect_mrad": 100, "detector": "Custom", "inner_mrad": 50, "outer_mrad": 300])
        XCTAssertTrue(pastCollected.refused, pastCollected.text)
        XCTAssertEqual(simulation.stem.settings.collectMrad, STEMSettings().collectMrad, "a refused call changes nothing")
        let stem = try await call("set_stem", ["semiangle_mrad": 20, "scan_step_angstrom": 1, "collect_mrad": 100, "defocus_nm": 0,
                                               "detector": "Custom", "inner_mrad": 0, "outer_mrad": 20])
        XCTAssertFalse(stem.refused, stem.text)
        XCTAssertNil(simulation.stem.detector, "0 to 20 at 20 mrad is no preset: Custom")
        let notRunning = try await call("stop_stem")
        XCTAssertTrue(notRunning.refused)
        let scan = try await call("run_stem")
        XCTAssertFalse(scan.refused, scan.text)
        XCTAssertTrue(scan.text.contains("Simulate"), scan.text)
        try await waitUntil("the STEM image", seconds: 300) { simulation.stem.scan?.isComplete == true && !simulation.stem.isRunning }
        now = try await read("read_stem")
        XCTAssertEqual(now["complete"] as? Bool, true, "\(now)")
        XCTAssertEqual(now["image_shown"] as? Bool, true)
        XCTAssertEqual(now["static_lattice"] as? Bool, true)
        XCTAssertTrue((now["method"] as? String)?.hasPrefix("STEM · Si [1 1 0] · 200 kV · 20 mrad · defocus 0 nm") == true, "\(now)")
        XCTAssertNotNil(now["radial_profile"] as? [String: Any])
        let again = try await call("run_stem")
        XCTAssertTrue(again.refused, "a complete image is not run again")
    }
}
