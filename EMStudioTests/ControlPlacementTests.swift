//
//  ControlPlacementTests.swift
//  The control-placement departures of #629, each changed or named where it lives: the Maps bottom pane's tabs run the full width
//  (§3), the Patterns room's tiles are buttons (a click, the keyboard and VoiceOver alike, not a tap gesture), and the three places that
//  keep their departure say why in one sentence (the toolbar's Image menu, Diffraction's own zoom, the pictures' focus ring). Red
//  before: the tabs `.fixedSize()`, the tiles `.onTapGesture`, no departure sentences.
//

import Foundation
import XCTest

nonisolated final class ControlPlacementTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    func testTheMapsTabsRunTheFullWidth() throws {
        let pane = try ui("MapsRoomAnalysis.swift")
        // The Detail panel's tabs (#1095; the results pane's before).
        let tabs = try XCTUnwrap(pane.components(separatedBy: "SegmentedControl(label: \"Detail\"").dropFirst().first?.components(separatedBy: "maps.results.tabs").first)
        XCTAssertTrue(tabs.contains(".frame(maxWidth: .infinity)"))
        XCTAssertFalse(pane.contains("Picker(\"Results\""), "a segmented Picker keeps its own width")
    }

    func testThePatternsTilesAreButtons() throws {
        let room = try ui("PatternsRoom.swift")
        XCTAssertTrue(room.contains("return Button { session.showMap(choice) } label: {"))
        XCTAssertFalse(room.contains(".onTapGesture { session.showMap(choice) }"))
        XCTAssertTrue(room.contains(".accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)"), "VoiceOver hears a button")
        XCTAssertTrue(room.contains(".accessibilityAction { session.showMap(choice) }"), "VoiceOver's press shows the map (the drive's AXPress did nothing)")
        XCTAssertTrue(room.contains(".allowsHitTesting(false)"), "the tile's Metal picture leaves the click to the button")
        let eels = try ui("EELSRoomInspector.swift")
        XCTAssertTrue(eels.contains(".accessibilityAction { selected = reference.id }"), "a reference row's press picks it")
    }

    func testEachKeptDepartureIsNamed() throws {
        XCTAssertTrue(try ui("ContentView.swift").contains("DEPARTURE from control-placement §1 (#1048"), "the toolbar's Export")
        XCTAssertTrue(try ui("DiffractionRoom.swift").contains("DEPARTURE from control-placement §6 (#629)"), "Diffraction's own zoom")
        XCTAssertTrue(try ui("WorkspaceView.swift").contains("DEPARTURE from the system focus ring (#629)"), "the picture's focus ring")
    }
}
