//
//  SimulationSessionFileTests.swift
//  A Simulation document saves to and reopens from its session file (#908): the file holds the phase's frozen copy and the settings
//  (voltage, camera length, k_max, zone axis and turn or the orientation set by hand, the Simulation section's switches and excitation
//  error), and an Open of it makes a new Simulation document with the same pattern and spot list, whose ⌘S writes the same file. A
//  file from a newer build, or one that cannot be read, is refused by name and opens nothing. Red before: there was no session file
//  for a simulation, and an Open of one was refused as an unknown format.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class SimulationSessionFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SimulationSessionFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A new simulation showing Au (the standard's structure as a library phase).
    @MainActor private func simulation(in state: AppState) async throws -> (OpenItem, CalibratedImage) {
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        analysis.setCrystal(.phase(PhaseCrystal(id: "test-au", name: "Au", structure: analysis.standard.structure)))
        return (item, image)
    }

    @MainActor private func reopened(_ url: URL, in state: AppState, besides item: OpenItem) async throws -> OpenItem {
        let before = Set(state.openItems.items.map(\.id))
        await state.open(urls: [url])?.value
        let new = state.openItems.items.filter { !before.contains($0.id) }
        XCTAssertEqual(new.count, 1, "one new document")
        let document = try XCTUnwrap(new.first)
        XCTAssertTrue(DemoDocuments.isSimulation(document.url))
        XCTAssertNotEqual(document.id, item.id)
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        return document
    }

    /// Mutation: a setting left out of the file or not applied (voltage, camera length, k_max, zone axis, turn, labels, double
    /// diffraction, excitation error), the phase not frozen, the reopened document not saving to its file.
    @MainActor func testASavedSimulationReopensWithTheSamePatternAndSpotList() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (item, image) = try await simulation(in: state)
        let analysis = item.diffraction
        analysis.typedBeamKV = 300
        XCTAssertTrue(analysis.setCameraLength(mm: 800))
        analysis.setKMax(2.5)
        XCTAssertTrue(analysis.setExcitationError(0.03))
        analysis.simulation.showsLabels = false
        analysis.simulation.doubleDiffraction = true
        analysis.setZoneAxis(SIMD3(1, 1, 0))
        analysis.setTurn(degrees: 15)
        let rows = item.simulatedSpotRows(image: image)
        XCTAssertFalse(rows.isEmpty)

        let url = folder.appendingPathComponent("Au 110.\(SimulationSessionFile.fileExtension)")
        try SimulationSessions.write(item, to: url)
        XCTAssertEqual(SimulationSessions.file(of: item), url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"kind\" : \"simulation\""), text)

        let document = try await reopened(url, in: state, besides: item)
        let again = document.diffraction
        XCTAssertEqual(again.crystal.phaseID, "test-au")
        XCTAssertEqual(again.crystal.name, "Au")
        XCTAssertEqual(again.crystal.structure.fingerprint, analysis.crystal.structure.fingerprint, "the frozen copy")
        XCTAssertEqual(again.typedBeamKV, 300)
        XCTAssertEqual(again.cameraLengthMM, 800)
        XCTAssertEqual(again.kMax, 2.5)
        XCTAssertEqual(again.simulation.excitationError, 0.03)
        XCTAssertFalse(again.simulation.showsLabels)
        XCTAssertTrue(again.simulation.doubleDiffraction)
        XCTAssertEqual(again.simulation.zoneAxis, SIMD3(1, 1, 0))
        XCTAssertEqual(again.simulation.inPlaneDegrees, 15)
        XCTAssertTrue(again.simulation.isShown)

        let reimage = try XCTUnwrap(document.session.image)
        let same = document.simulatedSpotRows(image: reimage)
        XCTAssertEqual(same.map(\.hkl), rows.map(\.hkl), "the same spot list")
        for (a, b) in zip(same, rows) {
            XCTAssertEqual(a.radiusPx, b.radiusPx, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(a.radiusMM), try XCTUnwrap(b.radiusMM), accuracy: 1e-9)
        }
        XCTAssertEqual(SimulationSessions.file(of: document), url, "⌘S writes the file it came from")
        XCTAssertEqual(SimulationSessions.saveTitle(for: document), "Save Simulation", "no panel: no ellipsis")
    }

    /// Mutation: the orientation set by hand not saved, or the typed zone axis drawn in its place on reopening.
    @MainActor func testAnOrientationSetByHandComesBack() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (item, _) = try await simulation(in: state)
        XCTAssertTrue(item.diffraction.tilt(down: 2, across: 1))
        let drawn = try XCTUnwrap(item.diffraction.drawnOrientation)
        let url = folder.appendingPathComponent("tilted.emsim")
        try SimulationSessions.write(item, to: url)

        let document = try await reopened(url, in: state, besides: item)
        XCTAssertEqual(document.diffraction.drawnOrientation, drawn)
        XCTAssertTrue(document.diffraction.isTurnedByHand)
    }

    /// Mutation: a newer file read as this version's, a damaged one opened at defaults, the refusal not naming the file, a refused
    /// file leaving a document behind.
    @MainActor func testANewerOrUnreadableFileIsRefusedByName() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let newer = folder.appendingPathComponent("from the future.emsim")
        try Data(#"{"kind": "simulation", "schema": 2, "minReaderSchema": 2}"#.utf8).write(to: newer)
        let damaged = folder.appendingPathComponent("damaged.emsim")
        try Data("not a simulation".utf8).write(to: damaged)

        XCTAssertThrowsError(try SimulationSessionFile.read(try Data(contentsOf: newer), name: "from the future.emsim")) { error in
            XCTAssertEqual(error as? SimulationSessionFile.Refusal, .newer(name: "from the future.emsim", reader: 2))
        }

        await state.open(urls: [newer])?.value
        let first = try XCTUnwrap(state.errorMessage)
        XCTAssertTrue(first.contains("from the future.emsim") && first.contains("newer version"), first)
        state.errorMessage = nil

        await state.open(urls: [damaged])?.value
        let second = try XCTUnwrap(state.errorMessage)
        XCTAssertTrue(second.contains("damaged.emsim") && second.contains("cannot be opened as a simulation"), second)
        XCTAssertTrue(state.openItems.items.isEmpty, "nothing opened")

        // A zone axis of zeros, or a camera length that is no number, is refused too.
        var file = SimulationSessionFile(phase: nil, beamKV: 200, cameraLengthMM: 500, kMax: 3, zoneAxis: SIMD3(0, 0, 0), turnDegrees: 0,
                                         orientation: nil, showsLabels: true, doubleDiffraction: false, excitationError: 0.02)
        XCTAssertThrowsError(try SimulationSessionFile.read(try file.encoded(), name: "zero.emsim"))
        file.zoneAxis = [0, 0, 1]
        file.cameraLengthMM = -1
        XCTAssertThrowsError(try SimulationSessionFile.read(try file.encoded(), name: "negative.emsim"))
        file.cameraLengthMM = 500
        XCTAssertEqual(try SimulationSessionFile.read(try file.encoded(), name: "fine.emsim"), file)
    }
}
