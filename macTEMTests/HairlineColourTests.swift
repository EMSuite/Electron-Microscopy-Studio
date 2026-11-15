//
//  HairlineColourTests.swift
//  A pane's hairline is the system separator, which reads in light and dark mode (#627), as MacEMUI's map tiles draw theirs. Red while
//  ten panes drew `Color.white.opacity(0.08)`, which cannot be seen on a light window.
//

import XCTest

nonisolated final class HairlineColourTests: XCTestCase {
    private let ui = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("macTEM/UI")

    func testNoPaneDrawsAWhiteHairline() throws {
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no views under \(ui.path)")
        var separators = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains(".border(Color.white.opacity("), "\(file.lastPathComponent) draws a white hairline, unseen in light mode")
            separators += text.components(separatedBy: ".border(.separator)").count - 1
        }
        XCTAssertGreaterThanOrEqual(separators, 10, "the panes' hairlines are the system separator")
    }
}
