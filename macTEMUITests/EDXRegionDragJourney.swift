//
//  EDXRegionDragJourney.swift
//  A UI journey draws a region in the EDS room with XCUITest's own drag (#634). On the demo spectrum image, with the Rectangle tool,
//  a drag on the colour mix makes Region 1 in the Regions table: at XCUITest's default speed, slow with a hold at the end, and after a
//  hover. Each way is its own test, so a run's failed names say which way stopped drawing.
//
//  THE CAUSE OF #634 (run by hand on GitHub's macos-26, ui.yml, 24 Nov 2026, runs 45346124492 and 45354261419): XCUITest's own drag
//  does reach the region's DragGesture; all three ways above drew Region 1. What did not draw was the workaround: mouse events posted
//  with CGEvent from the UI-test runner (the same 20-step drag EDXRealFileJourney posted) drew nothing. The runner may synthesize
//  input through XCUITest, but a CGEvent it posts to the HID tap is not delivered to the app under test. The 31 Oct note that blamed
//  the tile's tap gestures (MapTileView) no longer holds: the tile's clicks sit inside the viewport and the region layer's drag comes
//  first. The journeys now drag with XCUITest. (EDXRealFileJourney's wheel still posts CGEvents and skips when they draw nothing.)
//

import XCTest

nonisolated final class EDXRegionDragJourney: Journey {
    private enum DragWay { case xcuiTest, xcuiTestSlow, xcuiTestAfterHover }

    @MainActor private func mixTile() -> XCUIElement { app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Colour mix map'")).firstMatch }
    /// The Regions table's row of the n-th region, present once a region is drawn.
    @MainActor private func regionRow(_ n: Int) -> XCUIElement { element("edx.regionTable.Region \(n).pixels") }

    @MainActor private func note(_ name: String, _ text: String) {
        let a = XCTAttachment(string: text); a.name = name; a.lifetime = .keepAlways; add(a)
        print("EDXRegionDragJourney: \(name): \(text)")
    }

    @MainActor private func chooseRectangle() {
        let picker = waitFor("inspector.tabPicker", timeout: 30)
        let tab = picker.buttons["Settings"]
        if tab.exists, !tab.isSelected { tab.click() }
        waitFor("edx.tool", timeout: 20).radioButtons.element(boundBy: 1).click()
    }

    /// One way of dragging on a fresh launch: true when the Regions table gained Region 1.
    @MainActor private func drags(_ way: DragWay) throws -> Bool {
        try step("launch with the demo spectrum image, Rectangle tool") {
            launch(["--demo-spectrum-fixture"])
            waitFor("workspace.edx", timeout: 30).click()
            waitFor("edx.room", timeout: 30)
            waitFor("workspace.primaryAction", timeout: 60)
            XCTAssertTrue(mixTile().waitForExistence(timeout: 60), "no colour mix tile")
            chooseRectangle()
        }
        let mix = mixTile()
        note("mix tile", "frame \(mix.frame), hittable \(mix.isHittable)")
        var drew = false
        try step("drag \(way)") {
            let a = mix.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            let b = mix.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
            switch way {
            case .xcuiTest: a.click(forDuration: 0.2, thenDragTo: b)
            case .xcuiTestSlow: a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5)
            case .xcuiTestAfterHover:
                a.hover(); usleep(300_000)
                a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5)
            }
            drew = regionRow(1).waitForExistence(timeout: 8)
            note("result", "\(way): \(drew ? "drew Region 1" : "drew nothing")")
        }
        return drew
    }

    // One method per way, so the run's list of failed tests names a way that stopped drawing (the runner prints failed names only).
    @MainActor func test1_XCUITestDragAtDefaultSpeedDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTest)) }
    @MainActor func test2_XCUITestSlowDragDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTestSlow)) }
    @MainActor func test3_XCUITestDragAfterAHoverDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTestAfterHover)) }
}
