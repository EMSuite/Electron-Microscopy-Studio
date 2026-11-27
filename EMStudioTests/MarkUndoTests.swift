//
//  MarkUndoTests.swift
//  Edit > Undo for removing Image room marks (#325, first part): with a real UndoManager, a removed mark comes back with its id, kind,
//  points, width and place in the list; redo removes it again; Remove All is one undo; the record follows (the file is dirty after each).
//  Red before: no undo registered, Edit > Undo always dimmed.
//

import Foundation
import FormatoCore
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class MarkUndoTests: XCTestCase {
    @MainActor private func three() -> (ImageMeasurements, [ImageMark], ImageSession) {
        let image = FFTAnalysisTests.plant()
        let session = ImageSession()
        session.finishOpen(session.beginOpen(), image: image, url: URL(fileURLWithPath: "/data/plant.tif"), metadata: AcquisitionMetadata(), sem: nil)
        let measurements = ImageMeasurements()
        let marks = [
            ImageMark(kind: .distance, points: [ImagePoint(x: 2, y: 3), ImagePoint(x: 12, y: 3)]),
            ImageMark(kind: .profile, points: [ImagePoint(x: 4, y: 4), ImagePoint(x: 20, y: 9)], width: 5),
            ImageMark(kind: .angle, points: [ImagePoint(x: 1, y: 1), ImagePoint(x: 6, y: 6), ImagePoint(x: 11, y: 1)]),
        ]
        for mark in marks { XCTAssertNil(measurements.add(mark, on: image)) }
        return (measurements, measurements.marks, session)
    }

    @MainActor private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @MainActor func testUndoPutsARemovedMarkBackInItsPlaceAndRedoRemovesItAgain() {
        let (measurements, marks, session) = three()
        let undo = manager()
        undo.beginUndoGrouping()
        MarkUndo.remove([marks[1].id], in: measurements, session: session, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(measurements.marks.map(\.id), [marks[0].id, marks[2].id])
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Remove Profile")
        let afterRemove = measurements.revision

        undo.undo()
        XCTAssertEqual(measurements.marks, marks, "the same id, kind, points and width, in its place")
        XCTAssertGreaterThan(measurements.revision, afterRemove, "the record follows: the file is dirty again")
        XCTAssertTrue(undo.canRedo)

        undo.redo()
        XCTAssertEqual(measurements.marks.map(\.id), [marks[0].id, marks[2].id])
        undo.undo()
        XCTAssertEqual(measurements.marks, marks)
    }

    @MainActor func testRemoveAllIsOneUndo() {
        let (measurements, marks, session) = three()
        let undo = manager()
        undo.beginUndoGrouping()
        MarkUndo.remove(marks.map(\.id), in: measurements, session: session, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertTrue(measurements.marks.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Remove All Marks")
        undo.undo()
        XCTAssertEqual(measurements.marks, marks)
        XCTAssertFalse(undo.canUndo, "one step")
    }

    /// Without a manager (a test, a harness) the removal still happens and nothing is registered.
    @MainActor func testWithoutAManagerTheMarkIsStillRemoved() {
        let (measurements, marks, session) = three()
        MarkUndo.remove([marks[0].id], in: measurements, session: session, undoManager: nil)
        XCTAssertEqual(measurements.marks.count, 2)
    }

    func testTheActionNameSaysWhatWent() {
        let distance = ImageMark(kind: .distance, points: [ImagePoint(x: 0, y: 0), ImagePoint(x: 1, y: 1)])
        XCTAssertEqual(MarkUndo.actionName([distance]), "Remove Distance")
        XCTAssertEqual(MarkUndo.actionName([distance, distance]), "Remove All Marks")
    }

    /// The undo holds the image's owner weakly, never the pixels (#577): once the session is gone, Undo does nothing and the image is free.
    @MainActor func testTheUndoDoesNotKeepTheImage() {
        let undo = manager()
        weak var weakSession: ImageSession?
        do {
            let (m, marks, session) = three()
            weakSession = session
            undo.beginUndoGrouping()
            MarkUndo.remove([marks[0].id], in: m, session: session, undoManager: undo)
            undo.endUndoGrouping()
        }
        XCTAssertNil(weakSession, "the undo stack keeps no session, so no pixels")
        undo.undo()
    }
}
