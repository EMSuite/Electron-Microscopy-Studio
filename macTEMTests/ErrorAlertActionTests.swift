//
//  ErrorAlertActionTests.swift
//  The error alert's buttons (#1038, HIG Buttons: the primary role goes to the button people are most likely to choose): OK is the
//  default (Return) and the cancel (Esc), Copy Details the plain button; the alert draws its buttons from `ErrorAlertAction`.
//  Red before: no `ErrorAlertAction`; the alert held `Button("Copy Details")` beside `Button("OK", role: .cancel)`, so SwiftUI
//  made Copy Details the default and Return copied.
//

import XCTest
@testable import macTEM

nonisolated final class ErrorAlertActionTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testOKIsTheDefaultAndTheCancel() {
        XCTAssertEqual(ErrorAlertAction.allCases.filter(\.isDefault), [.ok], "Return presses OK")
        XCTAssertEqual(ErrorAlertAction.allCases.filter(\.isCancel), [.ok], "Esc presses OK")
        XCTAssertFalse(ErrorAlertAction.copyDetails.isDefault)
        XCTAssertEqual(ErrorAlertAction.allCases.map(\.title), ["Copy Details", "OK"])
    }

    func testTheAlertDrawsItsButtonsFromTheActions() throws {
        let view = try source("macTEM/UI/ContentView.swift")
        XCTAssertTrue(view.contains("errorAlertButton(.copyDetails)"))
        XCTAssertTrue(view.contains("errorAlertButton(.ok)"))
        XCTAssertTrue(view.contains(".keyboardShortcut(action.isDefault ? KeyboardShortcut.defaultAction : nil)"))
        XCTAssertFalse(view.contains("Button(\"OK\", role: .cancel)"), "the old pair made Copy Details the default")
    }
}
