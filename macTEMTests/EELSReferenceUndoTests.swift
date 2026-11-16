//
//  EELSReferenceUndoTests.swift
//  Edit > Undo for removing an EELS reference (#325; App/EELSReferenceUndo.swift), on the planted core loss of `EELSMLLSReferencesTests`: the
//  removed reference comes back with its id at its place, so the MLLS fit's signature is the one before; redo removes it again; an undo after
//  another reference was added, or after another file was opened, does nothing. Red before: no undo registered, Edit > Undo dimmed.
//

import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class EELSReferenceUndoTests: XCTestCase {
    /// The planted room with two references: the imported feature, then one from the whole map over N K.
    @MainActor private func twoReferences() async throws -> (EELSSession, URL) {
        let loaded = LoadedEELS(fileName: "feature.dm4", image: try EELSRoomTests.image(), beamEnergyKeV: 200, convergenceMrad: 0,
                                collectionMrad: 10, origin: "planted", coreLoss: try EELSMLLSReferencesTests.core(), coreLossOrigin: "planted core")
        let session = EELSSession()
        await session.bind(loaded).value
        session.setThreshold(.fixed(2.5))
        await session.settled()
        session.setConvolveLowLoss(false)
        for (edge, _) in EELSControlsTests.amounts { session.toggleEdge(edge) }
        session.setFitModel(.mlls)
        let url = try EELSMLLSReferencesTests.referenceFile()
        XCTAssertNotNil(session.importReference(url: url), session.referenceNotice ?? "")
        XCTAssertNotNil(session.addReferenceFromRegion(edge: .nitrogenK), session.referenceNotice ?? "")
        XCTAssertEqual(session.references.count, 2)
        return (session, url)
    }

    @MainActor private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @MainActor private func remove(_ id: EELSReference.ID, _ session: EELSSession, _ undo: UndoManager) {
        undo.beginUndoGrouping()
        EELSReferenceUndo.remove(id, in: session, undoManager: undo)
        undo.endUndoGrouping()
    }

    @MainActor func testUndoPutsTheReferenceBackInItsPlaceAndRedoRemovesIt() async throws {
        let (session, url) = try await twoReferences()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = session.references
        let undo = manager()
        remove(before[0].id, session, undo)
        XCTAssertEqual(session.references.map(\.id), [before[1].id])
        XCTAssertEqual(undo.undoActionName, "Remove Reference")

        undo.undo()
        XCTAssertEqual(session.references, before, "the same references, ids and curves, in their order")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(session.references.map(\.id), [before[1].id])
        undo.undo()
        XCTAssertEqual(session.references, before)
    }

    /// A reference added after the removal is not overwritten: the undo does nothing and offers no redo.
    @MainActor func testAnUndoAfterANewReferenceDoesNothing() async throws {
        let (session, url) = try await twoReferences()
        defer { try? FileManager.default.removeItem(at: url) }
        let undo = manager()
        remove(session.references[0].id, session, undo)
        XCTAssertNotNil(session.addReferenceFromRegion(edge: .oxygenK))
        let now = session.references
        undo.undo()
        XCTAssertEqual(session.references, now)
        XCTAssertFalse(undo.canRedo)
    }

    /// After the file is closed, the undo puts nothing on an empty room. Red under: the list alone compared (both empty after removing the
    /// last reference and closing).
    @MainActor func testAnUndoAfterTheFileClosedDoesNothing() async throws {
        let (session, url) = try await twoReferences()
        defer { try? FileManager.default.removeItem(at: url) }
        let undo = manager()
        remove(session.references[1].id, session, undo)
        remove(session.references[0].id, session, undo)
        XCTAssertTrue(session.references.isEmpty)
        session.close()
        undo.undo()
        XCTAssertTrue(session.references.isEmpty)
        XCTAssertFalse(undo.canRedo)
    }
}
