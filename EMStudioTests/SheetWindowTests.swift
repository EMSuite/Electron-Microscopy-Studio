//
//  SheetWindowTests.swift
//  A sheet goes on the window that asked (#625): each window's state knows its own `NSWindow` (`AppState.sheetWindow`, set by
//  `WindowTabbing` when its view enters the window, cleared when the window withdraws), `ExportPanels.hostWindow(for:)` takes it
//  over the main window, and an export writing in one window does not block another (`AppState.exportsWriting`, per state).
//

import AppKit
import SwiftUI
import XCTest
@testable import EMStudio

nonisolated final class SheetWindowTests: XCTestCase {

    /// The asking window wins; the main one is the fallback only for a state no window shows. Red under: `main ?? own`
    /// (the old rule: the main window always).
    func testTheAskingWindowIsTheHostAndTheMainOneOnlyTheFallback() {
        let asking = NSObject(), main = NSObject()
        XCTAssertTrue(ExportPanels.sheetHost(own: asking, main: main) === asking)
        XCTAssertTrue(ExportPanels.sheetHost(own: nil, main: main) === main)
        XCTAssertNil(ExportPanels.sheetHost(own: NSObject?.none, main: nil))
    }

    /// Two windows, each with its state: each state names its own window, and the host for each is that window, whichever is
    /// main. Withdrawn, the state names none. Red under: `sheetWindow` not set by `WindowTabbing`; the host read from
    /// `NSApp.mainWindow`.
    @MainActor func testEachWindowsStateHostsItsSheetsOnItsOwnWindow() throws {
        let windows = AppWindows()
        let front = AppState(launch: LaunchOptions(arguments: []))
        let back = AppState(launch: LaunchOptions(arguments: []))
        func window(for state: AppState) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                                  backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WindowTabbing(state: state, windows: windows))
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        let frontWindow = window(for: front), backWindow = window(for: back)
        XCTAssertTrue(front.sheetWindow?() === frontWindow, "the probe hands the state its window")
        XCTAssertTrue(back.sheetWindow?() === backWindow)
        XCTAssertTrue(ExportPanels.hostWindow(for: back) === backWindow, "the back window's export is a sheet on the back window")
        XCTAssertTrue(ExportPanels.hostWindow(for: front) === frontWindow)

        windows.enroll(back)
        windows.withdraw(back)
        XCTAssertNil(back.sheetWindow, "a withdrawn state names no window")
    }

    /// An export writing in one window leaves the other's count at zero. Red under: one count for the app (a static).
    @MainActor func testAWriteInOneWindowDoesNotCountInAnother() {
        let one = AppState(launch: LaunchOptions(arguments: []))
        let other = AppState(launch: LaunchOptions(arguments: []))
        one.exportsWriting += 1
        XCTAssertEqual(other.exportsWriting, 0)
    }
}
