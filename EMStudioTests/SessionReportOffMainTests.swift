//
//  SessionReportOffMainTests.swift
//  The SEM session report is set, encoded and written off the main actor (#251): `ExportPanels.sessionReportFile` runs in a
//  nonisolated context and writes the file the report's document makes.
//

import TEMCore
import XCTest
@testable import EMStudio

nonisolated final class SessionReportOffMainTests: XCTestCase {

    /// A Markdown report of one row, written from a nonisolated context: the file holds the document's text and the line names it.
    /// Red under: the report written only on the main actor (no `sessionReportFile`, or one isolated to it, does not compile here).
    func testTheReportIsWrittenOffTheMainActor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SessionReportOffMainTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = [SEMSessionRow(id: "dataset", kind: .dataset, label: "patterns_v2.h5", value: "HDF5 · 55 × 75 of 60 × 60", source: "Patterns",
                                  methods: [.patternReading])]
        let options = SEMSessionReport.Options(title: "demo session report", format: .markdown)
        let context = SEMSessionReport.Context(date: Date(timeIntervalSince1970: 1_800_000_000), software: "macEM 9.9.9 (1)",
                                               timeZone: TimeZone(identifier: "UTC") ?? .current)
        let url = directory.appendingPathComponent("demo session report.md")
        let line = try await ExportPanels.sessionReportFile(rows, options: options, context: context, to: url)
        XCTAssertTrue(line.hasPrefix("Exported demo session report.md"), line)
        let document = SEMSessionReport.document(rows, options: options, context: context)
        let expected = try XCTUnwrap(SEMReportFile.data(of: document, format: .markdown, context: context, directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), expected)
    }
}
