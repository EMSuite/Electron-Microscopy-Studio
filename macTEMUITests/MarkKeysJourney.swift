//
//  MarkKeysJourney.swift
//  The mark and spot cursor's keys (macEM#509, #510) in the real app: in the Image room, with Distance chosen, ⌥ and the arrows move the
//  cursor (⌥⇧ the coarse step), Return sets one end and then the other, and the Distance is listed, with no pointer drag. On a stack the
//  plain arrows still step the frames, now from the room's own keyed container, and the cursor's keys still make a mark there. In the
//  Diffraction room's Spot tool, ⌥⇧ and the arrows walk the cursor out to the {220} ring and Return adds the spot there. What this
//  shows that the unit tests cannot: the room's container has the keyboard after a click, on a stack too.
//

import XCTest

nonisolated final class MarkKeysJourney: Journey {
    /// ⌥⇧ and an arrow `times` times, then ⌥ and an arrow `fine` times, the same way.
    @MainActor private func walk(_ key: XCUIKeyboardKey, coarse times: Int, fine: Int = 0) {
        for _ in 0..<times { app.typeKey(key, modifierFlags: [.option, .shift]) }
        for _ in 0..<fine { app.typeKey(key, modifierFlags: .option) }
    }

    /// A Distance made with the keys alone: the pane is clicked once for the keyboard (a click is no mark), then ⌥-arrows and Return.
    @MainActor private func makeADistanceWithTheKeys() {
        showInspector(waitingFor: "image.tool")
        element("image.tool").radioButtons["Distance"].firstMatch.click()
        waitFor("image.view").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        walk(.leftArrow, coarse: 10, fine: 2)
        app.typeKey(.return, modifierFlags: [])
        walk(.rightArrow, coarse: 20, fine: 3)
        app.typeKey(.return, modifierFlags: [])
    }

    @MainActor func testTheKeysMakeADistanceOnTheDemoLattice() throws {
        try step("launch with the demo image") {
            launch(["--demo-fixture"])
            XCTAssertTrue(app.staticTexts["Demo lattice"].firstMatch.waitForExistence(timeout: 30))
        }
        try step("⌥-arrows and Return make a Distance") {
            makeADistanceWithTheKeys()
            let value = waitValue("image.mark", timeout: 20) { !$0.isEmpty }
            let (length, unit) = try XCTUnwrap(Self.leading(value), "no number in \"\(value)\"")
            XCTAssertEqual(unit, "nm", "the lattice is calibrated: \"\(value)\"")
            XCTAssertGreaterThan(length, 0, "\"\(value)\"")
        }
        try step("the status line reads the cursor's pixel after a key") {
            app.typeKey(.downArrow, modifierFlags: .option)
            waitStatus(containing: ["x ", "y ", "\u{00B7}"])
        }
    }

    @MainActor func testOnAStackTheArrowsStepFramesAndTheCursorKeysMakeAMark() throws {
        try step("launch with the demo stack") {
            launch(["--demo-stack-fixture"])
            showInspector(waitingFor: "image.stack.frame")
        }
        try step("→ steps to frame 2 after a click, ← back") {
            waitFor("image.view").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            app.typeKey(.rightArrow, modifierFlags: [])
            waitValue("image.stack.frame", timeout: 30) { $0 == "2" }
            app.typeKey(.end, modifierFlags: [])
            waitValue("image.stack.frame", timeout: 30) { $0 == "24" }
            app.typeKey(.home, modifierFlags: [])
            waitValue("image.stack.frame", timeout: 30) { $0 == "1" }
        }
        try step("⌥-arrows and Return make a Distance, and leave the frame alone") {
            makeADistanceWithTheKeys()
            waitValue("image.mark", timeout: 20) { !$0.isEmpty }
            XCTAssertEqual(element("image.stack.frame").value as? String, "1", "the cursor's keys stepped a frame")
        }
    }

    @MainActor func testTheKeysAddASpotInTheDiffractionRoom() throws {
        try step("launch with the demo pattern, Spot tool") {
            launch(["--demo-diffraction-fixture"])
            waitFor("diffraction.pane", timeout: 60)
            showInspector(waitingFor: "diffraction.tool")
            // A click in the Ring tool gives the pattern the keyboard and adds nothing (a ring is a drag).
            waitFor("diffraction.pane").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            element("diffraction.tool").radioButtons["Spot"].firstMatch.click()
        }
        try step("⌥⇧ and the arrows walk to the {220} spot at 105°, Return adds it") {
            // The cursor starts on the centre (256, 256); a coarse step is 5 px (1 % of 512). The planted {220} spot is at (241.6, 309.6).
            walk(.leftArrow, coarse: 3)
            walk(.downArrow, coarse: 11)
            app.typeKey(.return, modifierFlags: [])
            // The spot's row: its d, on the file's own scale (no ring has calibrated it here).
            let d = waitValue("diffraction.row.spot1.d", timeout: 60) { !$0.isEmpty }
            XCTAssertEqual(Journey.number(d) ?? .nan, 1.4419, accuracy: 0.05, "d: \(d)")
        }
    }
}
