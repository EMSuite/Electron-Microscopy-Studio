//
//  DemoDataTests.swift
//  App Review needs a way to try macTEM without a microscope file (macTEM#105). Help > Open Demo Data opens the generated
//  documents; each must land in its room with data there.
//

import DiffractoCore
import ShellEDXModel
import ShellPhaseLibrary
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class DemoDataTests: XCTestCase {
    @MainActor private var saved: PhaseLibrary!

    /// A phase library of its own in a temporary folder, never this Mac's: the silicon simulation must leave it empty.
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

    /// One word on screen: the room is EDS, so the menu, the demo's file name (the toolbar's centre display) and the names its exports
    /// carry say EDS too. Red before: the menu said "EDX Spectrum Image" and the document "Demo EDX".
    @MainActor func testTheDemoSaysEDSNotEDX() async throws {
        XCTAssertEqual(DemoDocument.edx.title, "EDS Spectrum Image")
        for demo in DemoDocument.allCases { XCTAssertFalse(demo.title.contains("EDX"), demo.title) }
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.edx)?.value
        await state.edx.settled()
        XCTAssertEqual(state.edx.fileName, "Demo EDS")
        XCTAssertEqual(try DemoDocuments.spectrumFile().lastPathComponent, "Demo EDS spectrum.msa")
        XCTAssertFalse(EDXRoomHost.macTEM.roomSource.contains("EDX"), EDXRoomHost.macTEM.roomSource)
        XCTAssertFalse(EDXRoomHost.macTEM.regionsTitle.contains("EDX"), EDXRoomHost.macTEM.regionsTitle)
    }

    /// #804: the recorded spot pattern opens as the selected file in the Diffraction room, and the silicon simulation is a Simulation
    /// document whose simulated phase is the shipped CIF's, with no Add Phase sheet over it (#1111). Mutation: the simulation keeps the
    /// room's standard, the CIF is set as a loose crystal (no simulated phase), the pattern is not selected - red.
    @MainActor func testTheSpotPatternAndTheSiliconSimulation() async throws {
        let pattern = AppState(launch: LaunchOptions(arguments: []))
        await pattern.openDemo(.spotPattern)?.value
        XCTAssertEqual(pattern.openItems.selected?.url.lastPathComponent, DemoDocuments.Shipped.nanowirePattern.fileName)
        XCTAssertEqual(pattern.navigation.workspaceArea, .diffraction)

        let simulation = AppState(launch: LaunchOptions(arguments: []))
        await simulation.openDemo(.siliconSimulation)?.value
        let item = try XCTUnwrap(simulation.openItems.selected)
        XCTAssertTrue(DemoDocuments.isSimulation(item.url))
        let phase = try XCTUnwrap(item.diffraction.simulatedPhase, "the CIF is the simulated phase, not a loose crystal")
        XCTAssertEqual(phase.structure.sites.count, 8)
        XCTAssertEqual(phase.structure.spaceGroupNumber, 227)
        XCTAssertEqual(phase.phaseID?.hasPrefix("cif-"), true, "the crystal is the CIF's phase, not a standard")
        XCTAssertFalse(item.diffractionView.isAddingPhase, "no Add Phase sheet over the silicon pattern")
        XCTAssertFalse(SimulationEmptyState.isShown(for: item))
        XCTAssertEqual(item.diffraction.orientationLine, "\(phase.name) [001]", "the header names silicon, not Au")
        XCTAssertTrue(PhaseServices.library.phases.isEmpty, "the demo adds nothing to the person's phase library")
        XCTAssertEqual(DiffractionPowderSection.table(of: item, openItems: simulation.openItems).phases.count, 1)
        XCTAssertEqual(DiffractionPowderSection.table(of: item, openItems: simulation.openItems).phases.first?.structure.spaceGroupNumber, 227)
        XCTAssertEqual(simulation.navigation.workspaceArea, .diffraction)
    }

    /// #1111: a window that holds a document opens the silicon simulation in a tab of its own, whose state is not the one that asked; the
    /// demo's phase is held for the document and set by whichever state lands it. Red before: the phase was set on the asking window's
    /// selected item after the open, so the new tab kept no phase (the Add Phase sheet up, an Au cell beside it).
    @MainActor func testTheDemoPhaseLandsInTheTabThatOpensTheSimulation() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let crystal = DiffractionCrystal.phase(PhaseCrystal(id: "test-al", name: "Al", structure: al.structure))
        let document = AppState.nextSimulationURL()
        DemoSimulations.hold(crystal, for: document)
        let tab = AppState(launch: LaunchOptions(arguments: []))   // the new tab's own state
        await tab.open(urls: [document])?.value
        let item = try XCTUnwrap(tab.openItems.selected)
        XCTAssertEqual(item.url, document)
        XCTAssertEqual(item.diffraction.simulatedPhase, crystal)
        XCTAssertFalse(item.diffractionView.isAddingPhase)
        XCTAssertEqual(tab.navigation.workspaceArea, .diffraction)
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
