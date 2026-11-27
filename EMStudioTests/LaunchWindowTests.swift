//
//  LaunchWindowTests.swift
//  A background launch that came up with no window opens one itself (EMSuite/Electron-Microscopy-Studio#727): File > New Window, as ⌘N did in the
//  drive. Red before: `LaunchWindow` did not exist.
//

import AppKit
import XCTest
@testable import EMStudio

nonisolated final class LaunchWindowTests: XCTestCase {
    func testAWindowIsOpenedOnlyWhenNoneIsThere() {
        XCTAssertTrue(LaunchWindow.needsWindow(enrolled: 0, mainCapableVisible: 0))
        XCTAssertFalse(LaunchWindow.needsWindow(enrolled: 1, mainCapableVisible: 0), "a window enrolled: never a second one")
        XCTAssertFalse(LaunchWindow.needsWindow(enrolled: 0, mainCapableVisible: 1), "a window on screen: never a second one")
    }

    /// The item it chooses is New Window with ⌘N alone, found in a submenu, and not an item of the same key with other modifiers.
    @MainActor func testItFindsFileNewWindow() throws {
        let main = NSMenu(), file = NSMenu(title: "File")
        let other = NSMenuItem(title: "New Tab", action: nil, keyEquivalent: "n")
        other.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(other)
        file.addItem(NSMenuItem(title: "New Window", action: nil, keyEquivalent: "n"))
        let top = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        top.submenu = file
        main.addItem(top)
        let found = try XCTUnwrap(LaunchWindow.newWindowItem(in: main))
        XCTAssertTrue(found.menu === file)
        XCTAssertEqual(found.index, 1)
        XCTAssertNil(LaunchWindow.newWindowItem(in: NSMenu()))
    }

    /// The app delegate checks once, a moment after the launch.
    func testTheDelegateChecksAfterTheLaunch() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("EMStudio/App/AppDelegate.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("LaunchWindow.ensureOne(enrolled: Self.windows?.onScreen.count ?? 0)"))
    }
}
