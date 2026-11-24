//
//  ExportMethodsTests.swift
//  The methods record inside the Image room's exports (#817, plan row X1; `ExportMethods`, `ExportSnapshot`): the record the room
//  fills from its lineage equals its golden (macTEMTests/Fixtures/methods), a PNG and a CSV carry it and give it back, the data lines
//  of a CSV are untouched, and "Leave out file names" leaves the data file's name out of the PNG and its record. Red before: the
//  record, its embedding and the option did not exist.
//

import FormatoCore
import Foundation
import ImagoCore
import ShellExport
import TEMCore
import XCTest
@testable import macTEM

nonisolated final class ExportMethodsTests: XCTestCase {

    private static let fingerprint = String(repeating: "0123456789abcdef", count: 4)
    private static let app = MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.2.0 (42)")
    private static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/methods")

    private func source(fileName: String = "planted.dm4") -> ExportSource {
        let axis = AxisCalibration(scale: 0.1, unit: "nm")
        let image = CalibratedImage(width: 64, height: 32, pixels: [Float](repeating: 0, count: 64 * 32), x: axis, y: axis,
                                    fileName: fileName, source: "ImageList.1", voltage: nil, notes: [])
        return ExportSource(image: image, software: "Electron Microscopy Studio 2.2.0 (42)")
    }

    /// One distance mark, as the Image room records it (`SessionMarks`): its ends in pixels, its length in the file's unit.
    private func lineage() throws -> SessionLineage {
        var lineage = SessionLineage()
        _ = try lineage.add(kind: SessionLineage.Kind.distance,
                            parameters: ["x1": "10.5", "y1": "20.0", "x2": "40.25", "y2": "20.0"],
                            results: ["pixels": "29.75", "length": "2.975", "unit": "nm", "scale_x": "0.1", "unit_x": "nm",
                                      "scale_y": "0.1", "unit_y": "nm"],
                            recorded: 1_791_900_000_123)
        return lineage
    }

    private func record(drawn: [String] = ["the image as displayed (window, gamma and colormap)", "a scale bar"]) throws -> MethodsRecord {
        let source = ExportMethods.source(source(), byteCount: 4096, fingerprint: Self.fingerprint, kind: "image")
        let lineage = try lineage()
        return ExportMethods.imageRecord(app: Self.app, exportKind: "image-png", source: source, lineage: lineage, drawn: drawn)
    }

    // MARK: - The golden

    /// The Image room's record of a PNG with one distance mark: the source with its calibrations, the mark as a step with its ends,
    /// its length and pixels as results, the scales left to the source. The kits are the built ones (compared apart, so a kit
    /// update does not move the golden).
    func testTheImageRoomsRecordIsItsGolden() throws {
        var built = try record()
        XCTAssertEqual(built.kits, ExportMethods.kits)
        XCTAssertFalse(built.kits.isEmpty)
        built.kits = []
        let golden = try MethodsRecord.decode(String(contentsOf: Self.goldens.appendingPathComponent("image-png.json"), encoding: .utf8))
        XCTAssertEqual(built, golden)
    }

    // MARK: - Inside the files

    /// A PNG carries the record in one text chunk and gives it back equal; the record's JSON is in the chunk as written.
    func testAPNGCarriesItsRecord() throws {
        let record = try record()
        let display = ImageExport.Display(normalized: [Float](repeating: 0.5, count: 64 * 32), width: 64, height: 32, low: 0, high: 1,
                                          gamma: 1, lut: (0..<1024).map { UInt8(truncatingIfNeeded: $0 / 4) }, colormap: "gray",
                                          windowLow: nil, windowHigh: nil, rawRange: nil)
        let rendered = try ImageExport.render(source: source(), display: display, marks: [],
                                              options: ImageExport.Options(scaleBar: true, marks: false), methods: record)
        XCTAssertEqual(ExportMethods.record(inPNG: rendered.png), record)
        let chunk = try XCTUnwrap(FormatoPNG.textEntries(in: rendered.png).first { $0.keyword == ExportMethods.pngKeyword })
        XCTAssertEqual(chunk.value, try record.json())
        let plain = try ImageExport.render(source: source(), display: display, marks: [], options: ImageExport.Options(scaleBar: true, marks: false))
        XCTAssertNil(ExportMethods.record(inPNG: plain.png), "no record asked, none written")
    }

    /// A CSV carries the record on one `# methods:` line after its other header lines; every other line is as it was.
    func testACSVCarriesItsRecordAndKeepsItsLines() throws {
        let record = try record(drawn: ["the selected line profile's samples"])
        let csv = "# Electron Microscopy Studio line profile\n# file: planted.dm4\nposition,value\n0,1\n1,2\n"
        let written = try ExportMethods.embedding(record, inText: csv)
        XCTAssertEqual(ExportMethods.record(inText: written), record)
        let lines = written.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let line = try ExportMethods.textPrefix + record.json()
        XCTAssertEqual(lines[2], line)
        XCTAssertEqual(lines.filter { !$0.hasPrefix(ExportMethods.textPrefix) },
                       csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        XCTAssertNil(ExportMethods.record(inText: csv))
    }

    // MARK: - Leave out file names

    /// "Leave out file names": the record names its source "source 1", its calibrations' provenance too, and nothing else changes.
    func testLeavingOutFileNamesRenamesTheSourceEverywhereInTheRecord() throws {
        let record = try record()
        let anonymous = record.withoutFileNames()
        XCTAssertEqual(anonymous.sources.map(\.fileName), ["source 1"])
        XCTAssertEqual(anonymous.sources[0].calibrations.map(\.provenance.file), ["source 1", "source 1"])
        XCTAssertFalse(try anonymous.json().contains("planted"))
        XCTAssertEqual(anonymous.sources[0].fingerprint, record.sources[0].fingerprint)
        XCTAssertEqual(anonymous.steps, record.steps)
    }

    /// The Image room's OK with the option on: the PNG's Title and its record name "source 1", and the data file's name is nowhere in
    /// the bytes; with it off, the record names the file and says what was drawn.
    func testTheImageExportLeavesOutTheFileNameWhenAsked() async throws {
        let display = ImageExport.Display(normalized: [Float](repeating: 0.5, count: 64 * 32), width: 64, height: 32, low: 0, high: 1,
                                          gamma: 1, lut: (0..<1024).map { UInt8(truncatingIfNeeded: $0 / 4) }, colormap: "gray",
                                          windowLow: nil, windowHigh: nil, rawRange: nil)
        let snapshot = try ExportImageSnapshot(source: source(), display: display, marks: [], defaultName: "planted", directory: nil,
                                           message: "", defaults: ExportImageDefaults(scaleBar: true, marks: true, offersMarks: false),
                                           methods: record(drawn: []))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("methods-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let named = folder.appendingPathComponent("named.png")
        _ = try await snapshot.write(to: named, options: ImageExport.Options(scaleBar: true, marks: true))
        let namedRecord = try XCTUnwrap(ExportMethods.record(inPNG: Data(contentsOf: named)))
        XCTAssertEqual(namedRecord.sources.map(\.fileName), ["planted.dm4"])
        XCTAssertEqual(namedRecord.drawn, ["the image as displayed (window, gamma and colormap)", "a scale bar"],
                       "no marks: none drawn, none said")

        let anonymous = folder.appendingPathComponent("anonymous.png")
        _ = try await snapshot.write(to: anonymous, options: ImageExport.Options(scaleBar: true, marks: true), leaveOutFileNames: true)
        let bytes = try Data(contentsOf: anonymous)
        XCTAssertEqual(ExportMethods.record(inPNG: bytes)?.sources.map(\.fileName), ["source 1"])
        XCTAssertEqual(try FormatoPNG.textEntries(in: bytes).first { $0.keyword == "Title" }?.value, "source 1")
        XCTAssertNil(bytes.range(of: Data("planted".utf8)), "the data file's name is nowhere in the PNG")
    }
}
