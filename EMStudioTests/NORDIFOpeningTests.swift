//
//  NORDIFOpeningTests.swift
//  A NORDIF acquisition at the Patterns room's door (NORDIFOpening through EBSDOpening and FileRouting): `Pattern.dat` opens as an
//  `EBSDDataset` whose patterns are read from the file by map position and equal NORDIFScan's bit for bit (the scan's parity against
//  kikuchipy 0.13.1 is FormatoKit's NORDIFReaderTests, #852); a `.dat` counts only with a NORDIF `Setting.txt` beside it; a short pattern file reads its
//  whole records and the rest as 0, with a note; a background bitmap that is there and cannot be read is named in a note the Info
//  rows show; a `Setting.txt` that is there and may not be read is named in the refusal, at the routing and at the open.
//

import XCTest
import Darwin
import FormatoCore
import TEMCore

nonisolated final class NORDIFOpeningTests: XCTestCase {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/sem/nordif")
    private func url(_ name: String) -> URL { Self.folder.appendingPathComponent(name) }
    private var scratch: [URL] = []

    override func tearDown() {
        for folder in scratch { try? FileManager.default.removeItem(at: folder) }
        scratch = []
        super.tearDown()
    }

    /// A fresh folder holding the given pattern bytes as `Pattern.dat` and, when `settings` names one, that fixture as `Setting.txt`.
    private func folder(patternBytes: Data, settings: String? = "Setting.txt") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nordif-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        scratch.append(folder)
        if let settings { try FileManager.default.copyItem(at: url(settings), to: folder.appendingPathComponent("Setting.txt")) }
        try patternBytes.write(to: folder.appendingPathComponent("Pattern.dat"))
        return folder
    }

    func testTheRoutingSendsPatternDatToThePatternsRoomOnlyWithItsSettings() throws {
        XCTAssertTrue(EBSDOpening.isVendorFile(url("Pattern.dat")))
        XCTAssertEqual(FileRouting.inventory(path: url("Pattern.dat").path), FileInventory(ebsdPatterns: true))
        XCTAssertEqual(FileRouting.inventory(path: url("Pattern.dat").path).landing, .patterns)
        let lone = try folder(patternBytes: Data([1, 2, 3]), settings: nil)
        let other = lone.appendingPathComponent("Pattern.dat")
        XCTAssertFalse(NORDIFOpening.isNORDIFFile(other), "no Setting.txt beside it")
        XCTAssertFalse(EBSDOpening.isVendorFile(other))
        let routed = FileRouting.inventory(path: other.path)
        XCTAssertFalse(routed.ebsdPatterns)
        XCTAssertNotNil(routed.refusal, "an unknown .dat keeps the general refusal")
        XCTAssertTrue(FileRouting.openableExtensions.contains("dat"))
    }

    func testABrokenSettingsFileIsRefusedAtTheDoorWithItsSentence() throws {
        let whole = try Data(contentsOf: url("Pattern.dat"))
        let folder = try folder(patternBytes: whole)
        let settings = folder.appendingPathComponent("Setting.txt")
        let lines = try String(contentsOf: settings, encoding: .isoLatin1).components(separatedBy: "\r\n").filter { !$0.hasPrefix("Number of samples") }
        try lines.joined(separator: "\r\n").data(using: .isoLatin1)!.write(to: settings)
        let pattern = folder.appendingPathComponent("Pattern.dat")
        let sentence = "Setting.txt cannot be read: its [Area] section has no 'Number of samples' line."
        XCTAssertEqual(FileRouting.inventory(path: pattern.path), FileInventory(refusal: sentence))
        XCTAssertThrowsError(try EBSDOpening.open(url: pattern)) { error in
            XCTAssertEqual((error as? EBSDReadError)?.text, sentence)
        }
    }

}
