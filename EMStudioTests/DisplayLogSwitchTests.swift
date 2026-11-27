//
//  DisplayLogSwitchTests.swift
//  The Display section's two log switches read apart (#1042): the picture's is "Log intensity", the histogram's log y-axis is the
//  histogram's own (EMSuiteUI's `HistogramChart`, its footer).
//  Red before: the picture's switch row read "Log", three rows under the histogram's "Log y-axis".
//

import XCTest
@testable import EMStudio

nonisolated final class DisplayLogSwitchTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testThePicturesLogSwitchIsNamedForWhatItChanges() throws {
        XCTAssertEqual(ImageRoomDisplayRows.logTitle, "Log intensity")
        let rows = try source("EMStudio/UI/ImageRoomDisplay.swift")
        XCTAssertTrue(rows.contains("InspectorRow(Self.logTitle) {"))
        XCTAssertTrue(rows.contains("Toggle(Self.logTitle, isOn: log)"), "VoiceOver reads the row's name")
        XCTAssertFalse(rows.contains("InspectorRow(\"Log\")"))
    }
}
