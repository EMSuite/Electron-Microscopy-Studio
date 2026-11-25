//
//  CrashReportOffer.swift
//  Role: After a crash or a hang, offer to send the report (#801, plan row Q15 of 2.3). EMSuiteUI keeps the system's crash and hang
//        reports in the app's own folder (`DiagnosticReportCollector`, started once at launch here); macOS hands a report over at the
//        launch after the crash. While the folder holds a report newer than the last one the person dismissed, the welcome canvas shows
//        one line with Report a Problem… (EMSuiteUI's window: the report and the summary go out through the person's own mail app or
//        browser, nothing is sent by the app) and Dismiss. Dismissed once, the line stays away until a newer report arrives.
//

import Foundation
import Observation
import ShellHelp
import TEMCore

@MainActor @Observable
final class CrashReportOffer {
    /// The newest report's file name the person dismissed (the report names sort by when they arrived).
    nonisolated static let dismissedKey = "crashReportOffer.dismissed"
    /// MetricKit hands over crashes, hangs and the other problems macOS records (CPU and disk-write exceptions), so the line names a
    /// problem report, not only a crash.
    static let line = "macOS recorded a problem with \(AppName.display) (a crash, a hang or another issue). Its report is kept on this Mac."

    /// The app's one offer, on the app's own folder and the standard defaults; nil in a UI-testing launch, so a person's reports never
    /// show in a journey and a journey's never in theirs.
    static let shared = CrashReportOffer(store: LaunchOptions().isUITesting ? nil : DiagnosticReportStore.standard(),
                                         defaults: .standard)

    /// The kept reports' folder's collector, for the app's life (`start`).
    private static var collector: DiagnosticReportCollector?

    /// Starts keeping the system's crash and hang reports; once, at launch.
    static func startCollecting() {
        guard collector == nil, !LaunchOptions().isUITesting else { return }
        collector = DiagnosticReportCollector.start()
    }

    private let store: DiagnosticReportStore?
    private let defaults: UserDefaults
    /// The newest report not yet dismissed, or nil: the line is offered while it is set.
    private(set) var report: String?

    init(store: DiagnosticReportStore?, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        refresh()
    }

    var isOffered: Bool { report != nil }

    /// Reads the folder again: a report the system delivered since the last read is offered.
    func refresh() {
        guard let newest = store?.reports().last?.lastPathComponent else { report = nil; return }
        let dismissed = defaults.string(forKey: Self.dismissedKey) ?? ""
        report = newest > dismissed ? newest : nil
    }

    /// Dismiss: this report and every older one stay away; a newer one is offered again.
    func dismiss() {
        if let report { defaults.set(report, forKey: Self.dismissedKey) }
        report = nil
    }
}
