//
//  AtomModelSpecimenTests.swift
//  Open an atom model as the specimen (#914, plan row MA14): a model built elsewhere (extended XYZ with a cell, plain XYZ without
//  one, CIF, POSCAR) is read once, kept by the document, and simulated in the phase's place. The beam runs along the model's c by
//  default (a or b on ask) and the model's own thickness is the slab's; a model without a cell gets 5 Å of vacuum around it; the
//  design's limits and sentences hold (a million atoms, an unknown format named with the converters' hint, a grid over 4096).
//  Red before: there was no atom model specimen.
//

import XCTest
import SimulatoCore
import TEMCore
import TEMSession

nonisolated final class AtomModelSpecimenTests: XCTestCase {

    /// Two fcc Al cells stacked along c (4.05 × 4.05 × 8.1 Å, 8 atoms), as extended XYZ.
    private let stacked = """
    8
    Lattice="4.05 0 0 0 4.05 0 0 0 8.1" Properties=species:S:1:pos:R:3 pbc="T T T"
    Al 0 0 0
    Al 0 2.025 2.025
    Al 2.025 0 2.025
    Al 2.025 2.025 0
    Al 0 0 4.05
    Al 0 2.025 6.075
    Al 2.025 0 6.075
    Al 2.025 2.025 4.05
    """

    private func model(_ text: String, _ name: String) throws -> AtomModelSpecimen {
        try AtomModelSpecimen(bytes: Data(text.utf8), fileName: name)
    }

    /// Mutation: the beam not along c by default, the model repeated along the beam, a or b not turning it, the counts lost - red.
    func testAnExtendedXYZModelIsTheSlabAlongItsC() throws {
        let m = try model(stacked, "Al stack.xyz")
        XCTAssertEqual(m.name, "Al stack")
        XCTAssertEqual(m.countsText, "Al 8")
        let alongC = try m.build(beamAlong: .c).get()
        XCTAssertEqual(alongC.box.x, 4.05, accuracy: 1e-9)
        XCTAssertEqual(alongC.box.y, 4.05, accuracy: 1e-9)
        XCTAssertEqual(alongC.box.z, 8.1, accuracy: 1e-9)
        XCTAssertEqual(alongC.periods, 1, "the model's own thickness, never repeated")
        XCTAssertEqual(alongC.slabAtoms, 8)
        XCTAssertTrue(m.summary(alongC, beam: .c).hasPrefix("Al stack: 8 atoms (Al 8), box "))
        XCTAssertTrue(m.summary(alongC, beam: .c).hasSuffix("beam along c."))
        let alongA = try m.build(beamAlong: .a).get()
        XCTAssertEqual(alongA.box.z, 4.05, accuracy: 1e-9, "along a the slab is a thick")
        XCTAssertEqual(alongA.slabAtoms, 8)
        XCTAssertTrue(m.notes(alongC).isEmpty, m.notes(alongC).joined(separator: "\n"))
    }

    /// A plain XYZ has no cell: the model is an isolated object with 5 Å of vacuum on every side, and the section says so.
    /// Mutation: no vacuum, vacuum on one side only, the note dropped - red.
    func testAModelWithoutACellGetsFiveAngstromsOfVacuum() throws {
        let m = try model("2\nCO\nC 0 0 0\nO 0 0 1.128\n", "CO.xyz")
        XCTAssertFalse(m.hasCell)
        let built = try m.build(beamAlong: .c).get()
        XCTAssertEqual(built.box.x, 10, accuracy: 1e-9)
        XCTAssertEqual(built.box.y, 10, accuracy: 1e-9)
        XCTAssertEqual(built.box.z, 11.128, accuracy: 1e-9)
        XCTAssertTrue(m.notes(built).contains { $0.hasPrefix("This file has no cell. The model is simulated as an isolated object with 5 Å") })
    }

    /// Atoms outside the cell are wrapped and counted; atoms closer than 0.5 Å are counted for a chip. Mutation: either count
    /// off by one, or a pair counted twice - red.
    func testWrappedAndCloseAtomsAreCounted() throws {
        let text = """
        3
        Lattice="4 0 0 0 4 0 0 0 4" Properties=species:S:1:pos:R:3 pbc="T T T"
        Al 1 1 1
        Al 1.3 1 1
        Al 5 2 2
        """
        let m = try model(text, "odd.xyz")
        XCTAssertEqual(m.wrappedCount, 1)
        XCTAssertEqual(m.closePairCount, 1)
        let notes = m.notes(try m.build(beamAlong: .c).get())
        XCTAssertTrue(notes.contains("1 atom lies outside the cell and is wrapped into it."), notes.joined(separator: "\n"))
        XCTAssertTrue(notes.contains { $0.hasPrefix("1 pair of atoms is closer than 0.5 Å") }, notes.joined(separator: "\n"))
    }

    /// Pairs are counted across the cell's faces on wrapped positions: an atom at the far face (fractional 1.0) sits on its twin
    /// at 0, and one 0.2 Å inside the far face is 0.2 Å from an atom at 0. Mutation: unwrapped positions, no periodic image -
    /// red.
    func testCloseAtomsAreCountedAcrossTheCellsFaces() throws {
        let text = """
        3
        Lattice="4 0 0 0 4 0 0 0 4" Properties=species:S:1:pos:R:3 pbc="T T T"
        Al 0 1 1
        Al 4 1 1
        Al 3.8 3 3
        """
        let m = try model(text, "faces.xyz")
        XCTAssertEqual(m.wrappedCount, 1, "fractional 1.0 lies outside [0, 1)")
        XCTAssertEqual(m.closePairCount, 1, "the atom at 4 Å is the one at 0")
        let twins = try model("2\nLattice=\"4 0 0 0 4 0 0 0 4\" Properties=species:S:1:pos:R:3 pbc=\"T T T\"\nAl 0.1 2 2\nAl 3.9 2 2\n", "twins.xyz")
        XCTAssertEqual(twins.closePairCount, 1, "0.2 Å apart through the face")
    }

    /// The design's sentences: an unknown format is refused by name with the converters' hint, the atom limit with grouped
    /// counts, a grid over 4096 with its size. Mutation: a format read as XYZ, another limit, ungrouped counts - red.
    func testTheDesignsRefusalsAreItsSentences() throws {
        XCTAssertThrowsError(try model("whatever", "grain.lmp")) { error in
            XCTAssertEqual((error as? AtomModelSpecimen.Refusal)?.sentence,
                           "grain.lmp is not a CIF, XYZ or POSCAR file. LAMMPS, PDB and CFG models open after atomsk or ASE converts them to one.")
        }
        XCTAssertEqual(AtomModelSpecimen.Refusal.tooManyAtoms(2_400_000).sentence, "This model has 2 400 000 atoms. The limit is 1 000 000.")
        XCTAssertTrue(AtomModelSpecimen.Refusal.gridTooLarge(nx: 8100, ny: 8100, sampling: 0.05).sentence
            .hasPrefix("This model needs a grid of 8100 x 8100 at 0.05 Å. The largest is 4096."))
        XCTAssertEqual(AtomModelSpecimen.grouped(999), "999")
        XCTAssertEqual(AtomModelSpecimen.grouped(1_000_000), "1 000 000")
        // 410 Å across at 0.05 Å is 8200 points: refused before any run.
        let wide = "1\nLattice=\"410 0 0 0 4 0 0 0 4\" Properties=species:S:1:pos:R:3 pbc=\"T T T\"\nAl 0 0 0\n"
        guard case .failure(let refusal) = try model(wide, "wide.xyz").build(beamAlong: .c) else { return XCTFail("a grid over 4096 built") }
        XCTAssertTrue(refusal.sentence.hasPrefix("This model needs a grid of "), refusal.sentence)
    }

    /// The document simulates the model in the phase's place, with no phase shown; the thickness field does not key it, the beam
    /// axis does, and back to Phase the model is gone. Mutation: the phase still required, the thickness rebuilding the model,
    /// the axis ignored - red.
    @MainActor
    func testTheDocumentSimulatesTheModelInThePhasesPlace() async throws {
        let simulation = SimulationModel()
        XCTAssertTrue(isNoPhase(simulation.specimen(crystal: nil, zoneAxis: SIMD3(0, 0, 1))))
        simulation.useAtomModel(try model(stacked, "Al stack.xyz"))
        if case .failure(.building) = simulation.specimen(crystal: nil, zoneAxis: SIMD3(0, 0, 1)) {} else {
            XCTFail("the slab is built off the main actor, not while drawing")
        }
        await simulation.buildModelSlabs()
        XCTAssertNotNil(simulation.sourceIdentity(crystal: nil))
        let built = try simulation.specimen(crystal: nil, zoneAxis: SIMD3(1, 1, 0)).get()
        XCTAssertEqual(built.box.z, 8.1, accuracy: 1e-9)
        simulation.setThickness(nm: 50)
        XCTAssertEqual(try simulation.specimen(crystal: nil, zoneAxis: SIMD3(0, 0, 1)).get().periods, 1)
        simulation.setBeamAxis(.b)
        await simulation.buildModelSlabs()
        XCTAssertEqual(try simulation.specimen(crystal: nil, zoneAxis: SIMD3(0, 0, 1)).get().box.z, 4.05, accuracy: 1e-9)
        XCTAssertEqual(simulation.thermalTurnedOn(crystal: nil)?.sigmas.keys.sorted(), [13])
        simulation.useAtomModel(nil)
        XCTAssertEqual(simulation.beamAxis, .c)
        XCTAssertTrue(isNoPhase(simulation.specimen(crystal: nil, zoneAxis: SIMD3(0, 0, 1))))
    }

    private func isNoPhase(_ result: Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>) -> Bool {
        if case .failure(.noPhase) = result { return true }
        return false
    }
}
