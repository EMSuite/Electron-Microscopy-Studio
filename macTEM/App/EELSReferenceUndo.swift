//
//  EELSReferenceUndo.swift
//  Role: Edit > Undo for removing an EELS reference (#325, after `MarkUndo`, `FFTSpotUndo` and `DiffractionUndo`): the References
//        section's Remove. The window's `UndoManager` comes from SwiftUI (`@Environment(\.undoManager)`) and is handed in by the view; a
//        nil manager registers nothing. The target is the room's `EELSSession`, never captured by the handler.
//
//        Undo puts the reference back with its id, name and curve at its place in the list, so the MLLS fit's signature is what it was;
//        redo removes it again. Each runs only while the list is exactly as the other left it on the same file
//        (`EELSSession.restoreReferences`): a reference added since, or another file opened, makes it do nothing and offer no redo.
//

import Foundation
import TEMCore
import TEMSession

@MainActor
enum EELSReferenceUndo {
    /// Removes the reference `id` ("Remove Reference").
    static func remove(_ id: EELSReference.ID, in session: EELSSession, undoManager: UndoManager?) {
        let before = session.references
        session.removeReference(id)
        let after = session.references
        guard before != after else { return }
        register(in: undoManager, session: session, generation: session.referenceGeneration, from: after, to: before)
    }

    private static func register(in manager: UndoManager?, session: EELSSession, generation: Int,
                                 from: [EELSReference], to: [EELSReference]) {
        guard let manager else { return }
        manager.registerUndo(withTarget: session) { [weak manager] session in
            // The Edit menu calls this on the main thread; the closure type is not actor-isolated, so say so once, here.
            MainActor.assumeIsolated {
                guard session.restoreReferences(to, from: from, generation: generation) else { return }
                register(in: manager, session: session, generation: generation, from: to, to: from)
            }
        }
        manager.setActionName("Remove Reference")
    }
}
