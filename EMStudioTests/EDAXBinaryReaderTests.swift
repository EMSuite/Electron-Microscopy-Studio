//
//  EDAXBinaryReaderTests.swift
//  The EDAX door (`EDAXOpening`, one `EBSDDataset` whose patterns stay in the file): a hexagonal grid refused, the `.ang` next to the
//  file paired by name as the dataset's crystal map, the patterns read by map position bit-exact. The reader's own parity against
//  kikuchipy 0.13.1 moved to FormatoKit with it (FormatoEBSDTests/EDAXBinaryReaderTests, #852).
//

import DiffractoOrientation
import FormatoCore
import TEMCore
import XCTest

nonisolated final class EDAXBinaryReaderTests: XCTestCase {

    static let fixturesFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func fixture(_ name: String) -> URL { fixturesFolder.appendingPathComponent(name) }

    // MARK: The door

    func testAHexagonalGridIsRefusedAtTheDoorInWords() throws {
        let url = Self.fixture("ebsd-edax-binary-hex.up2")
        XCTAssertNoThrow(try EDAXBinaryReader.read(url: url), "the reader reads it as kikuchipy does")
        XCTAssertThrowsError(try EDAXOpening.open(url: url)) { error in
            let text = (error as? EDAXReadError)?.text ?? ""
            XCTAssertTrue(text.contains("hexagonal grid"), text)
            XCTAssertTrue(text.contains("ebsd-edax-binary-hex.up2"), text)
        }
        XCTAssertEqual(FileRouting.inventory(path: url.path).refusal, "ebsd-edax-binary-hex.up2 was acquired on a hexagonal grid; only square-grid EBSD maps are read.")
        XCTAssertThrowsError(try EDAXOpening.open(url: Self.fixture("ebsd-tsl-hex.ang"))) { error in
            let text = (error as? EDAXReadError)?.text ?? ""
            XCTAssertTrue(text.contains("hexagonal grid"), text)
        }
    }

    func testTheANGNextToTheFileIsPairedByNameAndGivesAVersion1FileItsGrid() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("edax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let up1 = folder.appendingPathComponent("scan.up1")
        try FileManager.default.copyItem(at: Self.fixture("ebsd-edax-binary.up1"), to: up1)
        // Alone: nine patterns in one row, no map, kikuchipy's default detector; the patterns are the file's records, bit-exact.
        let alone = try EDAXOpening.open(url: up1)
        XCTAssertNil(alone.crystalMap)
        XCTAssertEqual(alone.format, .edaxBinary)
        XCTAssertEqual([alone.scanRows, alone.scanColumns], [1, 9])
        XCTAssertEqual(alone.notes, [])
        XCTAssertEqual(alone.detector.projectionCenters, [SIMD3(0.5, 0.5, 0.5)])
        let file = try EDAXBinaryReader.read(url: up1)
        XCTAssertEqual(alone.patterns.layout, .records(offset: file.patternOffset, recordBytes: file.bytesPerPattern, patternOffset: 0))
        XCTAssertEqual(try alone.allPatterns(), try EDAXBinaryReader.allPatterns(file))
        XCTAssertEqual(try EBSDPatternReader(alone).pattern(row: 0, column: 8), try EDAXBinaryReader.pattern(file, index: 8))
        XCTAssertEqual(FileRouting.inventory(path: up1.path), FileInventory(ebsdPatterns: true))
        // A 3 x 3 EDAX map with the same name: the scan takes its grid and step.
        let header = try String(contentsOf: Self.fixture("ebsd-tsl.ang"), encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("#") }
            .map { $0.replacingOccurrences(of: "NCOLS_ODD: 4", with: "NCOLS_ODD: 3").replacingOccurrences(of: "NCOLS_EVEN: 4", with: "NCOLS_EVEN: 3") }
        var rows: [String] = []
        for r in 0..<3 { for c in 0..<3 { rows.append("0.1 0.2 0.3 \(Double(c) * 2) \(Double(r) * 2) 100.0 0.5 1 1000 0.5") } }
        let ang = folder.appendingPathComponent("scan.ang")
        try (header + rows).joined(separator: "\n").appending("\n").write(to: ang, atomically: true, encoding: .utf8)
        let paired = try EDAXOpening.open(url: up1)
        let map = try XCTUnwrap(paired.crystalMap)
        XCTAssertEqual(map.pointCount, 9)
        XCTAssertEqual(map.shape, [3, 3])
        XCTAssertEqual(map.phaseIDs, [Int](repeating: 1, count: 9))
        XCTAssertEqual(map.phases.ids, [1])
        XCTAssertEqual(map.rotations[0], RotationConversions.eu2qu(SIMD3(0.1, 0.2, 0.3)))
        XCTAssertEqual(map.euler[0], SIMD3(0.1, 0.2, 0.3))
        XCTAssertEqual([paired.scanRows, paired.scanColumns], [3, 3])
        XCTAssertEqual(paired.stepX, 2)
        XCTAssertEqual(paired.stepY, 2)
        XCTAssertEqual(paired.notes, [])
        let angHeader = try ANGReader.read(url: ang).header
        XCTAssertEqual(paired.detector.projectionCenters, [paired.detector.brukerCenter(try XCTUnwrap(angHeader.projectionCenter), from: .tsl)], "the .ang's PC is TSL's")
        XCTAssertEqual(paired.sem.workingDistanceMM, angHeader.workingDistance)
        // Opened from the .ang side the same scan comes back, and the routing sends it to the Patterns room.
        let fromMap = try EDAXOpening.open(url: ang)
        XCTAssertEqual(fromMap.patterns.url, up1)
        XCTAssertEqual(fromMap, paired)
        XCTAssertEqual(FileRouting.inventory(path: ang.path), FileInventory(ebsdPatterns: true))
        XCTAssertEqual(try EBSDOpening.open(url: ang).dataset, paired)
        // A map of another point count is left out with a note; the patterns still open.
        try FileManager.default.removeItem(at: ang)
        try FileManager.default.copyItem(at: Self.fixture("ebsd-tsl.ang"), to: ang)
        let mismatched = try EDAXOpening.open(url: up1)
        XCTAssertNil(mismatched.crystalMap)
        XCTAssertEqual(mismatched.notes.count, 1)
        XCTAssertTrue(mismatched.notes[0].contains("12 points for 9 patterns"), mismatched.notes[0])
        XCTAssertEqual([mismatched.scanRows, mismatched.scanColumns], [1, 9])
        // A map alone, without its patterns: the pattern door refuses it with the sentence that names them (D-SEM-25); the routing sends it to
        // the Maps room (P3-04).
        try FileManager.default.removeItem(at: up1)
        XCTAssertThrowsError(try EDAXOpening.open(url: ang)) { error in
            XCTAssertTrue(((error as? EDAXReadError)?.text ?? "").hasPrefix("scan.ang is an orientation map without its patterns"), String(describing: error))
        }
        XCTAssertEqual(FileRouting.inventory(path: ang.path), FileInventory(orientationMap: true))
    }

    func testAnUnreadableCompanionLeavesANoteAndAnUnreadableMainFileThrows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("edax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let up2 = folder.appendingPathComponent("scan.up2")
        try FileManager.default.copyItem(at: Self.fixture("ebsd-edax-binary.up2"), to: up2)
        let ang = folder.appendingPathComponent("scan.ang")
        try "# GRID: SqrGrid\nnot a number\n".write(to: ang, atomically: true, encoding: .utf8)
        let scan = try EDAXOpening.open(url: up2)
        XCTAssertNil(scan.crystalMap)
        XCTAssertEqual(scan.notes.count, 1)
        XCTAssertTrue(scan.notes[0].hasPrefix("scan.ang next to it was not read:"), scan.notes[0])
        XCTAssertEqual([scan.scanRows, scan.scanColumns], [3, 4])
        XCTAssertThrowsError(try EDAXOpening.open(url: ang))
    }

    /// A companion `.ang` that reads but whose coordinates make no grid (here a second x that is NaN) is left out with the door's
    /// note, as an unreadable one is; the patterns open on their own. The `.ang` opened itself still fails. Red before: the open of
    /// the `.up2` threw the crystal map's refusal, which names neither file, and the patterns did not open.
    func testACompanionAngWhoseCoordinatesMakeNoGridLeavesANote() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("edax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let up2 = folder.appendingPathComponent("scan.up2")
        try FileManager.default.copyItem(at: Self.fixture("ebsd-edax-binary.up2"), to: up2)
        let header = try String(contentsOf: Self.fixture("ebsd-tsl.ang"), encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("#") }
            .map(String.init)
        let rows = ["0.1 0.2 0.3 0 0 100.0 0.5 1 1000 0.5", "0.1 0.2 0.3 nan 0 100.0 0.5 1 1000 0.5"]
        let ang = folder.appendingPathComponent("scan.ang")
        try (header + rows).joined(separator: "\n").appending("\n").write(to: ang, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ANGReader.read(url: ang).map.crystalMap()) { error in
            XCTAssertEqual(error as? CrystalMap.Refusal, .coordinates("x holds a value that is not a finite number"))
        }
        let scan = try EDAXOpening.open(url: up2)
        XCTAssertNil(scan.crystalMap)
        XCTAssertEqual([scan.scanRows, scan.scanColumns], [3, 4])
        XCTAssertEqual(scan.notes, ["scan.ang next to it was not read: The crystal map's coordinates make no grid: x holds a value that is not "
            + "a finite number."])
        XCTAssertEqual(try EBSDOpening.open(url: up2).dataset, scan)
        XCTAssertThrowsError(try EDAXOpening.open(url: ang), "the map opened itself keeps failing")
    }
}
