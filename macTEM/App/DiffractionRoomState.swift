//
//  DiffractionRoomState.swift
//  Role: the Diffraction room's own state for the window: the status line's readout over the pattern, and which of the room's
//        tables the window has already selected on its own in the shell's bottom area (#1094, #1112). Window-wide and not saved; composed by
//        `AppState` as `ImageRoomTools` is. The pattern's view state (the tool, the zoom, the display) is each open file's own
//        (`DiffractionViewState`, TEMSession), beside its results (`DiffractionAnalysis`).
//
//  The tables are tabs of the shell's bottom area (`ProcessTab`s beside Output, `WorkspaceView`, `processAreaStyle: .tabs`, #1112),
//  not a strip of the room: one tab at a time at full width, chosen in the area's header (`PanelNavigation.selectedProcessPane`),
//  under the bar the person drags; the area's height is the window's (`PanelNavigation.processFraction`, scene-stored) and one
//  toggle at the infobar's right end shows or hides the whole area. A fixed strip under the pattern showed the part's table always,
//  so the window selects that table on its own the first time a part asks for it (`offer`), opening the area if it is shut; after
//  that the tab, the toggle and the bar are the person's, and the window never selects it on its own again. Nothing here is saved:
//  the selected tab is not either, so a new window starts as the first did.
//

import Foundation
import Observation
import ShellLayout

@Observable
final class DiffractionRoomState {
    /// The status line's readout over the diffraction pattern (`DiffractionReadoutText`); nil when the pointer is elsewhere.
    var readout: String?
    /// The tables this window has selected on its own (`offer`), each once.
    private(set) var offeredTables: Set<DiffractionTable> = []

    /// Selects `table`'s tab in the bottom area the first time the window is asked to (`DiffractionPart.openingTable`), as the strip
    /// under the pattern showed it, and opens the area if it was shut (`selectProcessPane`). A table asked for again is left as it
    /// is, so a tab the person picked since (Output, another table), the area they shut or a drag of theirs is never undone.
    /// When another part or room takes the table away, the stored selection may name a tab no longer registered; that is harmless:
    /// the area draws Output then (`ProcessAreaLayout.shownTab`), and the table again if it is still the selection when it comes back.
    /// A table of the Maps room left selected is harmless the same way. (The panes' `keepAPaneShown`, Output put back when the tables
    /// went, is not needed for that reason and went with #1112.)
    func offer(_ table: DiffractionTable?, in panels: PanelNavigation) {
        guard let table, !offeredTables.contains(table) else { return }
        offeredTables.insert(table)
        panels.selectProcessPane(table.paneID)
    }
}

extension DiffractionTable {
    /// The table's tab in the shell's bottom area: "diffraction.readout", "diffraction.spots", "diffraction.peaks".
    nonisolated var paneID: ProcessPaneID { ProcessPaneID("diffraction.\(rawValue)") }
}
