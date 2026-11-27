//
//  SessionCommands.swift
//  Role: File > Save to Session, and in the Diffraction room File > Save Simulation for a Simulation document (#908), their
//        own `Commands` beside `ExportCommands`; the scene lists it first, so the item sits with Close and Save's group and
//        above the export Divider. ⌘S: free in macTEM (⌘O, ⌘W, ⇧⌘W, ⇧⌘E, ⌘1…5, ⌃⌘S/I/L use others; ⌃⌘S is the sidebar).
//        Enabled only in the Image room, for the selected file with its pixels, no read or save running, a session
//        state that allows saving, and something changed since the last save or restore (`OpenItem.canSave`). A menu
//        item cannot say why it is dimmed, so the reason is drawn in the Measure section (`ImageRoomSession.swift`).
//        The title ends in an ellipsis while the next save will ask for a place (no grant yet): HIG, an ellipsis means
//        more input is needed.
//

import SwiftUI
import TEMSession

struct SessionCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        // Read once, here: the item, its state and the room (a second read is a second dependency).
        let item = appState?.openItems.selected
        let inImageRoom = appState?.navigation.workspaceArea == .image
        // A Simulation document in the Diffraction room saves its session file instead (#908, `SimulationSessions`).
        let simulation = SimulationSessions.canSave(appState)
        let enabled = simulation || (inImageRoom && item?.canSave == true)
        // The title follows whether a grant is stored (`OpenItem.hasGrant`, observed).
        let title = simulation ? SimulationSessions.saveTitle(for: item) : SessionGrants.saveTitle(for: item)
        CommandGroup(after: .saveItem) {
            Button(title) {
                guard let appState else { return }
                if SimulationSessions.canSave(appState) { SimulationSessions.save(appState: appState) } else { SessionPanels.save(appState: appState) }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!enabled)
        }
    }
}
