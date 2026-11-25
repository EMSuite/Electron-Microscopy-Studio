//
//  WelcomeRecentsTests.swift
//  The welcome canvas lists the recent files (#802): one row per file File > Open Recent lists, in its order and with its titles,
//  each with the folder it sits in (the home folder written "~"), and the line that says a file can be dropped.
//

import XCTest
@testable import macTEM

nonisolated final class WelcomeRecentsTests: XCTestCase {

    /// Mutation: the rows lose the recents' order, take another title than the menu's, or show the whole home path - red.
    func testTheRowsAreTheMenusFilesWithTheirFolders() {
        let paths = ["/Users/a/data/AA6060 SAED.dm4", "/Volumes/Lab/maps/grain map 03.h5", "/Users/a/b.tif"]
        let titles = ["AA6060 SAED.dm4", "grain map 03.h5", "b.tif"]
        let rows = WelcomeRecents.rows(paths: paths, titles: titles, home: "/Users/a")
        XCTAssertEqual(rows.map(\.path), paths)
        XCTAssertEqual(rows.map(\.title), titles)
        XCTAssertEqual(rows.map(\.folder), ["~/data", "/Volumes/Lab/maps", "~"])
        XCTAssertEqual(WelcomeRecents.rows(paths: ["/Users/ab/x.dm4"], titles: ["x.dm4"], home: "/Users/a").first?.folder, "/Users/ab",
                       "a sibling of the home folder is not under it")
    }

    func testNoRecentFileNoRows() {
        XCTAssertEqual(WelcomeRecents.rows(paths: [], titles: []), [])
        XCTAssertTrue(WelcomeRecents.dropHint.contains("drop a file"))
    }
}
