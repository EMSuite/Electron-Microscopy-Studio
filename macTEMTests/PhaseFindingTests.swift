//
//  PhaseFindingTests.swift
//  The Find Phases core of plan rows R13 and R14 (#812, #813): candidates ranked against rings or spots by the kit
//  (`PhaseFinder.rank`, S11), each row the kit's numbers, ties kept together, and the sheet's sentences. Planted truth: gold's
//  rings with the scale held rank gold first; with the scale free gold and aluminium (0.7 % apart) are one tie. Red before: the
//  app had no phase finder.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation
import DiffractoScattering
import TEMCore

nonisolated final class PhaseFindingTests: XCTestCase {

    private static let candidates = [
        PhaseCandidate(name: "Al", structure: CrystalPresets.aluminum, source: .myPhases, formula: "Al", spaceGroup: "Fm-3m"),
        PhaseCandidate(name: "Au", structure: CrystalPresets.gold, source: .myPhases, formula: "Au", spaceGroup: "Fm-3m"),
        PhaseCandidate(name: "Si", structure: CrystalPresets.silicon, source: .materialsProject),
        PhaseCandidate(name: "Fe", structure: CrystalPresets.iron, source: .materialsProject),
    ]

    /// Gold's first six rings, exact.
    private func goldRings() throws -> [Double] {
        Array(try CrystalPresets.gold.kinematicReflections(kMax: 1.2, retainingAll: false).families.map(\.family.g).prefix(6))
    }

    /// The rows are the kit's scores, in the kit's order, with the candidates' names, formulas and sources.
    func testRowsAreTheKitsScores() throws {
        let q = try goldRings()
        let result = try PhaseFinding.rank(.rings(q), candidates: Self.candidates)
        let kit = try PhaseFinder.rank(rings: q, candidates: Self.candidates.map(\.structure))
        XCTAssertEqual(result.rows.map(\.id), kit.map(\.candidate))
        XCTAssertEqual(result.rows.map(\.explained), kit.map(\.explained))
        XCTAssertEqual(result.rows.map(\.strongMissing), kit.map { Optional($0.strongMissing) })
        XCTAssertEqual(result.rows.map(\.tie), kit.map(\.tie))
        XCTAssertEqual(result.rows.map(\.scale), kit.map(\.scale))
        XCTAssertEqual(result.rows.compactMap(\.misfitPercent), kit.map { 100 * $0.misfit })
        let au = try XCTUnwrap(result.rows.first { $0.name == "Au" })
        XCTAssertEqual(au.formula, "Au")
        XCTAssertEqual(au.spaceGroup, "Fm-3m")
        XCTAssertEqual(au.source, .myPhases)
        XCTAssertEqual(result.sourceSentence, "2 phases from My Phases, 2 from Materials Project")
        XCTAssertEqual(result.materialsProjectNote?.hasPrefix("Materials Project holds calculated"), true)
    }

    /// The scale held: gold first, at scale 1. The scale free: gold and aluminium one tie, and the sheet says why.
    func testGoldFirstWithTheScaleHeldAndTiedWithAluminiumWhenFree() throws {
        let q = try goldRings()
        let held = try PhaseFinding.rank(.rings(q), candidates: Self.candidates, fitScale: false)
        XCTAssertEqual(held.rows.first?.name, "Au")
        XCTAssertTrue(held.rows.allSatisfy { $0.scale == 1 })
        XCTAssertEqual(held.rows.first?.explained, 6)
        let free = try PhaseFinding.rank(.rings(q), candidates: Self.candidates, fitScale: true)
        let first = free.tie(free.rows[0].tie).map(\.name)
        XCTAssertTrue(first.contains("Au") && first.contains("Al"), "\(first)")
        let sentence = try XCTUnwrap(free.tieSentence(free.rows[0].tie))
        XCTAssertTrue(sentence.contains("fit equally well. This pattern cannot tell them apart"), sentence)
        XCTAssertTrue(sentence.contains("their scales differ by 0.7 %"), sentence)
        XCTAssertTrue(free.isTied(free.rows[0]))
    }

    /// With elements typed, only phases made of them are ranked (#1151): Ga, As keeps GaAs and leaves Si, Au and Al out; no elements
    /// keep every phase. A group that explains nothing is no tie and gets no "fit equally well". Red before: Si, Au and Al were
    /// ranked beside GaAs and called a tie at 0 of 29. Mutation: intersection instead of subset; the tie sentence for 0 explained.
    func testTypedElementsAndAGroupThatExplainsNothing() {
        XCTAssertFalse(PhaseFinding.isMade(CrystalPresets.silicon, of: ["Ga", "As"]))
        XCTAssertFalse(PhaseFinding.isMade(CrystalPresets.gold, of: ["Ga", "As"]))
        XCTAssertTrue(PhaseFinding.isMade(CrystalPresets.silicon, of: ["C", "Si"]), "a subset of the typed elements")
        XCTAssertTrue(PhaseFinding.isMade(CrystalPresets.silicon, of: ["Si"]))
        XCTAssertTrue(PhaseFinding.isMade(CrystalPresets.silicon, of: []), "no elements: every phase")

        func row(_ id: Int, _ name: String, explained: Int, tie: Int) -> PhaseFindingRow {
            PhaseFindingRow(id: id, name: name, formula: name, spaceGroup: "", source: .myPhases, explained: explained, measured: 29,
                            strongMissing: nil, strongExpected: nil, misfitPercent: nil, rmsDistance: nil, scale: 1, zoneAxis: nil,
                            tie: tie, refusal: nil)
        }
        let result = PhaseFindingResult(pattern: .rings([0.3]), fitScale: true,
                                        rows: [row(0, "GaAs", explained: 11, tie: 0), row(1, "gallium arsenide", explained: 11, tie: 0),
                                               row(2, "Si", explained: 0, tie: 1), row(3, "Au", explained: 0, tie: 1), row(4, "Al", explained: 0, tie: 1)])
        XCTAssertNotNil(result.tieSentence(0), "two phases explaining 11 are a tie")
        XCTAssertNil(result.tieSentence(1), "explaining nothing is no tie")
        XCTAssertFalse(result.isTied(result.rows[2]))
        XCTAssertTrue(result.isTied(result.rows[0]))
    }

    /// The row's sentence says the counts, never a verdict.
    func testRowSentence() throws {
        let q = try goldRings()
        let result = try PhaseFinding.rank(.rings(q), candidates: Self.candidates, fitScale: false)
        let au = try XCTUnwrap(result.rows.first { $0.name == "Au" })
        let text = result.sentence(for: au)
        XCTAssertTrue(text.hasPrefix("Au explains 6 of 6 rings; "), text)
        XCTAssertTrue(text.hasSuffix("misfit 0.0 %"), text)
        XCTAssertFalse(text.contains(" is "), text)
        XCTAssertNil(result.weakSentence)
    }

    /// When no candidate explains half the rings, the sheet says so.
    func testWeakSentence() throws {
        // Rings no candidate has: spaced at 0.37, 0.53, 0.71, 0.89, 1.07 Å⁻¹ (none of the four lattices).
        let result = try PhaseFinding.rank(.rings([0.37, 0.53, 0.71, 0.89, 1.07, 1.13]), candidates: Self.candidates, fitScale: false)
        let best = result.rows.map(\.explained).max() ?? 0
        if 2 * best < 6 {
            XCTAssertEqual(result.weakSentence, "No candidate explains more than \(best) of 6 rings.")
        } else {
            XCTAssertNil(result.weakSentence)
        }
    }

    /// Spots: each row is the solver's best for that phase; aluminium's pattern has aluminium first or tied first.
    func testSpotsRankWithTheSolver() throws {
        let volts = 200_000.0
        let o = try CrystalOrientation(zoneAxis: SIMD3(0, 1, 1), inPlaneAngle: 0.3, cell: CrystalPresets.aluminum.cell)
        let pattern = try SpotPattern.simulate(CrystalPresets.aluminum, orientation: o, volts: volts, kMax: 1.2)
        let strongest = try XCTUnwrap(pattern.spots.map(\.intensity).max())
        let spots = pattern.spots.filter { $0.intensity >= 1e-3 * strongest }.map(\.position)
        let result = try PhaseFinding.rank(.spots(spots, volts: volts), candidates: Self.candidates)
        let kit = try PhaseFinder.rank(spots: spots, candidates: Self.candidates.map(\.structure), volts: volts,
                                       kMax: PatternIndexing.reach)
        XCTAssertEqual(result.rows.map(\.id), kit.map(\.candidate))
        XCTAssertEqual(result.rows.map(\.explained), kit.map(\.explained))
        XCTAssertTrue(result.tie(result.rows[0].tie).contains { $0.name == "Al" })
        let al = try XCTUnwrap(result.rows.first { $0.name == "Al" })
        XCTAssertNil(al.strongMissing)
        XCTAssertNotNil(al.zoneAxis)
        XCTAssertTrue(result.sentence(for: al).hasPrefix("Al explains \(al.explained) of \(spots.count) spots at ["))
    }

    /// The kit's refusals: no ring, one spot.
    func testUnrankablePatternsThrow() {
        XCTAssertThrowsError(try PhaseFinding.rank(.rings([]), candidates: Self.candidates))
        XCTAssertThrowsError(try PhaseFinding.rank(.spots([SIMD2(0.1, 0)], volts: 200_000), candidates: Self.candidates))
    }
}
