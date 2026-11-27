//
//  LinkedFilePanels.swift
//  Role: Locate… (#824; the suite's files-exports design, rule 5): the open panel where the person picks the file a document's link
//        names when it is not connected. Nothing is read here; `LinkedFiles.locate` checks the pick's fingerprint.
//
//  WHY APPKIT (the suite's rule: only where SwiftUI cannot do the job, named where used): `NSOpenPanel` awaited as a sheet on the
//  document's window by the action that then checks and opens the file, as `FolderPanels` does; it reuses export's `present` and
//  `hostWindow` (`ExportPanels`).
//

import AppKit
import TEMCore

@MainActor
enum LinkedFilePanels {
    /// The sentence the panel shows.
    static func locateSentence(for link: LinkedFile) -> String {
        "Locate \(link.name): pick the file this document names. A file with other contents is named as different and linked only if you say so."
    }

    /// The file the person picked for `link`, or nil when the panel was cancelled, or when the window has a sheet up already (a beep,
    /// as for a refused action).
    static func locate(_ link: LinkedFile, appState: AppState) async -> URL? {
        guard let window = ExportPanels.hostWindow(for: appState) else {
            NSSound.beep()
            return nil
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Locate"
        panel.message = locateSentence(for: link)
        guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return nil }
        return url
    }
}
