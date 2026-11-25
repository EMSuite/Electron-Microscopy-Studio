//
//  CBEDPattern.swift
//  Role: a Simulation document's convergent-beam pattern with a thickness series (#912, plan row MA9): SimulatoKit's probe
//        (abTEM's `Probe(semiangle_cutoff=…)`) at the middle of a slab wide enough for the angular step asked, propagated by the
//        multislice with an exit wave kept about every 2 nm, and each wave's diffraction pattern (`diffraction_patterns(max_angle=
//        "cutoff")`). Every number is the kit's.
//
//        The box: the angular step of a pattern is λ / L for a box L across, so 0.25 mrad at 200 kV (λ = 0.0251 Å) needs 100 Å; the
//        orthogonal unit is repeated across to at least that, the repeats chosen so the two sides agree within 0.5 % (square pixels
//        in the pattern; any whole number of units, as √2 and √3 sides need: 17 × 12, 26 × 15). The sampling is the design's rule
//        with the pattern's edge as the largest angle (the smaller of 0.05 Å and λ / 3β), so abTEM's cutoff lands at the edge; the
//        edge must hold the probe and the first ring (`edgeSentence`). One period of potential is built and repeated across and
//        along the beam, as for the HRTEM image.
//
//        The frame: the pattern's rows run along the box's x (lab x), its columns along y, the suite's display frame (row = lab x),
//        the same as the kinematic overlay of the Diffraction room, so its labels sit on the discs.
//

import Foundation
import ImagoCore
import SimulatoCore
import SimulatoMultislice
import SimulatoProbe

/// What a CBED run is asked for. The defaults are the design's: 100 nm in steps of 2 nm, 0.25 mrad per pixel, a 50 mrad edge (a 600 ×
/// 600 grid for a 100 Å box at 200 kV, about 1.5 GB planned).
package nonisolated struct CBEDSettings: Sendable, Equatable, Hashable {
    /// The probe's convergence semiangle, mrad; nil is the largest that keeps the discs apart (`CBEDPattern.separatedSemiangle`).
    package var semiangleMrad: Double?
    /// The thickest pattern, nm.
    package var largestThicknessNM = 100.0
    /// The thickness step between stored patterns, nm.
    package var thicknessStepNM = 2.0
    /// The angular step of the pattern, mrad per pixel: it sets the box across (λ / step).
    package var angularStepMrad = 0.25
    /// The pattern's edge, mrad: the largest angle it shows, which sets the sampling (the kit's rule, the smaller of 0.05 Å and
    /// λ / 3β), so abTEM's `max_angle="cutoff"` lands on it. The 0.05 Å grid's own cutoff (about 167 mrad at 200 kV) would plan
    /// 16 GB or more for a 100 Å box.
    package var edgeMrad = 50.0

    package init() {}

    package static let largestThicknessRangeNM = 1.0 ... 500.0
    package static let angularStepRangeMrad = 0.05 ... 2.0
    package static let edgeRangeMrad = 20.0 ... 400.0
    package static let semiangleRangeMrad = 0.1 ... 50.0
}

/// The patterns of one CBED run, every stored thickness, in the suite's display frame.
package nonisolated struct CBEDPattern: Sendable, Equatable {
    /// `patterns[t]`: the pattern at `thicknessesNM[t]`, row-major, `rows` × `columns`, row = lab x, the direct beam at
    /// (rows / 2, columns / 2); Σ over a pattern is the probe's intensity reaching the edge (1 for none lost).
    package let patterns: [[Float]]
    package let rows: Int
    package let columns: Int
    /// The thickness of each stored pattern, nm, ascending.
    package let thicknessesNM: [Double]
    /// The angular step along rows, mrad per pixel; the reciprocal step is this over λ.
    package let rowStepMrad: Double
    /// The reciprocal step along rows and columns, 1/Å per pixel.
    package let rowDeltaQ: Double
    package let columnDeltaQ: Double
    package let semiangleMrad: Double
    package let volts: Double
    /// "Si [1 1 1]".
    package let specimen: String
    /// The slices along the beam to the thickest pattern.
    package let slices: Int
    /// The run was on Metal float32; false is the CPU float64 reference.
    package let onMetal: Bool
    /// The Metal run lies beyond the depth and grid its tolerance is registered to (`MetalAccuracy.covers`).
    package let beyondRegisteredDepth: Bool

    /// The chip past the registered depth: "400 slices on a 600 × 600 pattern: beyond the validated depth of the Metal path"; nil
    /// within it.
    package var depthChip: String? {
        beyondRegisteredDepth ? "\(slices) slices on a \(rows) × \(columns) pattern: \(CBEDRun.beyondDepthChip) of the Metal path" : nil
    }

    /// The pattern at stored thickness `index` (kept in range) as an image of the app: calibrated in 1/nm with the origin on the
    /// direct beam, the beam energy, and its method line in the notes.
    package func image(at index: Int, name: String) -> CalibratedImage {
        let i = min(max(index, 0), patterns.count - 1)
        let y = AxisCalibration(scale: rowDeltaQ * 10, unit: "1/nm", origin: Double(rows / 2))
        let x = AxisCalibration(scale: columnDeltaQ * 10, unit: "1/nm", origin: Double(columns / 2))
        return CalibratedImage(width: columns, height: rows, pixels: patterns[i], x: x, y: y, fileName: name, source: name, voltage: volts,
                               notes: ["simulated pattern, no measured data", methodLine(at: i)])
    }

    /// "CBED · Si [1 1 1] · 200 kV · 6.5 mrad · 84 nm · Lobato, infinite projection, 1 Å slices · static lattice · Metal (float32)",
    /// the design's line.
    package func methodLine(at index: Int) -> String {
        func n(_ v: Double, _ digits: Int = 3) -> String { UnitDisplay.number(v, digits: digits) }
        let t = thicknessesNM[min(max(index, 0), thicknessesNM.count - 1)]
        return ["CBED", specimen, "\(n(volts / 1000, 4)) kV", "\(n(semiangleMrad)) mrad", "\(n(t)) nm",
                "Lobato, infinite projection, \(n(SimulationSpecimen.sliceThickness)) Å slices", "static lattice",
                onMetal ? "Metal (float32)" : "exact (float64)"]
            .joined(separator: " · ")
    }

    /// The stored thickness nearest `nm`.
    package func index(nearest nm: Double) -> Int {
        thicknessesNM.indices.min { abs(thicknessesNM[$0] - nm) < abs(thicknessesNM[$1] - nm) } ?? 0
    }
}

package nonisolated enum CBEDRun {
    /// The relative mismatch of the box's two sides the repeats are chosen within (square pixels in the pattern).
    package static let squareTolerance = 0.005
    /// Under this width across, a probe overlaps its own periodic copies (the design's chip).
    package static let smallBoxAngstrom = 20.0

    /// The largest semiangle that keeps the discs apart, mrad, rounded down to 0.1: half the angle of the shortest reflection of the
    /// zero-order zone, λ |g| / 2 (Si [1 1 1] at 200 kV: 220, 6.5 mrad).
    package static func separatedSemiangle(shortestG: Double, volts: Double) throws -> Double {
        let lambda = try ElectronBeam(energy: volts).wavelength
        return max(0.1, ((lambda * shortestG / 2 * 1000) * 10).rounded(.down) / 10)
    }

    /// "At 9 mrad the discs overlap." when `semiangle` is above the separated one; nil when they stay apart.
    package static func overlapSentence(semiangleMrad: Double, separatedMrad: Double) -> String? {
        semiangleMrad > separatedMrad + 1e-9 ? "At \(UnitDisplay.number(semiangleMrad, digits: 3)) mrad the discs overlap." : nil
    }

    /// The box, grid and planes of a run, before it starts: what the plan line names.
    package struct Plan: Sendable, Equatable {
        /// Units across along x and y.
        package let repeats: SIMD2<Int>
        /// The box across, Å.
        package let box: SIMD2<Double>
        /// One unit's grid; the run's is `repeats` times it.
        package let unitGrid: SIMD2<Int>
        package var grid: SIMD2<Int> { repeats &* unitGrid }
        /// The periods each pattern is stored at, ascending.
        package let planePeriods: [Int]
        package let periods: Int
        /// The angular step the box gives along rows and columns, mrad per pixel.
        package let stepMrad: SIMD2<Double>

        /// "Box 100 × 100 Å (18 × 13 units) for 0.25 mrad per pixel · 600 × 600 grid · 50 patterns to 100 nm"
        package var sentence: String {
            func n(_ v: Double) -> String { UnitDisplay.number(v, digits: 3) }
            return "Box \(n(box.x)) × \(n(box.y)) Å (\(repeats.x) × \(repeats.y) units) for \(n(max(stepMrad.x, stepMrad.y))) mrad per pixel"
                + " · \(grid.x) × \(grid.y) grid · \(planePeriods.count) patterns"
        }

        /// "The box is 12 Å wide and repeats; the probe overlaps its own copies." under 20 Å across; nil otherwise.
        package var smallBoxSentence: String? {
            let narrow = min(box.x, box.y)
            guard narrow < smallBoxAngstrom else { return nil }
            return "The box is \(UnitDisplay.number(narrow, digits: 3)) Å wide and repeats; the probe overlaps its own copies."
        }
    }

    /// The plan of a run of `built`'s unit for `settings` at `volts`: repeats across to at least λ / step with square pixels,
    /// the sampling for the edge, and a stored period every step along the beam (each a cropped pattern; `run` holds one wave).
    package static func plan(_ built: SimulationSpecimen.Built, settings: CBEDSettings, volts: Double) throws -> Plan {
        let lambda = try ElectronBeam(energy: volts).wavelength
        let unit = SIMD2(built.box.x, built.box.y)
        let reach = lambda / (settings.angularStepMrad / 1000)
        let repeats = squareRepeats(unit: unit, reach: reach)
        let sampling = try SimulationPlan.sampling(largestAngle: settings.edgeMrad, energy: volts)
        let unitGrid = SIMD2(SimulationPlan.fftFriendlyLength(atLeast: Int((unit.x / sampling).rounded(.up))),
                             SimulationPlan.fftFriendlyLength(atLeast: Int((unit.y / sampling).rounded(.up))))
        let periodNM = built.box.z / 10
        let periods = max(1, Int((settings.largestThicknessNM / periodNM).rounded()))
        var planes: [Int] = []
        var t = settings.thicknessStepNM
        while t <= settings.largestThicknessNM + 1e-9 {
            let p = min(periods, max(1, Int((t / periodNM).rounded())))
            if planes.last != p { planes.append(p) }
            t += settings.thicknessStepNM
        }
        if planes.last != periods { planes.append(periods) }
        let box = SIMD2(Double(repeats.x) * unit.x, Double(repeats.y) * unit.y)
        return Plan(repeats: repeats, box: box, unitGrid: unitGrid, planePeriods: planes, periods: periods,
                    stepMrad: SIMD2(lambda / box.x * 1000, lambda / box.y * 1000))
    }

    /// The units across (x, y), each side at least `reach` Å, whose two sides agree within `squareTolerance`, the smallest box of
    /// those; the closest pair when none does. Both counts run to twice their least; any whole number is taken (the kit's FFT takes
    /// every length), so a √2 or √3 cell finds a square box (Si [1 1 0]: 17 × 12, 0.17 %).
    package static func squareRepeats(unit: SIMD2<Double>, reach: Double) -> SIMD2<Int> {
        let lowX = max(1, Int((reach / unit.x - 1e-9).rounded(.up))), lowY = max(1, Int((reach / unit.y - 1e-9).rounded(.up)))
        var square: (repeats: SIMD2<Int>, area: Double)?
        var closest = (repeats: SIMD2(lowX, lowY), mismatch: Double.infinity)
        for nx in lowX ... 2 * lowX {
            for ny in lowY ... 2 * lowY {
                let a = Double(nx) * unit.x, b = Double(ny) * unit.y
                let mismatch = abs(a - b) / max(a, b)
                if mismatch <= squareTolerance, a * b < square?.area ?? .infinity { square = (SIMD2(nx, ny), a * b) }
                if mismatch < closest.mismatch { closest = (SIMD2(nx, ny), mismatch) }
            }
        }
        return square?.repeats ?? closest.repeats
    }

    /// Why the edge cannot hold the pattern, or nil: the antialias cutoff sits at the edge, so a probe disc or the first ring's
    /// discs beyond it are left out of the run with no other sign. The edge needs twice the semiangle plus the first ring's angle
    /// λ|g| (the semiangle alone without a ring).
    package static func edgeSentence(edgeMrad: Double, semiangleMrad: Double, shortestG: Double?, volts: Double) -> String? {
        guard let lambda = try? ElectronBeam(energy: volts).wavelength else { return nil }
        let needed = 2 * semiangleMrad + (shortestG.map { lambda * $0 * 1000 } ?? 0)
        guard edgeMrad < needed else { return nil }
        return "A \(UnitDisplay.number(edgeMrad, digits: 3)) mrad edge cuts the discs off: this probe and the first ring need "
            + "\(UnitDisplay.number(needed.rounded(.up), digits: 3)) mrad."
    }

    /// A run the edge refuses (`edgeSentence`).
    package struct EdgeRefusal: Error, LocalizedError, Equatable {
        package let sentence: String
        package var errorDescription: String? { sentence }
    }

    /// Checks the run against this Mac before it starts; throws `HRTEMImage.PlanRefusal` when it does not fit.
    package static func checkPlan(_ plan: Plan, built: SimulationSpecimen.Built, settings: CBEDSettings, volts: Double,
                                  limits: SimulationLimits = .thisMac) throws {
        let grid = plan.grid
        // One stretch between stored planes is in memory at a time (`run`), its period's slices held once.
        let stretch = zip(plan.planePeriods, [0] + plan.planePeriods).map { $0 - $1 }.max() ?? plan.periods
        let perPeriod = max(1, built.slab.sliceThicknesses.count / built.slab.repeats.z)
        let request = SimulationPlan.Request(extent: plan.box, thickness: Double(stretch) * built.box.z,
                                             sliceThickness: SimulationSpecimen.sliceThickness, energy: volts, largestAngle: settings.edgeMrad,
                                             sampling: min(plan.box.x / Double(grid.x), plan.box.y / Double(grid.y)),
                                             elements: Set(built.slab.unit.structure.atoms.map(\.atomicNumber)).count,
                                             potential: .slices, illumination: .probes(positions: 1), storedExitPlanes: 1,
                                             distinctSlices: perPeriod)
        do { _ = try SimulationPlan(request, limits: limits) }
        catch let refusal as SimulationPlanError {
            switch refusal {
            case let .overBudget(required, budget, _): throw HRTEMImage.PlanRefusal.overBudget(requiredBytes: required, budgetBytes: budget)
            case let .bufferTooLarge(required, limit, _): throw HRTEMImage.PlanRefusal.overBudget(requiredBytes: required, budgetBytes: limit)
            case .gridTooLarge: throw HRTEMImage.PlanRefusal.gridTooLarge(nx: grid.x, ny: grid.y)
            case .invalidRequest: throw refusal
            }
        }
    }

    /// Runs the probe through the slab of `built` for `settings` at `volts` on Metal when this Mac has it (the CPU float64 path with
    /// `reference`), keeping a pattern at every planned period. `shortestG` (1/Å) is the first ring the edge must hold. Throws
    /// `EdgeRefusal`, `PlanRefusal`, the kit's errors, and `CancellationError`. `progress` gets the fraction done, when the kit
    /// reports one.
    package static func run(_ built: SimulationSpecimen.Built, settings: CBEDSettings, semiangleMrad: Double, volts: Double,
                            specimen: String, shortestG: Double? = nil, reference: Bool = false, limits: SimulationLimits = .thisMac,
                            progress: (@Sendable (Double?) -> Void)? = nil) throws -> CBEDPattern {
        if let sentence = edgeSentence(edgeMrad: settings.edgeMrad, semiangleMrad: semiangleMrad, shortestG: shortestG, volts: volts) {
            throw EdgeRefusal(sentence: sentence)
        }
        let plan = try Self.plan(built, settings: settings, volts: volts)
        try checkPlan(plan, built: built, settings: settings, volts: volts, limits: limits)
        let slab = built.slab
        let box = built.box
        let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
        let unit = try AtomicStructure(box: box, atoms: slab.structure.atoms.filter { $0.position.z < box.z })
        let across = try unit.repeated(plan.repeats.x, plan.repeats.y, 1)
        let periodSlices = Array(slab.sliceThicknesses.prefix(perPeriod))
        let grid = plan.grid
        let beam = try ElectronBeam(energy: volts)
        let onMetal = !reference && Multislice.metalIsAvailable
        // The probe crosses the slab one stored plane at a time, each stretch's exit wave the next one's incident wave, so only
        // one wave is held and each stretch's potential holds its distinct slices once (`Potential.build` shares a repeated
        // slice's values; a stretch of k periods repeats one period's slices k times).
        var stretches: [Int: ProjectedPotential] = [:]
        func potential(periods k: Int) throws -> ProjectedPotential {
            if let cached = stretches[k] { return cached }
            let made = try Potential(structure: try across.repeated(1, 1, k), nx: grid.x, ny: grid.y,
                                     sliceThicknesses: Array([[Double]](repeating: periodSlices, count: k).joined())).build()
            stretches[k] = made
            return made
        }
        var patterns: [[Float]] = []
        var rows = 0, columns = 0, rowDeltaQ = 0.0, columnDeltaQ = 0.0
        let edgeRad = settings.edgeMrad / 1000
        /// The pattern of `wave`, cropped about the direct beam to the edge asked, when it is inside the cutoff.
        func keep(_ wave: Waves) throws {
            let field = try wave.diffractionPattern(maxAngle: .cutoff)
            rowDeltaQ = field.samplingX; columnDeltaQ = field.samplingY
            // Cropped about the direct beam to the edge asked, when it is inside the cutoff; values[ix · ny + iy]: row = lab x.
            let halfRows = min(field.nx / 2, Int((edgeRad / (rowDeltaQ * beam.wavelength)).rounded(.up)))
            let halfColumns = min(field.ny / 2, Int((edgeRad / (columnDeltaQ * beam.wavelength)).rounded(.up)))
            rows = 2 * halfRows + 1; columns = 2 * halfColumns + 1
            let r0 = field.nx / 2 - halfRows, c0 = field.ny / 2 - halfColumns
            var cropped = [Float](repeating: 0, count: rows * columns)
            for r in 0 ..< rows {
                for c in 0 ..< columns where r0 + r < field.nx && c0 + c < field.ny {
                    cropped[r * columns + c] = Float(field.values[(r0 + r) * field.ny + c0 + c])
                }
            }
            patterns.append(cropped)
        }
        var wave = try Probe(beam: beam, grid: try potential(periods: plan.planePeriods.first ?? plan.periods).grid, aperture: Aperture(semiangleCutoff: semiangleMrad))
            .build(at: plan.box / 2)
        var done = 0
        for plane in plan.planePeriods {
            try Task.checkCancellation()
            let k = plane - done, start = Double(done) / Double(plan.periods), share = Double(k) / Double(plan.periods)
            let report: SimulationProgressHandler? = progress.map { handler -> SimulationProgressHandler in
                { (step: SimulationProgress) in handler(start + share * (step.fraction ?? 0)) }
            }
            guard let out = try Multislice.run(wave, through: try potential(periods: k), exitPlanes: .last,
                                               backend: onMetal ? .metal : .cpu, progress: report).last else { break }
            wave = out
            try keep(out)
            done = plane
        }
        let slices = plan.periods * perPeriod
        return CBEDPattern(patterns: patterns, rows: rows, columns: columns,
                           thicknessesNM: plan.planePeriods.map { Double($0) * box.z / 10 },
                           rowStepMrad: rowDeltaQ * beam.wavelength * 1000,
                           rowDeltaQ: rowDeltaQ, columnDeltaQ: columnDeltaQ, semiangleMrad: semiangleMrad, volts: volts, specimen: specimen,
                           slices: slices, onMetal: onMetal,
                           beyondRegisteredDepth: onMetal && !MetalAccuracy.registered.covers(nx: grid.x, ny: grid.y, slices: slices))
    }

    /// The chip past the registered depth.
    package static let beyondDepthChip = "beyond the validated depth"
}
