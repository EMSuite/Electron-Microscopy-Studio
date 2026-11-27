//
//  SEMImageJourney.swift
//  The Image room on the demo SEM image (a Thermo-style TIFF, 512 x 471 with a 29-row databar; design §9): the Info tab's Acquisition
//  section names the detector, the HV and the databar; the Display section says the databar is hidden (Settings > Images' default) and
//  the Size row says the scan alone (442 rows); unticking Settings > Images > Hide the SEM databar draws the 29 rows as a strip under
//  the picture while the image stays the scan (442 rows), ticking it removes the strip again (#626). Each step's screenshot is the
//  record of the strip for the taste check.
//

import XCTest

nonisolated final class SEMImageJourney: Journey {
    @MainActor private func infoTab() {
        let picker = waitFor("inspector.tabPicker", timeout: 20)
        (picker.radioButtons["Info"].exists ? picker.radioButtons["Info"] : picker.buttons["Info"]).click()
    }

    /// Settings (⌘,) > Images > Hide the SEM databar, set to `hidden`; the window is closed again (⌘W) so the dataset window is in front.
    @MainActor private func setDatabarHidden(_ hidden: Bool) {
        app.typeKey(",", modifierFlags: .command)
        waitFor("settings.sidebar.images", timeout: 20).click()
        let toggle = waitFor("settings.images.cropDatabar", timeout: 20)
        if ((toggle.value as? Int) == 1) != hidden { toggle.click() }
        XCTAssertEqual((toggle.value as? Int) == 1, hidden)
        app.typeKey("w", modifierFlags: .command)
    }

    @MainActor func testTheAcquisitionRowsAndTheDatabarControl() throws {
        try step("launch with the demo SEM image") {
            launch(["--demo-sem-tiff-fixture"])
            XCTAssertTrue(app.staticTexts["Demo SEM image.tif"].firstMatch.waitForExistence(timeout: 30) || element("toolbar.display.idle").waitForExistence(timeout: 30))
        }
        try step("Display says the databar is hidden") {
            showInspector(waitingFor: "image.sem.databarNote")
            let note = waitFor("image.sem.databarNote")
            XCTAssertTrue(((note.value as? String) ?? note.label).contains("Databar hidden"), "hiding the databar is the default")
        }
        try step("the Info tab's Acquisition section names the file's record") {
            infoTab()
            XCTAssertTrue((waitFor("image.sem.detector", timeout: 20).value as? String)?.contains("ETD") == true)
            XCTAssertTrue((waitFor("image.sem.hv").value as? String)?.contains("15 kV") == true)
            XCTAssertTrue((waitFor("image.sem.workingDistance").value as? String)?.contains("10 mm") == true)
            XCTAssertTrue((waitFor("image.sem.databar").value as? String)?.contains("29 rows") == true)
            XCTAssertTrue(app.staticTexts["512 × 442 px"].firstMatch.waitForExistence(timeout: 10), "the Size row is the scan alone")
        }
        try step("Settings > Images shows the databar as a strip under the picture") {
            setDatabarHidden(false)
            let strip = waitFor("image.sem.databarStrip", timeout: 20)
            let picture = waitFor("image.view")
            XCTAssertEqual(strip.frame.width, picture.frame.width, accuracy: 1, "the strip is as wide as the picture")
            XCTAssertEqual(strip.frame.minY, picture.frame.maxY, accuracy: 1, "the strip sits right under the picture")
            XCTAssertGreaterThan(strip.frame.height, 0)
            infoTab()
            XCTAssertTrue(app.staticTexts["512 × 442 px"].firstMatch.waitForExistence(timeout: 10), "the image stays the scan alone")
        }
        try step("Settings > Images hides it again") {
            setDatabarHidden(true)
            XCTAssertTrue(element("image.sem.databarStrip").waitForNonExistence(timeout: 10))
            infoTab()
            XCTAssertTrue(app.staticTexts["512 × 442 px"].firstMatch.waitForExistence(timeout: 10))
        }
    }
}
