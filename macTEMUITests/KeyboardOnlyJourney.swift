//
//  KeyboardOnlyJourney.swift
//  Each room's verb runs without the pointer (2.3 plan row Q10; design-dna principle 7, every pointer action has a keyboard twin): the
//  app is launched on a demo document, its workspace is chosen with Go to <workspace> (⌘1…⌘5) and the verb is run with Workspace ›
//  Run (⌘R). No click: the keys go to the frontmost app, so each step checks first that macTEM is frontmost. The rooms: EDS (Quantify),
//  EELS (Run), Patterns (Process) and Maps (Segment). The menu's key table, that no key is used twice and every verb has its item, is
//  MenuKeyTableTests.
//  Indexing is not here: a workspace key enters its first room that has data (Patterns), and no key moves to another room of the same
//  workspace, so Index has no path without the pointer yet (its issue names the gap).
//

import XCTest

nonisolated final class KeyboardOnlyJourney: Journey {

    /// Go to the workspace (⌘ and its digit), wait for the room, wait until the verb is on, and run it with ⌘R.
    @MainActor private func runTheVerb(workspace digit: String, room: String, verb: String) throws {
        try requireFrontmost()
        app.typeKey(digit, modifierFlags: .command)
        waitFor(room, timeout: 30)
        let button = waitFor("workspace.primaryAction", timeout: 60)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 120), .completed, "\(verb) never became available")
        XCTAssertTrue(button.label.contains(verb), "the toolbar's verb is \(verb): \(button.label)")
        try requireFrontmost()
        app.typeKey("r", modifierFlags: .command)
    }

    @MainActor func testQuantifyInTheEDSRoomFromTheKeyboard() throws {
        try step("launch with the demo spectrum image") { launch(["--demo-spectrum-fixture"]) }
        try step("⌘4 then ⌘R: Quantify fills the composition table") {
            try runTheVerb(workspace: "4", room: "edx.room", verb: "Quantify")
            waitFor("edx.compositionTable", timeout: 120)
        }
    }

    @MainActor func testRunInTheEELSRoomFromTheKeyboard() throws {
        try step("launch with the demo EELS spectrum image") { launch(["--demo-eels-fixture"]) }
        try step("⌘4 then ⌘R: Run aligns the zero-loss peak") {
            try runTheVerb(workspace: "4", room: "eels.room", verb: "Run")
            _ = waitValue("eels.pipeline", timeout: 120) { $0.contains("Align current") }
        }
    }

    @MainActor func testProcessInThePatternsRoomFromTheKeyboard() throws {
        try step("launch with the demo EBSD dataset") { launch(["--demo-ebsd-fixture"]) }
        try step("⌘3 then ⌘R: Process shows the processed pattern") {
            try runTheVerb(workspace: "3", room: "patterns.room", verb: "Process")
            let processed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.allWords("patterns.pattern.title").contains("processed") },
                                                      object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [processed], timeout: 120), .completed, allWords("patterns.pattern.title"))
        }
    }

    @MainActor func testSegmentInTheMapsRoomFromTheKeyboard() throws {
        try step("launch with the shipped .ang") { launch(["--demo-ang"]) }
        try step("⌘3 then ⌘R: Segment finds the grains") {
            try runTheVerb(workspace: "3", room: "maps.map", verb: "Segment")
            _ = waitStatus(containing: ["Segmented"], timeout: 120)
        }
    }
}
