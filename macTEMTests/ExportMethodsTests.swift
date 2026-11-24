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

/// The SEM rooms' records (#817): built from the record the session keeps of an export, each method a step with the package it
/// follows, the room's settings as the export's step, and the record inside a `.ang`, a CSV and a PNG by the file's extension.
nonisolated final class ExportMethodsSEMTests: XCTestCase {
    private static let fingerprint = String(repeating: "0123456789abcdef", count: 4)
    private static let app = MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.2.0 (42)")

    private func record() -> MethodsRecord {
        let file = SEMExportedFile(room: "Indexing", what: "EDAX ANG", source: "patterns_v2.h5",
                                   fields: [SEMSessionField("Layer", "IPF-Z"), SEMSessionField("Binning", "2")],
                                   methods: [.houghIndexing, .angWriter])
        let source = MethodsRecord.Source(fileName: "patterns_v2.h5", byteCount: 1000, fingerprint: Self.fingerprint, kind: "EBSD patterns",
                                          shape: [75, 55, 60, 60])
        return ExportMethods.semRecord(file, app: Self.app, exportKind: "indexing-edax-ang", source: source)
    }

    /// Hough indexing follows pyEBSDindex as kikuchipy drives it, the .ang writer orix: the steps name them in that order, and the
    /// settings are the export's own step (a number as a number).
    func testAnIndexingRecordNamesItsMethodsAndTheirPackages() {
        let record = record()
        XCTAssertEqual(record.room, "indexing")
        XCTAssertEqual(record.steps.map(\.name), [SEMMethod.houghIndexing.title, SEMMethod.angWriter.title, "EDAX ANG"])
        XCTAssertEqual(record.steps.map(\.method).prefix(2), [SEMMethod.houghIndexing.sentence, SEMMethod.angWriter.sentence])
        XCTAssertEqual(record.steps[0].reference?.name, "pyebsdindex")
        XCTAssertEqual(record.steps[1].reference?.name, "orix")
        XCTAssertEqual(record.references.map(\.name), ["pyebsdindex", "kikuchipy", "orix"])
        XCTAssertEqual(record.steps[2].settings, [MethodsRecord.Quantity(name: "Layer", value: .text("IPF-Z")),
                                                  MethodsRecord.Quantity(name: "Binning", value: .number(2))])
        XCTAssertEqual(record.drawn, ["EDAX ANG"])
        XCTAssertEqual(record.kits, ExportMethods.kits)
    }

    /// The record goes in by the file's extension: a `.ang` after its header, a CSV, a PNG; a method JSON and a `.ctf` stay as they were.
    func testTheRecordGoesInByTheFilesExtension() throws {
        let record = record()
        let ang = "# TEM_PIXperUM          1.000000\n# HEADER: End\n  0.1 0.2 0.3 0.0 0.0 1.0 0.9 1 1.0 0.5\n"
        let written = try ExportMethods.embedding(record, inFileWithExtension: "ang", data: Data(ang.utf8))
        let text = try XCTUnwrap(String(data: written, encoding: .utf8))
        XCTAssertEqual(ExportMethods.record(inText: text), record)
        XCTAssertEqual(text.split(separator: "\n").last, "  0.1 0.2 0.3 0.0 0.0 1.0 0.9 1 1.0 0.5", "the data line is as it was")
        let json = Data("{\"a\":1}".utf8)
        XCTAssertEqual(try ExportMethods.embedding(record, inFileWithExtension: "json", data: json), json)
        let ctf = Data("Channel Text File\nPrj test\n".utf8)
        XCTAssertEqual(try ExportMethods.embedding(record, inFileWithExtension: "ctf", data: ctf), ctf)
    }

    /// The source's fingerprint is the SHA-256 of its bytes ("abc": the FIPS 180-2 example) and its size.
    func testTheFingerprintIsTheFilesSHA256() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fingerprint-\(UUID().uuidString).bin")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let print = try ExportMethods.fingerprint(ofFileAt: url)
        XCTAssertEqual(print.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(print.byteCount, 3)
    }
}

/// The Particles section's and the Diffraction readout's CSVs (#817): the record names the segmentation's settings and counts, or
/// the readout's rings and spots, and sits on the CSV's `#` lines so the table reads as before.
nonisolated final class ExportMethodsTableTests: XCTestCase {
    private static let source = MethodsRecord.Source(fileName: "p.dm4", byteCount: 2000, fingerprint: String(repeating: "cd", count: 32),
                                                     kind: "image", shape: [ParticleTests.width, ParticleTests.height])
    private static let app = MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.2.0 (42)")

    /// The planted objects' CSV carries the settings it was cut with and what was found, scikit-image's steps each named.
    func testTheParticlesCSVCarriesItsSettingsAndCounts() throws {
        var settings = ParticleSettings()
        settings.sigma = 1
        let report = try ParticleCompute.analyse(pixels: ParticleTests.planted(), width: ParticleTests.width, height: ParticleTests.height,
                                                 settings: settings)
        let record = ExportMethods.particleRecord(app: Self.app, source: Self.source, settings: report.settings,
                                                  thresholdValue: report.thresholdValue, summary: report.summary)
        let csv = ParticleFormat.csv(report, scale: ParticleScale(perPixel: 0.5, unit: "nm"), fileName: "p.dm4")
        let written = try ExportMethods.embedding(record, inText: csv)
        let read = try XCTUnwrap(ExportMethods.record(inText: written))
        XCTAssertEqual(read, record)
        XCTAssertEqual(read.steps.map(\.name), ["Smoothing", "Threshold", "Objects"])
        XCTAssertEqual(read.steps[0].settings, [MethodsRecord.Quantity(name: "sigma", value: .number(1), units: "px")])
        XCTAssertEqual(read.steps[1].settings.first { $0.name == "threshold fraction of the range" }?.value, .number(0.5))
        XCTAssertEqual(read.results.first { $0.name == "counted" }?.value, .number(Double(report.summary.counted)))
        XCTAssertEqual(read.references, [MethodsRecord.Software(name: "scikit-image", version: "0.26.0")])
        XCTAssertEqual(written.split(separator: "\n").filter { !$0.hasPrefix("#") }, csv.split(separator: "\n").filter { !$0.hasPrefix("#") },
                       "the table is as it was")
    }

    /// The pattern's record tells a methods section where the centre came from, the scale with the wavelength and camera length its
    /// ring fit gave (five significant digits), what the rows were indexed against, and how many were measured and indexed.
    /// Mutation: the calibration step without its settings, the counts of the wrong kind, or the numbers in full - red.
    func testTheDiffractionRecordTellsTheCentreTheScaleAndTheIndexing() {
        let header = DiffractionExportHeader(fileName: "au.dm4", centreRow: 256, centreColumn: 256.5, centreSource: "a fitted ring",
                                             calibration: "fit Au {111}", deltaQ: 0.012500432, wavelengthAngstroms: 0.025079347,
                                             lengthPixels: 3190.1, lengthMM: 47.861234, fitVersusFilePercent: -0.987654, crystal: "Au",
                                             crystalSHA256: nil, kMax: 1.2, tolerancePercent: 2)
        let ring = DiffractionReadoutRow(id: UUID(), kind: .ring, number: 1, radiusPx: 34, q: 0.425, d: 2.355, family: "{111}",
                                         dListed: 2.3548, deltaPercent: 0.01, oddsText: nil, verdict: "matches", validation: "")
        let spot = DiffractionReadoutRow(id: UUID(), kind: .spot, number: 1, radiusPx: 80, q: 1, d: 1, family: nil, dListed: nil,
                                         deltaPercent: nil, oddsText: nil, verdict: "no family", validation: "")
        let record = ExportMethods.diffractionRecord(app: Self.app, source: Self.source, header: header, rows: [ring, spot])
        XCTAssertEqual(record.room, "diffraction")
        XCTAssertEqual(record.exportKind, "diffraction-readout-csv")
        XCTAssertEqual(record.steps.map(\.name), ["Centring", "Calibration", "Indexing"])
        XCTAssertEqual(record.steps[1].method, "a ring fit to the Au {111} ring of the standard")
        XCTAssertEqual(record.steps[1].settings, [MethodsRecord.Quantity(name: "Δq", value: .number(0.0125), units: "Å⁻¹ per pixel"),
                                                  MethodsRecord.Quantity(name: "wavelength", value: .number(0.025079), units: "Å"),
                                                  MethodsRecord.Quantity(name: "camera length", value: .number(47.861), units: "mm")])
        XCTAssertEqual(record.results.map(\.value), [.number(1), .number(1), .number(1), .number(-0.98765)])
        XCTAssertTrue(record.paragraph.contains("Centring used a fitted ring with centre row 256 px and centre column 256.5 px."),
                      record.paragraph)
        XCTAssertTrue(record.paragraph.contains("Calibration used a ring fit to the Au {111} ring of the standard with Δq 0.0125 Å⁻¹ per "
                                                    + "pixel, wavelength 0.025079 Å and camera length 47.861 mm."), record.paragraph)
        XCTAssertTrue(record.paragraph.contains("Indexing used the listed d-spacings of Au (d = 1/q) with tolerance 2 % and k_max 1.2 Å⁻¹."),
                      record.paragraph)
    }
}
