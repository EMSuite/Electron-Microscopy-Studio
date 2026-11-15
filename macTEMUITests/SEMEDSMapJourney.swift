//
//  SEMEDSMapJourney.swift
//  The EDS room on an SEM-EDS map file (#342): the committed rosettasciio Bruker fixture `16x16_12bit_packed_8bit.bcf`, copied into a
//  temporary folder and opened with `--open`, lands in the shared EDS room with its spectrum and maps; Auto ID runs once on it. The unit tests
//  read .bcf, .spd, .pts and .spx (SEMEDSMapReaderTests); this drives the door and the map pane. Before every click the journey checks that
//  macEM is the frontmost app with its window on screen.
//

import XCTest

nonisolated final class SEMEDSMapJourney: Journey {
    /// The committed fixture, beside the repo's sources.
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tools/parity/sem/fixtures/rsciio/bruker/16x16_12bit_packed_8bit.bcf")

    private var folder: URL?

    override func tearDown() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        super.tearDown()
    }

    /// A copy of the fixture in a fresh temporary folder, so nothing the app writes lands in the repo.
    private func copiedFixture() throws -> String {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.fixture.path), "the fixture is not at \(Self.fixture.path)")
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("semeds-map-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        folder = made
        let copy = made.appendingPathComponent(Self.fixture.lastPathComponent)
        try FileManager.default.copyItem(at: Self.fixture, to: copy)
        return copy.path
    }

    @MainActor func testABrukerMapOpensInTheEDSRoomAndAutoIDRuns() throws {
        let file = try copiedFixture()
        try step("open the .bcf map; the EDS room shows its spectrum and maps") {
            launch(["--open", file])
            if !element("edx.room").waitForExistence(timeout: 20) { bringToFront(room: "edx", in: "spectroscopy", timeout: 60) }
            waitFor("edx.room", timeout: 60)
            waitFor("edx.spectrum", timeout: 60)
            waitFor("edx.maps", timeout: 60)
        }
        try step("Auto ID runs on the map's spectrum") {
            let autoID = waitFor("edx.autoID", timeout: 30)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: autoID)
            XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 90), .completed, "Auto ID never became available on the map")
            try requireFrontmost()
            autoID.click()
            let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: autoID)
            XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 90), .completed, "Auto ID never finished on the map")
            XCTAssertFalse(app.images["xmark.octagon.fill"].exists, "Auto ID or the maps show a failure")
        }
    }
}
