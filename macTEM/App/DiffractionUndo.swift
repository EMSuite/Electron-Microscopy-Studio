//
//  DiffractionUndo.swift
//  Role: Edit > Undo for removing Diffraction room rings and spots (#325, after `MarkUndo` and `FFTSpotUndo`): ⌫ on a selected row, Remove
//        and Remove All. The window's `UndoManager` comes from SwiftUI (`@Environment(\.undoManager)`) and is handed in by the view; a nil
//        manager registers nothing (a test, a harness). The target is the file's `DiffractionAnalysis`, never captured by the handler.
//
//        Undo puts the marks back as they were before the removal, the scale a calibrating ring set with them
//        (`DiffractionAnalysis.restore`); redo removes them again. Each runs only while the marks are exactly as the other left them: a ring
//        fitted or a spot added since makes the undo do nothing and offer no redo, so nothing measured later is lost.
//

import Foundation
import TEMSession

@MainActor
enum DiffractionUndo {
    /// Removes the ring or spot `id` ("Remove Ring" or "Remove Spot").
    static func remove(_ id: UUID, in analysis: DiffractionAnalysis, undoManager: UndoManager?) {
        let name = analysis.rings.contains { $0.id == id } ? "Remove Ring" : "Remove Spot"
        change(in: analysis, undoManager: undoManager, actionName: name) { analysis.remove(id) }
    }

    /// Removes every ring and spot ("Remove All Rings and Spots").
    static func removeAll(in analysis: DiffractionAnalysis, undoManager: UndoManager?) {
        change(in: analysis, undoManager: undoManager, actionName: "Remove All Rings and Spots") { analysis.removeAll() }
    }

    private static func change(in analysis: DiffractionAnalysis, undoManager: UndoManager?, actionName: String, _ remove: () -> Void) {
        let before = analysis.marks
        remove()
        let after = analysis.marks
        guard before != after else { return }
        register(in: undoManager, analysis: analysis, actionName: actionName, from: after, to: before)
    }

    /// Registers the step that takes the marks from `from` to `to`; run, it registers the step back (the redo while undoing, and so on).
    private static func register(in manager: UndoManager?, analysis: DiffractionAnalysis, actionName: String,
                                 from: DiffractionAnalysis.Marks, to: DiffractionAnalysis.Marks) {
        guard let manager else { return }
        manager.registerUndo(withTarget: analysis) { [weak manager] analysis in
            // The Edit menu calls this on the main thread; the closure type is not actor-isolated, so say so once, here.
            MainActor.assumeIsolated {
                guard analysis.marks == from else { return }
                analysis.restore(to)
                register(in: manager, analysis: analysis, actionName: actionName, from: to, to: from)
            }
        }
        manager.setActionName(actionName)
    }
}
