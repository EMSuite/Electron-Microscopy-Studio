//
//  RoomSnapshotTests.swift
//  Snapshots of the app's rooms in light and in dark (#805, plan row P11 of 2.3), on EMSuiteUI's ShellSnapshotTesting (suite#137):
//  each room drawn at a fixed window size and compared with the PNG committed under __Snapshots__/RoomSnapshotTests/. They compare only
//  on CI's unit job on the org's Mac runner, where SNAPSHOTS=1 is set; elsewhere they skip (fonts and AppKit's controls differ
//  between Macs and macOS versions). A picture that
//  is new or differs fails the test, and CI puts it on the pr-pictures branch and in one comment on the pull request: that is the PR's
//  picture (CONTRIBUTING.md, Snapshot tests).
//
//  This first set is each room as a first run meets it: the welcome canvas, which the Image, FFT, Diffraction and Results rooms show
//  with no file, and the EDS, EELS, Patterns, Indexing and Maps rooms' own empty states with their one verb.
//

import ShellSnapshotTesting
import SwiftUI
import XCTest
@testable import macTEM

nonisolated final class RoomSnapshotTests: XCTestCase {
    static let windowSize = CGSize(width: 1100, height: 720)

    /// Draws `area` of a fresh window in both appearances and fails for each picture that is new or changed.
    @MainActor private func check(_ area: WorkspaceArea, file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(Snapshot.isEnabled, "snapshots are compared only where SNAPSHOTS=1 is set (CI's unit job)")
        let state = AppState()
        state.selectWorkspace(area)
        XCTAssertEqual(state.navigation.workspaceArea, area, "a fresh window enters every room")
        let view = ContentView().environment(state)
        // One picture to throw away first: the first window's `onAppear` turns the inspector on in `state` and SwiftUI animates
        // it in, so a picture of the first window catches it part way. Later windows start with it on and draw it at rest.
        _ = Snapshot.render(view, size: Self.windowSize, appearance: .light)
        for appearance in SnapshotAppearance.allCases {
            let result = Snapshot.verify(view, named: "\(area)-empty", size: Self.windowSize, appearance: appearance, testFile: file)
            if let failure = result.failure { XCTFail(failure, file: file, line: line) }
        }
    }

    @MainActor func testImageRoomEmpty() throws { try check(.image) }
    @MainActor func testEDSRoomEmpty() throws { try check(.edx) }
    @MainActor func testEELSRoomEmpty() throws { try check(.eels) }
    @MainActor func testPatternsRoomEmpty() throws { try check(.patterns) }
    @MainActor func testIndexingRoomEmpty() throws { try check(.indexing) }
    @MainActor func testMapsRoomEmpty() throws { try check(.maps) }
}
