//
//  HRTEMThermal.swift
//  Role: frozen phonons for the HRTEM image (#896, plan row MA4): the thermal vibrations a person sets (σ per element, the number of
//        configurations), the run of one configuration (SimulatoKit's `FrozenPhonons` with its seeded generator, a supercell across,
//        the multislice on the CPU float64 path), the plan the inspector shows before a run (the kit's `SimulationPlan`, with a time
//        from a 10-slice timing on this Mac), and the convergence readout (how much the image changed with the last configuration).
//        Configurations are seeded by their index (`FrozenPhonons.configurationSeed`), so a run stopped and continued equals one run
//        uninterrupted, bit for bit. Every number is the kit's.
//

import DiffractoCore
import Foundation
import SimulatoCore
import SimulatoMultislice
import SimulatoProbe

/// The thermal vibrations of an HRTEM simulation: one σ per element (Å, the standard deviation per axis, B = 8π²σ²) and the number of
/// configurations. Off (nil in the model) is the static lattice, which keeps the image live.
package nonisolated struct HRTEMThermal: Sendable, Equatable {
    /// σ per atomic number, Å.
    package var sigmas: [Int: Double]
    /// Frozen-phonon configurations to average.
    package var configurations: Int

    package init(sigmas: [Int: Double], configurations: Int = defaultConfigurations) {
        self.sigmas = sigmas
        self.configurations = configurations
    }

    /// abTEM's tutorials' 0.1 Å (B ≈ 0.79 Å², room temperature for most metals), for every element of the specimen.
    package static let defaultSigma = 0.1
    /// Ten configurations, the design's example; the convergence readout says whether more are needed.
    package static let defaultConfigurations = 10
    package static let configurationRange = 1 ... 100
    /// The generator's seed: fixed, so every run of the same settings gives the same image.
    package static let seed: UInt64 = 1
    /// The supercell across the beam, Å: at least 20 Å, the design's default box for frozen phonons (one orthogonal unit would make
    /// every unit vibrate alike).
    package static let lateralSize = SIMD2(20.0, 20.0)

    /// The default vibrations for a specimen with `atomicNumbers`.
    package static func defaults(for atomicNumbers: some Sequence<Int>) -> HRTEMThermal {
        HRTEMThermal(sigmas: Dictionary(atomicNumbers.map { ($0, defaultSigma) }, uniquingKeysWith: { a, _ in a }))
    }

    /// "Si 0.1 Å, O 0.08 Å", by atomic number.
    package var sigmaText: String {
        sigmas.keys.sorted().map { z in
            "\(Element.symbol(forAtomicNumber: z) ?? "Z \(z)") \(UnitDisplay.number(sigmas[z] ?? 0, digits: 3)) Å"
        }.joined(separator: ", ")
    }
}

extension HRTEMImage {
    /// The grid of a frozen-phonon run of `built` (a supercell across): the sampling rule for the aperture, square pixels
    /// (`squareGrid`, #1006).
    package static func thermalGrid(_ built: SimulationSpecimen.Built, optics: HRTEMOptics) throws -> (nx: Int, ny: Int) {
        let box = built.slabBox
        let sampling = try optics.apertureMrad.map { try SimulationPlan.sampling(largestAngle: $0, energy: optics.volts) } ?? finestSampling
        return squareGrid(extent: SIMD2(box.x, box.y), sampling: sampling)
    }

    /// What a frozen-phonon run of `built` needs (the kit's plan: grid, slices, steps, memory), checked against `limits`.
    /// Throws `PlanRefusal` when it does not fit: lower the thickness or the configurations.
    package static func thermalPlan(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, thermal: HRTEMThermal,
                                    limits: SimulationLimits = .thisMac) throws -> SimulationPlan {
        let (nx, ny) = try thermalGrid(built, optics: optics)
        let box = built.slabBox
        let planes = planePeriods(periods: built.periods, points: nx * ny * thermal.configurations)
        let request = SimulationPlan.Request(extent: SIMD2(box.x, box.y), thickness: box.z, sliceThickness: SimulationSpecimen.sliceThickness,
                                             energy: optics.volts, largestAngle: optics.apertureMrad ?? 1,
                                             sampling: min(box.x / Double(nx), box.y / Double(ny)),
                                             elements: Set(built.slab.structure.atoms.map(\.atomicNumber)).count, potential: .slices,
                                             configurations: thermal.configurations, storedExitPlanes: planes.count * thermal.configurations)
        do { return try SimulationPlan(request, limits: limits) }
        catch let refusal as SimulationPlanError {
            switch refusal {
            case let .overBudget(required, budget, _), let .bufferTooLarge(required, budget, _):
                throw PlanRefusal.overBudget(requiredBytes: required, budgetBytes: budget)
            case .gridTooLarge: throw PlanRefusal.gridTooLarge(nx: nx, ny: ny)
            case .invalidRequest: throw refusal
            }
        }
    }

    /// Slice steps per second of a frozen-phonon run on this Mac: a 10-slice run (the potential built and propagated, as each
    /// configuration does) on the run's grid, timed once.
    package static func measuredRate(_ built: SimulationSpecimen.Built, optics: HRTEMOptics) throws -> Double {
        let (nx, ny) = try thermalGrid(built, optics: optics)
        let slab = built.slab
        let slices = Array(slab.sliceThicknesses.prefix(10))
        let depth = slices.reduce(0, +)
        let top = try AtomicStructure(box: SIMD3(slab.structure.box.x, slab.structure.box.y, depth),
                                      atoms: slab.structure.atoms.filter { $0.position.z < depth })
        let potential = try Potential(structure: top, nx: nx, ny: ny, sliceThicknesses: slices)
        let start = ContinuousClock.now
        _ = try Multislice.run(.planeWave(beam: try ElectronBeam(energy: optics.volts), grid: potential.grid), through: potential, backend: .cpu)
        let elapsed = (ContinuousClock.now - start) / .seconds(1)
        return Double(slices.count) / max(elapsed, 1e-6)
    }

    /// The exit waves of configuration `index` of `thermal` on `built` (a supercell across), at `planes` periods. Throws
    /// `CancellationError` within a slice of the calling task's cancel; `progress` gets the kit's progress.
    package static func configurationWaves(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, thermal: HRTEMThermal, index: Int,
                                           planes: [Int], progress: SimulationProgressHandler? = nil) throws -> [Waves] {
        let slab = built.slab
        let (nx, ny) = try thermalGrid(built, optics: optics)
        let potential = try Potential(structure: try configuration(slab.structure, thermal: thermal, index: index), nx: nx, ny: ny,
                                      sliceThicknesses: slab.sliceThicknesses)
        let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
        return try Multislice.run(.planeWave(beam: try ElectronBeam(energy: optics.volts), grid: potential.grid), through: potential,
                                  exitPlanes: .afterSlices(planes.map { $0 * perPeriod - 1 }), backend: .cpu, progress: progress)
    }

    /// Configuration `index` of `thermal` on `structure`: the kit's generator seeded with `FrozenPhonons.configurationSeed(seed,
    /// index)`, three normals per atom in atom order, as `FrozenPhonons(structure:sigmas:configurations:seed:)` draws it, without
    /// drawing the configurations before it.
    package static func configuration(_ structure: AtomicStructure, thermal: HRTEMThermal, index: Int) throws -> AtomicStructure {
        let sigmas = try FrozenPhonons.siteSigmas(of: structure, sigmas: thermal.sigmas)
        var generator = GaussianGenerator(seed: FrozenPhonons.configurationSeed(HRTEMThermal.seed, index))
        var displacements: [SIMD3<Double>] = []
        displacements.reserveCapacity(sigmas.count)
        for sigma in sigmas {
            let x = generator.nextNormal()
            let y = generator.nextNormal()
            let z = generator.nextNormal()
            displacements.append(SIMD3(sigma * x, sigma * y, sigma * z))
        }
        return try FrozenPhonons(structure: structure, displacements: [displacements]).configuration(0)
    }

    /// `ensemble` with configuration `index` added (its exit waves at the ensemble's planes); `progress` gets the fraction of the
    /// configuration done. Throws `CancellationError` within a slice of the calling task's cancel.
    package static func addingConfiguration(to ensemble: HRTEMExitWaves, built: SimulationSpecimen.Built, optics: HRTEMOptics,
                                            thermal: HRTEMThermal, index: Int,
                                            progress: @escaping @Sendable (Double?) -> Void) throws -> HRTEMExitWaves {
        ensemble.adding(try configurationWaves(built, optics: optics, thermal: thermal, index: index, planes: ensemble.planePeriods,
                                               progress: { progress($0.fraction) }))
    }

    /// The plan line: "Grid 432 × 576, 130 slices, 10 configurations, 1.21 GB, about 3 min." (the time once this Mac's rate on the
    /// grid is measured). Throws `PlanRefusal` when the run does not fit.
    package static func thermalPlanLine(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, thermal: HRTEMThermal,
                                        stepsPerSecond: Double?) throws -> String {
        let plan = try thermalPlan(built, optics: optics, thermal: thermal)
        var parts = ["Grid \(plan.grid.nx) × \(plan.grid.ny)", UnitDisplay.count(plan.sliceCount, "slice", "slices"),
                     UnitDisplay.count(thermal.configurations, "configuration", "configurations"),
                     "\(UnitDisplay.number(Double(plan.memory.total) / Double(1 << 30), digits: 3)) GB"]
        if let stepsPerSecond, let seconds = try? plan.estimatedSeconds(stepsPerSecond: stepsPerSecond) {
            parts.append("about " + duration(seconds))
        }
        return parts.joined(separator: ", ") + "."
    }

    /// "40 s", "3 min", "1.5 h".
    package static func duration(_ seconds: Double) -> String {
        if seconds < 90 { return "\(max(1, Int(seconds.rounded()))) s" }
        if seconds < 5400 { return "\(Int((seconds / 60).rounded())) min" }
        return "\(UnitDisplay.number(seconds / 3600, digits: 2)) h"
    }

    /// The empty ensemble a frozen-phonon run fills, with the planes it stores.
    package static func thermalEnsemble(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, thermal: HRTEMThermal,
                                        specimen: String) throws -> HRTEMExitWaves {
        let (nx, ny) = try thermalGrid(built, optics: optics)
        return HRTEMExitWaves(configurations: [], planePeriods: planePeriods(periods: built.periods, points: nx * ny * thermal.configurations),
                              periodNM: built.box.z / 10, volts: optics.volts, apertureMrad: optics.apertureMrad, specimen: specimen,
                              thermal: thermal)
    }

    /// How much the image changed with the last configuration added: the RMS of the difference between the mean of all configurations
    /// and the mean without the last, over the RMS of the mean (one unit of the supercell, not tiled). Nil below two configurations.
    package static func convergence(_ exit: HRTEMExitWaves, thicknessIndex: Int, defocusNM: Double, optics: HRTEMOptics) throws -> Double? {
        let n = exit.configurations.count
        guard n >= 2 else { return nil }
        let plane = min(max(thicknessIndex, 0), exit.planePeriods.count - 1)
        let ctf = try optics.transferFunction(defocusNM: defocusNM)
        var sum: [Double] = []
        var last: [Double] = []
        for configuration in exit.configurations {
            last = try ctf.images(of: [configuration[plane]], defocus: [defocusNM * 10], tile: (x: 1, y: 1))[0][0].values
            if sum.isEmpty { sum = last } else { for i in sum.indices { sum[i] += last[i] } }
        }
        var difference = 0.0, magnitude = 0.0
        for i in sum.indices {
            let all = sum[i] / Double(n), before = (sum[i] - last[i]) / Double(n - 1)
            difference += (all - before) * (all - before)
            magnitude += all * all
        }
        return magnitude > 0 ? (difference / magnitude).squareRoot() : nil
    }
}
