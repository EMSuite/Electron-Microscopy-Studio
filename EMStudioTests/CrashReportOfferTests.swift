//
//  CrashReportOfferTests.swift
//  After a crash, the next launch offers to send the report (#801): a kept report newer than the last dismissed one is offered; a
//  dismissal is kept across launches, so the line stays away until a newer report arrives. On a temporary report folder and defaults.
//

import ShellHelp
import TEMCore
import XCTest
@testable import EMStudio

nonisolated final class CrashReportOfferTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "crash-offer-\(UUID().uuidString)", directoryHint: .isDirectory)
        suite = "crash-offer-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    /// Mutation: the offer ignores the folder, forgets a dismissal at the next launch, or never offers a newer report - red.
    @MainActor func testAReportIsOfferedUntilDismissedAndANewerOneAgain() throws {
        let store = DiagnosticReportStore(folder: folder)
        XCTAssertFalse(CrashReportOffer(store: store, defaults: defaults).isOffered, "no report, no line")

        try store.save([Data("{}".utf8)], receivedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let launch = CrashReportOffer(store: store, defaults: defaults)
        XCTAssertTrue(launch.isOffered, "the launch after a crash offers the report")
        launch.dismiss()
        XCTAssertFalse(launch.isOffered)
        XCTAssertFalse(CrashReportOffer(store: store, defaults: defaults).isOffered, "dismissed once, it stays away at the next launch")

        try store.save([Data("{}".utf8)], receivedAt: Date(timeIntervalSince1970: 1_800_086_400))
        XCTAssertFalse(launch.isOffered, "the line follows the folder only when it is read again")
        launch.refresh()
        XCTAssertTrue(launch.isOffered, "a newer report is offered again")
    }

    @MainActor func testNoFolderOffersNothing() {
        XCTAssertFalse(CrashReportOffer(store: nil, defaults: defaults).isOffered)
        XCTAssertTrue(CrashReportOffer.line.contains(AppName.display))
    }
}
