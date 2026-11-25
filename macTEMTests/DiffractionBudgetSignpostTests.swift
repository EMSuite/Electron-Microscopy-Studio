//
//  DiffractionBudgetSignpostTests.swift
//  The diffraction simulation's budgets (#797, plan row Q5): turning the crystal redraws the simulated spots (500 reflections) and
//  the crystal view within one frame, and Index answers for one 2048² pattern within 2 s. A shared CI runner's timing is no budget,
//  so here the test checks only that each budget's signpost fires, once per piece of work and never for a cached answer; the
//  budgets themselves are read from those signposts on the reference Mac in the release walk (docs/performance.md, "Diffraction
//  simulation budgets"). Red before: the room had no `diffraction.spots` or `diffraction.index` signpost.
//

import XCTest
import TEMCore
import TEMSession

nonisolated final class DiffractionBudgetSignpostTests: XCTestCase {

    @MainActor private func blankPattern() -> CalibratedImage {
        CalibratedImage(width: 256, height: 256, pixels: [Float](repeating: 1, count: 256 * 256), x: nil, y: nil,
                        fileName: "blank", source: "test", voltage: 200_000)
    }

    @MainActor private func shown(_ image: CalibratedImage) -> DiffractionAnalysis {
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        analysis.typedDeltaQ = 0.01
        analysis.simulation.isShown = true
        analysis.simulation.zoneAxis = SIMD3(0, 0, 1)
        return analysis
    }

    /// A turn of the crystal (the Tilt tool's step, as a drag on the crystal pane lands in `turnByHand`) makes the spots again
    /// inside one `diffraction.spots` interval; a redraw with nothing changed reads the cache and begins none.
    @MainActor func testATurnOfTheCrystalFiresTheSpotsSignpostOnce() throws {
        let image = blankPattern()
        let analysis = shown(image)
        XCTAssertNotNil(try analysis.simulatedSpots(image: image)?.get(), "the spots are drawn before the turn")

        Signposts.startRecording()
        XCTAssertTrue(analysis.tilt(down: 1, across: 0))
        XCTAssertNotNil(try analysis.simulatedSpots(image: image)?.get())
        _ = analysis.simulatedSpots(image: image)   // the same settings: the cached spots
        let names = Signposts.stopRecording()
        XCTAssertEqual(names.filter { $0 == "diffraction.spots" }.count, 1, "\(names)")
    }

    /// Index runs its whole answer (find the spots, the indexer, the orientation) inside one `diffraction.index` interval.
    @MainActor func testIndexFiresTheIndexSignpost() async throws {
        let image = blankPattern()
        let analysis = shown(image)
        XCTAssertNil(analysis.indexBlocker(image: image))

        Signposts.startRecording()
        let task = try XCTUnwrap(analysis.index(image: image), "Index starts")
        await task.value
        let names = Signposts.stopRecording()
        XCTAssertTrue(names.contains("diffraction.index"), "\(names)")
    }
}
