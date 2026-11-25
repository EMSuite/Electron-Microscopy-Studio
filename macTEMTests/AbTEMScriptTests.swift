//
//  AbTEMScriptTests.swift
//  Export a run as an abTEM script (#915, plan row MA11): the script rebuilds the run from the app's own numbers. A static run
//  writes the unit the app propagated (atom for atom, every coordinate in Swift's round-trip form), repeated to the slab's periods,
//  the app's grid, slices and stored exit planes, and the lens at the image's defocus and thickness; frozen phonons write the
//  supercell, the σ per element, the configurations done, and say in a comment that abTEM draws them with another generator. The
//  calls were checked against abTEM 1.0.10's signatures (Potential, PlaneWave, CTF, FrozenPhonons, `exit_planes` as slice indices).
//  Red before: there was no script.
//

import XCTest
import DiffractoCore
import SimulatoCore
import TEMCore

nonisolated final class AbTEMScriptTests: XCTestCase {

    private func run(_ built: SimulationSpecimen.Built, optics: HRTEMOptics = HRTEMOptics(), thermal: HRTEMThermal? = nil,
                     planePeriods: [Int] = [4, 8, 13], planeIndex: Int = 0, specimen: String = "Si [1 1 0]") -> AbTEMScript.Run {
        AbTEMScript.Run(built: built, optics: optics, defocusNM: 61.25, planePeriods: planePeriods, planeIndex: planeIndex,
                        thermal: thermal, specimen: specimen, methodLine: "HRTEM · Si [1 1 0]", writtenBy: "the app 2.6.0, the kit 0.7.0")
    }

    private func lines(_ text: String, starting prefix: String) -> [String] {
        text.components(separatedBy: "\n").filter { $0.hasPrefix(prefix) }
    }

    /// Mutation: the slab written instead of one unit, a coordinate rounded, the grid or the exit planes not the app's, the defocus
    /// or Cs in other units, the aperture written as a number when there is none - red.
    func testAStaticRunWritesTheAppsUnitGridSlicesAndLens() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 10).get()
        let text = try AbTEMScript.text(run(built, planeIndex: 1))
        let unit = built.slab.structure.atoms.filter { $0.position.z < built.box.z }
        XCTAssertEqual(unit.count, 16)
        XCTAssertEqual(lines(text, starting: "    (").count, 16, "one line per atom of one unit")
        let first = try XCTUnwrap(unit.first)
        XCTAssertTrue(text.contains("    (\(first.position.x), \(first.position.y), \(first.position.z)),"), "coordinates round-trip exactly")
        XCTAssertTrue(text.contains("numbers = [" + unit.map { "\($0.atomicNumber)" }.joined(separator: ", ") + "]"))
        XCTAssertTrue(text.contains("cell = (\(built.box.x), \(built.box.y), \(built.box.z))"))
        XCTAssertTrue(text.contains("atoms = unit * (1, 1, 13)"))

        let (nx, ny) = try HRTEMImage.grid(built, optics: HRTEMOptics())
        XCTAssertTrue(text.contains("gpts=(\(nx), \(ny))"))
        let perPeriod = built.slab.sliceThicknesses.count / 13
        let slices = built.slab.sliceThicknesses.prefix(perPeriod).map { "\($0)" }.joined(separator: ", ")
        XCTAssertTrue(text.contains("slice_thickness = (\(slices),) * 13"))
        XCTAssertTrue(text.contains("exit_planes = (\(4 * perPeriod - 1), \(8 * perPeriod - 1), \(13 * perPeriod - 1),)"))

        XCTAssertTrue(text.contains("wave = abtem.PlaneWave(energy=200000.0)"))
        XCTAssertTrue(text.contains("ctf = abtem.CTF(Cs=10000000.0, defocus=612.5, semiangle_cutoff=np.inf, soft=True,"))
        XCTAssertTrue(text.contains("focal_spread=50.0, angular_spread=0.0, energy=200000.0)"))
        XCTAssertTrue(text.contains("image = exit_waves[1].apply_ctf(ctf).intensity()"))
        XCTAssertTrue(text.contains("abtem.config.set({\"precision\": \"float64\", \"device\": \"cpu\"})"))
        XCTAssertFalse(text.contains("FrozenPhonons"))
    }

    /// The header names what wrote it and the versions it runs with; an aperture is written in mrad. Mutation: the versions left
    /// out, the aperture dropped - red.
    func testTheHeaderNamesTheVersionsAndAnApertureIsKept() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2).get()
        var optics = HRTEMOptics()
        optics.apertureMrad = 20
        let text = try AbTEMScript.text(run(built, optics: optics))
        XCTAssertTrue(text.hasPrefix("# HRTEM of Si [1 1 0], written by the app 2.6.0, the kit 0.7.0.\n"), text)
        XCTAssertTrue(text.contains("pip install \"abtem==1.0.10\" \"ase==3.29.0\""))
        XCTAssertTrue(text.contains("# The app's method line: HRTEM · Si [1 1 0]"))
        XCTAssertTrue(text.contains("semiangle_cutoff=20.0, soft=True"))
        XCTAssertTrue(AbTEMScript.writtenBy(appVersion: "2.6.0").hasPrefix("Electron Microscopy Studio 2.6.0"))
        XCTAssertEqual(AbTEMScript.fileName(run(built)), "Si [1 1 0] HRTEM.py")
    }

    /// Frozen phonons write the supercell with no repeat, σ by element symbol, the configurations done and abTEM's mean over them,
    /// and the generator difference as a comment, never silently. Mutation: one unit written, the comment dropped, the mean left
    /// out - red.
    func testFrozenPhononsWriteTheSupercellAndSayTheDrawDiffers() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 1,
                                                 lateralSize: HRTEMThermal.lateralSize).get()
        let text = try AbTEMScript.text(run(built, thermal: HRTEMThermal(sigmas: [14: 0.1], configurations: 3)))
        XCTAssertEqual(lines(text, starting: "    (").count, built.slabAtoms, "every atom of the supercell")
        XCTAssertFalse(text.contains("unit * ("))
        XCTAssertTrue(text.contains("cell = (\(built.slabBox.x), \(built.slabBox.y), \(built.slabBox.z))"))
        XCTAssertTrue(text.contains("abtem.FrozenPhonons(atoms, num_configs=3, sigmas={\"Si\": 0.1}, seed=1,"))
        XCTAssertTrue(text.contains("ensemble_mean=False)"))
        XCTAssertTrue(text.contains("# the app with SimulatoKit's seeded generator. The two agree as ensembles, not configuration by configuration."))
        XCTAssertTrue(text.contains("image = exit_waves[:, 0].apply_ctf(ctf).intensity().mean(0)"))
        let (nx, ny) = try HRTEMImage.thermalGrid(built, optics: HRTEMOptics())
        XCTAssertTrue(text.contains("gpts=(\(nx), \(ny))"))
    }

    /// One stored plane: abTEM adds the exit-plane axis only for more than one (multislice.py), so the script indexes none; the
    /// first index would be x. Mutation: `exit_waves[0]` written for one plane - red.
    func testOneStoredPlaneTakesNoPlaneIndex() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 1).get()
        let text = try AbTEMScript.text(run(built, planePeriods: [2]))
        XCTAssertTrue(text.contains("image = exit_waves.apply_ctf(ctf).intensity()"), text)
        XCTAssertFalse(text.contains("exit_waves[0]"))
        let thermal = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 1,
                                                   lateralSize: HRTEMThermal.lateralSize).get()
        let frozen = try AbTEMScript.text(run(thermal, thermal: HRTEMThermal(sigmas: [14: 0.1], configurations: 2), planePeriods: [2]))
        XCTAssertTrue(frozen.contains("image = exit_waves.apply_ctf(ctf).intensity().mean(0)"), frozen)
    }

    /// A phase's name cannot break the script or the file name: a line break ends no comment, a slash or colon makes no folder,
    /// and the array is saved under a fixed name. Mutation: the name written raw - red.
    func testAPhasesNameCannotBreakTheScriptOrItsFileName() throws {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 1).get()
        let name = "Al/Mg:\"Si\"\nimport os"
        let text = try AbTEMScript.text(run(built, planePeriods: [2], specimen: name))
        XCTAssertFalse(text.components(separatedBy: "\n").contains("import os"))
        XCTAssertTrue(text.contains("np.save(\"hrtem.npy\", image.array)"))
        XCTAssertEqual(AbTEMScript.fileName(run(built, specimen: name)), "Al-Mg-\"Si\" import os HRTEM.py")
    }
}
