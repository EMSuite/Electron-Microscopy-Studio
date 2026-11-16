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
        let tabs = try XCTUnwrap(pane.components(separatedBy: "Picker(\"Bottom pane\"").last?.components(separatedBy: "maps.bottom.tabs").first)
        XCTAssertTrue(tabs.contains(".frame(maxWidth: .infinity)"))
        XCTAssertFalse(tabs.contains(".fixedSize()"))
    }

    func testThePatternsTilesAreButtons() throws {
        let room = try ui("PatternsRoom.swift")
        XCTAssertTrue(room.contains("return Button { session.showMap(choice) } label: {"))
        XCTAssertFalse(room.contains(".onTapGesture { session.showMap(choice) }"))
    }

    func testEachKeptDepartureIsNamed() throws {
        XCTAssertTrue(try ui("ContentView.swift").contains("DEPARTURE from control-placement §1"), "the toolbar's Image menu")
        XCTAssertTrue(try ui("DiffractionRoom.swift").contains("DEPARTURE from control-placement §6 (#629)"), "Diffraction's own zoom")
        XCTAssertTrue(try ui("WorkspaceView.swift").contains("DEPARTURE from the system focus ring (#629)"), "the picture's focus ring")
    }
}
