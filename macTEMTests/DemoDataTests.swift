//
//  DemoDataTests.swift
//  App Review needs a way to try macTEM without a microscope file (macTEM#105). Help > Open Demo Data opens the generated
//  documents; each must land in its room with data there.
//

import DiffractoCore
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class DemoDataTests: XCTestCase {

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
    /// document whose crystal is the shipped CIF. Mutation: the simulation keeps the room's standard, the pattern is not selected - red.
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
        XCTAssertNotNil(item.diffraction.crystal.sha256, "the crystal is the CIF, not a standard")
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
