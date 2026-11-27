//
//  FFTSpotUndoTests.swift
//  Edit > Undo for removing FFT room spots (#325, second part; App/FFTSpotUndo.swift): with a real UndoManager, a removed spot comes back
//  with its id, number, answer and In Mask at its place in the list; redo removes it again; Remove All is one undo; ⌫ on the room
//  registers it; an undo after a new region does nothing. Red before: no undo registered, Edit > Undo always dimmed.
//

import Foundation
import TEMCore
import TEMSession
import ImagoCore
import ImagoFFT
import XCTest
@testable import EMStudio

nonisolated final class FFTSpotUndoTests: XCTestCase {
    /// An owner whose lanes answer at once (PaneKeysTests' arrangement), with three spots on region A's spectrum, all answered.
    @MainActor private func threeSpots() async throws -> FFTAnalysis {
        let analysis = FFTAnalysis(compute: FFTCompute(
            spectrum: { _, key in FFTAnalysisTests.fakeSpectrum(key) },
            spot: { _, _, row, col in
                do { return .measured(try FFTAnalysisTests.measured(row: row, col: col)) } catch let error as SpotMeasurementError {
                    return .refused(error)
                } catch { return .measuring }
            },
            maskedInverse: { _, key in FFTMaskedInverseProduct(key: key, canvas: FFTAnalysisTests.fakeCanvas(), imaginaryMax: 0) },
            filter: { _, key in
                FFTFilterProduct(key: key, absf: FFTAnalysisTests.fakeCanvas(), wiener: FFTAnalysisTests.fakeCanvas(), n: 64,
                                 passes: 3, finalDelta: 4.5)
            }))
        analysis.setRegion(FFTAnalysisTests.regionA, committed: true)
        analysis.show(FFTAnalysisTests.plant(), contentVersion: 1)
        try await waitUntil("the spectrum", seconds: 5) { analysis.isSpectrumCurrent }
        for (row, col) in [(37, 40), (29, 44), (31, 33)] { analysis.measureSpot(row: row, col: col) }
        try await waitUntil("the spots are answered", seconds: 5) {
            analysis.spots.count == 3 && analysis.spots.allSatisfy { if case .measuring = $0.outcome { false } else { true } }
        }
        return analysis
    }

    @MainActor private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @MainActor private func remove(_ ids: [FFTSpot.ID], _ analysis: FFTAnalysis, _ undo: UndoManager) {
        undo.beginUndoGrouping()
        FFTSpotUndo.remove(ids, in: analysis, undoManager: undo)
        undo.endUndoGrouping()
    }

    @MainActor func testUndoPutsARemovedSpotBackInItsPlaceAndRedoRemovesItAgain() async throws {
        let analysis = try await threeSpots()
        let spots = analysis.spots
        analysis.setInMask(spots[1].id, !spots[1].inMask)
        let inMask = analysis.spots[1].inMask
        let undo = manager()
        remove([spots[1].id], analysis, undo)
        XCTAssertEqual(analysis.spots.map(\.id), [spots[0].id, spots[2].id])
        XCTAssertEqual(undo.undoActionName, "Remove Spot")

        undo.undo()
        XCTAssertEqual(analysis.spots.map(\.id), spots.map(\.id), "the same spots, in their places")
        XCTAssertEqual(analysis.spots.map(\.number), [1, 2, 3], "with their numbers")
        XCTAssertEqual(analysis.spots[1].inMask, inMask, "and In Mask as it was")
        XCTAssertEqual(analysis.spots[1].measured, spots[1].measured, "and the answer, not asked again")
        XCTAssertTrue(undo.canRedo)

        undo.redo()
        XCTAssertEqual(analysis.spots.map(\.id), [spots[0].id, spots[2].id])
        undo.undo()
        XCTAssertEqual(analysis.spots.map(\.id), spots.map(\.id))
    }

    @MainActor func testRemoveAllIsOneUndoAndTheNextSpotTakesTheNextNumber() async throws {
        let analysis = try await threeSpots()
        let ids = analysis.spots.map(\.id)
        let undo = manager()
        remove(ids, analysis, undo)
        XCTAssertTrue(analysis.spots.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Remove All Spots")
        undo.undo()
        XCTAssertEqual(analysis.spots.map(\.id), ids)
        XCTAssertFalse(undo.canUndo, "one step")
        analysis.measureSpot(row: 40, col: 40)
        XCTAssertEqual(analysis.spots.last?.number, 4, "numbers are not reused while the spots stand")
    }

    /// A new region drops the spots; their undo then does nothing (they belong to a spectrum no longer shown) and offers no redo.
    @MainActor func testAnUndoAfterANewRegionDoesNothing() async throws {
        let analysis = try await threeSpots()
        let undo = manager()
        remove([analysis.spots[0].id], analysis, undo)
        analysis.setRegion(FFTAnalysisTests.flatRegion, committed: true)
        XCTAssertTrue(analysis.spots.isEmpty)
        undo.undo()
        XCTAssertTrue(analysis.spots.isEmpty)
        XCTAssertFalse(undo.canRedo)
    }

    /// ⌫ on the room goes through the same path, so Edit > Undo is offered after it.
    @MainActor func testTheDeleteKeyRegistersTheUndo() async throws {
        let analysis = try await threeSpots()
        let removed = try XCTUnwrap(analysis.spots.last)
        analysis.selection = removed.id
        let undo = manager()
        let keys = FFTRoomKeys(analysis: analysis, active: .spectrum, sourceSize: (96, 64), undoManager: undo)
        undo.beginUndoGrouping()
        XCTAssertTrue(keys.handle(.delete))
        undo.endUndoGrouping()
        XCTAssertEqual(analysis.spots.count, 2)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(analysis.spots.last?.id, removed.id)
    }
}
