//
//  DiffractionPhaseFinderTests.swift
//  Find Phases for an open pattern (#812) on the planted Au pattern (`DemoDocuments.diffractionPattern`): with nothing measured
//  it says why it cannot run; with the {111} ring calibrated it reads the ring's q from the readout, and its ranking is the core's
//  (`PhaseFinding.rank`, whose gold-ring truth PhaseFindingTests pins) on the same rings and candidates, Fit scale on or off, and a ranking
//  stops being current once the ring it ranked is gone.
//  The candidates are the room's crystal first, then its standards, each once. Red before: the room had no Find Phases.
//

import XCTest
import DiffractoCore
import DiffractoOrientation
import DiffractoScattering
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionPhaseFinderTests: XCTestCase {

    @MainActor private func candidates() -> [PhaseCandidate] {
        StandardCrystals.all.map { PhaseCandidate(name: $0.name, structure: $0.structure, source: .myPhases) }
    }

    /// The demo file carries its own scale, so with nothing measured the finder asks for a ring or spots.
    @MainActor func testWithNothingMeasuredItSaysWhy() {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        XCTAssertNotNil(analysis.calibration(for: image), "the demo file states its scale")
        XCTAssertEqual(DiffractionPhaseFinder.blocker(analysis: analysis, image: image), "Fit a ring or mark spots first")
        XCTAssertNil(DiffractionPhaseFinder().run(analysis: analysis, image: image, candidates: candidates()))
    }

    @MainActor func testTheRankingIsTheCoresOnTheRoomsRings() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let family = try XCTUnwrap(analysis.standardFamilies().first { $0.name == "{111}" })
        await analysis.fitRing(image: image, inner: 29, outer: 37, calibrateOn: family.family)?.value
        XCTAssertNil(DiffractionPhaseFinder.blocker(analysis: analysis, image: image))
        let pattern = try XCTUnwrap(DiffractionPhaseFinder.pattern(analysis: analysis, image: image))
        let q = try XCTUnwrap(analysis.readout(image: image).first?.q)
        XCTAssertEqual(pattern, .rings([q]))

        let finder = DiffractionPhaseFinder()
        for fit in [true, false] {
            finder.fitScale = fit
            await finder.run(analysis: analysis, image: image, candidates: candidates())?.value
            XCTAssertFalse(finder.isRunning)
            XCTAssertNil(finder.refusal)
            XCTAssertEqual(finder.result, try PhaseFinding.rank(pattern, candidates: candidates(), fitScale: fit))
        }
        XCTAssertEqual(finder.current(analysis: analysis, image: image), finder.result, "the ranking is of the pattern shown")
        analysis.removeAll()
        XCTAssertNil(finder.current(analysis: analysis, image: image), "the ring is gone: the ranking is not shown as current")
    }

    @MainActor func testTheCellsSayWhatTheRowSays() throws {
        let q = Array(try CrystalPresets.gold.kinematicReflections(kMax: 1.2, retainingAll: false).families.map(\.family.g).prefix(6))
        let result = try PhaseFinding.rank(.rings(q), candidates: candidates(), fitScale: false)
        let au = try XCTUnwrap(result.rows.first { $0.name == "Au" })
        XCTAssertEqual(result.rows.first?.name, "Au", "the scale held: gold first")
        XCTAssertEqual(DiffractionPhaseText.explains(au), "\(au.explained) of 6")
        XCTAssertEqual(DiffractionPhaseText.scale(au, fitScale: false), "fixed")
        XCTAssertEqual(DiffractionPhaseText.misfit(au), Num.fixed(au.misfitPercent ?? .nan, 1) + " %")
    }
}
