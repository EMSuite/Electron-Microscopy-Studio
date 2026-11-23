//
//  EDXRegionDragJourney.swift
//  Why a UI journey cannot draw a region in the EDS room by dragging (#634). On the demo spectrum image, with the Rectangle tool,
//  each way a journey can drag is tried in turn on the colour mix, and the Regions table says whether it drew: XCUITest's own drag
//  at its default speed, the same drag slow with a hold at the end, the same drag after the pointer has hovered over the tile, and
//  real mouse events posted from the runner (guarded: macEM frontmost, both points in its window). Each attempt attaches what it
//  saw, so one run names which of them reach the region's DragGesture. A diagnosis, not a gate: it fails only when the room never
//  showed the tools.
//

import XCTest

nonisolated final class EDXRegionDragJourney: Journey {
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

    @MainActor func testWhichDragDrawsARegion() throws {
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
        var drawn = 0
        var results: [String] = []
        // Each attempt draws in its own quarter of the tile, so a later one never lands on an earlier region's handles.
        func attempt(_ name: String, from: CGVector, to: CGVector, _ body: (XCUICoordinate, XCUICoordinate) -> Bool) throws {
            try step(name) {
                let a = mix.coordinate(withNormalizedOffset: from), b = mix.coordinate(withNormalizedOffset: to)
                let sent = body(a, b)
                let drew = sent && regionRow(drawn + 1).waitForExistence(timeout: 8)
                if drew { drawn += 1 }
                let line = "\(name): \(sent ? (drew ? "drew Region \(drawn)" : "drew nothing") : "not sent")"
                results.append(line); note(name, line)
            }
        }
        try attempt("XCUITest drag, default speed", from: CGVector(dx: 0.1, dy: 0.1), to: CGVector(dx: 0.4, dy: 0.4)) { a, b in
            a.click(forDuration: 0.2, thenDragTo: b); return true
        }
        try attempt("XCUITest drag, slow, held at the end", from: CGVector(dx: 0.6, dy: 0.1), to: CGVector(dx: 0.9, dy: 0.4)) { a, b in
            a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5); return true
        }
        try attempt("XCUITest drag after a hover", from: CGVector(dx: 0.1, dy: 0.6), to: CGVector(dx: 0.4, dy: 0.9)) { a, b in
            a.hover(); usleep(300_000)
            a.click(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5); return true
        }
        try attempt("real mouse events from the runner", from: CGVector(dx: 0.6, dy: 0.6), to: CGVector(dx: 0.9, dy: 0.9)) { a, b in
            realDrag(from: a.screenPoint, to: b.screenPoint)
        }
        note("summary", results.joined(separator: "\n"))
    }
}
