//
//  VariantPlacementTests.swift
//  The variants core of plan row R9 (#808): β″ in Al with the planted relationship ([1 0 0] ∥ [3 2 0] Al exact, [0 0 1] ∥
//  [1 -3 0] Al; Andersen et al. 1998) on an Al orientation gives the kit's 12 variants and its groups, each labelled by where
//  it puts the first pair; hiding a variant removes its spots; without a matrix orientation the room says so; pairs that fix
//  no orientation are refused in words. Red before: the app had no variants.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation
import TEMCore

nonisolated final class VariantPlacementTests: XCTestCase {

    private static let betaInAl = PrecipitateRelationship(
        first: (RelationshipVector(.direction, 1, 0, 0), RelationshipVector(.direction, 3, 2, 0)),
        second: (RelationshipVector(.direction, 0, 0, 1), RelationshipVector(.direction, 1, -3, 0)))

    private func alOrientation() throws -> CrystalOrientation {
        try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), inPlaneAngle: 12 * Double.pi / 180, cell: CrystalPresets.aluminum.cell)
    }

    private func place(hidden: Set<Int> = [], orientation: CrystalOrientation?) -> Result<VariantSet, VariantRefusal> {
        VariantPlacement.place(precipitate: "β″", precipitateStructure: CrystalPresets.betaDoublePrime, matrix: "Al",
                               matrixStructure: CrystalPresets.aluminum, relationship: Self.betaInAl, matrixOrientation: orientation,
                               volts: 200_000, hidden: hidden)
    }

    /// Twelve variants, the kit's orientations and groups, labels from the first pair, and the sentences.
    func testBetaDoublePrimeInAluminiumGivesTheKitsTwelveVariants() throws {
        let m = try alOrientation()
        let set = try place(orientation: m).get()
        let pairs = try XCTUnwrap(Self.betaInAl.pairs)
        var grouping = VariantGroupingSettings()
        grouping.relativeIntensityCut = 0.01
        let kit = try OrientationRelationship.variantOrientations(
            first: pairs.first, second: pairs.second, precipitate: CrystalPresets.betaDoublePrime, matrix: CrystalPresets.aluminum,
            matrixOrientation: m, volts: 200_000, kMax: PatternIndexing.reach, grouping: grouping)
        XCTAssertEqual(set.variants, kit)
        XCTAssertEqual(set.rows.count, 12)
        XCTAssertEqual(set.rows.map(\.group), kit.map(\.group))
        XCTAssertEqual(set.rows.map(\.number), Array(1...12))
        XCTAssertTrue(set.rows.allSatisfy { $0.label.hasPrefix("[1 0 0] ∥ [") && $0.label.hasSuffix("] Al") }, "\(set.rows.map(\.label))")
        XCTAssertEqual(Set(set.rows.map(\.label)).count, 12)
        let groups = Set(kit.map(\.group)).count
        XCTAssertEqual(set.groupCount, groups)
        XCTAssertTrue(set.summarySentence.hasPrefix("β″ in Al · 12 variants, "), set.summarySentence)
        XCTAssertEqual(set.sheetSentence, "12 variants. The second pair is 0.04° from parallel. The first pair is kept exact.")
        let shared = Dictionary(grouping: kit, by: \.group).values.filter { $0.count > 1 }.count
        XCTAssertEqual(set.lookAlikeSentences.count, shared)
        XCTAssertTrue(set.lookAlikeSentences.allSatisfy { $0.hasPrefix("Variants ") && $0.hasSuffix(" predict the same spots in this view") })
        // every drawn spot of every variant is in the merged list, under that variant
        for v in set.variants {
            for s in VariantPlacement.drawn(v.pattern) {
                XCTAssertTrue(set.spots.contains { spot in
                    spot.members.contains { $0.variant == v.index && $0.hkl == s.hkl }
                }, "variant \(v.index) \(s.hkl)")
            }
        }
    }

    /// Hiding a variant removes its spots from the merged list (and nothing else's); its row stays, marked hidden.
    func testHidingAVariantRemovesItsSpots() throws {
        let m = try alOrientation()
        let all = try place(orientation: m).get()
        let some = try place(hidden: [0, 5], orientation: m).get()
        XCTAssertTrue(some.spots.allSatisfy { spot in spot.members.allSatisfy { $0.variant != 0 && $0.variant != 5 } })
        XCTAssertEqual(some.rows.filter(\.isHidden).map(\.id), [0, 5])
        XCTAssertEqual(some.rows.count, 12)
        let shown = all.variants.filter { $0.index != 0 && $0.index != 5 }
        XCTAssertEqual(some.spots, VariantPlacement.merge(shown))
    }

    /// Without the matrix's orientation the room says to index it first; pairs that fix nothing are refused in words.
    func testRefusalsInWords() throws {
        guard case .failure(let none) = place(orientation: nil) else { return XCTFail("placed without a matrix orientation") }
        XCTAssertEqual(none.sentence, "Index the matrix first. Variants are placed from its orientation.")
        var parallel = Self.betaInAl
        parallel.secondPrecipitate = RelationshipVector(.direction, 2, 0, 0)
        let bad = VariantPlacement.place(precipitate: "β″", precipitateStructure: CrystalPresets.betaDoublePrime, matrix: "Al",
                                         matrixStructure: CrystalPresets.aluminum, relationship: parallel,
                                         matrixOrientation: try alOrientation(), volts: 200_000)
        guard case .failure(let why) = bad else { return XCTFail("parallel vectors placed variants") }
        XCTAssertEqual(why.sentence, "These pairs do not fix an orientation.")
        var zero = Self.betaInAl
        zero.firstMatrix = RelationshipVector(.direction, 0, 0, 0)
        XCTAssertNil(zero.pairs)
    }

    /// Words: the relationship, the variant lists, a codable document value.
    func testWords() throws {
        XCTAssertEqual(Self.betaInAl.text(matrix: "Al"), "[1 0 0] ∥ [3 2 0] Al, [0 0 1] ∥ [1 -3 0] Al")
        XCTAssertEqual(RelationshipVector(.plane, 0, 0, 1).text, "(0 0 1)")
        XCTAssertEqual(VariantPlacement.variantsText([2]), "Variant 3")
        XCTAssertEqual(VariantPlacement.variantsText([1, 2]), "Variants 2 and 3")
        XCTAssertEqual(VariantPlacement.variantsText([0, 3, 6]), "Variants 1, 4 and 7")
        let data = try JSONEncoder().encode(Self.betaInAl)
        XCTAssertEqual(try JSONDecoder().decode(PrecipitateRelationship.self, from: data), Self.betaInAl)
    }
}
