//
//  HelpMenuLinksTests.swift
//  The Help menu opens the documentation, tutorials and feedback (#753), and the welcome canvas offers the tutorials and New
//  Simulation beside the demo data (#802). Every address is a page the website serves: the paths below are the pages of
//  EMSuite/website (docs/electron-microscopy-studio/index.html, docs/tasks/index.html, docs/data/index.html, suite/releases.html,
//  support.html), checked against that repository when they were written; a moved page is changed here and in `HelpMenuLinks`.
//  Red before: `HelpMenuLinks` did not exist, the Help menu had the system's Help book item, and the welcome canvas had neither
//  the Tutorials link nor New Simulation.
//

import XCTest
@testable import macTEM

nonisolated final class HelpMenuLinksTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Mutation: an item drops out, the order changes, or an address names a page the website does not serve - red.
    func testTheMenuOpensTheWebsitesPagesInOrder() {
        XCTAssertEqual(HelpMenuLinks.all.map(\.title), [HelpMenuLinks.help.title, "Tutorials", "Example Data", "Release Notes",
                                                        HelpMenuLinks.support.title, "Send Feedback…"])
        XCTAssertTrue(HelpMenuLinks.help.title.hasSuffix(" Help"), HelpMenuLinks.help.title)
        XCTAssertTrue(HelpMenuLinks.support.title.hasSuffix(" Support"), HelpMenuLinks.support.title)
        let served = ["https://mac4dstem.com/docs/electron-microscopy-studio/", "https://mac4dstem.com/docs/tasks/",
                      "https://mac4dstem.com/docs/data/", "https://mac4dstem.com/suite/releases.html",
                      "https://mac4dstem.com/support.html"]
        XCTAssertEqual([HelpMenuLinks.help, HelpMenuLinks.tutorials, HelpMenuLinks.exampleData, HelpMenuLinks.releaseNotes,
                        HelpMenuLinks.support].map(\.url.absoluteString), served)
        XCTAssertEqual(HelpMenuLinks.all.count, 6)
        XCTAssertEqual(Set(HelpMenuLinks.all.map(\.id)).count, 6, "titles are the ForEach ids")
    }

    func testSendFeedbackWritesToTheProjectsAddress() throws {
        let url = HelpMenuLinks.sendFeedback.url
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "mail@mac4dstem.com")
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value?.hasSuffix(" feedback"), true)
        XCTAssertFalse(url.absoluteString.contains(" "), "the subject is percent-encoded")
    }

    /// The menu replaces the system's Help group, gives the documentation ⌘?, and keeps Report a Problem…; the welcome canvas has
    /// New Simulation (the menu's own call) and the Tutorials link to the same page as Help > Tutorials.
    func testTheMenuAndTheWelcomeCanvasAreWired() throws {
        let app = try source("macTEM/App/macTEMApp.swift")
        XCTAssertTrue(app.contains("CommandGroup(replacing: .help)"))
        XCTAssertTrue(app.contains("Button(HelpMenuLinks.help.title) { openURL(HelpMenuLinks.help.url) }\n                .keyboardShortcut(\"?\", modifiers: .command)"))
        XCTAssertTrue(app.contains("ForEach(HelpMenuLinks.guides)") && app.contains("ForEach(HelpMenuLinks.contact)"))
        XCTAssertTrue(app.contains("Button(\"Report a Problem…\") { openWindow(id: FeedbackWindow.id) }"))
        let welcome = try source("macTEM/UI/WorkspaceView.swift")
        XCTAssertTrue(welcome.contains("Button(\"New Simulation\") { appState.newSimulation() }"))
        XCTAssertTrue(welcome.contains("accessibilityIdentifier(\"welcome.newSimulation\")"))
        XCTAssertTrue(welcome.contains("Link(destination: HelpMenuLinks.tutorials.url)"))
        XCTAssertTrue(welcome.contains("accessibilityIdentifier(\"welcome.tutorials\")"))
    }
}
