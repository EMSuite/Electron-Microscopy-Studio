//
//  FirstRunJourney.swift
//  The first run (#803, plan row Q17 of 2.3): from the welcome canvas to a first result in three clicks, and every room's empty state
//  offering its one verb. A UI-testing launch keeps Open Recent and the last session in memory and reads no kept crash report, so the
//  window opens as a first run does: the welcome canvas, with no Recent list and no report line.
//
//  The three clicks: Try Demo Data, the shipped SEM-EDS spectrum (BAM TM002), the toolbar's Quantify. The result is the composition
//  table with a weight percent for each element. Each click is counted; a fourth fails the journey.
//
//  The empty states: on a fresh launch every room can be entered, and each shows the one button that fills it: Open… for the
//  rooms that read images (the welcome canvas), Open Spectrum Image… (EDS), Open EELS Spectrum Image…, Open EBSD Dataset… (Patterns,
//  Indexing) and Open Orientation Map….
//

import XCTest

nonisolated final class FirstRunJourney: Journey {
    /// Each room (its sidebar row and its workspace's) and the identifier of the verb its empty state offers.
    static let emptyStates: [(room: String, workspace: String, verb: String)] = [
        ("image", "imaging", "welcome.openImage"),
        ("fft", "imaging", "welcome.openImage"),
        ("edx", "spectroscopy", "edx.openImage"),
        ("eels", "spectroscopy", "eels.openImage"),
        ("diffraction", "diffraction", "welcome.openImage"),
        ("patterns", "ebsd", "patterns.openDataset"),
        ("indexing", "ebsd", "indexing.openDataset"),
        ("maps", "ebsd", "maps.openMap"),
        ("results", "results", "welcome.openImage"),
    ]

    @MainActor private var clicks = 0

    /// A click the first run counts.
    @MainActor private func click(_ element: XCUIElement) throws {
        try requireFrontmost()
        clicks += 1
        element.click()
    }

    @MainActor func testWelcomeToAFirstResultInThreeClicks() throws {
        try step("a first launch shows the welcome canvas, with nothing recent and no report line") {
            launch()
            waitFor("welcome.openImage", timeout: 30)
            XCTAssertFalse(element("welcome.recent").exists, "a first run has no recent files")
            XCTAssertFalse(element("welcome.crashReport").exists, "a first run has no crash report")
        }
        try step("Try Demo Data, the shipped SEM-EDS spectrum") {
            try click(waitFor("welcome.tryDemo", timeout: 20))
            let item = app.menuItems["SEM-EDS Spectrum (BAM TM002)"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), "no SEM-EDS spectrum under Try Demo Data")
            try click(item)
            waitFor("edx.room", timeout: 30)
        }
        try step("Quantify, and the composition is read") {
            let verb = waitFor("workspace.primaryAction", timeout: 60)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: verb)
            XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 90), .completed, "Quantify never became available on the shipped spectrum")
            try click(verb)
            waitFor("edx.compositionTable", timeout: 120)
            let weights = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'edx.composition.' AND identifier ENDSWITH '.wt'"))
            XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 60), "the table holds no weight percent")
            XCTAssertLessThanOrEqual(clicks, 3, "a first result took \(clicks) clicks")
        }
    }

    @MainActor func testEveryRoomsEmptyStateOffersItsVerb() throws {
        try step("launch with no file") { launch() }
        for (room, workspace, verb) in Self.emptyStates {
            try step("\(room): the empty room offers \(verb)") {
                try requireFrontmost()
                bringToFront(room: room, in: workspace, timeout: 10)
                let button = waitFor(verb, timeout: 20)
                XCTAssertTrue(button.isEnabled, "\(room)'s \(verb) is dimmed on a first run")
            }
        }
    }
}
