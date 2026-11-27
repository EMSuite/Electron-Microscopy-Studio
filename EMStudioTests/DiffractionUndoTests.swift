//
//  DiffractionUndoTests.swift
//  Edit > Undo for removing Diffraction room rings and spots (#325; App/DiffractionUndo.swift), on the planted Au pattern: a removed
//  calibrating ring comes back with the scale it set; Remove All is one undo; Clear on the calibration is undone; redo removes again; an
//  undo after a new mark does nothing.
//  Red before: no undo registered, Edit > Undo always dimmed.
//

import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class DiffractionUndoTests: XCTestCase {
    /// The Au pattern with {111} fitted and calibrating, and one spot.
    @MainActor private func marked() async throws -> (DiffractionAnalysis, CalibratedImage) {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let family = try XCTUnwrap(analysis.standardFamilies().first { $0.name == "{111}" })
        await analysis.fitRing(image: image, inner: 29, outer: 37, calibrateOn: family.family)?.value
        analysis.addSpot(image: image, row: 256, column: 256 + 55.48)
        XCTAssertEqual(analysis.rings.count, 1)
        XCTAssertEqual(analysis.spots.count, 1)
        XCTAssertNotNil(analysis.ringCalibration, "the ring set the scale")
        return (analysis, image)
    }

    @MainActor private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @MainActor private func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @MainActor func testUndoPutsACalibratingRingBackWithItsScale() async throws {
        let (analysis, _) = try await marked()
        let before = analysis.marks
        let undo = manager()
        step(undo) { DiffractionUndo.remove(analysis.rings[0].id, in: analysis, undoManager: undo) }
        XCTAssertTrue(analysis.rings.isEmpty)
        XCTAssertNil(analysis.ringCalibration, "removing the calibrating ring clears its scale")
        XCTAssertEqual(undo.undoActionName, "Remove Ring")

        undo.undo()
        XCTAssertEqual(analysis.marks, before, "the ring, its id and the scale it set")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertTrue(analysis.rings.isEmpty)
        XCTAssertNil(analysis.ringCalibration)
        undo.undo()
        XCTAssertEqual(analysis.marks, before)
    }

    @MainActor func testRemoveAllIsOneUndo() async throws {
        let (analysis, _) = try await marked()
        let before = analysis.marks
        let undo = manager()
        step(undo) { DiffractionUndo.removeAll(in: analysis, undoManager: undo) }
        XCTAssertTrue(analysis.rings.isEmpty && analysis.spots.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Remove All Rings and Spots")
        undo.undo()
        XCTAssertEqual(analysis.marks, before)
        XCTAssertFalse(undo.canUndo, "one step")
    }

    /// Remove Spots (#784) removes the spots only: the calibrating ring and its scale stay, and one undo puts the spots back.
    @MainActor func testRemoveSpotsKeepsTheRingsAndIsOneUndo() async throws {
        let (analysis, _) = try await marked()
        let before = analysis.marks
        let undo = manager()
        step(undo) { DiffractionUndo.removeSpots(in: analysis, undoManager: undo) }
        XCTAssertTrue(analysis.spots.isEmpty)
        XCTAssertEqual(analysis.rings, before.rings)
        XCTAssertNotNil(analysis.ringCalibration, "the ring's scale stays")
        XCTAssertEqual(undo.undoActionName, "Remove Spots")
        undo.undo()
        XCTAssertEqual(analysis.marks, before)
    }

    /// A spot added after the removal is not lost to the undo: it does nothing and offers no redo.
    @MainActor func testAnUndoAfterANewMarkDoesNothing() async throws {
        let (analysis, image) = try await marked()
        let undo = manager()
        step(undo) { DiffractionUndo.remove(analysis.spots[0].id, in: analysis, undoManager: undo) }
        XCTAssertEqual(undo.undoActionName, "Remove Spot")
        analysis.addSpot(image: image, row: 256 - 55.48, column: 256)
        let now = analysis.marks
        undo.undo()
        XCTAssertEqual(analysis.marks, now)
        XCTAssertFalse(undo.canRedo)
    }

    /// Clear on the calibration is undone: the scale and its family come back, the marks untouched; redo clears again.
    @MainActor func testUndoPutsAClearedCalibrationBack() async throws {
        let (analysis, _) = try await marked()
        let before = analysis.marks
        let undo = manager()
        step(undo) { DiffractionUndo.clearCalibration(in: analysis, undoManager: undo) }
        XCTAssertNil(analysis.ringCalibration)
        XCTAssertEqual(analysis.rings.count, 1, "the ring stays")
        XCTAssertEqual(undo.undoActionName, "Clear Calibration")
        undo.undo()
        XCTAssertEqual(analysis.marks, before, "the scale and its family")
        undo.redo()
        XCTAssertNil(analysis.ringCalibration)
    }

    /// Without a manager the removal still happens.
    @MainActor func testWithoutAManagerTheRowIsStillRemoved() async throws {
        let (analysis, _) = try await marked()
        DiffractionUndo.remove(analysis.spots[0].id, in: analysis, undoManager: nil)
        XCTAssertTrue(analysis.spots.isEmpty)
    }
}
