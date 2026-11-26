//
//  SimulationEmptyStateTests.swift
//  File > New Simulation opens its document with the Add Phase sheet in front (#788), and Cancel there leaves an empty state on the
//  pattern with the one button Add Phase… (#907). The sheet is the room's, not the Phases section's, so it comes up whether or not
//  the inspector is shown. Red before: the document opened with no sheet, and with no phase it drew the calibration standard's spots
//  and listed them as if they were the simulation's.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class SimulationEmptyStateTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Mutation: the sheet not set up on landing, set up on a measured pattern, or set up again on a document that holds a phase.
    @MainActor func testNewSimulationOpensWithTheAddPhaseSheetInFront() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertTrue(DemoDocuments.isSimulation(item.url))
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        XCTAssertTrue(item.diffractionView.isAddingPhase, "the Add Phase sheet is in front")
        XCTAssertTrue(SimulationEmptyState.isShown(for: item), "no phase yet")

        // A document that already shows a phase lands without the sheet.
        item.diffractionView.isAddingPhase = false
        item.diffraction.setCrystal(.phase(PhaseCrystal(id: "test-au", name: "Au", structure: item.diffraction.standard.structure)))
        state.landSimulation([(id: item.id, url: item.url)])
        XCTAssertFalse(item.diffractionView.isAddingPhase)

        // A measured pattern never opens with it, nor shows the empty state.
        await state.open(urls: [DemoDocuments.patternURL])?.value
        let pattern = try XCTUnwrap(state.openItems.items.first { $0.url == DemoDocuments.patternURL })
        XCTAssertFalse(pattern.diffractionView.isAddingPhase)
        XCTAssertFalse(SimulationEmptyState.isShown(for: pattern))
    }

    /// Mutation: Cancel leaving the sheet up or the standard's spots listed; Add Phase… not bringing the sheet back; a shown phase
    /// keeping the empty state.
    @MainActor func testCancelLeavesTheEmptyStateWithTheOneButton() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        let view = item.diffractionView
        item.diffraction.bind(image)

        SimulationEmptyState.cancel(view)
        XCTAssertFalse(view.isAddingPhase)
        XCTAssertTrue(SimulationEmptyState.isShown(for: item), "Cancel leaves the empty state")
        XCTAssertFalse(item.simulatedSpotRows(image: image).isEmpty, "the owner still simulates the standard (the door reads it)")
        XCTAssertEqual(SimulationEmptyState.spotRows(of: item, image: image).count, 0, "the Spots table lists nothing")

        SimulationEmptyState.addPhase(view)
        XCTAssertTrue(view.isAddingPhase, "Add Phase… brings the sheet back")

        item.diffraction.setCrystal(.phase(PhaseCrystal(id: "test-au", name: "Au", structure: item.diffraction.standard.structure)))
        XCTAssertFalse(SimulationEmptyState.isShown(for: item), "a shown phase ends the empty state")
        XCTAssertFalse(SimulationEmptyState.spotRows(of: item, image: image).isEmpty)

        // The empty state holds one sentence and one button, Add Phase…; the room holds the sheet, and the Phases section's button
        // raises the same one.
        let file = try Self.source("macTEM/UI/DiffractionAddPhase.swift")
        let emptyView = try XCTUnwrap(file.components(separatedBy: "struct SimulationEmptyStateView").last?
            .components(separatedBy: "struct DiffractionAddPhaseSheet").first)
        XCTAssertEqual(emptyView.components(separatedBy: "Button(").count - 1, 1, "one button")
        XCTAssertTrue(emptyView.contains("Button(\"Add Phase…\") { SimulationEmptyState.addPhase(view) }"))
        let room = try Self.source("macTEM/UI/DiffractionRoom.swift")
        XCTAssertTrue(room.contains(".modifier(DiffractionAddPhaseSheet(item: item))"))
        XCTAssertTrue(room.contains("if SimulationEmptyState.isShown(for: item) { SimulationEmptyStateView(view: view) }"))
        let inspector = try Self.source("macTEM/UI/DiffractionRoomInspector.swift")
        XCTAssertTrue(inspector.contains("Button(\"Add Phase…\") { SimulationEmptyState.addPhase(item.diffractionView) }"))
        XCTAssertFalse(inspector.contains("AddPhaseSheet("), "one sheet, the room's")
    }

    /// The Powder Pattern pane, its Peaks table and its exports drew the calibration standard (Au) while the document showed no phase,
    /// beside a library that held only Si (stabilization walk). Mutation: the table built from the standard in the empty state; the
    /// panes or the header not asking the empty state; the door's powder_pattern answering with Au.
    @MainActor func testNoPhaseShownDrawsNoStandardInThePowderAndCrystalPanes() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertTrue(SimulationEmptyState.isShown(for: item))
        XCTAssertTrue(DiffractionPowderSection.table(of: item, openItems: state.openItems).phases.isEmpty, "no Au in the empty state")

        item.diffraction.setCrystal(.phase(PhaseCrystal(id: "test-si", name: "Si", structure: CrystalPresets.silicon)))
        XCTAssertEqual(DiffractionPowderSection.table(of: item, openItems: state.openItems).phases.map(\.name), ["Si"])

        // A measured pattern keeps its standard as the crystal to compare against.
        await state.open(urls: [DemoDocuments.patternURL])?.value
        let pattern = try XCTUnwrap(state.openItems.items.first { $0.url == DemoDocuments.patternURL })
        XCTAssertEqual(DiffractionPowderSection.table(of: pattern, openItems: state.openItems).phases.map(\.name), ["Au"])

        let pane = try Self.source("macTEM/UI/DiffractionSidePane.swift")
        XCTAssertTrue(pane.contains("case .crystal where SimulationEmptyState.isShown(for: item):"))
        XCTAssertTrue(pane.contains("case .powder where SimulationEmptyState.isShown(for: item):"))
        let room = try Self.source("macTEM/UI/DiffractionRoom.swift")
        XCTAssertTrue(room.contains("if !SimulationEmptyState.isShown(for: item), let line = analysis.orientationHeaderLine("))
        let door = try Self.source("macTEM/App/AgentDoorDiffractionScience.swift")
        XCTAssertTrue(door.contains("if SimulationEmptyState.isShown(for: item) { return .refusal(status: 409, message: SimulationEmptyState.paneSentence) }"))
    }
}
