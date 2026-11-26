//
//  DemoDataTests.swift
//  App Review needs a way to try macTEM without a microscope file (macTEM#105). Help > Open Demo Data opens the generated
//  documents; each must land in its room with data there.
//

import DiffractoCore
import ShellPhaseLibrary
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class DemoDataTests: XCTestCase {
    @MainActor private var saved: PhaseLibrary!

    /// The silicon simulation adds its CIF to the phase library: a library of its own in a temporary folder, never this Mac's.
    @MainActor override func setUp() async throws {
        saved = PhaseServices.library
        PhaseServices.library = PhaseLibrary(store: PhaseLibraryStore(folder: FileManager.default.temporaryDirectory
            .appending(path: "DemoDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)))
    }

    @MainActor override func tearDown() async throws {
        PhaseServices.library = saved
    }

    /// Mutation: point any case's `openDemo` at the wrong document, or drop the room switch - red.
    @MainActor func testEveryDemoOpensInItsRoomWithDataThere() async throws {
        for demo in DemoDocument.allCases {
            let state = AppState(launch: LaunchOptions(arguments: []))
            await state.openDemo(demo)?.value
            XCTAssertEqual(state.navigation.workspaceArea, demo.room, demo.title)
            XCTAssertNil(state.roomUnavailableReason(demo.room), "\(demo.title): \(demo.room) has no data")
        }
    }

    /// The four generated documents, one per room, then the SEM ones: the generated SEM image (the Image room again, as a file with an
    /// SEM header, #355), the shipped SEM-EDS spectrum (the EDS room again, as a real file), the shipped nickel EBSD scan (Patterns)
    /// and the shipped two-phase orientation map (Maps).
    func testTheMenuOffersOneEntryPerRoomWithData() {
        XCTAssertEqual(DemoDocument.allCases.map(\.room), [.image, .diffraction, .edx, .eels, .image, .edx, .patterns, .maps,
                                                           .diffraction, .diffraction])
        XCTAssertEqual(Set(DemoDocument.allCases.map(\.title)).count, DemoDocument.allCases.count)
        XCTAssertEqual(DemoDocument.semImage.title, "SEM Image (generated)")
    }

    /// #804: the recorded spot pattern opens as the selected file in the Diffraction room, and the silicon simulation is a Simulation
    /// document that shows the shipped CIF as a library phase, with no Add Phase sheet and no empty state, so the crystal and powder
    /// panes draw Si, not the standard. Mutation: the simulation keeps the room's standard, or sets the CIF as a crystal that is no
    /// library phase (it opened in its empty state, drawing Au, before), the pattern is not selected - red.
    @MainActor func testTheSpotPatternAndTheSiliconSimulation() async throws {
        let pattern = AppState(launch: LaunchOptions(arguments: []))
        await pattern.openDemo(.spotPattern)?.value
        XCTAssertEqual(pattern.openItems.selected?.url.lastPathComponent, DemoDocuments.Shipped.nanowirePattern.fileName)
        XCTAssertEqual(pattern.navigation.workspaceArea, .diffraction)

        let simulation = AppState(launch: LaunchOptions(arguments: []))
        await simulation.openDemo(.siliconSimulation)?.value
        let item = try XCTUnwrap(simulation.openItems.selected)
        XCTAssertTrue(DemoDocuments.isSimulation(item.url))
        XCTAssertEqual(item.diffraction.crystal.structure.sites.count, 8)
        XCTAssertEqual(item.diffraction.crystal.structure.spaceGroupNumber, 227)
        let phaseID = try XCTUnwrap(item.diffraction.crystal.phaseID, "the crystal is a library phase, not a standard")
        XCTAssertTrue(phaseID.hasPrefix("cif-"), "the shipped CIF, added as Open CIF… adds one")
        XCTAssertEqual(PhaseServices.library.phases.map(\.id), [phaseID])
        XCTAssertFalse(SimulationEmptyState.isShown(for: item))
        XCTAssertFalse(item.diffractionView.isAddingPhase, "no Add Phase sheet over the demo")
        XCTAssertEqual(DiffractionPowderSection.table(of: item, openItems: simulation.openItems).phases.count, 1)
        XCTAssertEqual(DiffractionPowderSection.table(of: item, openItems: simulation.openItems).phases.first?.structure.spaceGroupNumber, 227)
        XCTAssertEqual(simulation.navigation.workspaceArea, .diffraction)
    }

    /// The generated SEM image goes through the app's own Open as a file from disk, so the Image room has it with the file's SEM
    /// header: the databar rows the room crops. Red before #355: the menu had no such entry (the file opened by a launch flag only).
    @MainActor func testTheSEMImageOpensAsAFileWithItsSEMHeader() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.semImage)?.value
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        XCTAssertEqual(state.openItems.selected?.url.lastPathComponent, "Demo SEM image.tif")
        XCTAssertEqual(state.imageSession.image?.height, DemoDocuments.semScanRows, "the picture is the scan, its databar cropped")
        XCTAssertEqual(state.imageSession.sem?.databarRows, DemoDocuments.semDatabarRows, "the file's own SEM header came with it")
    }
}
