//
//  HRTEMThermalTests.swift
//  Frozen phonons for a Simulation document's HRTEM image (#896, plan row MA4): one configuration is the kit's own draw, a run
//  stopped and continued gives the image an uninterrupted run gives, a run too large for this Mac is refused before it starts, the
//  convergence readout needs two configurations, and the settings are kept only when valid. The kit's frozen phonons are pinned to
//  abTEM 1.0.10 in SimulatoKit; this file pins the app's use of them. Red before: there were no frozen phonons.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoMultislice
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class HRTEMThermalTests: XCTestCase {

    private let si = SIMD3(1, 1, 0)

    private func supercell(nm: Double = 1) throws -> SimulationSpecimen.Built {
        try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: si, thicknessNM: nm, lateralSize: HRTEMThermal.lateralSize).get()
    }

    /// Configuration `index` is the kit's configuration `index` of the same seed, drawn without the ones before it. Mutation: the seed
    /// not by index, the normals in another order, σ per element not per site.
    func testOneConfigurationIsTheKitsDraw() throws {
        let structure = try supercell().slab.structure
        let thermal = HRTEMThermal(sigmas: [14: 0.1], configurations: 5)
        let kit = try FrozenPhonons(structure: structure, sigmas: thermal.sigmas, configurations: 5, seed: HRTEMThermal.seed)
        for index in [0, 3, 4] {
            let mine = try HRTEMImage.configuration(structure, thermal: thermal, index: index)
            XCTAssertEqual(mine.atoms.map(\.position), try kit.configuration(index).atoms.map(\.position), "configuration \(index)")
        }
    }

    /// The supercell reaches 20 Å across in whole units, and the plan names its grid, slices, configurations and memory; a run too
    /// large for this Mac is refused before it starts. Mutation: one unit across, the configurations left out of the plan, no check.
    func testThePlanNamesTheRunAndRefusesOneTooLarge() throws {
        let built = try supercell()
        XCTAssertGreaterThanOrEqual(built.slabBox.x, 20)
        XCTAssertGreaterThanOrEqual(built.slabBox.y, 20)
        XCTAssertEqual(built.slabBox.x.truncatingRemainder(dividingBy: built.box.x), 0, accuracy: 1e-9)
        let thermal = HRTEMThermal(sigmas: [14: 0.1], configurations: 10)
        let line = try HRTEMImage.thermalPlanLine(built, optics: HRTEMOptics(), thermal: thermal, stepsPerSecond: nil)
        XCTAssertTrue(line.hasPrefix("Grid "), line)
        XCTAssertTrue(line.contains("10 configurations"), line)
        XCTAssertTrue(line.hasSuffix("GB."), line)
        let timed = try HRTEMImage.thermalPlanLine(built, optics: HRTEMOptics(), thermal: thermal, stepsPerSecond: 1)
        XCTAssertTrue(timed.contains(", about "), timed)

        let tiny = SimulationLimits(memoryBudget: 1 << 20, largestBuffer: 1 << 20)
        XCTAssertThrowsError(try HRTEMImage.thermalPlan(built, optics: HRTEMOptics(), thermal: thermal, limits: tiny)) { error in
            guard case .overBudget = error as? HRTEMImage.PlanRefusal else { return XCTFail("\(error)") }
        }
    }

    /// The convergence readout compares the mean with and without the last configuration: nil below two, 0 when the last equals the
    /// mean before it. Mutation: a readout from one configuration, the last not left out.
    func testConvergenceNeedsTwoConfigurations() throws {
        let built = try supercell(nm: 0.5)
        let optics = HRTEMOptics()
        let thermal = HRTEMThermal(sigmas: [14: 0.1], configurations: 2)
        let empty = try HRTEMImage.thermalEnsemble(built, optics: optics, thermal: thermal, specimen: "Si [1 1 0]")
        let one = try HRTEMImage.addingConfiguration(to: empty, built: built, optics: optics, thermal: thermal, index: 0) { _ in }
        XCTAssertNil(try HRTEMImage.convergence(one, thicknessIndex: 0, defocusNM: 30, optics: optics))
        let twice = one.adding(one.configurations[0])
        XCTAssertEqual(try XCTUnwrap(HRTEMImage.convergence(twice, thicknessIndex: 0, defocusNM: 30, optics: optics)), 0, accuracy: 1e-12)
        let two = try HRTEMImage.addingConfiguration(to: one, built: built, optics: optics, thermal: thermal, index: 1) { _ in }
        XCTAssertGreaterThan(try XCTUnwrap(HRTEMImage.convergence(two, thicknessIndex: 0, defocusNM: 30, optics: optics)), 0)
        XCTAssertTrue(HRTEMImage.methodLine(two, thicknessIndex: 0, defocusNM: 30, optics: optics)
            .contains("frozen phonons, 2 configurations, σ Si 0.1 Å"))
    }

    /// Simulate with two configurations, then two more by Continue, gives the image a run of four gives, bit for bit; the busy line
    /// and the run's gate clear when it ends. Mutation: Continue starting over, configurations seeded by run instead of by index.
    @MainActor func testAStoppedRunContinuedEqualsOneUninterrupted() async throws {
        let crystal = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let parts = SimulationModel()
        parts.setThickness(nm: 0.5)
        parts.useThermalVibrations(true, crystal: crystal)
        XCTAssertEqual(parts.thermal?.sigmas, [14: HRTEMThermal.defaultSigma])
        XCTAssertTrue(parts.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 2)))
        await parts.simulate(crystal: crystal, zoneAxis: si)
        XCTAssertFalse(parts.isSimulating)
        XCTAssertEqual(parts.exitWaves?.configurations.count, 2)
        XCTAssertFalse(parts.canContinue(crystal: crystal, zoneAxis: si))
        XCTAssertTrue(parts.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 4)))
        XCTAssertTrue(parts.canContinue(crystal: crystal, zoneAxis: si), "more asked for: Continue")
        await parts.simulate(crystal: crystal, zoneAxis: si)
        XCTAssertEqual(parts.exitWaves?.configurations.count, 4)
        XCTAssertNotNil(parts.convergence)

        let whole = SimulationModel()
        whole.setThickness(nm: 0.5)
        XCTAssertTrue(whole.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 4)))
        await whole.simulate(crystal: crystal, zoneAxis: si)
        let a = try XCTUnwrap(parts.hrtemImage(name: "a")?.get()), b = try XCTUnwrap(whole.hrtemImage(name: "b")?.get())
        XCTAssertEqual(a.pixels, b.pixels)
        XCTAssertEqual(parts.convergence, whole.convergence)
    }

    /// A setting the run was started for, changed mid-run, stops it: nothing lands for the old settings, and the one-run gate is free
    /// for the next document. Mutation: the run left going (it lands its configuration over the new thickness), the gate held.
    @MainActor func testAChangedSettingStopsTheRunAndFreesTheGate() async throws {
        let crystal = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let model = SimulationModel()
        model.setThickness(nm: 0.5)
        XCTAssertTrue(model.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 4)))
        let run = Task { await model.simulate(crystal: crystal, zoneAxis: si) }
        // The run marks itself running before its first await, so a few turns of the main actor are enough.
        for _ in 0 ..< 100 where !model.isSimulating { await Task.yield() }
        XCTAssertTrue(model.isSimulating)
        model.setThickness(nm: 1)
        await run.value
        XCTAssertFalse(model.isSimulating)
        XCTAssertNil(model.exitWaves, "nothing landed for the old thickness")

        let next = SimulationModel()
        next.setThickness(nm: 0.5)
        XCTAssertTrue(next.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 1)))
        await next.simulate(crystal: crystal, zoneAxis: si)
        XCTAssertNil(next.computeFailure)
        XCTAssertEqual(next.exitWaves?.configurations.count, 1)
    }

    /// Off and on again keeps the σ set before. Mutation: the defaults again.
    @MainActor func testOffAndOnKeepsTheVibrations() {
        let crystal = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let model = SimulationModel()
        model.useThermalVibrations(true, crystal: crystal)
        XCTAssertTrue(model.setThermal(HRTEMThermal(sigmas: [14: 0.07], configurations: 20)))
        model.useThermalVibrations(false, crystal: crystal)
        XCTAssertNil(model.thermal)
        model.useThermalVibrations(true, crystal: crystal)
        XCTAssertEqual(model.thermal, HRTEMThermal(sigmas: [14: 0.07], configurations: 20))
    }

    /// Frozen phonons are kept only with finite σ of at least 0 and configurations in range; a σ change stops a run and keeps the
    /// static lattice's waves from being taken for them. Mutation: no check, configurations outside the range kept.
    @MainActor func testTheSettingsAreKeptOnlyWhenValid() {
        let model = SimulationModel()
        XCTAssertFalse(model.setThermal(HRTEMThermal(sigmas: [14: -0.1])))
        XCTAssertFalse(model.setThermal(HRTEMThermal(sigmas: [14: .nan])))
        XCTAssertFalse(model.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 0)))
        XCTAssertFalse(model.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 101)))
        XCTAssertNil(model.thermal)
        XCTAssertTrue(model.setThermal(HRTEMThermal(sigmas: [14: 0.08], configurations: 100)))
        XCTAssertEqual(model.thermal?.sigmaText, "Si 0.08 Å")
        XCTAssertTrue(model.setThermal(nil))
        XCTAssertNil(model.thermal)
    }

    /// The toolbar's line and fraction for the Image room's run. Mutation: the configuration counted from 0, the fraction of the
    /// running configuration ignored.
    func testTheBusyLineCountsConfigurations() {
        let progress = SimulationModel.ThermalProgress(configuration: 3, configurations: 10, fraction: 0.5)
        XCTAssertEqual(BusyOperation.simulating(progress), "Simulating: configuration 3 of 10")
        XCTAssertEqual(BusyOperation.simulationFraction(progress), 0.25, accuracy: 1e-12)
        XCTAssertEqual(HRTEMImage.duration(40), "40 s")
        XCTAssertEqual(HRTEMImage.duration(180), "3 min")
    }
}
