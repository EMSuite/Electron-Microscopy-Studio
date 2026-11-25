//
//  SimulationSpecimenTests.swift
//  A Simulation document's specimen (#893, plan row MA1): the shown phase built along the typed zone axis by SimulatoKit's slab
//  builder. Si [1 1 0] (a 5.4309 Å, the room's standard) gives the box a × a√2 × a√2 with 16 atoms a period and no strain, as abTEM's
//  `orthogonalize_cell` gives for the kit's pin (5.431 × 7.6806 × 7.6806 Å, 16 atoms). The slab and the pattern show the same
//  crystal: the slab's orientation is the pattern's turned about the beam, on the design's validation structures. Red before: there
//  was no specimen.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoMultislice
import TEMCore
import TEMSession
import simd

nonisolated final class SimulationSpecimenTests: XCTestCase {

    private func phase(_ structure: CrystalStructure, name: String = "Si") -> DiffractionCrystal {
        .phase(PhaseCrystal(id: "mp-149", name: name, structure: structure))
    }

    /// Mutation: another box, a cell of the wrong frame, the thickness not rounded to whole periods, the strain not read.
    func testSiliconAlong110ReadsItsBoxAtomsAndStrain() throws {
        let a = 5.4309
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 10).get()
        XCTAssertEqual(built.box.x, a, accuracy: 1e-9)
        XCTAssertEqual(built.box.y, a * 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(built.box.z, a * 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(built.unitAtoms, 16)
        XCTAssertEqual(built.periods, 13, "10 nm is 13.02 periods of 7.680 Å")
        XCTAssertEqual(built.slabAtoms, 16 * 13)
        XCTAssertEqual(built.thicknessNM, 13 * a * 2.0.squareRoot() / 10, accuracy: 1e-12)
        XCTAssertEqual(built.strain, 0, accuracy: 1e-12)
        XCTAssertEqual(SimulationSpecimen.percent(built.strain), "0 %")
    }

    /// The pattern and the slab are one crystal: the slab's orientation shares the pattern's zone axis (third column), and the
    /// pattern turned by `inPlaneAngle` is the slab's orientation, on the design's validation structures. Al [0 0 1] needs no turn:
    /// both take a as x. Mutation: the cell built in another frame, the angle's sign or column swapped, the zone axis reversed.
    func testTheSlabsRotationEqualsThePatternsOrientation() throws {
        let cases: [(CrystalStructure, SIMD3<Int>)] = [
            (CrystalPresets.aluminum, SIMD3(0, 0, 1)), (CrystalPresets.aluminum, SIMD3(1, 1, 0)),
            (CrystalPresets.aluminum, SIMD3(1, 1, 1)), (CrystalPresets.aluminum, SIMD3(1, 1, 2)),
            (CrystalPresets.silicon, SIMD3(1, 1, 0)), (CrystalPresets.copper, SIMD3(1, 1, 1)),
            (CrystalPresets.iron, SIMD3(0, 0, 1)), (CrystalPresets.iron, SIMD3(1, 1, 1)),
            (CrystalPresets.magnesium, SIMD3(0, 0, 1)), (CrystalPresets.magnesium, SIMD3(1, 0, 0)),
            (CrystalPresets.betaDoublePrime, SIMD3(0, 1, 0)),
        ]
        for (structure, uvw) in cases {
            let built = try SimulationSpecimen.build(structure, zoneAxis: uvw, thicknessNM: 2, maximumStrain: 0.01).get()
            let slab = built.slab.orientation
            let pattern = try CrystalOrientation(zoneAxis: uvw, inPlaneAngle: 0, cell: structure.cell).matrix
            XCTAssertLessThan(simd_length(slab.columns.2 - pattern.columns.2), 1e-9, "\(uvw): the same zone axis")
            let turned = try CrystalOrientation(zoneAxis: uvw, inPlaneAngle: built.inPlaneAngle, cell: structure.cell).matrix
            for (u, v) in [(turned.columns.0, slab.columns.0), (turned.columns.1, slab.columns.1), (turned.columns.2, slab.columns.2)] {
                XCTAssertLessThan(simd_length(u - v), 1e-9, "\(uvw): the pattern turned by \(built.inPlaneAngle) rad is the slab")
            }
        }
        let al001 = try SimulationSpecimen.build(CrystalPresets.aluminum, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 2).get()
        XCTAssertEqual(al001.inPlaneAngle, 0, accuracy: 1e-12)
    }

    /// A partly occupied site is refused in a sentence that names it. Mutation: the site's label or its occupancy lost.
    func testAPartlyOccupiedSiteSaysItsSentence() {
        let structure = CrystalStructure(cell: UnitCell(a: 4, b: 4, c: 4, alphaDeg: 90, betaDeg: 90, gammaDeg: 90),
                                         sites: [AtomSite(z: 13, fractional: .zero, occupancy: 0.5, label: "Al1")], operations: [])
        guard case .failure(let refusal) = SimulationSpecimen.build(structure, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 2) else {
            return XCTFail("a half-occupied site is refused")
        }
        XCTAssertEqual(refusal, .partialOccupancy(site: "Al1 (Al)", occupancy: 0.5))
        XCTAssertTrue(refusal.sentence.hasPrefix("Site Al1 (Al) is occupied 50 % of the time"), refusal.sentence)
        XCTAssertNil(refusal.acceptableStrain)
    }

    /// A strain over the limit says its sentence with the strain found; Build with Strain builds that crystal along that axis with it, and
    /// only there. β'' along [1 0 0] has no unstrained box within the kit's repetitions, so a limit of zero refuses it. Mutation: the
    /// accepted strain kept for another axis, or not passed to the builder.
    @MainActor func testAStrainOverTheLimitSaysItsSentenceAndUseAnywayBuildsIt() throws {
        let crystal = phase(CrystalPresets.betaDoublePrime, name: "β''")
        let axis = SIMD3(1, 0, 0)
        guard case .failure(let refusal) = SimulationSpecimen.build(crystal.structure, zoneAxis: axis, thicknessNM: 2,
                                                                  maximumStrain: 0) else {
            return XCTFail("β'' [1 0 0] carries some strain")
        }
        let strain = try XCTUnwrap(refusal.acceptableStrain)
        XCTAssertGreaterThan(strain, 0)
        XCTAssertTrue(refusal.sentence.contains("Build with Strain"), refusal.sentence)

        let model = SimulationModel()
        model.acceptStrain(strain, crystal: crystal, zoneAxis: axis)
        XCTAssertEqual(model.maximumStrain(crystal: crystal, zoneAxis: axis), strain)
        XCTAssertEqual(model.maximumStrain(crystal: crystal, zoneAxis: SIMD3(0, 1, 0)), SimulationSpecimen.defaultMaximumStrain,
                       "accepted for this axis only")
        let built = try SimulationSpecimen.build(crystal.structure, zoneAxis: axis, thicknessNM: 2, maximumStrain: strain).get()
        XCTAssertEqual(built.strain, strain)
    }

    /// The document's model: no phase asks for one; the thickness is kept in its range and changes the periods. Mutation: a nil
    /// crystal built anyway, the range not kept, the cache keyed without the thickness.
    @MainActor func testTheModelAsksForAPhaseAndFollowsTheThickness() throws {
        let model = SimulationModel()
        XCTAssertEqual(model.specimen(crystal: nil, zoneAxis: SIMD3(1, 1, 0)), .failure(.noPhase))
        XCTAssertEqual(SimulationSpecimen.Refusal.noPhase.sentence, "Add a phase to simulate.")
        let si = phase(CrystalPresets.silicon)
        XCTAssertEqual(try model.specimen(crystal: si, zoneAxis: SIMD3(1, 1, 0)).get().periods, 13)
        model.setThickness(nm: 5)
        XCTAssertEqual(try model.specimen(crystal: si, zoneAxis: SIMD3(1, 1, 0)).get().periods, 7, "5 nm is 6.51 periods")
        model.setThickness(nm: 1e6)
        XCTAssertEqual(model.thicknessNM, SimulationSpecimen.thicknessRangeNM.upperBound)
        model.setThickness(nm: .nan)
        XCTAssertEqual(model.thicknessNM, SimulationSpecimen.thicknessRangeNM.upperBound, "a non-finite value changes nothing")
    }
}
