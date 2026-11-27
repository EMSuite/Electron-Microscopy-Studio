//
//  RoomSizeRuleTests.swift
//  The size rule (#905, plan row X13, pin Z1; `RoomSizeRule`): a file a room reads whole is refused before it is read when the room's
//  peak factor times its stored bytes passes this Mac's memory minus 4 GB, in a sentence that names the file, what the room needs, what
//  this Mac has and what works instead. Macs of 8, 16, 32 and 64 GB; a scan a room streams is never refused; a TIFF stack counts one
//  frame; the factors are never below the size table's measured peaks (docs/performance.md). Red before: the rule did not exist, and
//  a file too large opened until the Mac ran out of memory.
//

import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class RoomSizeRuleTests: XCTestCase {
    private let gib: UInt64 = 1 << 30
    private let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()

    /// A 9.6 GB EDS spectrum image needs about 29 GB at a factor of 3: refused on 8, 16 and 32 GB Macs, opened on 64 GB.
    func testASpectrumImageOnMacsOf8To64GB() {
        let stored = UInt64(9.6 * Double(gib))
        let sentence = "map_07.emd holds a 9.6 GB spectrum image. The EDS room needs about 29 GB to open it and this Mac has %@. "
            + "Open a binned copy, or open it on a Mac with 36 GB."
        for memory: UInt64 in [8, 16, 32] {
            XCTAssertEqual(RoomSizeRule.refusal(fileName: "map_07.emd", storedBytes: stored, room: .eds, memory: memory * gib),
                           String(format: sentence, "\(memory) GB"), "\(memory) GB")
        }
        XCTAssertNil(RoomSizeRule.refusal(fileName: "map_07.emd", storedBytes: stored, room: .eds, memory: 64 * gib))
    }

    /// An image of 1 GB opens on 8 GB (3 GB of 4); one of 2 GB needs 6 GB and is refused there, opened on 16 GB.
    func testAnImageAtTheEdgeOfAn8GBMac() {
        XCTAssertNil(RoomSizeRule.refusal(fileName: "a.tif", storedBytes: gib, room: .image, memory: 8 * gib))
        XCTAssertEqual(RoomSizeRule.refusal(fileName: "b.tif", storedBytes: 2 * gib, room: .image, memory: 8 * gib),
                       "b.tif holds a 2 GB image. The Image room needs about 6 GB to open it and this Mac has 8 GB. "
                           + "Open a binned or cropped copy, or open it on a Mac with 16 GB.")
        XCTAssertNil(RoomSizeRule.refusal(fileName: "b.tif", storedBytes: 2 * gib, room: .image, memory: 16 * gib))
    }

    /// A cube no Mac holds says so instead of naming one.
    func testACubeNoMacHolds() throws {
        let sentence = try XCTUnwrap(RoomSizeRule.refusal(fileName: "huge.hspy", storedBytes: 200 * gib, room: .eels, memory: 64 * gib))
        XCTAssertTrue(sentence.hasSuffix("Open a binned copy; no Mac holds it whole."), sentence)
    }

    /// The Patterns and Maps rooms stream their scans: the rule never refuses a file only they read; a file with a cube is held to
    /// the cube's room.
    func testAScanThatStreamsIsNotRefused() {
        let scan = FileInventory(ebsdPatterns: true)
        XCTAssertNil(RoomSizeRule.refusal(fileName: "scan.h5", inventory: scan, storedBytes: 100 * gib, memory: 8 * gib))
        let cube = FileInventory(image: true, eelsSpectrumImage: true)
        XCTAssertTrue(RoomSizeRule.refusal(fileName: "si.dm4", inventory: cube, storedBytes: 4 * gib, memory: 8 * gib)?
            .contains("The EELS room") == true)
    }

    /// A Velox file or a HyperSpy file with several images is read an image or a frame at a time: the Image room does not hold it
    /// to the file; its spectrum image still is. Red before (review): a 5 GB Velox frame series was refused on a 16 GB Mac.
    func testAFileReadAFrameAtATimeIsNotHeldToTheFile() {
        let images = FileInventory(image: true)
        for name in ["series.emd", "frames.hspy", "run.emi"] {
            XCTAssertNil(RoomSizeRule.refusal(fileName: name, inventory: images, storedBytes: 5 * gib, memory: 16 * gib), name)
        }
        XCTAssertNotNil(RoomSizeRule.refusal(fileName: "frame.dm4", inventory: images, storedBytes: 5 * gib, memory: 16 * gib))
        let cube = FileInventory(image: true, edsSpectrumImage: true)
        XCTAssertTrue(RoomSizeRule.refusal(fileName: "map.emd", inventory: cube, storedBytes: 5 * gib, memory: 16 * gib)?
            .contains("The EDS room") == true)
    }

    /// A TIFF stack is read a frame at a time: the rule counts one frame, not the file; a single image counts the file.
    func testAStackCountsOneFrame() throws {
        let stack = try ImageStackTests.tempStack(frames: 8)
        defer { try? FileManager.default.removeItem(at: stack) }
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: stack.path)[.size] as? NSNumber).uint64Value
        XCTAssertEqual(RoomSizeRule.readBytes(path: stack.path), size / 8)
    }

    /// Pin Z1: a room's factor is never below the peak factor the size table measured for it (docs/performance.md); rows without a
    /// number yet are skipped.
    func testTheFactorsHoldTheMeasuredPeaks() throws {
        let doc = try String(contentsOf: root.appendingPathComponent("docs/performance.md"), encoding: .utf8)
        let section = try XCTUnwrap(doc.components(separatedBy: "## Size table").dropFirst().first, "the size table section")
        for line in section.split(separator: "\n") where line.hasPrefix("| ") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count > 7, let room = RoomSizeRule.Room(rawValue: cells[1]), let measured = Double(cells[7]) else { continue }
            XCTAssertGreaterThanOrEqual(RoomSizeRule.peakFactor(room), measured, "\(cells[2]): the \(room.rawValue) room's factor")
        }
    }

    /// The Open refuses a file this Mac cannot hold before any reader runs: no row, no room, and the alert says why. Red before: the
    /// file was read.
    @MainActor func testTheOpenRefusesBeforeReading() async throws {
        let source = try XCTUnwrap(Bundle(for: RoomSizeRuleTests.self).url(forResource: "planted-2d", withExtension: "dm4"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("size-rule-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("planted.dm4")
        try FileManager.default.copyItem(at: source, to: url)
        let state = AppState(launch: LaunchOptions(arguments: []))
        state.physicalMemory = RoomSizeRule.margin + 1024   // a kilobyte left over: the file needs more
        await state.open(urls: [url])?.value
        XCTAssertTrue(state.openItems.items.isEmpty, "no row was made, so nothing was read")
        let message = try XCTUnwrap(state.errorMessage)
        XCTAssertTrue(message.hasPrefix("planted.dm4 holds a "), message)
        XCTAssertTrue(message.contains("The Image room needs about"), message)
        XCTAssertTrue(message.contains("this Mac has 4 GB"), message)
    }
}
