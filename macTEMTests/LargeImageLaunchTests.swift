//
//  LargeImageLaunchTests.swift
//  `--demo-large-image <n>` (2.3 plan row Q4): the launch and first-picture budgets open a generated n x n 16-bit TIFF, so the sandboxed
//  app reads a file it wrote itself, of a size the journey names. Red before: no such flag; a launch could open only the 512 px demo.
//

import XCTest
import TEMSession
@testable import macTEM

nonisolated final class LargeImageLaunchTests: XCTestCase {

    @MainActor func testTheFlagTakesASideInRangeOnly() {
        XCTAssertEqual(LaunchOptions(arguments: ["--demo-large-image", "2048"]).demoLargeImageSide, 2048)
        XCTAssertEqual(LaunchOptions(arguments: ["--demo-large-image", "4096"]).demoLargeImageSide, 4096)
        XCTAssertNil(LaunchOptions(arguments: ["--demo-large-image"]).demoLargeImageSide, "no side after the flag")
        XCTAssertNil(LaunchOptions(arguments: ["--demo-large-image", "big"]).demoLargeImageSide)
        XCTAssertNil(LaunchOptions(arguments: ["--demo-large-image", "16384"]).demoLargeImageSide, "over 8192")
        XCTAssertNil(LaunchOptions(arguments: ["--demo-large-image", "32"]).demoLargeImageSide, "under 64")
        XCTAssertNil(LaunchOptions(arguments: []).demoLargeImageSide)
    }

    /// The file is written once, is the side asked for at 2 bytes a pixel after its header, and counts as a demo (not a recent file).
    func testTheFileIsWrittenOnceAsADemo() throws {
        let url = try DemoDocuments.largeImageFile(side: 300)
        defer { try? FileManager.default.removeItem(at: url) }
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 300 * 300 * 2)
        XCTAssertLessThan(size, 300 * 300 * 2 + 1024)
        let written = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        XCTAssertEqual(try DemoDocuments.largeImageFile(side: 300), url)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, written, "not written again")
        XCTAssertTrue(DemoDocuments.isWrittenDemo(url))
    }

    /// A launch with the flag opens the image in the Image room, drawn.
    @MainActor func testALaunchWithTheFlagOpensTheImage() async throws {
        let state = AppState(launch: LaunchOptions(arguments: ["--demo-large-image", "256"]))
        try await waitUntil("the generated image to open", seconds: 30) { state.presentation.canvas != nil }
        let url = try DemoDocuments.largeImageFile(side: 256)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(state.imageSession.url, url)
        XCTAssertNil(state.openItems.selected?.readFailure)
        XCTAssertEqual(state.navigation.workspaceArea, .image)
    }
}
