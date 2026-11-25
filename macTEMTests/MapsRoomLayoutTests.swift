//
//  MapsRoomLayoutTests.swift
//  The Maps room's layout (#1064, approved 25 Nov 2026): the map leads, the results take the trailing pane at full height, no strip
//  under them, and the picked point is an inset on the map opposite the scale bar that Display hides. Red before: a vertical split put
//  the map beside the live pattern pane over a strip of tabs, and there was no `MapsRoomLayout`, no inset and no switch.
//

import ShellAgentDoor
import ShellLayout
import SwiftUI
import XCTest
@testable import macTEM

nonisolated final class MapsRoomLayoutTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    @MainActor func testTheResultsTakeTheTrailingPaneAndTheStripIsEmpty() throws {
        XCTAssertEqual(MapsRoomLayout.leading, .map)
        XCTAssertEqual(MapsRoomLayout.trailing, .results)
        XCTAssertNil(MapsRoomLayout.bottom, "no strip under the panes")
        let room = try ui("MapsRoom.swift")
        XCTAssertFalse(room.contains("VerticalPaneSplit("), "no strip")
        XCTAssertFalse(room.contains("LivePatternPane("), "the pattern is no pane of its own")
        XCTAssertTrue(room.contains("PaneSplit(storageKey: MapsRoomLayout.splitKey, resizeLabel: \"Resize the map and the results\", leadingName: \"Map\") { upper(document)"))
        XCTAssertTrue(room.contains("} trailing: { MapsResultsPane(session: session, state: state) }"))
        XCTAssertNotEqual(MapsRoomLayout.splitKey, "maps.split", "the old map | pattern fraction does not size the results")
    }

    /// The inset sits opposite the scale bar (the footer's leading corner), takes no clicks, follows Display's switch and leaves a small
    /// map alone.
    @MainActor func testThePickedPointIsAnInsetOppositeTheScaleBar() throws {
        XCTAssertEqual(MapsRoomLayout.insetAlignment, .topTrailing)
        XCTAssertTrue(MapsRoomLayout.fitsInset(in: CGSize(width: 500, height: 400)))
        XCTAssertFalse(MapsRoomLayout.fitsInset(in: CGSize(width: 200, height: 400)), "a narrow map keeps its pixels")
        // #1089: on the duplex steel map in a narrow pane (350 × 300 points) the inset is a quarter of the short side, not 120 points,
        // and the two IPF keys shrink to their smallest.
        let small = CGSize(width: 350, height: 300)
        XCTAssertEqual(try XCTUnwrap(MapsRoomLayout.insetSide(in: small)), 63, accuracy: 0.5)
        XCTAssertEqual(MapsRoomLayout.insetSide(in: CGSize(width: 900, height: 800)), LayoutPolicy.mapsInsetSide, "a large map keeps the full inset")
        let keys = MapsRoomLayout.keyWidth(in: small, count: 2)
        XCTAssertLessThan(keys, LayoutPolicy.mapsKeyInsetWidth / 2, "the keys shrink on a small map")
        XCTAssertEqual(MapsRoomLayout.keyWidth(in: CGSize(width: 2000, height: 800), count: 1), LayoutPolicy.mapsKeyInsetWidth)
        XCTAssertTrue(MapsRoomState().showsPointInset, "on by default")
        let room = try ui("MapsRoom.swift")
        XCTAssertTrue(room.contains("if state.showsPointInset, let side = MapsRoomLayout.insetSide(in: box) { MapsPointInset(session: session, patterns: patterns, side: side)"))
        XCTAssertTrue(room.contains(".frame(width: box.width, height: box.height, alignment: MapsRoomLayout.insetAlignment) .allowsHitTesting(false)"))
        let inspector = try ui("MapsRoomInspector.swift")
        XCTAssertTrue(inspector.contains("InspectorSection(\"Display\") {"))
        XCTAssertTrue(inspector.contains("Toggle(\"Pattern inset\", isOn: $state.showsPointInset) .toggleStyle(.switch).labelsHidden()"))
    }

    /// The door reads and sets the inset through the room's own state, and the coverage names its switch.
    @MainActor func testTheDoorReachesTheInset() {
        XCTAssertTrue(MacTEMAgentDoor.mapsParameters.contains { $0.name == "show_inset" })
        XCTAssertEqual(AgentDoorCoverage.controls["maps.showInset"], .tool("set_maps"))
        XCTAssertEqual(AgentDoorCoverage.controls["maps.results.tabs"], .tool("set_maps"))
        let appState = AppState(launch: LaunchOptions(arguments: []))
        XCTAssertNil(MacTEMAgentDoor.applyMaps(["show_inset": "false"], to: appState))
        XCTAssertFalse(appState.mapsRoom.showsPointInset)
        XCTAssertNil(MacTEMAgentDoor.applyMaps(["show_inset": "true"], to: appState))
        XCTAssertTrue(appState.mapsRoom.showsPointInset)
    }
}
