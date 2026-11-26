//
//  DiffractionVariantsTests.swift
//  A precipitate in the Diffraction room's crystal (#808): without Index's matrix orientation the room says so; a relationship is
//  typed as a paper states it ("(h k l)" a plane, "[u v w]" a direction, a minus or an overbar); a new precipitate or relationship
//  shows every variant again; and β″ in Al placed on the planted Au pattern's scale lands each merged spot where the readout's
//  scale puts its q. Red before: the room had no precipitate.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession

nonisolated final class DiffractionVariantsTests: XCTestCase {

    @MainActor func testWithoutAMatrixOrientationTheRoomSaysSo() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        analysis.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named("Al"))))
        let variants = DiffractionVariants()
        variants.setPrecipitate(.init(name: "Si", structure: CrystalPresets.silicon))
        variants.setRelationship(VariantPlacement.betaDoublePrimeInAluminium)
        XCTAssertNil(variants.placed, "nothing placed before a placement lands")
        await variants.place(try XCTUnwrap(variants.inputs(analysis: analysis, image: image)))
        let result = try XCTUnwrap(variants.variants(analysis: analysis, image: image))
        XCTAssertEqual(result, .failure(.noMatrixOrientation))
        XCTAssertEqual(VariantRefusal.noMatrixOrientation.sentence, "Index the matrix first. Variants are placed from its orientation.")
    }

    /// Mutation: the guard for what is already placed not dropping the placement in flight - red (B lands over A).
    @MainActor func testGoingBackToWhatIsPlacedDropsThePlacementInFlight() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let variants = DiffractionVariants()
        let a = try XCTUnwrap(variants.inputs(analysis: analysis, image: image))
        var b = a
        b.volts = a.volts / 2
        await variants.place(a)
        XCTAssertEqual(variants.placed?.inputs, a)
        let inFlight = Task { await variants.place(b) }
        try await waitUntil("B to be in flight", seconds: 10) { variants.placing == b || variants.placed?.inputs == b }
        await variants.place(a)
        await inFlight.value
        XCTAssertEqual(variants.placed?.inputs, a, "the room went back to A: B's answer, landing late, is stale")
        XCTAssertNil(variants.placing)
    }

    func testARelationshipIsTypedAsAPaperStatesIt() {
        XCTAssertEqual(RelationshipVector.parse("[1 0 0]"), RelationshipVector(.direction, 1, 0, 0))
        XCTAssertEqual(RelationshipVector.parse(" (0 0 1) "), RelationshipVector(.plane, 0, 0, 1))
        XCTAssertEqual(RelationshipVector.parse("[1 -3 0]"), RelationshipVector(.direction, 1, -3, 0))
        XCTAssertEqual(RelationshipVector.parse("[13\u{0304}0]"), RelationshipVector(.direction, 1, -3, 0))
        XCTAssertNil(RelationshipVector.parse("1 0 0"), "a vector says whether it is a plane or a direction")
        XCTAssertNil(RelationshipVector.parse("[0 0 0]"))
        XCTAssertNil(RelationshipVector.parse("(1 0]"))
        for v in [RelationshipVector(.plane, 1, 1, 1), RelationshipVector(.direction, 3, 2, 0)] {
            XCTAssertEqual(RelationshipVector.parse(v.text), v, "a vector reads back as it is written")
        }
    }

    @MainActor func testANewPrecipitateOrRelationshipShowsEveryVariantAgain() {
        let variants = DiffractionVariants()
        variants.setHidden(2, true)
        variants.setHidden(5, true)
        variants.setHidden(5, false)
        XCTAssertEqual(variants.hidden, [2])
        variants.setPrecipitate(.init(name: "Si", structure: CrystalPresets.silicon))
        XCTAssertEqual(variants.hidden, [])
        variants.setHidden(1, true)
        variants.setRelationship(VariantPlacement.betaDoublePrimeInAluminium)
        variants.setHidden(1, true)
        var other = VariantPlacement.betaDoublePrimeInAluminium
        other.secondMatrix = RelationshipVector(.direction, 3, -1, 0)
        variants.setRelationship(other)
        XCTAssertEqual(variants.hidden, [])
    }

    /// #1137, #1152. Mutation: a precipitate or a relationship chosen by default - red.
    @MainActor func testNothingIsChosenForThePerson() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let variants = DiffractionVariants()
        XCTAssertNil(variants.precipitate)
        XCTAssertNil(variants.relationship)
        await variants.place(try XCTUnwrap(variants.inputs(analysis: analysis, image: image)))
        XCTAssertEqual(variants.variants(analysis: analysis, image: image), .failure(.noPrecipitate))
        variants.setPrecipitate(.init(name: "Si", structure: CrystalPresets.silicon))
        await variants.place(try XCTUnwrap(variants.inputs(analysis: analysis, image: image)))
        XCTAssertEqual(variants.variants(analysis: analysis, image: image), .failure(.noRelationship))
        XCTAssertEqual(VariantRefusal.noRelationship.sentence, "Type the orientation relationship as a paper states it: two parallel pairs.",
                       "no literature example is offered (#1152)")

        var typed = VariantPlacement.betaDoublePrimeInAluminium
        typed.secondMatrix = RelationshipVector(.direction, 3, -1, 0)
        variants.setRelationship(typed)
        variants.setPrecipitate(.init(name: "Al", structure: CrystalPresets.aluminum))
        XCTAssertEqual(variants.relationship, typed, "a typed relationship stays with a new precipitate")
    }

    @MainActor func testTheSpotsLandWhereTheScalePutsTheirQ() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let family = try XCTUnwrap(analysis.standardFamilies().first { $0.name == "{111}" })
        await analysis.fitRing(image: image, inner: 29, outer: 37, calibrateOn: family.family)?.value
        let orientation = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell)
        let set = try VariantPlacement.place(precipitate: "β″", precipitateStructure: CrystalPresets.betaDoublePrime, matrix: "Al",
                                             matrixStructure: CrystalPresets.aluminum,
                                             relationship: VariantPlacement.betaDoublePrimeInAluminium,
                                             matrixOrientation: orientation, volts: 200_000).get()
        XCTAssertEqual(set.rows.count, 12)
        let pixels = DiffractionVariants().pixels(of: set, analysis: analysis, image: image)
        XCTAssertFalse(pixels.isEmpty)
        let centre = try XCTUnwrap(analysis.centre)
        let calibration = try XCTUnwrap(analysis.calibration(for: image))
        for p in pixels {
            let r = ((p.row - centre.row) * (p.row - centre.row) + (p.column - centre.column) * (p.column - centre.column)).squareRoot()
            let measured = calibration.q(radius: r)
            XCTAssertTrue(set.spots.contains { s in
                s.members.map(\.variant) == p.variants
                    && abs((s.position.x * s.position.x + s.position.y * s.position.y).squareRoot() - measured) <= 1e-9 * measured
            }, "a spot at q \(measured) of variants \(p.variants)")
            XCTAssertLessThanOrEqual(p.relative, 1)
        }
    }
}
