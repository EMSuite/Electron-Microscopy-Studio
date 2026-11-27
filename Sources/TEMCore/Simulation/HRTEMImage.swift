//
//  HRTEMImage.swift
//  Role: the HRTEM image of a Simulation document's specimen (#894, plan row MA2): SimulatoKit's multislice of a plane wave through
//        one orthogonal unit of the slab, with an exit wave stored at whole periods, and the image of a stored exit wave at a
//        defocus by the kit's contrast transfer function (abTEM's `waves.apply_ctf(CTF(...)).intensity()`), tiled to the view.
//
//        Why one unit: a static crystal under a plane wave has the crystal's period, so one orthogonal unit is exact and the image is
//        tiled (the design's "live HRTEM"). Below about 128² points the CPU float64 path is faster than Metal (the kit's break-even),
//        so this is the reference path. Moving the defocus is one inverse FFT of the stored wave; moving the thickness picks another
//        stored wave; the voltage or the aperture (the sampling) runs the multislice again. Every number is the kit's.
//

import Foundation
import ImagoCore
import SimulatoCore
import SimulatoMultislice
import SimulatoProbe
import TEMBase

/// The objective lens and the beam of an HRTEM image. The defaults are the design's Uncorrected preset at 200 kV (Cs 1.0 mm, focal
/// spread 5 nm), with abTEM's defaults where it has one: no angular spread and no objective aperture.
package nonisolated struct HRTEMOptics: Sendable, Equatable {
    package var volts = 200_000.0
    /// Spherical aberration, mm.
    package var csMM = 1.0
    /// The 1/e half-width of the focal spread, nm (temporal coherence).
    package var focalSpreadNM = 5.0
    /// The angular spread, mrad (spatial coherence, the beam's divergence).
    package var angularSpreadMrad = 0.0
    /// The objective aperture's semiangle, mrad; nil is none. It also sets the sampling.
    package var apertureMrad: Double?
    /// The width the tiled image reaches at least, nm (the design's Field of view: the unit cell is tiled).
    package var fieldOfViewNM = 4.0

    package init() {}

    /// The kit's transfer function at `defocusNM` (abTEM's sign: positive is underfocus). `HRTEMImage.image` passes the defocus to
    /// `images(of:defocus:)` as well, which overrides the one set here; `applying(_:)` uses this one.
    package func transferFunction(defocusNM: Double) throws -> ContrastTransferFunction {
        var aberrations = Aberrations()
        aberrations.Cs = csMM * 1e7
        aberrations.defocus = defocusNM * 10
        return try ContrastTransferFunction(aberrations: aberrations, semiangleCutoff: apertureMrad ?? .infinity,
                                            focalSpread: focalSpreadNM * 10, angularSpread: angularSpreadMrad)
    }

    /// Scherzer defocus, nm: √(3/2 Cs λ), the kit's (abTEM's).
    package func scherzerDefocusNM() throws -> Double {
        try ContrastTransferFunction.scherzerDefocus(Cs: csMM * 1e7, energy: volts) / 10
    }
}

/// The exit waves of a slab at whole periods: the multislice result the image is made from. A static lattice has one configuration
/// (one orthogonal unit across); a frozen-phonon run one per configuration done (a supercell across), and the image is the mean of
/// their intensities.
package nonisolated struct HRTEMExitWaves: Sendable, Equatable {
    /// `configurations[c][i]`: the exit wave of configuration c after `planePeriods[i]` periods.
    package let configurations: [[Waves]]
    /// The number of periods each stored wave is at, ascending; the last is the slab's whole thickness. Every period while they fit
    /// in `HRTEMImage.storedWavesBudget`, else every n-th and the last (the design's tiered storage).
    package let planePeriods: [Int]
    /// One period along the beam, nm.
    package let periodNM: Double
    /// The voltage and aperture they were computed for (the aperture set the sampling).
    package let volts: Double
    package let apertureMrad: Double?
    /// What was simulated, for the method line: "Si [1 1 0]".
    package let specimen: String
    /// The thermal vibrations of a frozen-phonon run; nil for a static lattice.
    package let thermal: HRTEMThermal?

    package init(configurations: [[Waves]], planePeriods: [Int], periodNM: Double, volts: Double, apertureMrad: Double?,
                 specimen: String, thermal: HRTEMThermal? = nil) {
        self.configurations = configurations
        self.planePeriods = planePeriods
        self.periodNM = periodNM
        self.volts = volts
        self.apertureMrad = apertureMrad
        self.specimen = specimen
        self.thermal = thermal
    }

    /// The first configuration's exit waves, one per stored plane (a static lattice's only ones).
    package var waves: [Waves] { configurations.first ?? [] }

    /// The thickness of the stored wave `index` (kept in range), nm.
    package func thicknessNM(at index: Int) -> Double {
        Double(planePeriods[min(max(index, 0), planePeriods.count - 1)]) * periodNM
    }

    /// The image's nanometres per pixel along its columns (lab y) and rows (lab x), as `HRTEMImage.image` calibrates it.
    package var nanometresPerPixel: (x: Double, y: Double)? {
        guard let grid = waves.first?.grid else { return nil }
        return (grid.extentY / Double(grid.ny) / 10, grid.extentX / Double(grid.nx) / 10)
    }

    /// The same waves with configuration `waves` added (a frozen-phonon run's next one).
    package func adding(_ waves: [Waves]) -> HRTEMExitWaves {
        HRTEMExitWaves(configurations: configurations + [waves], planePeriods: planePeriods, periodNM: periodNM, volts: volts,
                       apertureMrad: apertureMrad, specimen: specimen, thermal: thermal)
    }
}

package nonisolated enum HRTEMImage {
    /// The sampling without an aperture, Å: the kit's rule's finest (the smaller of 0.05 Å and λ / 3β is 0.05 Å for any β below
    /// about 160 mrad at 200 kV).
    package static let finestSampling = 0.05

    /// The most memory the stored exit waves may take, bytes: 256 MiB (16 bytes a point each, complex float64).
    package static let storedWavesBudget = 256 << 20

    /// Why a run was refused before it started, in the room's words.
    package enum PlanRefusal: LocalizedError, Equatable {
        /// The run needs more memory than this Mac allows a run (`SimulationLimits.thisMac`).
        case overBudget(requiredBytes: Int, budgetBytes: Int)
        /// The unit's grid is larger than a run may be.
        case gridTooLarge(nx: Int, ny: Int)

        package var errorDescription: String? {
            func gb(_ b: Int) -> String { UnitDisplay.number(Double(b) / Double(1 << 30), digits: 2) }
            switch self {
            case let .overBudget(required, budget):
                return "This run needs about \(gb(required)) GB, more than the \(gb(budget)) GB this Mac allows a run: lower the thickness."
            case let .gridTooLarge(nx, ny):
                return "One unit of this specimen needs a \(nx) × \(ny) grid, more than a run may have: choose a smaller unit (another zone axis)."
            }
        }
    }

    /// The grid of `built`'s unit for `optics`: the sampling is the kit's rule for the aperture (the smaller of 0.05 Å and λ / 3β),
    /// the lengths in proportion to the box's sides so the pixels are square (`squareGrid`, #1006).
    package static func grid(_ built: SimulationSpecimen.Built, optics: HRTEMOptics) throws -> (nx: Int, ny: Int) {
        let sampling = try optics.apertureMrad.map { try SimulationPlan.sampling(largestAngle: $0, energy: optics.volts) } ?? finestSampling
        return squareGrid(extent: SIMD2(built.box.x, built.box.y), sampling: sampling)
    }

    /// How far the two pixel sides of a grid may differ, relative: 0.5 % (CBED's square box takes the same).
    package static let squarePixelTolerance = 0.005

    /// The grid of `extent` (Å) at `sampling` (Å) whose pixels are square (#1006). abTEM takes each axis on its own,
    /// gpts = ⌈extent / sampling⌉, so its pixels differ by under one point in a length; raising each length on its own to factors 2, 3
    /// and 5 instead stretched them (Si [1 1 0]: 109 and 154 points to 120 and 160, 6 %). Each length is at least ⌈extent / sampling⌉
    /// (no axis coarser than `sampling`, abTEM's per-axis rule), and the pair is the one of fewest points whose pixel sides agree within
    /// `squarePixelTolerance`: lengths of factors 2, 3 and 5 when such a pair exists, else of factors up to 11 (the lengths SciPy's
    /// `next_fast_len` takes; the kit's FFT takes every length). The search runs to twice the least length (at least 128 more); with no
    /// pair within the tolerance there, the pair whose pixels are closest.
    package static func squareGrid(extent: SIMD2<Double>, sampling: Double) -> (nx: Int, ny: Int) {
        let leastX = max(1, Int((extent.x / sampling).rounded(.up)))
        let leastY = max(1, Int((extent.y / sampling).rounded(.up)))
        func isSmooth(_ n: Int, _ primes: [Int]) -> Bool {
            guard n >= 1 else { return false }
            var k = n
            for p in primes { while k % p == 0 { k /= p } }
            return k == 1
        }
        func next(_ n: Int, _ primes: [Int]) -> Int {
            var m = max(1, n)
            while !isSmooth(m, primes) { m += 1 }
            return m
        }
        func previous(_ n: Int, _ primes: [Int]) -> Int {
            var m = n
            while m >= 1 && !isSmooth(m, primes) { m -= 1 }
            return m
        }
        func mismatch(_ nx: Int, _ ny: Int) -> Double {
            let px = extent.x / Double(nx), py = extent.y / Double(ny)
            return abs(px - py) / max(px, py)
        }
        func search(_ primes: [Int]) -> (square: (nx: Int, ny: Int)?, closest: (nx: Int, ny: Int)) {
            var square: (nx: Int, ny: Int, points: Int, mismatch: Double)?
            var closest: (nx: Int, ny: Int, points: Int, mismatch: Double)?
            let top = max(2 * leastX, leastX + 128)
            var nx = next(leastX, primes)
            while nx <= top {
                let ideal = Double(nx) * extent.y / extent.x
                let below = previous(Int(ideal), primes)
                let above = next(max(Int(ideal.rounded(.up)), leastY), primes)
                for ny in (below >= leastY ? [below, above] : [above]) {
                    let m = mismatch(nx, ny), points = nx * ny
                    if m <= squarePixelTolerance,
                       square.map({ points < $0.points || (points == $0.points && m < $0.mismatch) }) ?? true {
                        square = (nx, ny, points, m)
                    }
                    if closest.map({ m < $0.mismatch || (m == $0.mismatch && points < $0.points) }) ?? true {
                        closest = (nx, ny, points, m)
                    }
                }
                nx = next(nx + 1, primes)
            }
            let fallback = closest.map { (nx: $0.nx, ny: $0.ny) } ?? (nx: next(leastX, primes), ny: next(leastY, primes))
            return (square.map { (nx: $0.nx, ny: $0.ny) }, fallback)
        }
        if let square = search([2, 3, 5]).square { return square }
        let wide = search([2, 3, 5, 7, 11])
        return wide.square ?? wide.closest
    }

    /// The periods to store a wave at: every one while `periods` waves of `points` grid points fit in `budget` bytes, else every
    /// n-th, and always the last.
    package static func planePeriods(periods: Int, points: Int, budget: Int = storedWavesBudget) -> [Int] {
        let fit = max(1, budget / max(points * 16, 1))
        let stride = max(1, Int((Double(periods) / Double(fit)).rounded(.up)))
        var planes = Array(Swift.stride(from: stride, through: periods, by: stride))
        if planes.last != periods { planes.append(periods) }
        return planes
    }

    /// Checks the run against this Mac before it starts (`SimulationPlan` with `SimulationLimits.thisMac`, built slices, one plane
    /// wave, every stored plane); throws `PlanRefusal` when it does not fit.
    package static func checkPlan(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, limits: SimulationLimits = .thisMac) throws {
        let (nx, ny) = try grid(built, optics: optics)
        let box = built.box
        let planes = planePeriods(periods: built.periods, points: nx * ny)
        let request = SimulationPlan.Request(extent: SIMD2(box.x, box.y), thickness: Double(built.periods) * box.z,
                                             sliceThickness: SimulationSpecimen.sliceThickness, energy: optics.volts,
                                             largestAngle: optics.apertureMrad ?? 1, sampling: min(box.x / Double(nx), box.y / Double(ny)),
                                             elements: Set(built.slab.unit.structure.atoms.map(\.atomicNumber)).count,
                                             potential: .slices, storedExitPlanes: planes.count)
        do { _ = try SimulationPlan(request, limits: limits) }
        catch let refusal as SimulationPlanError {
            switch refusal {
            case let .overBudget(required, budget, _): throw PlanRefusal.overBudget(requiredBytes: required, budgetBytes: budget)
            case let .bufferTooLarge(required, limit, _): throw PlanRefusal.overBudget(requiredBytes: required, budgetBytes: limit)
            case .gridTooLarge: throw PlanRefusal.gridTooLarge(nx: nx, ny: ny)
            case .invalidRequest: throw refusal
            }
        }
    }

    /// Propagates a plane wave through the slab of `built` (one orthogonal unit across) on the CPU float64 path, keeping the exit
    /// wave at `planePeriods`. The potential of ONE period is built and repeated along the beam (the repeated slices share their
    /// storage), so memory and build time do not grow with the thickness; the run is checked against this Mac first
    /// (`checkPlan`). Throws `PlanRefusal`, the kit's errors, and `CancellationError` when the calling task is cancelled.
    package static func exitWaves(_ built: SimulationSpecimen.Built, optics: HRTEMOptics, specimen: String,
                                  limits: SimulationLimits = .thisMac) throws -> HRTEMExitWaves {
        try checkPlan(built, optics: optics, limits: limits)
        let slab = built.slab   // one unit across (no lateral size), every period, shifted so no plane sits on a slice boundary
        let box = built.box
        let (nx, ny) = try grid(built, optics: optics)
        // The slab is the shifted unit repeated along z (atoms wrapped into [0, period) before repeating): period 0 is the atoms below z = period.
        let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
        let unit = try AtomicStructure(box: box, atoms: slab.structure.atoms.filter { $0.position.z < box.z })
        let onePeriod = try Potential(structure: unit, nx: nx, ny: ny, sliceThicknesses: Array(slab.sliceThicknesses.prefix(perPeriod))).build()
        let potential = try onePeriod.tiled(repetitionsX: 1, repetitionsY: 1, repetitionsZ: slab.repeats.z)
        let beam = try ElectronBeam(energy: optics.volts)
        let periods = planePeriods(periods: slab.repeats.z, points: nx * ny)
        let waves = try Multislice.run(.planeWave(beam: beam, grid: potential.grid), through: potential,
                                       exitPlanes: .afterSlices(periods.map { $0 * perPeriod - 1 }), backend: .cpu)
        return HRTEMExitWaves(configurations: [waves], planePeriods: periods, periodNM: box.z / 10, volts: optics.volts,
                              apertureMrad: optics.apertureMrad, specimen: specimen)
    }

    /// The image of the stored exit wave `thicknessIndex` at `defocusNM`, tiled to at least the field of view across, as an
    /// image of the app in the simulated pattern's lab frame: x down the rows, y along the columns (the kit's own storage order, no
    /// flip), calibrated in nm.
    package static func image(_ exit: HRTEMExitWaves, thicknessIndex: Int, defocusNM: Double, optics: HRTEMOptics,
                              name: String) throws -> CalibratedImage {
        let plane = min(max(thicknessIndex, 0), exit.planePeriods.count - 1)
        let grid = exit.waves[plane].grid
        let tile = (x: tiles(grid.extentX, optics.fieldOfViewNM), y: tiles(grid.extentY, optics.fieldOfViewNM))
        let ctf = try optics.transferFunction(defocusNM: defocusNM)
        // A frozen-phonon image is the mean of the configurations' intensities (abTEM's ensemble mean), taken on one unit and tiled
        // once (each configuration's image is periodic in the supercell, so the mean of the tiles is the tile of the mean).
        var sum: [Double]?
        var unit: RealField?
        for configuration in exit.configurations {
            let one = try ctf.images(of: [configuration[plane]], defocus: [defocusNM * 10], tile: (x: 1, y: 1))[0][0]
            if sum == nil { sum = one.values } else { for i in one.values.indices { sum![i] += one.values[i] } }
            unit = one
        }
        guard let unit, let sum else { throw SimulatoError.invalidFrozenPhonons("no configuration") }
        let scale = 1 / Double(exit.configurations.count)
        let mean = try exit.configurations.count == 1 ? unit
            : RealField(nx: unit.nx, ny: unit.ny, values: sum.map { $0 * scale }, samplingX: unit.samplingX, samplingY: unit.samplingY)
        let field = try mean.tiled(repetitionsX: tile.x, repetitionsY: tile.y)
        // The kit's storage order is the image: lab x down the rows, lab y along the columns, row 0 at x = 0, as the simulated
        // pattern and the crystal pane draw the lab frame (py4DSTEM's), so this image's FFT lines up with the pattern (#931).
        let width = field.ny, height = field.nx
        let pixels = field.values.map { Float($0) }
        let x = AxisCalibration(scale: field.samplingY / 10, unit: "nm")
        let y = AxisCalibration(scale: field.samplingX / 10, unit: "nm")
        return CalibratedImage(width: width, height: height, pixels: pixels, x: x, y: y, fileName: name, source: name,
                               voltage: optics.volts,
                               notes: ["simulated image, no measured data",
                                       methodLine(exit, thicknessIndex: thicknessIndex, defocusNM: defocusNM, optics: optics)])
    }

    /// The potential every HRTEM image is computed with, as the HRTEM section and the method line name it.
    package static let potentialName = "Lobato, infinite projection"

    /// The method line every result carries, naming every setting: "HRTEM · Si [1 1 0] · 200 kV · 10 nm · defocus 61.33 nm · Cs 1 mm ·
    /// focal spread 5 nm · angular spread 0 mrad · no aperture · Lobato, infinite projection, 1 Å slices · static lattice · exact
    /// (float64)" (the design's line).
    package static func methodLine(_ exit: HRTEMExitWaves, thicknessIndex: Int, defocusNM: Double, optics: HRTEMOptics) -> String {
        func n(_ v: Double, _ digits: Int = 3) -> String { UnitDisplay.number(v, digits: digits) }
        let aperture = optics.apertureMrad.map { "aperture \(n($0)) mrad" } ?? "no aperture"
        return ["HRTEM", exit.specimen, "\(n(optics.volts / 1000, 4)) kV", "\(n(exit.thicknessNM(at: thicknessIndex))) nm",
                "defocus \(n(defocusNM, 4)) nm", "Cs \(n(optics.csMM, 4)) mm", "focal spread \(n(optics.focalSpreadNM)) nm",
                "angular spread \(n(optics.angularSpreadMrad)) mrad", aperture,
                "\(potentialName), \(n(SimulationSpecimen.sliceThickness)) Å slices", lattice(exit), "exact (float64)"]
            .joined(separator: " · ")
    }

    /// "static lattice", or the frozen phonons: "frozen phonons, 3 of 10 configurations, σ Si 0.1 Å".
    package static func lattice(_ exit: HRTEMExitWaves) -> String {
        guard let thermal = exit.thermal else { return "static lattice" }
        let done = exit.configurations.count
        let count = done == thermal.configurations ? "\(done) configurations" : "\(done) of \(thermal.configurations) configurations"
        return "frozen phonons, \(count), σ \(thermal.sigmaText)"
    }

    /// How many units of `extent` Å reach `widthNM`.
    static func tiles(_ extent: Double, _ widthNM: Double) -> Int { max(1, Int((widthNM * 10 / extent).rounded(.up))) }
}
