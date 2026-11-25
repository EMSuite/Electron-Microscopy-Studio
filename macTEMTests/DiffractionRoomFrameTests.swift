//
//  DiffractionRoomFrameTests.swift
//  The Diffraction room sits on the frame (#1094): its centre is the shell's `WorkspaceCentre`, the side pane and the pattern each a
//  `CentrePanel` with the frame's one header, the pattern alone in the single-panel form; its tables (Readout, Spots, Peaks) are panes
//  of the shell's bottom area beside Output, behind the bar the person drags, where a fixed-height strip under the pattern held one
//  at a time behind a Readout · Spots switch. The window shows the table the strip showed the first time a part asks for it, and
//  never again on its own: the person's toggles are theirs. Red before: `HorizontalPaneSplit` and the room's own header row, the
//  strip at `LayoutPolicy.diffractionReadoutHeight`, no Diffraction tab in the bottom area.
//

import ShellLayout
import XCTest
@testable import macTEM

nonisolated final class DiffractionRoomFrameTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The centre is the frame's: two panels with the stored divider, or the pattern alone; each panel has the shared header, and the
    /// pattern's header keeps every fact and control the room's header row had. Mutation: the room's own split or header row back.
    func testTheCentreIsTheFramesWithItsPanelHeaders() throws {
        let room = try ui("DiffractionRoom.swift")
        XCTAssertTrue(room.contains("WorkspaceCentre(storageKey: DiffractionCrystalSplit.storageKey, defaultFraction: DiffractionCrystalSplit.defaultCrystalFraction,"),
                      "two panels on the frame's centre")
        XCTAssertTrue(room.contains("{ DiffractionSidePaneView(item: item, analysis: analysis, view: view, pane: pane) } trailing: { patternPanel(analysis: analysis, view: view, rows: rows) }"),
                      "the side pane leads, the pattern trails")
        XCTAssertTrue(room.contains("} else { WorkspaceCentre { patternPanel(analysis: analysis, view: view, rows: rows) } }"), "the single-panel form")
        XCTAssertFalse(room.contains("HorizontalPaneSplit("), "no split of the room's own")
        XCTAssertFalse(room.contains("DiffractionHeader(item: item, analysis: analysis, view: view)"), "no header row across the room")
        XCTAssertTrue(room.contains("CentrePanel(title: image.fileName) { DiffractionPatternPane(item: item, analysis: analysis, view: view, rows: rows) .modifier(DiffractionZoomCommands(item: item, view: view)) } controls: { DiffractionHeaderFacts(item: item, analysis: analysis, view: view) } readout: { DiffractionHeaderScale(item: item, analysis: analysis) }"),
                      "the pattern's panel: the file, its facts at the right, the scale's summary in the readout slot")
        for id in ["diffraction.scale", "diffraction.index.verdict", "diffraction.simulation.place", "diffraction.view", "diffraction.figureDrag"] {
            XCTAssertTrue(room.contains(".accessibilityIdentifier(\"\(id)\")"), "\(id) kept in the header")
        }
        let side = try ui("DiffractionSidePane.swift")
        XCTAssertTrue(side.contains("CentrePanel(title: DiffractionPaneWords.title(pane)) { switch pane {"), "the side pane's header is the frame's")
        XCTAssertFalse(side.contains(".frame(height: LayoutPolicy.paneHeaderHeight)"), "no header of its own")
    }

    /// No strip under the pattern: no fixed height, no switch between the tables. The tables are drawn by the bottom area's pane.
    /// Mutation: the strip back.
    func testThereIsNoTableStripUnderThePattern() throws {
        let room = try ui("DiffractionRoom.swift")
        XCTAssertFalse(room.contains("diffractionReadoutHeight"), "no fixed-height strip")
        XCTAssertFalse(room.contains("diffraction.lowerTable") || room.contains("SegmentedPicker("), "no Readout · Spots switch")
        XCTAssertTrue(room.contains("struct DiffractionTablePane: View {"))
        XCTAssertTrue(room.contains("case .readout: DiffractionReadoutTable(analysis: analysis, view: view, rows: analysis.readout(image: image))"))
        XCTAssertTrue(room.contains("DiffractionSpotTable(view: view, rows: analysis.indexSpotRows)"))
    }

    /// The bottom area lists the part's tables after Output while the Diffraction room shows a document, and only then. Mutation:
    /// the tabs dropped, or supplied in every room.
    func testTheTablesAreTabsOfTheBottomArea() throws {
        let workspace = try ui("WorkspaceView.swift")
        // The Maps room's tables follow the Diffraction tables (#1095).
        XCTAssertTrue(workspace.contains("tabs: [ProcessTab.output { OutputPane(log: appState.activityLog) }] + diffractionTabs + mapsTabs,"))
        XCTAssertTrue(workspace.contains("guard appState.navigation.workspaceArea == .diffraction, appState.openItems.selected != nil else { return [] } return DiffractionPart.tables(appState.diffractionPart)"))
        XCTAssertTrue(workspace.contains("ProcessTab(id: table.paneID, title: table.title, systemImage: table.systemImage) { DiffractionTablePane(table: table) }"))
        XCTAssertTrue(workspace.contains(".onChange(of: diffractionTables) { DiffractionRoomState.keepAPaneShown(supplied: diffractionTables, in: appState.navigation.panels) }"))
        let room = try ui("DiffractionRoom.swift")
        XCTAssertTrue(room.contains(".onChange(of: DiffractionPart.openingTable(part, hasSpots: Self.hasSpots(item))) { offerTable() }"))
    }

    /// Each table has a pane of its own, never Output's, with a name and a symbol for its toggle.
    @MainActor func testEachTableHasItsOwnPane() {
        let ids = DiffractionTable.allCases.map(\.paneID)
        XCTAssertEqual(Set(ids).count, DiffractionTable.allCases.count)
        XCTAssertFalse(ids.contains(.output))
        XCTAssertEqual(ids.map(\.rawValue), ["diffraction.readout", "diffraction.spots", "diffraction.peaks"])
        XCTAssertEqual(DiffractionTable.allCases.map(\.title), ["Readout", "Spots", "Peaks"])
        XCTAssertTrue(DiffractionTable.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    /// A fresh window (the area shut, Output the only pane shown) shows the part's table with the area open, as the strip showed it;
    /// a table hidden by the person, or the area shut by them, stays so when the part asks again. Another table is shown once too.
    /// Mutation: `offer` showing a table every time it is asked, or never.
    @MainActor func testTheStripsTableIsShownOnceAndThePersonsToggleWins() {
        let state = DiffractionRoomState()
        let panels = PanelNavigation()
        XCTAssertFalse(panels.showProcessArea, "a fresh window's area is shut")
        state.offer(nil, in: panels)
        XCTAssertFalse(panels.showProcessArea, "no table, nothing shown")

        state.offer(.readout, in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(DiffractionTable.readout.paneID))
        XCTAssertTrue(panels.shownProcessPanes.contains(.output), "Output stays as the person had it")
        XCTAssertTrue(panels.showProcessArea, "the area opens with it")

        panels.toggleProcessPane(DiffractionTable.readout.paneID)
        state.offer(.readout, in: panels)
        XCTAssertFalse(panels.shownProcessPanes.contains(DiffractionTable.readout.paneID), "hidden by the person, it stays hidden")

        panels.showProcessArea = false
        state.offer(.spots, in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(DiffractionTable.spots.paneID), "Index answered: the Spots table shows once")
        XCTAssertTrue(panels.showProcessArea)
        panels.showProcessArea = false
        state.offer(.spots, in: panels)
        XCTAssertFalse(panels.showProcessArea, "the area the person shut stays shut")
        XCTAssertEqual(state.offeredTables, [.readout, .spots])
    }

    /// The area never stands open with none of its panes: when the tables on offer go (another part or room) and only they were
    /// shown, Output comes back; while one shown is still offered, nothing changes. Mutation: the guard dropped, or Output forced.
    @MainActor func testTheAreaKeepsAPaneWhenTheTablesGo() {
        let panels = PanelNavigation()
        panels.shownProcessPanes = [DiffractionTable.readout.paneID]
        DiffractionRoomState.keepAPaneShown(supplied: [.readout, .spots], in: panels)
        XCTAssertEqual(panels.shownProcessPanes, [DiffractionTable.readout.paneID], "still on offer: left alone")
        DiffractionRoomState.keepAPaneShown(supplied: [], in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(.output), "the tables went: Output shows")
    }
}
