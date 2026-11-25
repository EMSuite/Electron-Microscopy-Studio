//
//  DiffractionRoomState.swift
//  Role: the Diffraction room's own state for the window: the status line's readout over the pattern, and which of the room's
//        tables the window has already shown on its own in the shell's bottom area (#1094). Window-wide and not saved; composed by
//        `AppState` as `ImageRoomTools` is. The pattern's view state (the tool, the zoom, the display) is each open file's own
//        (`DiffractionViewState`, TEMSession), beside its results (`DiffractionAnalysis`).
//
//  The tables are panes of the shell's bottom area (`ProcessTab`s beside Output, `WorkspaceView`), not a strip of the room: the bar
//  above them drags, the area's height is the window's (`PanelNavigation.processFraction`, scene-stored) and each table has its toggle
//  at the infobar's right end. A fixed strip under the pattern showed the part's table always, so the window shows that table on
//  its own the first time a part asks for it (`offer`), opening the area if it is shut; after that the person's toggles and the bar
//  are theirs, and the window never shows it on its own again. Nothing here is saved: the shown panes are not either
//  (`PanelNavigation.shownProcessPanes`), so a new window starts as the first did.
//

import Foundation
import Observation
import ShellLayout

@Observable
final class DiffractionRoomState {
    /// The status line's readout over the diffraction pattern (`DiffractionReadoutText`); nil when the pointer is elsewhere.
    var readout: String?
    /// The tables this window has shown on its own (`offer`), each once.
    private(set) var offeredTables: Set<DiffractionTable> = []

    /// Shows `table` in the bottom area the first time the window is asked to (`DiffractionPart.openingTable`), as the strip under
    /// the pattern showed it: its pane joins the shown panes and the area opens if it was shut (`toggleProcessPane`). A table asked
    /// for again, or one the person already shows, is left as it is, so a toggle or a drag of theirs is never undone.
    func offer(_ table: DiffractionTable?, in panels: PanelNavigation) {
        guard let table, !offeredTables.contains(table) else { return }
        offeredTables.insert(table)
        guard !panels.shownProcessPanes.contains(table.paneID) else { return }
        panels.toggleProcessPane(table.paneID)
    }

    /// The bottom area never stands open and empty (the shell's rule): when the tables on offer change (another part, another
    /// room) and no pane shown is still among them or Output, Output is shown.
    static func keepAPaneShown(supplied: [DiffractionTable], in panels: PanelNavigation) {
        let offered = Set(supplied.map(\.paneID)).union([ProcessPaneID.output])
        guard panels.shownProcessPanes.isDisjoint(with: offered) else { return }
        panels.shownProcessPanes.insert(.output)
    }
}

extension DiffractionTable {
    /// The table's pane in the shell's bottom area: "diffraction.readout", "diffraction.spots", "diffraction.peaks".
    nonisolated var paneID: ProcessPaneID { ProcessPaneID("diffraction.\(rawValue)") }
}
