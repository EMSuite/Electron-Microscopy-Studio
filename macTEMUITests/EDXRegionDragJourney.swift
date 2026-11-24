//
//  EDXRegionDragJourney.swift
//  Why a UI journey cannot draw a region in the EDS room by dragging (#634). On the demo spectrum image, with the Rectangle tool,
//  each way a journey can drag is tried in turn on the colour mix, and the Regions table says whether it drew: XCUITest's own drag
//  at its default speed, the same drag slow with a hold at the end, the same drag after the pointer has hovered over the tile, and
//  real mouse events posted from the runner (guarded: macEM frontmost, both points in its window). Each attempt attaches what it
//  saw; a way that does not draw fails its own test, so one run names which of them reach the region's DragGesture. A diagnosis
//  run by hand (ui.yml), not a gate.
//

import XCTest

nonisolated final class EDXRegionDragJourney: Journey {
    private enum DragWay { case xcuiTest, xcuiTestSlow, xcuiTestAfterHover, realEvents }

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

    /// Real mouse events from the runner, as EDXRealFileJourney posts them; false when the guard refused.
    @MainActor private func realDrag(from a: CGPoint, to b: CGPoint) -> Bool {
        guard app.state == .runningForeground else { note("real events refused", "macEM is not frontmost"); return false }
        let w = app.windows.firstMatch.frame
        guard w.contains(a), w.contains(b) else { note("real events refused", "a point is outside the window \(w)"); return false }
        func post(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
        post(.mouseMoved, a); usleep(150_000)
        post(.leftMouseDown, a); usleep(100_000)
        for i in 1...20 {
            let t = Double(i) / 20
            post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); usleep(20_000)
        }
        post(.leftMouseUp, b)
        return true
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
            var sent = true
            switch way {
            case .xcuiTest: a.click(forDuration: 0.2, thenDragTo: b)
            case .xcuiTestSlow: a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5)
            case .xcuiTestAfterHover:
                a.hover(); usleep(300_000)
                a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5)
            case .realEvents: sent = realDrag(from: a.screenPoint, to: b.screenPoint)
            }
            drew = sent && regionRow(1).waitForExistence(timeout: 8)
            note("result", "\(way): \(sent ? (drew ? "drew Region 1" : "drew nothing") : "not sent")")
        }
        return drew
    }

    // One method per way, so the run's list of failed tests names the ways that do not draw (the runner prints failed names only).
    @MainActor func test1_XCUITestDragAtDefaultSpeedDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTest)) }
    @MainActor func test2_XCUITestSlowDragDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTestSlow)) }
    @MainActor func test3_XCUITestDragAfterAHoverDrawsARegion() throws { XCTAssertTrue(try drags(.xcuiTestAfterHover)) }
    @MainActor func test4_RealMouseEventsDrawARegion() throws { XCTAssertTrue(try drags(.realEvents)) }
}
