//
//  FFTFindSpotsOffMainTests.swift
//  Find Spots runs the finder off the main actor (#623): it hands back its run, the room's button is off while it runs, its peaks land only
//  on the spectrum they were found on, and a newer Find Spots supersedes an older one.
//

import XCTest
import TEMCore
import TEMSession

nonisolated final class FFTFindSpotsOffMainTests: XCTestCase {

    /// Awaited, the run puts the planted reflections on the transform; a transform changed while it ran takes none of its peaks. Red under:
    /// the peaks landing on a spectrum they were not found on; the running flag left on.
    @MainActor func testTheFoundPeaksLandOnlyOnTheirSpectrum() async throws {
        let analysis = FFTAnalysis(compute: .live)
        analysis.show(try FFTPreprocessTests.lattice(), contentVersion: 1)
        try await waitUntil("the spectrum to land", seconds: 10) { analysis.isSpectrumCurrent }

        let run = analysis.findSpots()
        XCTAssertTrue(analysis.isFindingSpots, "the button is off while the finder runs")
        await run.value
        XCTAssertFalse(analysis.isFindingSpots)
        XCTAssertEqual(analysis.spots.count, 2, "the planted lattice's two reflections")

        let stale = analysis.findSpots()
        analysis.setPreprocess(FFTPreprocess(window: .hann))
        await stale.value
        XCTAssertTrue(analysis.spots.isEmpty, "the peaks of the old transform are not put on the new one")
        XCTAssertFalse(analysis.isFindingSpots)
        XCTAssertNil(analysis.findSpotsFailure)
    }

    /// Two Find Spots in a row put one set of spots on the transform. Red under: an older run landing after a newer one.
    @MainActor func testANewerFindSupersedesAnOlderOne() async throws {
        let analysis = FFTAnalysis(compute: .live)
        analysis.show(try FFTPreprocessTests.lattice(), contentVersion: 1)
        try await waitUntil("the spectrum to land", seconds: 10) { analysis.isSpectrumCurrent }
        let first = analysis.findSpots(), second = analysis.findSpots()
        await first.value
        await second.value
        XCTAssertEqual(analysis.spots.count, 2)
        XCTAssertEqual(analysis.spots.map(\.number), [1, 2])
    }
}
