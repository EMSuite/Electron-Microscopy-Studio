//
//  MapsRoomLayoutTests.swift
//  The Maps room's layout (#1064, approved 25 Nov 2026; on the frame since #1089 and #1095): the map leads, the Detail panel trails, no
//  strip of the room's own under them, and the picked point is the Detail panel's (its pattern or unit cell), never an inset on the map.
//  Red before #1064: a vertical split put the map beside the live pattern pane over a strip of tabs. Red before #1095: the results
//  pane trailed and the picked point sat on the map behind Display › Pattern inset.
//

import ShellAgentDoor
import SwiftUI
import XCTest
@testable import EMStudio

nonisolated final class MapsRoomLayoutTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    @MainActor func testTheDetailTakesTheTrailingPanelAndTheRoomHasNoStrip() throws {
        XCTAssertEqual(MapsRoomLayout.leading, .map)
        XCTAssertEqual(MapsRoomLayout.trailing, .detail)
        let room = try ui("MapsRoom.swift")
        XCTAssertFalse(room.contains("VerticalPaneSplit("), "no strip")
        XCTAssertFalse(room.contains("LivePatternPane("), "the pattern is no pane of its own")
        XCTAssertTrue(room.contains("} trailing: { CentrePanel(title: \"Detail\") { MapsDetailPane(session: session, state: state, patterns: patternsDataset.map { _ in appState.ebsd }) } }"))
        XCTAssertNotEqual(MapsRoomLayout.centreKey, "maps.split", "the old map | pattern fraction does not size the Detail panel")
        XCTAssertNotEqual(MapsRoomLayout.centreKey, "maps.resultsSplit", "nor the results pane's half")
        XCTAssertEqual(MapsRoomLayout.centreKey, "workspace.centre.maps.fraction")
        XCTAssertGreaterThan(MapsRoomLayout.defaultFraction, 0.5, "the map, the data, takes more than half until the person drags")
    }

    /// The picked point is the Detail panel's Point tab, with the colour key under it; nothing of it is placed over the map, and its
    /// switch is gone from Display.
    @MainActor func testThePickedPointIsTheDetailPanelsNotAnInset() throws {
        XCTAssertEqual(MapsRoomState().detailTab, .point, "the panel opens on the point, as the map showed it")
        let room = try ui("MapsRoom.swift")
        XCTAssertTrue(room.contains("MapsPointDetail(session: session, patterns: patterns) Divider() MapsColourKey(session: session)"))
        XCTAssertFalse(room.contains("MapsPointInset("))
        XCTAssertFalse(room.contains("fitsInset("))
        XCTAssertFalse(room.contains("insetAlignment"))
        XCTAssertFalse(room.contains(".background(.regularMaterial"), "no plate over the map")
        let inspector = try ui("MapsRoomInspector.swift")
        XCTAssertFalse(inspector.contains("Pattern inset"), "the inset's switch went with the inset")
        XCTAssertFalse(inspector.contains("maps.showInset"))
        XCTAssertTrue(inspector.contains("ImageRoomDisplayRows(presentation: session.propertyPresentation, colormapID: \"maps.colormap\")"),
                      "Display keeps a value layer's rows")
    }

    /// The door reads and sets the Detail panel's tab through the room's own state; the inset's parameter and its coverage row went.
    @MainActor func testTheDoorReachesTheDetailPanel() {
        XCTAssertFalse(MacTEMAgentDoor.mapsParameters.contains { $0.name == "show_inset" })
        XCTAssertNil(AgentDoorCoverage.controls["maps.showInset"])
        XCTAssertEqual(AgentDoorCoverage.controls["maps.results.tabs"], .tool("set_maps"))
        let appState = AppState(launch: LaunchOptions(arguments: []))
        XCTAssertNil(MacTEMAgentDoor.applyMaps(["tab": "odf"], to: appState))
        XCTAssertEqual(appState.mapsRoom.detailTab, .odf)
        XCTAssertNil(MacTEMAgentDoor.applyMaps(["tab": "point"], to: appState))
        XCTAssertEqual(appState.mapsRoom.detailTab, .point)
    }
}
