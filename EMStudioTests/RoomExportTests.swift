//
//  RoomExportTests.swift
//  One export path for the rooms (#269, UI/RoomFileTransfer.swift): one export file whose types hold every type a room passes to the save
//  panel (a missing one makes the panel fall back to the first type, MacEMUI#106), the rooms' panels through `roomImporter` and
//  `roomExporter`, and every `--export-dir` write through `ExportDirectoryFile` (so through `ExportFile.write`). A refactor: nothing
//  changes on screen. Red before: four FileDocument types (Patterns, Indexing, Maps, the Diffraction CSV), the panel block copied in four
//  rooms, and the Patterns, Indexing and Maps rooms writing the export folder with `FileManager` and `Data.write` beside `ExportFile`.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import EMStudio

nonisolated final class RoomExportTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Every type a room's export kind names, and the Maps room's PNG, PDF, SVG and CSV, is one the file writes. Red under: a kind's type left out.
    @MainActor func testTheExportFileWritesEveryTypeARoomExports() {
        let types = Set(RoomExportFile.readableContentTypes)
        let rooms = PatternsExportKind.allCases.map(\.contentType) + IndexingExportKind.allCases.map(\.contentType)
            + EELSExportKind.allCases.map(\.contentType) + [.png, .pdf, .svg, .commaSeparatedText]
        for type in rooms { XCTAssertTrue(types.contains(type), "\(type.identifier)") }
        XCTAssertEqual(RoomExportFile.readableContentTypes.count, types.count, "each type once")
        XCTAssertEqual(RoomExportFile(text: "a,µ\n").data, Data("a,µ\n".utf8))
    }

    /// One FileDocument in the app, and the four rooms present their panels through the shared modifiers.
    func testTheRoomsShareOneFileAndOnePanelPath() throws {
        let ui = ["PatternsRoom", "IndexingRoom", "MapsRoom", "EELSRoom", "DiffractionRoomInspector", "ImageRoomParticles"]
        for name in ui {
            let text = try source("EMStudio/UI/\(name).swift")
            XCTAssertFalse(text.contains(": FileDocument"), "\(name) declares its own export file")
            XCTAssertFalse(text.contains("EDXExportFile"), "\(name) uses the EDS room's file")
        }
        for name in ["PatternsRoom", "IndexingRoom", "MapsRoom", "EELSRoom"] {
            let text = try source("EMStudio/UI/\(name).swift")
            XCTAssertTrue(text.contains(".roomImporter(isPresented: $showImporter, types: importTypes"), name)
            XCTAssertTrue(text.contains(".roomExporter(isPresented:"), name)
            XCTAssertFalse(text.contains(".fileExporter(") || text.contains(".fileImporter("), name)
        }
    }

    /// The export-folder writes go through `ExportDirectoryFile`. Red under: a room making the folder and writing the bytes itself.
    func testEveryExportFolderWriteGoesThroughOneWriter() throws {
        for name in ["PatternsRoomState", "IndexingRoomState", "MapsRoomState", "EELSRoomState"] {
            let text = try source("EMStudio/App/\(name).swift")
            XCTAssertFalse(text.contains("FileManager.default.createDirectory"), name)
            XCTAssertFalse(text.contains("data.write(to:"), name)
            XCTAssertTrue(text.contains("try ExportDirectoryFile.write(data, named:"), name)
        }
    }

    /// The writer the rooms now share: the folder made, the bytes at "<dir>/<name>.<ext>" as given.
    func testTheFolderWriterMakesTheFolderAndKeepsTheBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("room-export-\(UUID().uuidString)/inner", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2])
        let url = try ExportDirectoryFile.write(bytes, named: "scan IPF-Z.png", into: dir)
        XCTAssertEqual(url, dir.appendingPathComponent("scan IPF-Z.png"))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
