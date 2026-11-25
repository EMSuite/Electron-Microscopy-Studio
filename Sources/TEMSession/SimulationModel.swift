//
//  SimulationModel.swift
//  Role: a Simulation document's multislice state (2.5): the specimen's thickness and the strain the person accepted (#893, MA1),
//        and the HRTEM image's optics, defocus and thickness with the exit waves it is made from (#894, MA2). The
//        phase and the zone axis stay the Diffraction room's (`DiffractionAnalysis.crystal`, `simulation.zoneAxis`), so the pattern and
//        the specimen are always built from the same crystal and axis. The slab is built by `SimulationSpecimen` (SimulatoKit's
//        slab builder) and cached on the crystal's identity, the axis, the thickness and the strain limit. The exit waves (one orthogonal
//        unit at whole periods, at most 256 MiB) are computed off the main actor and kept with the key they were made for; the image is made
//        from them on demand, one inverse FFT, so moving Defocus or Thickness redraws at once. With frozen phonons on (#896, MA4)
//        the waves are no longer live: Simulate runs the configurations one at a time on a supercell across, keeps each one that
//        finishes (Stop keeps them, Continue adds the rest), and reads how much the last one changed the image. One simulation runs
//        at a time on this Mac. An atom model opened as the specimen (#914, MA14) takes the phase's place: the document keeps the
//        model as read, the beam runs along its c (or a, or b), and its own thickness is the slab's; the rest is the same.
//

import DiffractoCore
import DiffractoScattering
import Foundation
import ImagoCore
import Observation
import TEMCore

@Observable
package final class SimulationModel {
    /// The thickness asked for, nm; the slab takes the whole number of periods nearest it.
    package private(set) var thicknessNM = SimulationSpecimen.defaultThicknessNM
    /// The strain Build with Strain accepted for the crystal and zone axis it was accepted on; nil uses the kit's 0.1 % limit.
    package private(set) var acceptedStrain: AcceptedStrain?

    package struct AcceptedStrain: Sendable, Equatable {
        package let crystal: String
        package let zoneAxis: SIMD3<Int>
        package let strain: Double
    }

    /// The HRTEM image's lens and beam.
    package private(set) var optics = HRTEMOptics()
    /// The defocus, nm (positive is underfocus); nil is Scherzer defocus for the optics.
    package private(set) var defocusNM: Double?
    /// Which stored exit wave the image shows, from 0 (one period); nil is the thickest.
    package private(set) var thicknessIndex: Int?
    /// The exit waves of the specimen in `exitKey`; nil before the first run and while a changed specimen runs again.
    package private(set) var exitWaves: HRTEMExitWaves?
    /// The multislice is running.
    package private(set) var isComputing = false
    /// Why the last run gave no exit waves, in the kit's words; nil after one that did.
    package private(set) var computeFailure: String?
    /// Why the last image could not be made from the stored waves; nil after one that was.
    package private(set) var imageFailure: String?
    @ObservationIgnored private var exitKey: ExitKey?
    /// The image asked for while one is being made (the latest call's, which reads the settings when it starts), and the task making them.
    @ObservationIgnored private var pendingRender: (() async -> Void)?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    /// Frozen phonons: nil is the static lattice, whose image is live; set, the image waits for Simulate.
    package private(set) var thermal: HRTEMThermal?
    /// The frozen-phonon run going now: which configuration, of how many, and how far through it; nil when none runs.
    package private(set) var thermalProgress: ThermalProgress?
    /// How much the image changed with the last configuration added, at the defocus and thickness it was read at; nil below two.
    package private(set) var convergence: Convergence?
    /// Place Beside: the measured image the HRTEM image is shown beside, and how; nil shows the simulation alone (#898).
    package private(set) var beside: HRTEMBeside?
    /// What Place Beside's link to its measured file is now, while the measured image is not open (#824); nil before it is resolved.
    package private(set) var besideLinkState: LinkedFileState?

    package nonisolated struct Convergence: Sendable, Equatable {
        /// RMS of the change over RMS of the image.
        package let change: Double
        package let defocusNM: Double
        package let thicknessIndex: Int
    }
    /// Slice steps per second of a frozen-phonon run on this Mac, by grid: the plan line's time, measured once per grid.
    package private(set) var measuredRates: [GridSize: Double] = [:]
    @ObservationIgnored private var thermalTask: Task<Void, Never>?
    /// The vibrations set before frozen phonons were last turned off.
    @ObservationIgnored private var lastThermal: HRTEMThermal?
    @ObservationIgnored private var thermalCache: (key: Key, result: Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>)?

    package nonisolated struct ThermalProgress: Sendable, Equatable {
        /// The configuration running, from 1.
        package let configuration: Int
        package let configurations: Int
        /// How far through it, 0...1; nil before the kit counts.
        package var fraction: Double?

        package init(configuration: Int, configurations: Int, fraction: Double? = nil) {
            self.configuration = configuration
            self.configurations = configurations
            self.fraction = fraction
        }
    }

    package nonisolated struct GridSize: Hashable, Sendable {
        // periphery:ignore - read by the synthesized == (and hash)
        package let nx: Int
        // periphery:ignore - read by the synthesized == (and hash)
        package let ny: Int
    }

    /// Raised each time new exit waves land: what a view keys work on the stored waves by.
    package private(set) var wavesRevision = 0
    /// Kinematic or Dynamical (#911, MA8): the Diffraction room's simulated spots from the kit's kinematical pattern, or from the
    /// zone-axis beams of the stored exit waves at the shown thickness.
    package private(set) var isDynamical = false
    /// The zone-axis beams of the stored exit waves at every stored thickness, or why the kit read none; nil with no waves.
    package private(set) var dynamicalSpots: Result<DynamicalSpots, DynamicalAbsence>?

    package nonisolated struct DynamicalAbsence: Error, Equatable, Sendable {
        package let sentence: String
    }
    /// The run going now and what it computes for.
    @ObservationIgnored private var running: (key: ExitKey, number: Int, task: Task<Void, Never>)?
    /// Counts the runs started, so each one's answer is told apart from a cancelled run's of the same key.
    @ObservationIgnored private var runNumber = 0

    /// What the stored exit waves were computed for: the specimen as built (its periods, not the thickness typed, so 10.0 and
    /// 10.1 nm, the same 13 periods, keep the waves), the voltage, the aperture and the thermal vibrations (their σ, not the
    /// number of configurations, so asking for more continues the run).
    private struct ExitKey: Equatable {
        // periphery:ignore - read by the synthesized == (and hash)
        let crystal: String
        // periphery:ignore - read by the synthesized == (and hash)
        let zoneAxis: SIMD3<Int>
        // periphery:ignore - read by the synthesized == (and hash)
        let periods: Int?
        // periphery:ignore - read by the synthesized == (and hash)
        let maximumStrain: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let volts: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let apertureMrad: Double?
        // periphery:ignore - read by the synthesized == (and hash)
        let sigmas: [Int: Double]?
    }

    private struct Key: Equatable {
        // periphery:ignore - read by the synthesized == (and hash)
        let crystal: String
        // periphery:ignore - read by the synthesized == (and hash)
        let zoneAxis: SIMD3<Int>
        // periphery:ignore - read by the synthesized == (and hash)
        let thicknessNM: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let maximumStrain: Double
    }
    @ObservationIgnored private var cache: (key: Key, result: Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>)?
    @ObservationIgnored private var drawnCache: (built: SimulationSpecimen.Built, drawn: SlabDrawing.Drawn)?
    @ObservationIgnored private var columnsCache: (key: ColumnsKey, columns: [SlabDrawing.Column])?
    /// The specimen's atom columns are marked on the HRTEM image (#897).
    package private(set) var marksColumns = false

    /// The atom model simulated in the phase's place (Source: Atom Model…); nil simulates the Diffraction room's phase.
    package private(set) var atomModel: AtomModelSpecimen?
    /// The model's axis the beam runs along.
    package private(set) var beamAxis = AtomModelSpecimen.BeamAxis.c
    /// Raised each time a model's slab lands: views key their runs on it (with `sourceIdentity`).
    package private(set) var modelSlabsRevision = 0
    /// The model's slabs, built off the main actor (a million atoms cut and sorted would stall drawing): one unit across, and the
    /// supercell at least `HRTEMThermal.lateralSize` across that frozen phonons and a STEM scan run on, per beam axis.
    @ObservationIgnored private var modelSlabs: [ModelSlabKey: Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>] = [:]
    @ObservationIgnored private var modelBuildTask: Task<Void, Never>?

    private struct ModelSlabKey: Hashable {
        let identity: String
        // periphery:ignore - read by the synthesized == (and hash)
        let axis: AtomModelSpecimen.BeamAxis
        // periphery:ignore - read by the synthesized == (and hash)
        let thermal: Bool
    }

    package init() {}

    /// Simulates `model` in the phase's place, or the phase again (nil). Stops a run going: its configurations are of another
    /// specimen. The model's slab is built off the main actor; until it lands the specimen is "building".
    package func useAtomModel(_ model: AtomModelSpecimen?) {
        guard model != atomModel else { return }
        stop()
        atomModel = model
        // A model has no reflections: Dynamical runs on a phase only (#953).
        if model != nil { isDynamical = false }
        modelSlabs = modelSlabs.filter { $0.key.identity == model?.identity }
        if model == nil { beamAxis = .c }
        scheduleModelBuild()
    }

    /// Turns the model so the beam runs along `axis`.
    package func setBeamAxis(_ axis: AtomModelSpecimen.BeamAxis) {
        guard axis != beamAxis else { return }
        stop()
        beamAxis = axis
        scheduleModelBuild()
    }

    /// What the specimen is, for a view's run key: the model with its beam axis and slabs landed, else the phase's identity; nil
    /// with neither.
    package func sourceIdentity(crystal: DiffractionCrystal?) -> String? {
        if let atomModel { return "\(atomModel.identity) \(beamAxis.rawValue) \(modelSlabsRevision)" }
        return crystal?.identity
    }

    /// The name a run's patterns and images carry: the model along its beam axis, else the phase down `zoneAxis`; nil with neither.
    package func sourceName(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> String? {
        source(crystal: crystal, zoneAxis: zoneAxis)?.name
    }

    /// The axis a run's beam runs down: the model's beam axis as a unit [u v w] while a model is the source, else `zoneAxis`.
    package func sourceZoneAxis(_ zoneAxis: SIMD3<Int>) -> SIMD3<Int> {
        guard atomModel != nil else { return zoneAxis }
        return SIMD3<Int>(beamAxis == .a ? 1 : 0, beamAxis == .b ? 1 : 0, beamAxis == .c ? 1 : 0)
    }

    // What needs a phase's reflections or the thickness field refuses while a model is the source, in one sentence each (#953).
    package static let modelDynamicalSentence = "Dynamical intensities need a phase: an atom model has no reflections to label. "
        + "Its CBED pattern and images run on the model."
    package static let modelFitDiscsSentence = "Type the convergence semiangle: Fit Discs reads a phase's reflections, and an atom model has none."
    package static let modelLabelsSentence = "No simulated spots or hkl labels: the pattern is an atom model's, which has no reflections to label."
    package static let modelThicknessSentence = "The atom model's thickness is its own slab's: Use in Simulation sets a phase's thickness only."

    private func scheduleModelBuild() {
        modelBuildTask?.cancel()
        guard atomModel != nil else { return }
        modelBuildTask = Task { [weak self] in await self?.buildModelSlabs() }
    }

    /// Builds the open model's slabs not yet built (one unit across, then the supercell a STEM scan and frozen phonons need) off
    /// the main actor, and returns when they have landed. Each lands even when the model changed meanwhile: it is valid for its key.
    package func buildModelSlabs() async {
        guard let atomModel else { return }
        let axis = beamAxis
        // The supercell is built whatever the vibrations: a STEM scan always runs on it (`thermalSpecimen`, #953).
        for lateral in [nil, HRTEMThermal.lateralSize] as [SIMD2<Double>?] {
            let key = ModelSlabKey(identity: atomModel.identity, axis: axis, thermal: lateral != nil)
            guard modelSlabs[key] == nil else { continue }
            let result = await offMainActor { atomModel.build(beamAlong: axis, lateralSize: lateral) }
            modelSlabs[key] = result
            modelSlabsRevision += 1
        }
    }

    /// What a run is made of, whichever the specimen is: its key, the name its images carry, its elements and how it is built.
    private struct Source {
        let identity: String
        let zoneAxis: SIMD3<Int>
        let name: String
        let atomicNumbers: [Int]
        /// Builds the slab at a thickness, nm, a strain limit and a lateral size (nil is one unit across).
        let build: (Double, Double, SIMD2<Double>?) -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>
    }

    /// The atom model when one is open, else the phase along `zoneAxis`; nil with neither.
    private func source(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Source? {
        if let atomModel {
            let axis = beamAxis
            // The model's own thickness is the slab's: the thickness field does not key it.
            let along = sourceZoneAxis(.zero)
            let slabs = modelSlabs
            return Source(identity: atomModel.identity, zoneAxis: along, name: "\(atomModel.name) along \(axis.rawValue)",
                          atomicNumbers: atomModel.atomicNumbers) { _, _, lateral in
                slabs[ModelSlabKey(identity: atomModel.identity, axis: axis, thermal: lateral != nil)] ?? .failure(.building)
            }
        }
        guard let crystal else { return nil }
        return Source(identity: crystal.identity, zoneAxis: zoneAxis, name: "\(crystal.name) \(ZoneAxisText.text(zoneAxis))",
                      atomicNumbers: crystal.structure.sites.map(\.z)) { thickness, limit, lateral in
            SimulationSpecimen.build(crystal.structure, zoneAxis: zoneAxis, thicknessNM: thickness, maximumStrain: limit, lateralSize: lateral)
        }
    }

    /// Sets the thickness, nm, kept in the field's range; a non-finite value changes nothing.
    package func setThickness(nm: Double) {
        guard nm.isFinite else { return }
        let new = min(max(nm, SimulationSpecimen.thicknessRangeNM.lowerBound), SimulationSpecimen.thicknessRangeNM.upperBound)
        guard new != thicknessNM else { return }
        stop()
        thicknessNM = new
    }

    /// The strain limit for `crystal` along `zoneAxis`: the one Build with Strain accepted there (the kit's test is "at most", and the same
    /// box gives the same strain), else the kit's default.
    package func maximumStrain(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Double {
        source(crystal: crystal, zoneAxis: zoneAxis).map(maximumStrain) ?? SimulationSpecimen.defaultMaximumStrain
    }

    private func maximumStrain(_ source: Source) -> Double {
        if let acceptedStrain, acceptedStrain.crystal == source.identity, acceptedStrain.zoneAxis == source.zoneAxis {
            return acceptedStrain.strain
        }
        return SimulationSpecimen.defaultMaximumStrain
    }

    /// Build with Strain: builds this crystal along this axis with the strain the refusal named.
    package func acceptStrain(_ strain: Double, crystal: DiffractionCrystal, zoneAxis: SIMD3<Int>) {
        guard strain.isFinite, strain >= 0 else { return }
        stop()
        acceptedStrain = AcceptedStrain(crystal: crystal.identity, zoneAxis: zoneAxis, strain: strain)
    }

    // MARK: HRTEM

    /// The Simulation section's Kinematic | Dynamical switch.
    package func setDynamical(_ on: Bool) { isDynamical = on }

    /// Why Dynamical draws the kinematical spots, in the room's words; nil while it is off, while a run goes, and when the beams are
    /// drawn. Thermal vibrations first (the beams are read on the static lattice, and their waves are not live), then the specimen's
    /// refusal, the run's failure and the kit's absence. Writes no observed state.
    package func dynamicalAbsence(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> String? {
        guard isDynamical, !isComputing else { return nil }
        if atomModel != nil { return Self.modelDynamicalSentence }
        if thermal != nil { return Self.thermalDynamicalSentence }
        if case .failure(let refusal) = specimen(crystal: crystal, zoneAxis: zoneAxis) { return refusal.sentence }
        if let computeFailure { return "No dynamical intensities: \(computeFailure)" }
        if exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis), case .failure(let absence)? = dynamicalSpots {
            return "No dynamical intensities: \(absence.sentence)"
        }
        return nil
    }

    /// The beams the Diffraction room draws in place of the kinematical intensities: those of the shown thickness, while Dynamical
    /// is on and the stored waves are this crystal's along this axis; else nil (the kinematical pattern). Writes no observed state.
    package func dynamicalBeams(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> DynamicalBeams? {
        guard isDynamical, atomModel == nil, exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis), case .success(let spots)? = dynamicalSpots,
              let index = shownThicknessIndex else { return nil }
        return spots.beams(at: index)
    }

    /// The defocus the image is drawn at, nm: the one set, else Scherzer defocus (0 when the optics give none).
    package var effectiveDefocusNM: Double { defocusNM ?? ((try? optics.scherzerDefocusNM()) ?? 0) }

    /// Sets the defocus, nm; a non-finite value changes nothing.
    package func setDefocus(nm: Double) {
        guard nm.isFinite else { return }
        defocusNM = nm
    }

    /// Back to Scherzer defocus for the optics.
    package func useScherzerDefocus() { defocusNM = nil }

    /// Shows the exit wave after `index + 1` periods (kept in the stored range when the image is made).
    package func setThicknessIndex(_ index: Int) { thicknessIndex = max(0, index) }

    /// Changes the lens or the beam; a voltage or an aperture other than the stored waves' makes `exitWavesAreCurrent` false.
    package func setOptics(_ new: HRTEMOptics) {
        if new.volts != optics.volts || new.apertureMrad != optics.apertureMrad { stop() }
        optics = new
    }

    /// The widest field of view, nm: 20 nm (at the finest sampling 4 000 pixels across; the image is made off the main actor).
    package nonisolated static let largestFieldOfViewNM = 20.0

    /// Edits the optics, every control's one path: the edit is kept only when every value stays valid (a positive voltage, a finite
    /// Cs, spreads of at least 0, an aperture above 0 or none, a field of view above 0 and at most `largestFieldOfViewNM`).
    /// Returns whether it was kept.
    @discardableResult
    package func changeOptics(_ edit: (inout HRTEMOptics) -> Void) -> Bool {
        var new = optics
        edit(&new)
        guard Self.isValid(new) else { return false }
        if new.volts != optics.volts || new.apertureMrad != optics.apertureMrad { stop() }
        optics = new
        return true
    }

    /// Place Beside, or the simulation alone (nil). Kept only with a finite rotation and an inset size in
    /// `HRTEMBeside.insetCellRange`; returns whether it was kept. The image is redrawn by the caller (`refreshHRTEMImage`).
    @discardableResult
    package func setBeside(_ new: HRTEMBeside?) -> Bool {
        if let new {
            guard new.rotationDegrees.isFinite, HRTEMBeside.insetCellRange.contains(new.insetCells.x),
                  HRTEMBeside.insetCellRange.contains(new.insetCells.y) else { return false }
        }
        if new?.link != beside?.link { besideLinkState = nil }
        beside = new
        return true
    }

    /// What resolving or locating Place Beside's link found; dropped when it is not about the link Place Beside holds now.
    package func setBesideLinkState(_ state: LinkedFileState?, for link: LinkedFile) {
        guard beside?.link == link else { return }
        besideLinkState = state
    }

    /// Every value of `optics` valid, as `changeOptics` keeps them.
    package nonisolated static func isValid(_ optics: HRTEMOptics) -> Bool {
        optics.volts.isFinite && optics.volts > 0 && optics.csMM.isFinite
            && optics.focalSpreadNM.isFinite && optics.focalSpreadNM >= 0 && optics.angularSpreadMrad.isFinite && optics.angularSpreadMrad >= 0
            && (optics.apertureMrad.map { $0.isFinite && $0 > 0 } ?? true)
            && optics.fieldOfViewNM.isFinite && optics.fieldOfViewNM > 0 && optics.fieldOfViewNM <= largestFieldOfViewNM
    }

    /// Makes the image of the stored waves at the current settings off the main actor, passes it through `prepare` there too (the
    /// caller's canvas and thumbnail), and hands the result to `deliver` (nothing before the first run). Calls while an image is being
    /// made coalesce into one more, made at the settings current when it starts and handed to the last call's `deliver`, so a
    /// dragged slider never queues images. A failure is `imageFailure`. Returns the task that ends when no image is pending.
    @discardableResult
    package func render<Prepared: Sendable>(name: String, prepare: @escaping @Sendable (CalibratedImage) -> Prepared,
                                            deliver: @escaping (Prepared) -> Void) -> Task<Void, Never>? {
        pendingRender = { [weak self] in
            guard let self, let exitWaves = self.exitWaves, let index = self.shownThicknessIndex else { return }
            let defocus = self.effectiveDefocusNM, optics = self.optics
            let made: Result<Prepared, any Error> = await offMainActor {
                Result { prepare(try HRTEMImage.image(exitWaves, thicknessIndex: index, defocusNM: defocus, optics: optics, name: name)) }
            }
            switch made {
            case .success(let prepared):
                self.imageFailure = nil
                deliver(prepared)
            case .failure(let error):
                self.imageFailure = ErrorDetail.text(error)
            }
        }
        if let renderTask { return renderTask }
        let task = Task { [weak self] in
            while let self, let request = self.pendingRender {
                self.pendingRender = nil
                await request()
            }
            self?.renderTask = nil
        }
        renderTask = task
        return task
    }

    /// Takes the document's beam energy, so the pattern and the image of one document share one voltage (the Calibration section's
    /// typed kV, which the Microscope section's Voltage also sets); nothing for a missing or non-positive value.
    package func adoptVoltage(kV: Double?) {
        guard let kV, kV.isFinite, kV > 0, optics.volts != kV * 1000 else { return }
        stop()
        optics.volts = kV * 1000
    }

    /// Whether the stored exit waves are those of this specimen and optics.
    package func exitWavesAreCurrent(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Bool {
        guard let source = source(crystal: crystal, zoneAxis: zoneAxis), let exitKey else { return false }
        return exitKey == exitKeyFor(source)
    }

    /// Runs the multislice for this specimen and optics off the main actor when the stored exit waves are not theirs, and returns
    /// when they are current or the run failed. A call for the run already going waits for it; a call for another specimen or optics
    /// cancels it and starts its own, so only the newest run's answer lands, whoever calls (the HRTEM section's task, Show HRTEM
    /// Image, the door). A finished run lands even when its caller went away: its result is valid for its key.
    package func updateExitWaves(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) async {
        guard thermal == nil else {
            // Frozen phonons are not live: Simulate runs them.
            cancelRun()
            return
        }
        guard let source = source(crystal: crystal, zoneAxis: zoneAxis), !exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) else {
            // The stored waves are what is asked for (or there is nothing to ask): a run for anything else must not land over them.
            cancelRun()
            return
        }
        guard case .success(let built) = specimen(crystal: crystal, zoneAxis: zoneAxis) else {
            cancelRun()
            exitWaves = nil
            dynamicalSpots = nil
            exitKey = nil
            return
        }
        let key = exitKeyFor(source)
        if let running, running.key == key {
            await running.task.value
            return
        }
        cancelRun()
        let optics = optics
        let specimen = source.name
        isComputing = true
        runNumber += 1
        let number = runNumber
        let task = Task { [weak self] in
            // The beams are read in the same waves (one forward FFT each), so the pattern and the image are one run (#911).
            let result: Result<(HRTEMExitWaves, Result<DynamicalSpots, DynamicalAbsence>), any Error> = await offMainActor {
                Result {
                    let waves = try HRTEMImage.exitWaves(built, optics: optics, specimen: specimen)
                    let spots = Result { try DynamicalSpots(waves, built: built) }.mapError { DynamicalAbsence(sentence: ErrorDetail.text($0)) }
                    return (waves, spots)
                }
            }
            self?.land(result, key: key, run: number)
        }
        running = (key, number, task)
        await task.value
    }

    /// Cancels the run going now, if any: its answer will not land.
    private func cancelRun() {
        running?.task.cancel()
        running = nil
        isComputing = false
    }

    /// A run's answer: kept when it is the run going now (by its number: a cancelled run of the same key is not), dropped otherwise.
    private func land(_ result: Result<(HRTEMExitWaves, Result<DynamicalSpots, DynamicalAbsence>), any Error>, key: ExitKey, run number: Int) {
        guard running?.number == number else { return }
        running = nil
        isComputing = false
        switch result {
        case .success(let (waves, spots)):
            exitWaves = waves
            dynamicalSpots = spots
            wavesRevision += 1
            exitKey = key
            computeFailure = nil
            if let thicknessIndex, thicknessIndex >= waves.waves.count { self.thicknessIndex = nil }
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            exitWaves = nil
            dynamicalSpots = nil
            exitKey = nil
            computeFailure = ErrorDetail.text(error)
        }
    }

    /// The stored wave the image shows: the one set, kept in range, else the thickest; nil before the first run.
    package var shownThicknessIndex: Int? {
        guard let exitWaves, !exitWaves.waves.isEmpty else { return nil }
        return min(thicknessIndex ?? (exitWaves.waves.count - 1), exitWaves.waves.count - 1)
    }

    /// The image of the stored exit waves at the defocus and thickness, or why there is none; nil before the first run.
    package func hrtemImage(name: String) -> Result<CalibratedImage, any Error>? {
        guard let exitWaves, let index = shownThicknessIndex else { return nil }
        return Result { try HRTEMImage.image(exitWaves, thicknessIndex: index, defocusNM: effectiveDefocusNM, optics: optics, name: name) }
    }

    private func exitKeyFor(_ source: Source) -> ExitKey {
        let periods: Int? = if case .success(let built) = specimen(source) { built.periods } else { nil }
        return ExitKey(crystal: source.identity, zoneAxis: source.zoneAxis, periods: periods,
                       maximumStrain: maximumStrain(source), volts: optics.volts,
                       apertureMrad: optics.apertureMrad, sigmas: thermal?.sigmas)
    }

    // MARK: Frozen phonons (#896)

    /// Turns frozen phonons on (σ per element, Å, and the number of configurations) or off (nil). Kept only when every σ is finite
    /// and at least 0 and the configurations are in `HRTEMThermal.configurationRange`; returns whether it was kept. A change of σ
    /// stops a run going: its configurations are of other vibrations.
    @discardableResult
    package func setThermal(_ new: HRTEMThermal?) -> Bool {
        if let new {
            guard new.sigmas.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  HRTEMThermal.configurationRange.contains(new.configurations) else { return false }
        }
        if new?.sigmas != thermal?.sigmas { stop() }
        thermal = new
        return true
    }

    /// Frozen phonons on with the default σ for every element of `crystal`, or off.
    /// Off and on again keeps the σ and configurations set before, when they name the same elements.
    package func useThermalVibrations(_ on: Bool, crystal: DiffractionCrystal?) {
        guard on else {
            if let thermal { lastThermal = thermal }
            setThermal(nil)
            return
        }
        guard thermal == nil, let new = thermalTurnedOn(crystal: crystal) else { return }
        setThermal(new)
    }

    /// What turning frozen phonons on for `crystal` sets: the σ and configurations set before when they name the same elements,
    /// else the defaults. Nil without a crystal or an atom model.
    package func thermalTurnedOn(crystal: DiffractionCrystal?) -> HRTEMThermal? {
        guard let source = source(crystal: crystal, zoneAxis: SIMD3(0, 0, 1)) else { return nil }
        let defaults = HRTEMThermal.defaults(for: source.atomicNumbers)
        if let lastThermal, Set(lastThermal.sigmas.keys) == Set(defaults.sigmas.keys) { return lastThermal }
        return defaults
    }

    /// A frozen-phonon run is going in this document.
    package var isSimulating: Bool { thermalProgress != nil }

    /// The specimen of a frozen-phonon run: the slab with whole units to at least `HRTEMThermal.lateralSize` across. Cached.
    package func thermalSpecimen(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>)
        -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal> {
        guard let source = source(crystal: crystal, zoneAxis: zoneAxis) else { return .failure(.noPhase) }
        let limit = maximumStrain(source)
        // A model's slabs are built off the main actor and kept by `buildModelSlabs`.
        if atomModel != nil { return source.build(thicknessNM, limit, HRTEMThermal.lateralSize) }
        let key = Key(crystal: source.identity, zoneAxis: source.zoneAxis, thicknessNM: thicknessNM, maximumStrain: limit)
        if let thermalCache, thermalCache.key == key { return thermalCache.result }
        let result = source.build(thicknessNM, limit, HRTEMThermal.lateralSize)
        thermalCache = (key, result)
        return result
    }

    /// Why Simulate cannot run now, in the room's words; nil when it can. One ladder for the toolbar verb and the door: no frozen
    /// phonons, the specimen's refusal, a run too large for this Mac, another document's run.
    package func simulateBlocker(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> String? {
        guard thermal != nil else { return "Frozen phonons are off: the static lattice's image is live." }
        if case .failure(let refusal) = thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis) { return refusal.sentence }
        if case .failure(let error)? = thermalPlanLine(crystal: crystal, zoneAxis: zoneAxis) { return ErrorDetail.text(error) }
        if !isSimulating, SimulationGate.shared.owner != nil { return "Another document is simulating; this one can run when it ends." }
        return nil
    }

    /// The stored configurations can be continued: they are of this specimen, optics and vibrations, and fewer than asked for.
    package func canContinue(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Bool {
        guard let thermal, let exitWaves, exitWaves.thermal != nil, exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis)
        else { return false }
        return !exitWaves.configurations.isEmpty && exitWaves.configurations.count < thermal.configurations
    }

    /// The plan line of a run (grid, slices, configurations, memory, and the time once measured), or why it does not fit this Mac;
    /// nil with frozen phonons off or no specimen.
    package func thermalPlanLine(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Result<String, any Error>? {
        guard let thermal, case .success(let built) = thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis) else { return nil }
        let rate = (try? HRTEMImage.thermalGrid(built, optics: optics)).flatMap { measuredRates[GridSize(nx: $0.nx, ny: $0.ny)] }
        return Result { try HRTEMImage.thermalPlanLine(built, optics: optics, thermal: thermal, stepsPerSecond: rate) }
    }

    /// Times a 10-slice run on the grid of a frozen-phonon run, off the main actor, once per grid (the plan line's time).
    package func measureRate(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) async {
        guard thermal != nil, case .success(let built) = thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis),
              let grid = try? HRTEMImage.thermalGrid(built, optics: optics) else { return }
        let size = GridSize(nx: grid.nx, ny: grid.ny)
        // Timed on a quiet Mac only: against a running simulation the rate would be slow and kept.
        guard measuredRates[size] == nil, SimulationGate.shared.owner == nil else { return }
        let optics = optics
        if let rate = await offMainActor({ try? HRTEMImage.measuredRate(built, optics: optics) }) { measuredRates[size] = rate }
    }

    /// Simulate (and Continue): runs the frozen-phonon configurations not yet stored, one at a time off the main actor, and lands
    /// each one as it finishes, so the image and the convergence readout grow while it runs. Configurations are seeded by their
    /// index, so a run stopped and continued gives the image an uninterrupted one gives. Returns when the run ends (done, stopped
    /// or failed); nothing while another document's run is going (one at a time on this Mac). `landed` is called after each
    /// configuration lands (the caller redraws the image).
    /// `current` reads the document's phase and zone axis now: a configuration lands only while they, the thickness, the optics and
    /// the vibrations are still the run's (the model's own setters stop the run; the phase and axis are the Diffraction room's).
    package func simulate(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>,
                          current: (() -> (crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>))? = nil,
                          landed: @escaping () -> Void = {}) async {
        guard let source = source(crystal: crystal, zoneAxis: zoneAxis), let thermal, thermalTask == nil else { return }
        guard SimulationGate.shared.owner == nil else {
            computeFailure = "Another document is simulating; this one can run when it ends."
            return
        }
        let built: SimulationSpecimen.Built
        switch thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis) {
        case .success(let b): built = b
        case .failure(let refusal):
            computeFailure = refusal.sentence
            return
        }
        let key = exitKeyFor(source)
        let optics = optics
        let start: HRTEMExitWaves
        do {
            _ = try HRTEMImage.thermalPlan(built, optics: optics, thermal: thermal)
            let fresh = try HRTEMImage.thermalEnsemble(built, optics: optics, thermal: thermal,
                                                      specimen: source.name)
            if canContinue(crystal: crystal, zoneAxis: zoneAxis), let exitWaves, exitWaves.planePeriods == fresh.planePeriods {
                start = HRTEMExitWaves(configurations: exitWaves.configurations, planePeriods: fresh.planePeriods, periodNM: fresh.periodNM,
                                       volts: fresh.volts, apertureMrad: fresh.apertureMrad, specimen: fresh.specimen, thermal: thermal)
            } else {
                start = fresh
            }
        } catch {
            computeFailure = ErrorDetail.text(error)
            return
        }
        cancelRun()
        computeFailure = nil
        let id = ObjectIdentifier(self)
        SimulationGate.shared.owner = id
        let total = thermal.configurations
        thermalProgress = ThermalProgress(configuration: start.configurations.count + 1, configurations: total)
        let task = Task { [weak self] in
            var ensemble = start
            for index in start.configurations.count ..< total {
                guard !Task.isCancelled, let model = self else { break }
                model.thermalProgress = ThermalProgress(configuration: index + 1, configurations: total)
                let progress: @Sendable (Double?) -> Void = { [weak model] fraction in
                    Task { @MainActor in
                        guard let model, model.thermalProgress?.configuration == index + 1 else { return }
                        model.thermalProgress?.fraction = fraction
                    }
                }
                let before = ensemble
                let made: Result<HRTEMExitWaves, any Error> = await offMainActor {
                    Result { try HRTEMImage.addingConfiguration(to: before, built: built, optics: optics, thermal: thermal, index: index,
                                                                progress: progress) }
                }
                let now = current?() ?? (crystal: crystal, zoneAxis: zoneAxis)
                guard !Task.isCancelled, let nowSource = model.source(crystal: now.crystal, zoneAxis: now.zoneAxis), model.exitKeyFor(nowSource) == key
                else { break }
                switch made {
                case .success(let grown):
                    ensemble = grown
                    let stored = ensemble, shown = model.shownIndex(of: stored), defocus = model.effectiveDefocusNM, imaging = model.optics
                    let change = await offMainActor {
                        try? HRTEMImage.convergence(stored, thicknessIndex: shown, defocusNM: defocus, optics: imaging)
                    }
                    model.landConfiguration(stored, key: key, convergence: change.map { Convergence(change: $0, defocusNM: defocus, thicknessIndex: shown) })
                    landed()
                case .failure(let error):
                    if !(error is CancellationError) { model.computeFailure = ErrorDetail.text(error) }
                }
                if case .failure = made { break }
            }
            if SimulationGate.shared.owner == id { SimulationGate.shared.owner = nil }
            self?.endSimulation()
        }
        thermalTask = task
        await task.value
    }

    /// Stop: ends the frozen-phonon run within a slice; the configurations that finished stay, and Continue adds the rest.
    package func stop() { thermalTask?.cancel() }

    private func shownIndex(of waves: HRTEMExitWaves) -> Int {
        min(thicknessIndex ?? (waves.planePeriods.count - 1), waves.planePeriods.count - 1)
    }

    private func landConfiguration(_ ensemble: HRTEMExitWaves, key: ExitKey, convergence: Convergence?) {
        exitWaves = ensemble
        // The beams are read on the static lattice only (#911): a thermal ensemble's would need the mean over configurations.
        dynamicalSpots = .failure(DynamicalAbsence(sentence: Self.thermalDynamicalSentence))
        exitKey = key
        wavesRevision += 1
        self.convergence = convergence
        if let thicknessIndex, thicknessIndex >= ensemble.planePeriods.count { self.thicknessIndex = nil }
    }

    /// Why a frozen-phonon run gives no dynamical spot intensities.
    package static let thermalDynamicalSentence = "Dynamical intensities are read on the static lattice; switch Thermal vibrations off to see them."

    private func endSimulation() {
        thermalTask = nil
        thermalProgress = nil
    }

    // MARK: Specimen

    /// The specimen of the atom model, or of `crystal` along `zoneAxis` at the thickness, or why there is none. Neither:
    /// "Add a phase to simulate." Cached; it writes no observed state, so a view may call it while drawing.
    package func specimen(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal> {
        guard let source = source(crystal: crystal, zoneAxis: zoneAxis) else { return .failure(.noPhase) }
        return specimen(source)
    }

    private func specimen(_ source: Source) -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal> {
        let limit = maximumStrain(source)
        if atomModel != nil { return source.build(thicknessNM, limit, nil) }
        let key = Key(crystal: source.identity, zoneAxis: source.zoneAxis, thicknessNM: thicknessNM, maximumStrain: limit)
        if let cache, cache.key == key { return cache.result }
        let result = source.build(thicknessNM, limit, nil)
        cache = (key, result)
        return result
    }

    /// The slab of `crystal` along `zoneAxis` as the crystal pane draws it (#897): capped at `SlabDrawing.drawnAtomLimit`, with
    /// the count named; nil while no specimen builds. Cached with the specimen, so a view may call it while drawing.
    package func drawnSlab(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> SlabDrawing.Drawn? {
        guard case .success(let built) = specimen(crystal: crystal, zoneAxis: zoneAxis) else { return nil }
        if let drawnCache, drawnCache.built == built { return drawnCache.drawn }
        let drawn = SlabDrawing.drawn(built)
        drawnCache = (built, drawn)
        return drawn
    }

    /// The specimen's atom columns on `image`, its HRTEM image (#897); nil while no specimen builds. Cached on the specimen and the
    /// image's size and sampling, so a view may call it while drawing (each zoom step redraws the image pane).
    package func columns(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>, on image: CalibratedImage) -> [SlabDrawing.Column]? {
        guard case .success(let built) = specimen(crystal: crystal, zoneAxis: zoneAxis) else { return nil }
        let key = ColumnsKey(built: built, width: image.width, height: image.height, x: image.x?.scale, y: image.y?.scale)
        if let columnsCache, columnsCache.key == key { return columnsCache.columns }
        let columns = SlabDrawing.columns(built, on: image)
        columnsCache = (key, columns)
        return columns
    }

    private struct ColumnsKey: Equatable {
        let built: SimulationSpecimen.Built
        let width: Int, height: Int
        let x: Double?, y: Double?

        // Written out (not synthesized) so the unused-code scan sees each field read.
        static func == (a: ColumnsKey, b: ColumnsKey) -> Bool {
            a.built == b.built && a.width == b.width && a.height == b.height && a.x == b.x && a.y == b.y
        }
    }

    /// Why the Atom columns rings are not drawn though the switch is on, in the section's words; nil when they are. The rings read
    /// the HRTEM image's size and calibration as the simulation's, so they wait for the image of this specimen, and Place Beside's
    /// pair (at the measured image's scale) has none.
    package func columnsBlocker(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> String? {
        if beside != nil { return "Column rings show on the simulation alone; turn Place Beside off." }
        if !exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) { return "The rings wait for the image of this specimen." }
        return nil
    }

    /// The rings to draw on `image`: the columns while the switch is on and nothing blocks them, else nil.
    package func drawnColumns(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>, on image: CalibratedImage) -> [SlabDrawing.Column]? {
        guard marksColumns, columnsBlocker(crystal: crystal, zoneAxis: zoneAxis) == nil else { return nil }
        return columns(crystal: crystal, zoneAxis: zoneAxis, on: image)
    }

    /// Marks the atom columns of the specimen on its HRTEM image (the HRTEM section's Atom columns switch and the door's).
    package func setMarksColumns(_ on: Bool) { marksColumns = on }
}

extension DiffractionAnalysis {
    /// The phase a Simulation document simulates: the shown library phase; nil while the room uses a calibration standard or a loose
    /// CIF ("Add a phase to simulate.").
    package var simulatedPhase: DiffractionCrystal? { crystal.phaseID == nil ? nil : crystal }

    /// The simulated phase's `count` strongest kinematic families (name and d, Å), strongest first (ties: the longer spacing first), for the transfer function
    /// strip; empty without a phase or a list.
    package func strongestSpacings(count: Int = 3) -> [(label: String, d: Double)] {
        guard simulatedPhase != nil, let list = list() else { return [] }
        return list.families.sorted { $0.intensity != $1.intensity ? $0.intensity > $1.intensity : $0.family.d > $1.family.d }.prefix(max(count, 0))
            .map { (label: DiffractionCompute.familyName($0.family), d: $0.family.d) }
    }
}

/// The one frozen-phonon run the app allows at a time (a run takes the Mac's memory budget). Observable, so another document's
/// Simulate, drawn disabled while a run goes, is enabled again when it ends.
@Observable package final class SimulationGate {
    package static let shared = SimulationGate()
    /// The model whose run goes; nil when none does.
    package fileprivate(set) var owner: ObjectIdentifier?

    /// The sentence for a run another document's run keeps waiting.
    package static let busySentence = "Another document is simulating; this one can run when it ends."

    /// Takes this Mac's one simulation for `id`; false while another holds it (the same `id` may take it again).
    package func acquire(_ id: ObjectIdentifier) -> Bool {
        guard owner == nil || owner == id else { return false }
        owner = id
        return true
    }

    /// Gives it back, when `id` holds it.
    package func release(_ id: ObjectIdentifier) {
        if owner == id { owner = nil }
    }
}
