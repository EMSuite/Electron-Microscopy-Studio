//
//  VariantDoubleDiffractionTests.swift
//  Double diffraction between the matrix and its precipitate's variants (#809): β″ in Al down [0 0 1] adds spots between the
//  crystals, each the kit's (`DoubleDiffraction.spots(crystals:)`) between two crystals with its routes in words; never more than
//  the cap are drawn, and the sentence says how many there are; with every variant hidden there are none. Red before: no such spots.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import TEMCore

nonisolated final class VariantDoubleDiffractionTests: XCTestCase {

    private func setting() throws -> (VariantSet, CrystalOrientation) {
        let orientation = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell)
        let set = try VariantPlacement.place(precipitate: "β″", precipitateStructure: CrystalPresets.betaDoublePrime, matrix: "Al",
                                             matrixStructure: CrystalPresets.aluminum,
                                             relationship: VariantPlacement.betaDoublePrimeInAluminium,
                                             matrixOrientation: orientation, volts: 200_000).get()
        return (set, orientation)
    }

    private func added(_ set: VariantSet, _ orientation: CrystalOrientation, hidden: Set<Int> = [], cap: Int = 200) throws
        -> VariantDoubleDiffraction {
        try VariantPlacement.doubleDiffraction(set: set, matrixStructure: CrystalPresets.aluminum, matrixOrientation: orientation,
                                               precipitateStructure: CrystalPresets.betaDoublePrime, volts: 200_000, hidden: hidden,
                                               cap: cap)
    }

    func testTheSpotsAreTheKitsBetweenCrystals() throws {
        let (set, orientation) = try setting()
        let all = try added(set, orientation, cap: .max)
        XCTAssertGreaterThan(all.total, 0)
        XCTAssertEqual(all.spots.count, all.total)
        XCTAssertTrue(all.spots.allSatisfy { !$0.routes.isEmpty })
        XCTAssertTrue(all.spots.allSatisfy { $0.routes.allSatisfy { $0.contains(" then ") } })
        XCTAssertEqual(all.countSentence, "\(all.total) spots by double diffraction between the crystals, drawn as dashed rings.")
    }

    /// Mutation: keeping the kit's variant-with-variant sums - red (two variants shown, every route must pass through Al).
    func testEveryRouteGoesThroughTheMatrix() throws {
        let (set, orientation) = try setting()
        let twoShown = Set(set.variants.map(\.index).dropFirst(2))
        let added = try added(set, orientation, hidden: twoShown, cap: .max)
        XCTAssertGreaterThan(added.total, 0)
        for spot in added.spots {
            XCTAssertTrue(spot.routes.allSatisfy { $0.hasPrefix("Al: ") || $0.contains(" then Al: ") }, "\(spot.routes)")
        }
    }

    func testNeverMoreThanTheCapIsDrawn() throws {
        let (set, orientation) = try setting()
        let capped = try added(set, orientation, cap: 3)
        XCTAssertEqual(capped.spots.count, min(3, capped.total))
        if capped.total > 3 {
            XCTAssertEqual(capped.countSentence,
                           "\(capped.total) spots by double diffraction between the crystals: 3 of them drawn, the strongest routes first.")
        }
    }

    func testWithEveryVariantHiddenThereAreNone() throws {
        let (set, orientation) = try setting()
        let none = try added(set, orientation, hidden: Set(set.variants.map(\.index)))
        XCTAssertEqual(none.total, 0)
        XCTAssertEqual(none.countSentence, "No spot by double diffraction between the crystals in this view.")
    }
}
