//
//  FFTSpotUndo.swift
//  Role: Edit > Undo for removing FFT room spots (#325, second part, after `MarkUndo`): ⌫ on a selected spot, a row's Remove and
//        Remove All. The window's `UndoManager` comes from SwiftUI (`@Environment(\.undoManager)`) and is handed in by the view; a nil
//        manager registers nothing (a test, a harness). The target is the room's `FFTAnalysis`, held weakly so Edit > Undo never keeps a
//        closed file's owner (and its image) alive.
//
//        Undo puts each spot back with its id, number, answer and In Mask, at its place in the list (`FFTAnalysis.restoreSpots`); redo
//        removes them again. Spots of another spectrum (a new region or file since), or back already, are left alone: the undo then does
//        nothing and offers no redo.
//

import Foundation
import TEMSession

@MainActor
enum FFTSpotUndo {
    /// Removes the spots `ids` and registers the undo that puts them back. All of them at once is one "Remove All Spots"; one is
    /// "Remove Spot".
    static func remove(_ ids: [FFTSpot.ID], in analysis: FFTAnalysis, undoManager: UndoManager?) {
        let removed = analysis.spots.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, spot: $0.element) }
        guard !removed.isEmpty else { return }
        let all = removed.count == analysis.spots.count && removed.count > 1
        if all { analysis.removeAllSpots() } else {
            for entry in removed { analysis.removeSpot(entry.spot.id) }
        }
        register(in: undoManager, analysis: analysis, actionName: all ? "Remove All Spots" : (removed.count == 1 ? "Remove Spot" : "Remove Spots"),
                 undo: { [weak analysis] in analysis?.restoreSpots(removed) ?? false },
                 redo: { [weak analysis] in
                     guard let analysis else { return false }
                     let ids = Set(removed.map(\.spot.id))
                     guard ids.isSubset(of: Set(analysis.spots.map(\.id))) else { return false }
                     for id in ids { analysis.removeSpot(id) }
                     return true
                 })
    }

    private static func register(in manager: UndoManager?, analysis: FFTAnalysis, actionName: String,
                                 undo: @escaping @MainActor () -> Bool, redo: @escaping @MainActor () -> Bool) {
        guard let manager else { return }
        manager.registerUndo(withTarget: analysis) { [weak manager] analysis in
            // The Edit menu calls this on the main thread; the closure type is not actor-isolated, so say so once, here. The owner is
            // the handler's argument, never captured, so the manager does not keep it alive.
            MainActor.assumeIsolated {
                guard undo() else { return }
                // Registered while the manager is undoing, it becomes the redo (and, while redoing, the undo).
                register(in: manager, analysis: analysis, actionName: actionName, undo: redo, redo: undo)
            }
        }
        manager.setActionName(actionName)
    }
}
