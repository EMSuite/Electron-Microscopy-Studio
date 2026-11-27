//
//  MapsHeadingPickerTests.swift
//  The Maps room's map is chosen in the map pane's heading and its colour key sits on the map (#1065, approved 25 Nov 2026): the
//  heading's menu offers every map kind the inspector's Map row offered, on the same property; the results have no Key tab; the key on
//  the map follows the map kind. Red before: the Map row in the inspector, a plain title in the heading, the Key tab, no `MapsKeyKind`.
//  On the frame (#1095) the picker is the Map panel's control beside its title "Map", and the key is the Detail panel's, under the
//  picked point (#1089: on the map's footer it covered the map).
//

import ShellAgentDoor
import TEMCore
import XCTest
@testable import EMStudio

nonisolated final class MapsHeadingPickerTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The heading is a menu of `session.layers` that sets `session.setLayer`, the property the inspector row set; the inspector has
    /// no Map row left, only the line on what the map shows.
    func testTheHeadingOffersEveryMapKind() throws {
        let room = try ui("MapsRoom.swift")
        let header = try XCTUnwrap(room.components(separatedBy: "struct MapsMapControls: View {").dropFirst().first?
            .components(separatedBy: "struct MapsPointerReadout: View {").first)
        XCTAssertTrue(header.contains("Menu { Picker(\"Map\", selection: Binding(get: { session.layer }, set: { session.setLayer($0) })) { ForEach(session.layers) { layer in Text(layer.title).tag(layer) } }"))
        XCTAssertTrue(header.contains("Text(MapsRoomFormat.layerTitle(session.layer, stale: staleness != nil))"), "the menu's label names the map")
        XCTAssertTrue(room.contains("CentrePanel(title: \"Map\") {"), "beside the panel's title")
        XCTAssertTrue(room.contains("} controls: { MapsMapControls(session: appState.maps, staleness: appState.mapsStaleness) }"), "in the panel's controls")
        XCTAssertEqual(MapsRoomFormat.layerTitle(.ipf(.z)), "IPF-Z")
        XCTAssertEqual(MapsRoomFormat.layerTitle(.ipf(.z), stale: true), "IPF-Z · stale")
        XCTAssertTrue(header.contains(".accessibilityIdentifier(\"maps.layer\")"))
        XCTAssertTrue(room.contains("DEPARTURE from control-placement §1 (#1065"), "the picker in the centre is a named departure")
        let inspector = try ui("MapsRoomInspector.swift")
        XCTAssertFalse(inspector.contains("Picker(\"Map\""), "the inspector holds no Map row")
        XCTAssertFalse(inspector.contains("InspectorRow(\"Map\")"))
        XCTAssertTrue(inspector.contains("InspectorNote(note(session.layer))"), "the line on what the map shows stays")
        XCTAssertTrue(inspector.contains("InspectorValueRow(\"Source\""), "Source stays")
    }

    /// The key has no tab of its own: it is under the picked point on the Detail panel's Point tab (#1089), and the Grains table is a
    /// table of the bottom area (#1095), not a tab.
    @MainActor func testTheDetailHasNoKeyTab() {
        XCTAssertEqual(MapsDetailTab.allCases, [.point, .poleFigures, .odf, .histogram])
        XCTAssertFalse(MapsDetailTab.allCases.map(\.rawValue).contains("Key"))
        XCTAssertFalse(MapsDetailTab.allCases.map(\.rawValue).contains("Grains"))
        XCTAssertEqual(MapsRoomState().detailTab, .point)
        let tabs = MacTEMAgentDoor.mapsParameters.first { $0.name == "tab" }
        XCTAssertEqual(tabs?.kind, .choice(["point", "pole_figures", "odf", "histogram"]), "the door's tab choices follow")
        XCTAssertEqual(AgentDoorCoverage.controls["maps.layer"], .tool("set_maps"), "the door's layer goes through the same property")
        XCTAssertNil(AgentDoorCoverage.controls["maps.key.pane"])
    }

    /// The key on the map follows the map kind: IPF keys along the layer's axis, the phase legend, the grain map's line, a colour bar.
    func testTheKeyFollowsTheMapKind() throws {
        XCTAssertEqual(MapsKeyKind.of(.ipf(.z)), .ipf(.z))
        XCTAssertEqual(MapsKeyKind.of(.ipf(.x)), .ipf(.x))
        XCTAssertEqual(MapsKeyKind.of(.phase), .phases)
        XCTAssertEqual(MapsKeyKind.of(.derived(.grains)), .grains)
        XCTAssertEqual(MapsKeyKind.of(.derived(.kam)), .colourBar)
        XCTAssertEqual(MapsKeyKind.of(.property("CI")), .colourBar)
        XCTAssertEqual(MapsRoomFormat.keyUnit(.property("CI")), "CI")
        XCTAssertEqual(MapsRoomFormat.keyUnit(.derived(.kam)), "KAM (°)")
        let room = try ui("MapsRoom.swift")
        XCTAssertTrue(room.contains("MapsColourKey(session: session)"), "the key is the Detail panel's")
        XCTAssertFalse(room.contains("MapsKeyInset("), "not on the map's footer")
        XCTAssertTrue(room.contains("switch MapsKeyKind.of(session.layer) {"))
    }
}
