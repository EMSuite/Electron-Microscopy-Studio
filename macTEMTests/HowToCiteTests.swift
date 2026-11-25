//
//  HowToCiteTests.swift
//  Help > How to Cite (#828): the app's citation is CITATION.cff's (title, author, licence, repository) and every reference a room
//  lists is an entry of its references, with that entry's DOI (or its address where it has none). Read from the repository's file.
//

import XCTest
@testable import macTEM

nonisolated final class HowToCiteTests: XCTestCase {
    private func citationFile() throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("CITATION.cff"), encoding: .utf8)
    }

    /// The value of a top-level `key:` line of CITATION.cff, quotes dropped.
    private func field(_ key: String, in text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(key): ") }
            .map { String($0.dropFirst(key.count + 2)).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
    }

    /// Mutation: the app's citation drifts from CITATION.cff (title, author, licence or repository) - red.
    func testTheCitationIsCITATIONcff() throws {
        let cff = try citationFile()
        XCTAssertEqual(field("title", in: cff), HowToCite.title)
        XCTAssertEqual(field("license", in: cff), HowToCite.license)
        XCTAssertEqual(field("repository-code", in: cff), HowToCite.repository)
        XCTAssertTrue(cff.contains("  - family-names: \(HowToCite.familyName)\n    given-names: \(HowToCite.givenNames)\n"), "the author")
        let text = HowToCite.text(version: "2.3.0", year: 2026)
        XCTAssertEqual(text, "Lobpreis, P. (2026). Electron Microscopy Studio (version 2.3.0) [Computer software]. GPL-3.0-only. "
                       + "https://github.com/EMSuite/Electron-Microscopy-Studio")
        let bibtex = HowToCite.bibtex(version: "2.3.0", year: 2026)
        XCTAssertTrue(bibtex.hasPrefix("@software{") && bibtex.contains("version = {2.3.0}") && bibtex.hasSuffix("}"))
    }

    /// Mutation: a room lists a package CITATION.cff does not reference, or with another DOI - red.
    func testEveryRoomReferenceIsInCITATIONcff() throws {
        let cff = try citationFile()
        let list = try XCTUnwrap(cff.range(of: "\nreferences:\n")).upperBound
        let references = String(cff[list...])
        for area in WorkspaceArea.allCases {
            for reference in HowToCite.references(for: area) {
                let entry = reference.link.hasPrefix("https://") ? "url: \"\(reference.link)\"" : "doi: \(reference.link)"
                XCTAssertTrue(references.contains(entry), "\(area): \(reference.title)'s \(entry) is not in CITATION.cff")
            }
        }
        XCTAssertFalse(HowToCite.references(for: .indexing).isEmpty)
        XCTAssertTrue(HowToCite.references(for: .diffraction).isEmpty, "py4DSTEM is not in CITATION.cff")
    }

    /// How to Cite and Report a Problem are Help items, not windows of the Window menu (#1032): both scenes drop their own Window-menu
    /// item, so How to Cite is listed once (Help) and Report a Problem no longer sits between Move & Resize and Objects. Red before:
    /// How to Cite in Help and Window, Report a Problem in Window.
    func testHowToCiteAndReportAProblemLeaveTheWindowMenu() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        func squeezed(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let cite = try squeezed("macTEM/App/HowToCite.swift")
        XCTAssertTrue(cite.contains("Window(\"How to Cite\", id: Self.id) { HowToCiteView(windows: windows) } // Help > How to Cite opens it;"), "the scene as read")
        XCTAssertTrue(cite.contains("a second How to Cite there (#1032). .commandsRemoved()"), "How to Cite's scene drops its Window-menu item")
        let app = try squeezed("macTEM/App/macTEMApp.swift")
        XCTAssertTrue(app.contains("FeedbackWindow(Self.helpLinks) // Not a Window-menu item"))
        XCTAssertTrue(app.contains("opens it (#753). .commandsRemoved()"), "Report a Problem's scene drops its Window-menu item")
        XCTAssertEqual(app.components(separatedBy: "Button(\"How to Cite\")").count - 1, 1, "How to Cite once in the commands")
    }
}
