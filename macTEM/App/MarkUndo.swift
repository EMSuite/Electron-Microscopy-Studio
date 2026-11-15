//
//  MarkUndo.swift
//  Role: Edit > Undo for removing Image room marks (#325, first part: marks): ⌫ on a selected mark, a row's Remove and Remove All. The
//        window's `UndoManager` comes from SwiftUI (`@Environment(\.undoManager)`) and is handed in by the view, as mac4DSTEM's
//        `ReplaceUndo` does; a nil manager registers nothing (a test, a harness). The target is the window's `ImageMeasurements`.
//
//        Undo puts each mark back with its id, kind, points and width, at its place in the list (`ImageMeasurements.restore`); redo removes
//        them again. A mark that is back already, or a list of another image (a different file shown since), is left alone: the undo
//        then does nothing and offers no redo.
//

import Foundation
import TEMCore
import TEMSession

@MainActor
enum MarkUndo {
    /// Removes the marks `ids` (in the list's order) and registers the undo that puts them back on the image `session` shows when the undo
    /// runs. The undo holds the session weakly and never the pixels, so a closed file's image is not kept alive by Edit > Undo (#577).
    /// The action name says what went: "Remove Distance", "Remove Angle", "Remove Profile", or "Remove All Marks".
    static func remove(_ ids: [ImageMark.ID], in measurements: ImageMeasurements, session: ImageSession?, undoManager: UndoManager?) {
        let removed = measurements.marks.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, mark: $0.element) }
        guard !removed.isEmpty else { return }
        if removed.count == measurements.marks.count, removed.count > 1 { measurements.removeAll() } else {
            for entry in removed { measurements.remove(entry.mark.id) }
        }
        guard let session else { return }
        register(in: undoManager, measurements: measurements, actionName: actionName(removed.map(\.mark)),
                 undo: { [weak session] in
                     guard let image = session?.image else { return false }
                     return restore(removed, in: measurements, on: image)
                 },
                 redo: { removeAgain(removed, in: measurements) })
    }

    nonisolated static func actionName(_ marks: [ImageMark]) -> String {
        guard marks.count == 1, let kind = marks.first?.kind else { return "Remove All Marks" }
        return "Remove " + kind.rawValue.capitalized
    }

    private static func restore(_ removed: [(index: Int, mark: ImageMark)], in measurements: ImageMeasurements, on image: CalibratedImage) -> Bool {
        guard removed.allSatisfy({ entry in !measurements.marks.contains { $0.id == entry.mark.id } }) else { return false }
        for entry in removed.sorted(by: { $0.index < $1.index }) {
            guard measurements.restore(entry.mark, at: entry.index, on: image) == nil else { return false }
        }
        return true
    }

    private static func removeAgain(_ removed: [(index: Int, mark: ImageMark)], in measurements: ImageMeasurements) -> Bool {
        let ids = Set(removed.map(\.mark.id))
        guard ids.isSubset(of: Set(measurements.marks.map(\.id))) else { return false }
        for id in ids { measurements.remove(id) }
        return true
    }

    private static func register(in manager: UndoManager?, measurements: ImageMeasurements, actionName: String,
                                 undo: @escaping @MainActor () -> Bool, redo: @escaping @MainActor () -> Bool) {
        guard let manager else { return }
        manager.registerUndo(withTarget: measurements) { [weak manager] _ in
            // The Edit menu calls this on the main thread; the closure type is not actor-isolated, so say so once, here.
            MainActor.assumeIsolated {
                guard undo() else { return }
                // Registered while the manager is undoing, it becomes the redo (and, while redoing, the undo).
                register(in: manager, measurements: measurements, actionName: actionName, undo: redo, redo: undo)
            }
        }
        manager.setActionName(actionName)
    }
}
