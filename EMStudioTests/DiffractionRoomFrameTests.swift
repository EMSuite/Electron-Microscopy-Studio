//
//  DiffractionRoomFrameTests.swift
//  The Diffraction room sits on the frame (#1094): its centre is the shell's `WorkspaceCentre`, the side pane and the pattern each a
//  `CentrePanel` with the frame's one header, the pattern alone in the single-panel form; its tables (Readout, Spots, Peaks) are tabs
//  of the shell's bottom area beside Output (#1112: one at a time at full width, chosen in the area's header, one toggle for the
//  area), behind the bar the person drags, where a fixed-height strip under the pattern held one at a time behind a Readout · Spots
//  switch. The window selects the table the strip showed the first time a part asks for it, and never again on its own: the
//  person's choice of tab is theirs. Red before: `HorizontalPaneSplit` and the room's own header row, the strip at
//  `LayoutPolicy.diffractionReadoutHeight`, no Diffraction tab in the bottom area; before #1112 the tables were panes side by side.
//

import ShellLayout
import XCTest
@testable import EMStudio

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

    /// No strip under the pattern: no fixed height, no switch of the room's between the tables. The tables are drawn by the bottom
    /// area's tab.
    /// Mutation: the strip back.
    func testThereIsNoTableStripUnderThePattern() throws {
        let room = try ui("DiffractionRoom.swift")
        XCTAssertFalse(room.contains("diffractionReadoutHeight"), "no fixed-height strip")
        XCTAssertFalse(room.contains("diffraction.lowerTable") || room.contains("SegmentedPicker("), "no Readout · Spots switch")
        XCTAssertTrue(room.contains("struct DiffractionTablePane: View {"))
        XCTAssertTrue(room.contains("case .readout: DiffractionReadoutTable(analysis: analysis, view: view, rows: analysis.readout(image: image))"))
        XCTAssertTrue(room.contains("DiffractionSpotTable(view: view, rows: analysis.indexSpotRows)"))
    }

    /// The bottom area lists the part's tables after Output while the Diffraction room shows a document, and only then, as tabs (one
    /// at a time at full width, #1112). Mutation: the tabs dropped, supplied in every room, or the area back to panes side by side.
    func testTheTablesAreTabsOfTheBottomArea() throws {
        let workspace = try ui("WorkspaceView.swift")
        // The Maps room's tables follow the Diffraction tables (#1095).
        XCTAssertTrue(workspace.contains("tabs: [ProcessTab.output { OutputPane(log: appState.activityLog) }] + imageTabs + diffractionTabs + mapsTabs,"))
        XCTAssertTrue(workspace.contains("guard appState.navigation.workspaceArea == .diffraction, appState.openItems.selected != nil else { return [] } return DiffractionPart.tables(appState.diffractionPart)"))
        XCTAssertTrue(workspace.contains("ProcessTab(id: table.paneID, title: table.title, systemImage: table.systemImage) { DiffractionTablePane(table: table) }"))
        XCTAssertTrue(workspace.contains("processAreaStyle: .tabs,"), "one tab at a time at full width, one toggle for the area")
        XCTAssertFalse(workspace.contains("keepAPaneShown"), "nothing puts Output back: a stale selection shows as Output (`shownTab`)")
        let room = try ui("DiffractionRoom.swift")
        XCTAssertTrue(room.contains(".onChange(of: DiffractionPart.openingTable(part, hasSpots: Self.hasSpots(item))) { offerTable() }"))
    }

    /// Each table has a tab of its own, never Output's, with a name for the area's header and a symbol.
    @MainActor func testEachTableHasItsOwnPane() {
        let ids = DiffractionTable.allCases.map(\.paneID)
        XCTAssertEqual(Set(ids).count, DiffractionTable.allCases.count)
        XCTAssertFalse(ids.contains(.output))
        XCTAssertEqual(ids.map(\.rawValue), ["diffraction.readout", "diffraction.spots", "diffraction.peaks"])
        XCTAssertEqual(DiffractionTable.allCases.map(\.title), ["Readout", "Spots", "Peaks"])
        XCTAssertTrue(DiffractionTable.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    /// A fresh window (the area shut, Output selected) selects the part's table with the area open, as the strip showed it; once
    /// the person picks another tab (Output) or shuts the area, a second offer of that table leaves their choice. Another table is
    /// selected once too. Mutation: `offer` selecting a table every time it is asked, or never, or not opening a shut area.
    @MainActor func testTheStripsTableIsSelectedOnceAndThePersonsChoiceWins() {
        let state = DiffractionRoomState()
        let panels = PanelNavigation()
        XCTAssertFalse(panels.showProcessArea, "a fresh window's area is shut")
        XCTAssertEqual(panels.selectedProcessPane, .output)
        state.offer(nil, in: panels)
        XCTAssertFalse(panels.showProcessArea, "no table, nothing shown")
        XCTAssertEqual(panels.selectedProcessPane, .output)

        state.offer(.readout, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, DiffractionTable.readout.paneID, "the strip's table is the tab shown")
        XCTAssertTrue(panels.showProcessArea, "the area opens with it")

        panels.selectProcessPane(.output)
        state.offer(.readout, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, .output, "the person chose Output: a second offer leaves it")

        panels.showProcessArea = false
        state.offer(.spots, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, DiffractionTable.spots.paneID, "Index answered: the Spots table is selected once")
        XCTAssertTrue(panels.showProcessArea)
        panels.showProcessArea = false
        state.offer(.spots, in: panels)
        XCTAssertFalse(panels.showProcessArea, "the area the person shut stays shut")
        XCTAssertEqual(state.offeredTables, [.readout, .spots])
    }

    /// A table left selected when another part or room takes the tables away shows as Output, never an empty area, and shows again
    /// when its table comes back still selected; the shell's rule (`ProcessAreaLayout.shownTab`), so the app keeps nothing of its own
    /// for it. Mutation: the area drawing a tab it does not hold.
    @MainActor func testASelectionLeftFromAnotherRoomShowsOutput() {
        let readout = DiffractionTable.readout.paneID
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: readout, in: [.output]), .output, "the tables went: Output shows")
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: MapsTable.grains.paneID, in: [.output, readout, DiffractionTable.spots.paneID]),
                       .output, "a Maps table left selected in the Diffraction room: Output")
        XCTAssertEqual(ProcessAreaLayout.shownTab(selected: readout, in: [.output, readout]), readout, "back: the table shows again")
    }
}
