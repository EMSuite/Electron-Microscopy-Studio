//
//  TIASpectraRooms.swift
//  Role: the room of a TIA series of spectra whose .emi does not say EDS or EELS (#906, `TIASpectra.room`): an Open asks once for all
//        such files it holds, on a sheet, and the answer is kept for each file for the app's life, so Open Recent, a tab of its own and
//        Reopen Last Session do not ask again. The agent door's `open_file` gives the answer as its `room` and asks nothing.
//
//  WHY APPKIT (the suite's rule: only where SwiftUI cannot do the job, named where used): an `NSAlert` sheet awaited in the middle of
//  an Open (`AppState.open(urls:)`), as the folder panel is (`FolderPanels`); SwiftUI's `confirmationDialog` is a view's state, which
//  the Open cannot wait on. It reuses the session panels' `sheetButton` and export's `hostWindow` as a caller.
//

import AppKit
import Synchronization
import TEMCore

nonisolated enum TIASpectraRooms {
    /// The answer for each file by its standardised path.
    private static let answers = Mutex<[String: TIASpectra.Room]>([:])

    static func remember(_ room: TIASpectra.Room, for url: URL) {
        answers.withLock { $0[url.standardizedFileURL.path] = room }
    }

    static func room(for url: URL) -> TIASpectra.Room? {
        answers.withLock { $0[url.standardizedFileURL.path] }
    }

    /// `inventory` with the room kept for `url` when it asks for one; otherwise as it is.
    static func routed(_ inventory: FileInventory, url: URL) -> FileInventory {
        guard inventory.asksForSpectraRoom, let room = room(for: url) else { return inventory }
        var routed = inventory
        routed.asksForSpectraRoom = false
        switch room {
        case .eds: routed.edsSpectrumImage = true
        case .eels: routed.eelsSpectrumImage = true
        }
        return routed
    }

    /// The room the person chose for the spectra of `names`, or nil when they chose Don't Open, the window closed under the sheet, or
    /// the window has a sheet up already (a beep, as for a refused action).
    @MainActor
    static func ask(names: [String], appState: AppState) async -> TIASpectra.Room? {
        guard let window = ExportPanels.hostWindow(for: appState) else {
            NSSound.beep()
            return nil
        }
        let alert = NSAlert()
        alert.messageText = TIASpectra.askTitle(names: names)
        alert.informativeText = TIASpectra.askDetail
        for room in TIASpectra.Room.allCases { alert.addButton(withTitle: room.rawValue) }
        alert.addButton(withTitle: "Don’t Open").keyEquivalent = "\u{1b}"
        let index = await SessionPanels.sheetButton(alert, on: window)
        return TIASpectra.Room.allCases.indices.contains(index) ? TIASpectra.Room.allCases[index] : nil
    }
}
