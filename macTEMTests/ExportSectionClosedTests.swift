//
//  ExportSectionClosedTests.swift
//  Export starts closed in every room (control placement §2: "Fitting and Export start closed; the first two start open"; #637).
//  The Results room is the rule's "break when": a single table whose Export is the room's job, so its Export stays open.
//

import XCTest

nonisolated final class ExportSectionClosedTests: XCTestCase {

    private var uiFolder: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("macTEM/UI")
    }

    /// Every room's Export section passes `startsExpanded: false`. Red under: an Export section that opens by default (Diffraction,
    /// EELS and FFT did before #637).
    func testExportStartsClosedInEveryRoom() throws {
        let files = try FileManager.default.contentsOfDirectory(at: uiFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        var sections = 0
        for file in files where file.lastPathComponent != "ResultsRoomInspector.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("InspectorSection(\"Export\"") {
                sections += 1
                XCTAssertTrue(line.contains("startsExpanded: false"), "\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThanOrEqual(sections, 6, "the rooms' Export sections are found (Patterns, Indexing, Maps, Diffraction, EELS, FFT)")
    }
}
