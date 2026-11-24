//
//  WelcomeRecents.swift
//  Role: The welcome canvas's Recent list (#802, plan row Q16 of 2.3; the welcome mockup of 23 Nov): the files File > Open Recent
//        lists, newest first, each a row with its name as the menu shows it and the folder it sits in, opened by a click as the menu
//        item opens it (`AppState.openRecent`). Under it, the line that says a file can be dropped on the window (ContentView takes the
//        drop). A thin slice: New Simulation joins the buttons with #788, the Tutorials link once the documentation is live (#753).
//

import Foundation

nonisolated enum WelcomeRecents {
    /// One row: the title File > Open Recent shows and the folder, the home folder written "~".
    nonisolated struct Row: Equatable, Sendable {
        let path: String
        let title: String
        let folder: String
    }

    static let dropHint = "Or drop a file anywhere in this window"

    /// The rows, in the recents' order (newest first), titled as the menu titles them.
    static func rows(paths: [String], titles: [String], home: String = NSHomeDirectory()) -> [Row] {
        zip(paths, titles).map { path, title in
            let folder = (path as NSString).deletingLastPathComponent
            let shown = folder == home ? "~" : folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
            return Row(path: path, title: title, folder: shown)
        }
    }
}
