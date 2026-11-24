//
//  AgentDoorHRTEMTests.swift
//  The agent door's HRTEM tools (#899, plan row MA13), through a real door over MCP, on a document File > New Simulation opens
//  (#846's new_simulation is tested beside it): read_simulation reads the specimen's refusal before a phase and its summary after,
//  set_simulation refuses a phase the library does not hold and a call with one bad value changes nothing, sets the specimen,
//  defocus and frozen phonons through the sections' intents, run_simulation computes the static image and then Simulate, and
//  stop_run stops a frozen-phonon run keeping what it averaged. Red before: the door had none of these tools. The numbers are
//  SimulatoKit's (HRTEMImageTests, HRTEMThermalTests); the door adds none of its own.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class AgentDoorHRTEMTests: XCTestCase {
    @MainActor private var door: AgentDoor!
    @MainActor private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)
    @MainActor private var keep: [AppState] = []

    @MainActor override func setUp() async throws {
        defaultsSuite = "agent-door-hrtem-tests-\(UUID().uuidString)"
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

    @MainActor private func read() async throws -> [String: Any] {
        let answer = try await call("read_simulation")
        XCTAssertFalse(answer.refused, answer.text)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(answer.text.utf8)) as? [String: Any], answer.text)
    }

    /// The whole walk an agent makes: open, refuse, set, run static, run frozen phonons, stop. Mutation: a tool missing, the phase
    /// taken from outside the library, run_simulation not showing the image, stop_run not reaching the Image room's run.
    @MainActor func testAnAgentSimulatesSiliconStaticAndWithFrozenPhonons() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        keep.append(state)
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }
        let refusedBefore = try await call("read_simulation")
        XCTAssertTrue(refusedBefore.refused, "no Simulation document yet")

        await state.newSimulation()?.value
        try await waitUntil("the Simulation document to open", seconds: 30) {
            state.openItems.selected.map { DemoDocuments.isSimulation($0.url) } ?? false
        }
        let simulation = try XCTUnwrap(state.openItems.selected)
        let before = try await read()
        XCTAssertEqual(before["specimen_refusal"] as? String, SimulationSpecimen.Refusal.noPhase.sentence)
        let noPhase = try await call("set_simulation", ["frozen_phonons": true])
        XCTAssertTrue(noPhase.refused)
        XCTAssertEqual(noPhase.text, SimulationSpecimen.Refusal.noPhase.sentence)

        let unknown = try await call("set_simulation", ["phase": "no such phase \(UUID().uuidString)"])
        XCTAssertTrue(unknown.refused)
        XCTAssertTrue(unknown.text.contains("No phase"), unknown.text)

        // The phase as the library's Show gives it (the library is the person's, so the test does not write into it).
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        let set = try await call("set_simulation", ["zone_axis": "1 1 0", "thickness_nm": 0.5, "defocus_nm": 30])
        XCTAssertFalse(set.refused, set.text)
        // One bad value refuses the whole call: the good ones before it are not applied.
        let mixed = try await call("set_simulation", ["thickness_nm": 2, "cs_mm": 2, "sigma": "Si 0.1"])
        XCTAssertTrue(mixed.refused, mixed.text)
        var now = try await read()
        XCTAssertEqual(now["thickness_nm"] as? Double, 0.5, "\(now)")
        XCTAssertEqual(now["cs_mm"] as? Double, 1, "\(now)")
        XCTAssertEqual(now["zone_axis"] as? String, "[1 1 0]")
        XCTAssertEqual(now["defocus_nm"] as? Double, 30)
        XCTAssertNotNil(now["specimen"] as? String, "\(now)")
        let transfer = try XCTUnwrap(now["transfer"] as? [String: Any], "\(now)")
        XCTAssertNotNil(transfer["scherzer_defocus_nm"] as? Double)
        XCTAssertTrue((now["potential"] as? String)?.hasPrefix("Lobato") == true, "\(now)")

        let ran = try await call("run_simulation")
        XCTAssertFalse(ran.refused, ran.text)
        try await waitUntil("the exit waves", seconds: 120) {
            simulation.multislice.exitWavesAreCurrent(crystal: simulation.diffraction.simulatedPhase, zoneAxis: SIMD3(1, 1, 0))
        }
        now = try await read()
        XCTAssertEqual(now["image_shown"] as? Bool, true)
        XCTAssertTrue((now["method"] as? String)?.contains("static lattice") == true, "\(now)")

        let thermal = try await call("set_simulation", ["frozen_phonons": true])
        XCTAssertFalse(thermal.refused, thermal.text)
        let tuned = try await call("set_simulation", ["sigma": "Si 0.08", "configurations": 2])
        XCTAssertFalse(tuned.refused, tuned.text)
        let badSigma = try await call("set_simulation", ["sigma": "Si lots"])
        XCTAssertTrue(badSigma.refused)
        let simulate = try await call("run_simulation")
        XCTAssertFalse(simulate.refused, simulate.text)
        XCTAssertTrue(simulate.text.contains("Simulate"), simulate.text)
        try await waitUntil("two configurations", seconds: 120) { simulation.multislice.exitWaves?.configurations.count == 2 && !simulation.multislice.isSimulating }
        now = try await read()
        let phonons = try XCTUnwrap(now["frozen_phonons"] as? [String: Any], "\(now)")
        XCTAssertEqual(phonons["averaged"] as? Int, 2)
        XCTAssertNotNil(phonons["convergence_percent"] as? Double)
        XCTAssertNotNil(phonons["plan"] as? String)
        XCTAssertTrue((now["method"] as? String)?.contains("frozen phonons, 2 configurations, σ Si 0.08 Å") == true, "\(now)")

        let more = try await call("set_simulation", ["configurations": 20])
        XCTAssertFalse(more.refused, more.text)
        let resumed = try await call("run_simulation")
        XCTAssertTrue(resumed.text.contains("Continue"), resumed.text)
        try await waitUntil("the run to start", seconds: 30) { simulation.multislice.isSimulating || simulation.multislice.exitWaves?.configurations.count == 20 }
        if simulation.multislice.isSimulating {
            let stopped = try await call("stop_run")
            XCTAssertFalse(stopped.refused, stopped.text)
        }
        try await waitUntil("the run to end", seconds: 120) { !simulation.multislice.isSimulating }
        let averaged = simulation.multislice.exitWaves?.configurations.count ?? 0
        XCTAssertGreaterThanOrEqual(averaged, 2, "Stop keeps what was averaged")
        if averaged < 20 { XCTAssertTrue(simulation.multislice.canContinue(crystal: simulation.diffraction.simulatedPhase, zoneAxis: SIMD3(1, 1, 0))) }
    }
}
