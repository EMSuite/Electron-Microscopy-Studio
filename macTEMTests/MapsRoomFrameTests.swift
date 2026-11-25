//
//  MapsRoomFrameTests.swift
//  The Maps room sits on the frame (#1089, #1095): its centre is the shell's `WorkspaceCentre`, the Map and Detail panels each a
//  `CentrePanel`; the map is fitted to its panel and nothing is placed over it but what is the map's; the Grains table and the picked
//  grain's slip planes are tables of the shell's bottom area beside Output, each shown by the window on its own once, as the Diffraction
//  tables are (#1094). Red before: a `PaneSplit` of the room's own with the results pane, the picked point's inset and the colour key
//  over the map, the slip planes as lines of text under the Grains table, no Maps tab in the bottom area, no `MapsRoomLayout.mapBox`.
//

import CoreGraphics
import Foundation
import ShellLayout
import XCTest
@testable import macTEM

nonisolated final class MapsRoomFrameTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The source between `start` and `end`.
    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        try XCTUnwrap(text.components(separatedBy: start).dropFirst().first?.components(separatedBy: end).first, start)
    }

    // MARK: The centre

    /// The centre is the frame's: two panels with the room's own stored divider, the map's panel with the map picker in its controls
    /// and the pointer's point in its readout, the Detail panel trailing. Mutation: the room's own split back.
    func testTheCentreIsTheFramesWithTwoPanels() throws {
        let room = try ui("MapsRoom.swift")
        XCTAssertTrue(room.contains("WorkspaceCentre(storageKey: MapsRoomLayout.centreKey, defaultFraction: MapsRoomLayout.defaultFraction, resizeLabel: \"Resize the map and the detail\", leadingName: \"Map\") { upper(document)"))
        XCTAssertFalse(room.contains("PaneSplit("), "no split of the room's own")
        XCTAssertTrue(room.contains("CentrePanel(title: \"Map\") { MapPane(session: appState.maps, state: appState.mapsRoom, patterns: patternsDataset.map { _ in appState.ebsd }, map: document.map) } controls: { MapsMapControls(session: appState.maps, staleness: appState.mapsStaleness) } readout: { MapsPointerReadout(state: appState.mapsRoom) }"))
        XCTAssertTrue(room.contains("CentrePanel(title: \"Detail\") { MapsDetailPane("))
        let pane = try slice(room, from: "struct MapPane: View {", to: "private func content(in size: CGSize)")
        XCTAssertFalse(pane.contains(".frame(height: LayoutPolicy.paneHeaderHeight)"), "no header of the map's own: the panel's")
        XCTAssertFalse(pane.contains(".padding(8)"), "no inset of its own: the panel's")
    }

    /// Nothing is placed over the map but what is the map's: its pixels, the boundaries, outline and traces, the pick, the marker and
    /// the footer's scale bar and zoom. The picked point and the colour key are the Detail panel's. Mutation: an inset or the key back
    /// in the map's stack.
    func testNothingSitsOnTheMapButTheMap() throws {
        let room = try ui("MapsRoom.swift")
        let map = try slice(room, from: "private func content(in size: CGSize) -> some View {", to: "/// A click, a drag or the handle picks")
        for inset in ["MapsPointDetail(", "MapsPointInset(", "MapsColourKey(", "MapsKeyInset(", "MapsPointTab(", ".background(.regularMaterial", "maps.map.notIndexed"] {
            XCTAssertFalse(map.contains(inset), "\(inset) over the map")
        }
        XCTAssertTrue(map.contains("MapsAnalysisOverlay(session: session, geometry: geometry)"), "the boundaries and traces are the map's")
        XCTAssertTrue(map.contains("ScaleBar(unitsPerPoint:"), "the scale bar is the map's")
        XCTAssertTrue(map.contains("let box = MapsRoomLayout.mapBox(columns: shape.columns, rows: shape.rows, in: size)"), "the map is fitted")
        let detail = try slice(try ui("MapsRoomAnalysis.swift"), from: "struct MapsDetailPane: View {", to: "// MARK: - The tables in the bottom area")
        XCTAssertTrue(detail.contains("case .point: MapsPointTab(session: session, patterns: patterns)"), "the point and the key are Detail's")
        XCTAssertTrue(room.contains("MapsPointDetail(session: session, patterns: patterns) Divider() MapsColourKey(session: session)"))
        let controls = try slice(room, from: "struct MapsMapControls: View {", to: "struct MapsPointerReadout: View {")
        XCTAssertTrue(controls.contains(".accessibilityIdentifier(\"maps.map.notIndexed\")"), "the points not indexed are a fact of the header")
    }

    // MARK: The fit

    /// The map is the largest box of its aspect in its panel: 117 × 100 in a tall panel fills the width, in a wide one the height; it
    /// never leaves the panel and keeps its aspect, and it grows with the panel. Mutation: a cap, an upscale past the panel, a swapped
    /// aspect.
    func testTheMapFillsItsPanel() {
        let tall = MapsRoomLayout.mapBox(columns: 117, rows: 100, in: CGSize(width: 600, height: 900))
        XCTAssertEqual(tall.width, 600, accuracy: 1e-9, "a tall panel: the width")
        XCTAssertEqual(tall.height, 600 * 100 / 117, accuracy: 1e-9)
        let wide = MapsRoomLayout.mapBox(columns: 117, rows: 100, in: CGSize(width: 1200, height: 500))
        XCTAssertEqual(wide.height, 500, accuracy: 1e-9, "a wide panel: the height")
        XCTAssertEqual(wide.width, 500 * 117.0 / 100, accuracy: 1e-9)
        let strip = MapsRoomLayout.mapBox(columns: 1000, rows: 100, in: CGSize(width: 400, height: 300))
        XCTAssertEqual(strip.width, 400, accuracy: 1e-9, "a wide map in a squarer panel: the width")
        XCTAssertEqual(strip.height, 40, accuracy: 1e-9)
        for panel in [CGSize(width: 600, height: 900), CGSize(width: 1200, height: 500), CGSize(width: 37, height: 2000), CGSize(width: 3000, height: 41)] {
            for (columns, rows) in [(117, 100), (1000, 100), (100, 1000), (1, 1)] {
                let box = MapsRoomLayout.mapBox(columns: columns, rows: rows, in: panel)
                XCTAssertLessThanOrEqual(box.width, panel.width + 1e-9, "\(columns) × \(rows) in \(panel)")
                XCTAssertLessThanOrEqual(box.height, panel.height + 1e-9, "\(columns) × \(rows) in \(panel)")
                XCTAssertTrue(abs(box.width - panel.width) < 1e-9 || abs(box.height - panel.height) < 1e-9, "one side fills the panel")
                XCTAssertEqual(box.width / box.height, CGFloat(columns) / CGFloat(rows), accuracy: 1e-9, "the aspect is kept")
            }
        }
        let bigger = MapsRoomLayout.mapBox(columns: 117, rows: 100, in: CGSize(width: 1200, height: 1800))
        XCTAssertEqual(bigger.width, 2 * tall.width, accuracy: 1e-9, "it grows with the window: no size of its own")
        XCTAssertEqual(MapsRoomLayout.mapBox(columns: 117, rows: 100, in: .zero), .zero)
    }

    // MARK: The tables

    /// Grains and Slip are tables of the bottom area while the room shows a map, and only then; Slip is a real, sortable table of the
    /// picked grain's planes with a one-line state for no grain. Mutation: the tabs dropped, or the planes back as text.
    func testTheTablesAreTabsOfTheBottomArea() throws {
        let workspace = try ui("WorkspaceView.swift")
        XCTAssertTrue(workspace.contains("tabs: [ProcessTab.output { OutputPane(log: appState.activityLog) }] + diffractionTabs + mapsTabs,"))
        XCTAssertTrue(workspace.contains("guard appState.navigation.workspaceArea == .maps, appState.maps.document != nil else { return [] } return MapsTable.allCases"))
        XCTAssertTrue(workspace.contains("ProcessTab(id: table.paneID, title: table.title, systemImage: table.systemImage) { MapsTablePane(table: table) }"))
        XCTAssertTrue(workspace.contains(".onChange(of: mapsTables) { MapsRoomState.keepAPaneShown(supplied: mapsTables, in: appState.navigation.panels) }"))
        let analysis = try ui("MapsRoomAnalysis.swift")
        XCTAssertTrue(analysis.contains("case .grains: MapsGrainsTable(session: appState.maps) case .slip: MapsSlipTable(session: appState.maps)"))
        let slip = try slice(analysis, from: "struct MapsSlipTable: View {", to: "extension GrainRow {")
        XCTAssertTrue(slip.contains("Table(rows, sortOrder: $sortOrder) {"), "a table, sortable")
        for column in ["TableColumn(\"Plane\", value: \\.id)", "TableColumn(\"Schmid factor\", value: \\.schmid)",
                       "TableColumn(SEMColumnSpeech.header(\"Trace °\"), value: \\.traceOrder)", "TableColumn(\"Colour\", value: \\.colourWord)",
                       "TableColumn(SEMColumnSpeech.header(\"Inclined °\"), value: \\.inclinationDegrees)"] {
            XCTAssertTrue(slip.contains(column), column)
        }
        XCTAssertTrue(slip.contains(".accessibilityIdentifier(\"maps.slip.empty\")"))
        XCTAssertFalse(try ui("MapsRoom.swift").contains("MapsGrainsTable("), "no table in the centre")
        XCTAssertFalse(analysis.contains("case .grains: MapsGrainsTable(session: session)"), "no Grains tab in the Detail panel")
    }

    /// The one line in place of the Slip table says what is missing, in order.
    @MainActor func testTheSlipTableSaysWhyItIsEmpty() {
        XCTAssertEqual(MapsSlipTable.emptyLine(segmented: false, picked: false), "Segment the map, then pick a grain for its slip systems.")
        XCTAssertEqual(MapsSlipTable.emptyLine(segmented: true, picked: false), "Pick a grain on the map or in the Grains table for its slip systems.")
        XCTAssertTrue(MapsSlipTable.emptyLine(segmented: true, picked: true).contains("inspector's Slip section"))
    }

    /// A trace parallel to the map sorts after every angle and reads as `traceText` says it. Mutation: NaN in the sort.
    func testAPlaneWithNoTraceSortsLast() {
        let none = MapsSlipRow(id: 0, plane: "(111)", colour: "blue", schmid: 0.4, traceDegrees: .nan, inclinationDegrees: 0)
        let some = MapsSlipRow(id: 1, plane: "(110)", colour: "m", schmid: 0.3, traceDegrees: 132, inclinationDegrees: 61)
        XCTAssertEqual(none.traceOrder, .infinity)
        XCTAssertEqual(some.traceOrder, 132)
        XCTAssertEqual(none.traceText(), "no trace")
        XCTAssertEqual(some.traceText(locale: Locale(identifier: "en_US")), "132")
        XCTAssertEqual(some.colourWord, "magenta")
        XCTAssertEqual([none, some].sorted(using: KeyPathComparator(\MapsSlipRow.traceOrder)).map(\.id), [1, 0])
    }

    /// Each table has a pane of its own, never Output's or a Diffraction table's, with a name and a symbol for its toggle.
    @MainActor func testEachTableHasItsOwnPane() {
        let ids = MapsTable.allCases.map(\.paneID)
        XCTAssertEqual(ids.map(\.rawValue), ["maps.table.grains", "maps.table.slip"])
        XCTAssertFalse(ids.contains(.output))
        XCTAssertTrue(Set(ids).isDisjoint(with: DiffractionTable.allCases.map(\.paneID)))
        XCTAssertEqual(MapsTable.allCases.map(\.title), ["Grains", "Slip"])
        XCTAssertTrue(MapsTable.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    /// The window shows Grains once Segment has grains, Slip once a picked grain has planes, nothing before. Mutation: Grains before
    /// Segment, or Slip without a grain.
    func testWhatTheWindowOffers() throws {
        XCTAssertEqual(MapsTable.opening(hasGrains: false, hasSlip: false), [])
        XCTAssertEqual(MapsTable.opening(hasGrains: false, hasSlip: true), [])
        XCTAssertEqual(MapsTable.opening(hasGrains: true, hasSlip: false), [.grains])
        XCTAssertEqual(MapsTable.opening(hasGrains: true, hasSlip: true), [.grains, .slip])
        let room = try ui("MapsRoom.swift")
        XCTAssertTrue(room.contains(".onChange(of: MapsTable.opening(hasGrains: session.analysis != nil, hasSlip: session.selectedSlip != nil), initial: true) { _, tables in for table in tables { state.offer(table, in: appState.navigation.panels) } }"))
        XCTAssertTrue(room.contains(".modifier(MapsOffersTables(session: session, state: state))"))
    }

    /// A fresh window (the area shut) shows Grains with the area open; a table the person hid, or an area they shut, stays so when
    /// it is offered again. Mutation: `offer` showing a table every time, or never.
    @MainActor func testATableIsShownOnceAndThePersonsToggleWins() {
        let state = MapsRoomState()
        let panels = PanelNavigation()
        XCTAssertFalse(panels.showProcessArea, "a fresh window's area is shut")
        state.offer(nil, in: panels)
        XCTAssertFalse(panels.showProcessArea, "no table, nothing shown")

        state.offer(.grains, in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(MapsTable.grains.paneID))
        XCTAssertTrue(panels.shownProcessPanes.contains(.output), "Output stays as the person had it")
        XCTAssertTrue(panels.showProcessArea, "the area opens with it")

        panels.toggleProcessPane(MapsTable.grains.paneID)
        state.offer(.grains, in: panels)
        XCTAssertFalse(panels.shownProcessPanes.contains(MapsTable.grains.paneID), "hidden by the person, it stays hidden")

        panels.showProcessArea = false
        state.offer(.slip, in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(MapsTable.slip.paneID), "a grain picked: Slip shows once")
        XCTAssertTrue(panels.showProcessArea)
        panels.showProcessArea = false
        state.offer(.slip, in: panels)
        XCTAssertFalse(panels.showProcessArea, "the area the person shut stays shut")
        XCTAssertEqual(state.offeredTables, [.grains, .slip])
    }

    /// The area never stands open with none of its panes: when the Maps tables go and only they were shown, Output comes back.
    @MainActor func testTheAreaKeepsAPaneWhenTheTablesGo() {
        let panels = PanelNavigation()
        panels.shownProcessPanes = [MapsTable.grains.paneID]
        MapsRoomState.keepAPaneShown(supplied: MapsTable.allCases, in: panels)
        XCTAssertEqual(panels.shownProcessPanes, [MapsTable.grains.paneID], "still on offer: left alone")
        MapsRoomState.keepAPaneShown(supplied: [], in: panels)
        XCTAssertTrue(panels.shownProcessPanes.contains(.output), "the tables went: Output shows")
    }
}
