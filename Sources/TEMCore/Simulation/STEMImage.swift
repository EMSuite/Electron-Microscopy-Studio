//
//  STEMImage.swift
//  Role: a Simulation document's STEM image (#913, plan row MA10): SimulatoKit's probe (abTEM's `Probe(semiangle_cutoff=…,
//        defocus=…, Cs=…)`) scanned over one projected unit of the specimen through the slab, with abTEM's `FlexibleAnnularDetector`
//        (the scattered intensity in 1 mrad rings at every position), so BF, ABF, ADF and HAADF are bands summed after the run
//        (`ScanMeasurement.integrateRadial`), not four runs. The scan is the kit's resumable `STEMRun`: Stop keeps every finished
//        configuration and position, and Continue goes on from there. Every number is the kit's.
//
//        The box: the slab built at least 20 Å across (the design's default for a probe, so it does not overlap its own copies); the
//        scan covers one orthogonal unit at its origin, and the image is that unit tiled to the field of view. The sampling is the
//        design's rule with the collection angle as the largest angle (the smaller of 0.05 Å and λ / 3β). Frozen phonons are the
//        document's (`HRTEMThermal`): each configuration displaces the whole slab with the generator seeded by its index, so a
//        stopped and continued run equals an uninterrupted one.
//
//        The frame: the image's rows run along the box's x (lab x), its columns along y, as the HRTEM image and the patterns.
//

import Foundation
import ImagoCore
import SimulatoCore
import SimulatoDetector
import SimulatoMultislice
import SimulatoProbe

/// An annular band of the detector, mrad.
package nonisolated struct STEMBand: Sendable, Equatable, Hashable {
    package var inner: Double
    package var outer: Double
    package init(inner: Double, outer: Double) { self.inner = inner; self.outer = outer }
}

/// The design's detector presets (Paul, 23 Nov): BF, ABF and ADF relative to the probe's semiangle α, HAADF fixed.
package nonisolated enum STEMDetector: String, CaseIterable, Sendable, Equatable {
    case bf, abf, adf, haadf

    package var title: String {
        switch self {
        case .bf: "BF"
        case .abf: "ABF"
        case .adf: "ADF"
        case .haadf: "HAADF"
        }
    }

    /// BF 0 to α/2, ABF α/2 to α, ADF 1.5α to 3α, HAADF 60 to 200 mrad (at α = 20: 0 to 10, 10 to 20, 30 to 60, 60 to 200).
    package func band(semiangleMrad a: Double) -> STEMBand {
        switch self {
        case .bf: STEMBand(inner: 0, outer: a / 2)
        case .abf: STEMBand(inner: a / 2, outer: a)
        case .adf: STEMBand(inner: 1.5 * a, outer: 3 * a)
        case .haadf: STEMBand(inner: 60, outer: 200)
        }
    }

    /// The preset whose band, snapped to the rings, is `band`'s at `semiangleMrad`; nil for a custom band.
    package static func matching(_ band: STEMBand, semiangleMrad: Double) -> STEMDetector? {
        let snapped = band.snapped()
        return allCases.first { $0.band(semiangleMrad: semiangleMrad).snapped() == snapped }
    }
}

/// What a STEM run is asked for. The defaults are the design's.
package nonisolated struct STEMSettings: Sendable, Equatable, Hashable {
    /// The probe's convergence semiangle, mrad (the Uncorrected preset's 10; Cs Corrected 20).
    package var semiangleMrad = 10.0
    /// The probe's defocus, nm, abTEM's sign; nil is Scherzer defocus for the optics' Cs.
    package var defocusNM: Double?
    /// The scan step, Å; nil is Nyquist for the probe, λ / 4α (abTEM's `nyquist_sampling`: 0.63 Å at 10 mrad, 200 kV).
    package var scanStepAngstrom: Double?
    /// The largest angle collected, mrad: the detector's outer edge, which sets the sampling.
    package var collectMrad = 200.0

    package init() {}

    package static let semiangleRangeMrad = 1.0 ... 60.0
    package static let scanStepRangeAngstrom = 0.05 ... 2.0
    package static let collectRangeMrad = 20.0 ... 400.0
    /// The detector's ring width, mrad: every band is summed from rings this wide.
    package static let ringMrad = 1.0
}

extension STEMBand {
    /// The band on the rings' edges (the nearest whole ring, `STEMSettings.ringMrad`), at least one ring wide: the band the kit
    /// sums, which every field, plot and method line states (ABF at 1 mrad, 0.5 to 1, is 1 to 2).
    package nonisolated func snapped() -> STEMBand {
        let ring = STEMSettings.ringMrad
        let i = (inner / ring).rounded() * ring
        return STEMBand(inner: i, outer: max((outer / ring).rounded() * ring, i + ring))
    }
}

/// A STEM run in progress or done: the kit's resumable scan, with what the image needs to be drawn from it at any time.
package nonisolated struct STEMScan: Sendable {
    /// The kit's run; `run.measurements()` is the mean over the configurations finished at every position.
    package var run: STEMRun
    /// The detector's rings, as the kit lays them on the grid.
    package let rings: SegmentedDetector
    /// The scan step along lab x and y, Å, and the unit it covers.
    package let step: SIMD2<Double>
    package let unit: SIMD2<Double>
    package let settings: STEMSettings
    package let defocusNM: Double
    package let volts: Double
    package let csMM: Double
    /// "Si [1 1 0]".
    package let specimen: String
    package let thicknessNM: Double
    package let slices: Int
    package let thermal: HRTEMThermal?
    package let onMetal: Bool

    /// Positions finished in every configuration so far, and the configurations finished.
    package var completedConfigurations: Int { run.completedConfigurations }
    /// Positions finished in the configuration under way.
    package var completedPositions: Int { run.completedPositions }
    package var configurations: Int { run.configurationCount }
    /// No position has any configuration yet.
    package var isEmpty: Bool { run.completedConfigurations == 0 && run.completedPositions == 0 }
    package var isComplete: Bool { run.isComplete }

    /// The intensity in each ring, the mean over the positions with at least one configuration: the radial plot under the image.
    /// Angles are the rings' centres, mrad.
    package func radialProfile() -> (angles: [Double], intensities: [Double]) {
        guard let m = run.measurements().first else { return ([], []) }
        let bins = rings.radialBins
        let width = (rings.outer - rings.inner) / Double(bins)
        let positions = m.values.count / max(bins, 1)
        let filled = run.completedConfigurations > 0 ? positions : run.completedPositions
        var sum = [Double](repeating: 0, count: bins)
        for p in 0 ..< filled { for b in 0 ..< bins { sum[b] += m.values[p * bins + b] } }
        let n = Double(max(filled, 1))
        return ((0 ..< bins).map { rings.inner + (Double($0) + 0.5) * width }, sum.map { $0 / n })
    }

    /// The image of `band` over the scan (one unit), each position the sum of the rings inside the band; positions not yet
    /// reached are 0. Throws the kit's refusal of a band beyond the rings.
    package func unitImage(band: STEMBand) throws -> RealField {
        guard let m = run.measurements().first else { throw SimulatoError.invalidScan("no detector") }
        let band = band.snapped()
        let summed = try m.integrateRadial(inner: band.inner, outer: band.outer, detector: rings)
        guard let field = summed.image(samplingX: step.x, samplingY: step.y) else { throw SimulatoError.invalidScan("not a grid scan") }
        return field
    }

    /// The image of `band` tiled to `fieldOfViewNM`, as an image of the app: rows down lab x, calibrated in nm, the method line in
    /// its notes.
    package func image(band: STEMBand, fieldOfViewNM: Double, name: String) throws -> CalibratedImage {
        let unitField = try unitImage(band: band)
        let field = try unitField.tiled(repetitionsX: HRTEMImage.tiles(unit.x, fieldOfViewNM), repetitionsY: HRTEMImage.tiles(unit.y, fieldOfViewNM))
        let x = AxisCalibration(scale: field.samplingY / 10, unit: "nm")
        let y = AxisCalibration(scale: field.samplingX / 10, unit: "nm")
        return CalibratedImage(width: field.ny, height: field.nx, pixels: field.values.map { Float($0) }, x: x, y: y, fileName: name,
                               source: name, voltage: volts, notes: ["simulated image, no measured data", methodLine(band: band)])
    }

    /// "Not quantitative: high-angle contrast needs thermal vibrations." for a band beyond the probe's angle on the static lattice.
    package func notQuantitative(band: STEMBand) -> String? {
        thermal == nil && band.snapped().inner >= settings.semiangleMrad ? STEMImage.notQuantitative : nil
    }

    /// "STEM · Si [1 1 0] · 200 kV · 10 mrad · defocus 61.33 nm · Cs 1 mm · HAADF 60 to 200 mrad · 10 nm · scan step 0.627 Å ·
    /// Lobato, infinite projection, 1 Å slices · frozen phonons, 10 configurations, σ Si 0.1 Å · Metal (float32)", the design's line.
    package func methodLine(band: STEMBand) -> String {
        func n(_ v: Double, _ digits: Int = 3) -> String { UnitDisplay.number(v, digits: digits) }
        let band = band.snapped()
        let name = STEMDetector.matching(band, semiangleMrad: settings.semiangleMrad)?.title ?? "Band"
        let lattice: String
        if let thermal {
            let done = run.completedConfigurations
            let count = done == thermal.configurations ? "\(done) configurations" : "\(done) of \(thermal.configurations) configurations"
            lattice = "frozen phonons, \(count), σ \(thermal.sigmaText)"
        } else {
            lattice = "static lattice"
        }
        return ["STEM", specimen, "\(n(volts / 1000, 4)) kV", "\(n(settings.semiangleMrad)) mrad", "defocus \(n(defocusNM, 4)) nm",
                "Cs \(n(csMM, 4)) mm", "\(name) \(n(band.inner)) to \(n(band.outer)) mrad", "\(n(thicknessNM)) nm",
                "scan step \(n(max(step.x, step.y))) Å", "\(HRTEMImage.potentialName), \(n(SimulationSpecimen.sliceThickness)) Å slices",
                lattice, onMetal ? "Metal (float32)" : "exact (float64)"]
            .joined(separator: " · ")
    }
}

package nonisolated enum STEMImage {
    /// The design's chip.
    package static let notQuantitative = "Not quantitative: high-angle contrast needs thermal vibrations."

    /// The longest slice the run is advanced in, once a slice has made progress.
    package static let longestSlice = Duration.seconds(10)

    /// The next slice after one of `slice`: doubled when it finished nothing (a configuration's potential still being built, so a
    /// slow start is never cut off), else grown towards `longestSlice` and never shortened, since every resume sets its
    /// configuration up again.
    package static func nextSlice(after slice: Duration, progressed: Bool) -> Duration {
        progressed ? max(slice, min(slice * 2, longestSlice)) : slice * 2
    }

    /// Why the probe wraps onto its own copies in the box: its geometric cone through the specimen (2tα) plus its own width
    /// (1.22 λ / α) passes the box's shorter side. Nil when it fits.
    package static func wrapSentence(thicknessNM: Double, boxAngstrom: Double, semiangleMrad: Double, volts: Double) -> String? {
        guard let lambda = try? ElectronBeam(energy: volts).wavelength, semiangleMrad > 0 else { return nil }
        let alpha = semiangleMrad / 1000
        let spread = 2 * thicknessNM * 10 * alpha + 1.22 * lambda / alpha
        guard spread > boxAngstrom else { return nil }
        func n(_ v: Double) -> String { UnitDisplay.number(v, digits: 3) }
        return "The probe spreads to \(n(spread)) Å through \(n(thicknessNM)) nm, past the \(n(boxAngstrom)) Å box: it wraps onto its "
            + "own copies. Thin the specimen or lower the semiangle."
    }

    /// Nyquist sampling for a probe of `semiangleMrad`, Å: λ / 4α (abTEM's `Aperture.nyquist_sampling`).
    package static func nyquistStep(semiangleMrad: Double, volts: Double) throws -> Double {
        try ElectronBeam(energy: volts).wavelength / (4 * semiangleMrad / 1000)
    }

    /// The probe's defocus, nm: the one set, else Scherzer for `csMM` (abTEM's `scherzer_defocus`).
    package static func defocusNM(_ settings: STEMSettings, csMM: Double, volts: Double) throws -> Double {
        if let typed = settings.defocusNM { return typed }
        return try ContrastTransferFunction.scherzerDefocus(Cs: csMM * 1e7, energy: volts) / 10
    }

    /// The grid of a run of `built` (the slab at least 20 Å across): the sampling for the collection angle, lengths of 2, 3, 5.
    package static func grid(_ built: SimulationSpecimen.Built, settings: STEMSettings, volts: Double) throws -> (nx: Int, ny: Int) {
        let box = built.slabBox
        let sampling = try SimulationPlan.sampling(largestAngle: settings.collectMrad, energy: volts)
        return (SimulationPlan.fftFriendlyLength(atLeast: Int((box.x / sampling).rounded(.up))),
                SimulationPlan.fftFriendlyLength(atLeast: Int((box.y / sampling).rounded(.up))))
    }

    /// The scan over one orthogonal unit at the origin, at the step set or Nyquist's.
    package static func scan(_ built: SimulationSpecimen.Built, settings: STEMSettings, volts: Double) throws -> GridScan {
        let step = try settings.scanStepAngstrom ?? nyquistStep(semiangleMrad: settings.semiangleMrad, volts: volts)
        return try GridScan(start: .zero, end: SIMD2(built.box.x, built.box.y), samplingX: step, samplingY: step)
    }

    /// The kit's plan of a run (grid, slices, positions, configurations, memory) against `limits`; throws `HRTEMImage.PlanRefusal`
    /// when it does not fit.
    package static func plan(_ built: SimulationSpecimen.Built, settings: STEMSettings, volts: Double, configurations: Int,
                             limits: SimulationLimits = .thisMac) throws -> SimulationPlan {
        let (nx, ny) = try grid(built, settings: settings, volts: volts)
        let box = built.slabBox
        let positions = try scan(built, settings: settings, volts: volts).positions.count
        let request = SimulationPlan.Request(extent: SIMD2(box.x, box.y), thickness: box.z, sliceThickness: SimulationSpecimen.sliceThickness,
                                             energy: volts, largestAngle: settings.collectMrad,
                                             sampling: min(box.x / Double(nx), box.y / Double(ny)),
                                             elements: Set(built.slab.structure.atoms.map(\.atomicNumber)).count, potential: .slices,
                                             illumination: .probes(positions: positions), configurations: configurations)
        do { return try SimulationPlan(request, limits: limits) }
        catch let refusal as SimulationPlanError {
            switch refusal {
            case let .overBudget(required, budget, _), let .bufferTooLarge(required, budget, _):
                throw HRTEMImage.PlanRefusal.overBudget(requiredBytes: required, budgetBytes: budget)
            case .gridTooLarge: throw HRTEMImage.PlanRefusal.gridTooLarge(nx: nx, ny: ny)
            case .invalidRequest: throw refusal
            }
        }
    }

    /// "Grid 480 × 480, 100 slices, 63 positions, 10 configurations, 1.2 GB." Throws `PlanRefusal` when the run does not fit.
    package static func planLine(_ built: SimulationSpecimen.Built, settings: STEMSettings, volts: Double, configurations: Int) throws -> String {
        let plan = try Self.plan(built, settings: settings, volts: volts, configurations: configurations)
        let positions = try Self.scan(built, settings: settings, volts: volts).positions.count
        return ["Grid \(plan.grid.nx) × \(plan.grid.ny)", UnitDisplay.count(plan.sliceCount, "slice", "slices"),
                UnitDisplay.count(positions, "position", "positions"), UnitDisplay.count(configurations, "configuration", "configurations"),
                "\(UnitDisplay.number(Double(plan.memory.total) / Double(1 << 30), digits: 3)) GB"].joined(separator: ", ") + "."
    }

    /// A run of `built` for `settings` with the document's optics' Cs and `thermal` (nil: the static lattice), not yet started:
    /// the probe, one potential per configuration (built when its configuration starts, on the GPU with Metal), the scan and the
    /// rings. `reference` keeps it on the CPU float64 path. Throws `PlanRefusal` and the kit's refusals.
    package static func prepare(_ built: SimulationSpecimen.Built, settings: STEMSettings, csMM: Double, volts: Double,
                                thermal: HRTEMThermal?, specimen: String, reference: Bool = false,
                                limits: SimulationLimits = .thisMac) throws -> STEMScan {
        let configurations = thermal?.configurations ?? 1
        _ = try plan(built, settings: settings, volts: volts, configurations: configurations, limits: limits)
        let (nx, ny) = try grid(built, settings: settings, volts: volts)
        let slab = built.slab
        let structures = try thermal.map { t in try (0 ..< t.configurations).map { try HRTEMImage.configuration(slab.structure, thermal: t, index: $0) } }
            ?? [slab.structure]
        let potentials = try structures.map { try Potential(structure: $0, nx: nx, ny: ny, sliceThicknesses: slab.sliceThicknesses) }
        let beam = try ElectronBeam(energy: volts)
        let defocus = try defocusNM(settings, csMM: csMM, volts: volts)
        var aberrations = Aberrations()
        aberrations.Cs = csMM * 1e7
        aberrations.defocus = defocus * 10
        let probe = try Probe(beam: beam, grid: potentials[0].grid, aperture: Aperture(semiangleCutoff: settings.semiangleMrad),
                              aberrations: aberrations)
        let detector = try FlexibleAnnularDetector(step: STEMSettings.ringMrad, inner: 0, outer: settings.collectMrad)
        let rings = try detector.segmented(for: probe.grid, beam: beam)
        let scan = try Self.scan(built, settings: settings, volts: volts)
        let onMetal = !reference && Multislice.metalIsAvailable
        let run = try STEMRun(probe: probe, potentials: potentials, scan: scan, detectors: [rings], backend: onMetal ? .metal : .cpu)
        let unit = SIMD2(built.box.x, built.box.y)
        return STEMScan(run: run, rings: rings, step: SIMD2(unit.x / Double(scan.nx), unit.y / Double(scan.ny)), unit: unit,
                        settings: settings, defocusNM: defocus, volts: volts, csMM: csMM, specimen: specimen,
                        thicknessNM: built.slabBox.z / 10, slices: slab.sliceThicknesses.count, thermal: thermal, onMetal: onMetal)
    }

    /// Runs `scan` off the calling actor for about `slice`, then hands it back with every finished position kept (the kit's run
    /// stops after its current round of positions, and continues from there when called again); the caller draws the image and
    /// calls again until `isComplete`. A cancel of the calling task stops it the same way: the scan returned keeps what was done
    /// (Stop keeps finished configurations), and the caller reads `Task.isCancelled`. Throws the kit's errors, never
    /// `CancellationError`. `progress` gets the fraction of the whole run done, when the kit reports one.
    package static func advance(_ scan: STEMScan, slice: Duration = .seconds(1),
                                progress: (@Sendable (Double?) -> Void)? = nil) async throws -> STEMScan {
        let report: SimulationProgressHandler? = progress.map { handler -> SimulationProgressHandler in
            { (step: SimulationProgress) in handler(step.fraction) }
        }
        let worker = Task.detached { () -> (STEMScan, (any Error)?) in
            var running = scan
            do { _ = try running.run.run(progress: report); return (running, nil) }
            catch { return (running, error) }
        }
        let timer = Task.detached {
            try? await Task.sleep(for: slice)
            worker.cancel()
        }
        let (advanced, error) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        timer.cancel()
        if let error, !(error is CancellationError) { throw error }
        return advanced
    }
}
