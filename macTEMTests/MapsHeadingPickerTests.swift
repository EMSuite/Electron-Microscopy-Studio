//
//  MapsHeadingPickerTests.swift
//  The Maps room's map is chosen in the map pane's heading and its colour key sits on the map (#1065, approved 25 Nov 2026): the
//  heading's menu offers every map kind the inspector's Map row offered, on the same property; the results have no Key tab; the key on
//  the map follows the map kind. Red before: the Map row in the inspector, a plain title in the heading, the Key tab, no `MapsKeyKind`.
//

import ShellAgentDoor
import TEMCore
import XCTest
@testable import macTEM

nonisolated final class MapsHeadingPickerTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The heading is a menu of `session.layers` that sets `session.setLayer`, the property the inspector row set; the inspector has
    /// no Map row left, only the line on what the map shows.
    func testTheHeadingOffersEveryMapKind() throws {
        let room = try ui("MapsRoom.swift")
        let header = try XCTUnwrap(room.components(separatedBy: "private var header: some View {").dropFirst().first?
            .components(separatedBy: "private func content(in size: CGSize)").first)
        XCTAssertTrue(header.contains("Menu { Picker(\"Map\", selection: Binding(get: { session.layer }, set: { session.setLayer($0) })) { ForEach(session.layers) { layer in Text(layer.title).tag(layer) } }"))
        XCTAssertTrue(header.contains("Text(MapsRoomFormat.mapTitle(session.layer, stale: staleness != nil))"), "the menu's label names the map")
        XCTAssertTrue(header.contains(".accessibilityIdentifier(\"maps.layer\")"))
        XCTAssertTrue(room.contains("DEPARTURE from control-placement §1 (#1065"), "the picker in the centre is a named departure")
        let inspector = try ui("MapsRoomInspector.swift")
        XCTAssertFalse(inspector.contains("Picker(\"Map\""), "the inspector holds no Map row")
        XCTAssertFalse(inspector.contains("InspectorRow(\"Map\")"))
        XCTAssertTrue(inspector.contains("InspectorNote(note(session.layer))"), "the line on what the map shows stays")
        XCTAssertTrue(inspector.contains("InspectorValueRow(\"Source\""), "Source stays")
    }

    @MainActor func testTheResultsHaveNoKeyTab() {
        XCTAssertEqual(MapsResultsTab.allCases, [.grains, .poleFigures, .odf, .histogram])
        XCTAssertFalse(MapsResultsTab.allCases.map(\.rawValue).contains("Key"))
        XCTAssertEqual(MapsRoomState().resultsTab, .grains)
        let tabs = MacTEMAgentDoor.mapsParameters.first { $0.name == "tab" }
        XCTAssertEqual(tabs?.kind, .choice(["grains", "pole_figures", "odf", "histogram"]), "the door's tab choices follow")
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
        XCTAssertTrue(room.contains("MapsKeyInset(session: session)"), "the key is on the map's footer")
        XCTAssertTrue(room.contains("switch MapsKeyKind.of(session.layer) {"))
    }
}
