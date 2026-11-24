//
//  SimulationModel.swift
//  Role: a Simulation document's multislice state (2.5): the specimen's thickness and the strain the person accepted (#893, MA1),
//        and the HRTEM image's optics, defocus and thickness with the exit waves it is made from (#894, MA2). The
//        phase and the zone axis stay the Diffraction room's (`DiffractionAnalysis.crystal`, `simulation.zoneAxis`), so the pattern and
//        the specimen are always built from the same crystal and axis. The slab is built by `SimulationSpecimen` (SimulatoKit's
//        slab builder) and cached on the crystal's identity, the axis, the thickness and the strain limit. The exit waves (one orthogonal
//        unit at whole periods, at most 256 MiB) are computed off the main actor and kept with the key they were made for; the image is made
//        from them on demand, one inverse FFT, so moving Defocus or Thickness redraws at once.
//

import DiffractoCore
import Foundation
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
    /// Raised each time new exit waves land: what a view keys work on the stored waves by.
    package private(set) var wavesRevision = 0
    /// The run going now and what it computes for.
    @ObservationIgnored private var running: (key: ExitKey, number: Int, task: Task<Void, Never>)?
    /// Counts the runs started, so each one's answer is told apart from a cancelled run's of the same key.
    @ObservationIgnored private var runNumber = 0

    /// What the stored exit waves were computed for: the specimen as built (its periods, not the thickness typed, so 10.0 and
    /// 10.1 nm, the same 13 periods, keep the waves), the voltage and the aperture.
    private struct ExitKey: Equatable {
        let crystal: String
        let zoneAxis: SIMD3<Int>
        let periods: Int?
        let maximumStrain: Double
        let volts: Double
        let apertureMrad: Double?
    }

    private struct Key: Equatable {
        let crystal: String
        let zoneAxis: SIMD3<Int>
        let thicknessNM: Double
        let maximumStrain: Double
    }
    @ObservationIgnored private var cache: (key: Key, result: Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal>)?

    package init() {}

    /// Sets the thickness, nm, kept in the field's range; a non-finite value changes nothing.
    package func setThickness(nm: Double) {
        guard nm.isFinite else { return }
        thicknessNM = min(max(nm, SimulationSpecimen.thicknessRangeNM.lowerBound), SimulationSpecimen.thicknessRangeNM.upperBound)
    }

    /// The strain limit for `crystal` along `zoneAxis`: the one Build with Strain accepted there (the kit's test is "at most", and the same
    /// box gives the same strain), else the kit's default.
    package func maximumStrain(crystal: DiffractionCrystal, zoneAxis: SIMD3<Int>) -> Double {
        if let acceptedStrain, acceptedStrain.crystal == crystal.identity, acceptedStrain.zoneAxis == zoneAxis {
            return acceptedStrain.strain
        }
        return SimulationSpecimen.defaultMaximumStrain
    }

    /// Build with Strain: builds this crystal along this axis with the strain the refusal named.
    package func acceptStrain(_ strain: Double, crystal: DiffractionCrystal, zoneAxis: SIMD3<Int>) {
        guard strain.isFinite, strain >= 0 else { return }
        acceptedStrain = AcceptedStrain(crystal: crystal.identity, zoneAxis: zoneAxis, strain: strain)
    }

    // MARK: HRTEM

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
    package func setOptics(_ new: HRTEMOptics) { optics = new }

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
        optics.volts = kV * 1000
    }

    /// Whether the stored exit waves are those of this specimen and optics.
    package func exitWavesAreCurrent(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Bool {
        guard let crystal, let exitKey else { return false }
        return exitKey == exitKeyFor(crystal: crystal, zoneAxis: zoneAxis)
    }

    /// Runs the multislice for this specimen and optics off the main actor when the stored exit waves are not theirs, and returns
    /// when they are current or the run failed. A call for the run already going waits for it; a call for another specimen or optics
    /// cancels it and starts its own, so only the newest run's answer lands, whoever calls (the HRTEM section's task, Show HRTEM
    /// Image, the door). A finished run lands even when its caller went away: its result is valid for its key.
    package func updateExitWaves(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) async {
        guard let crystal, !exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) else {
            // The stored waves are what is asked for (or there is nothing to ask): a run for anything else must not land over them.
            cancelRun()
            return
        }
        guard case .success(let built) = specimen(crystal: crystal, zoneAxis: zoneAxis) else {
            cancelRun()
            exitWaves = nil
            exitKey = nil
            return
        }
        let key = exitKeyFor(crystal: crystal, zoneAxis: zoneAxis)
        if let running, running.key == key {
            await running.task.value
            return
        }
        cancelRun()
        let optics = optics
        let specimen = "\(crystal.name) \(ZoneAxisText.text(zoneAxis))"
        isComputing = true
        runNumber += 1
        let number = runNumber
        let task = Task { [weak self] in
            let result: Result<HRTEMExitWaves, any Error> = await offMainActor {
                Result { try HRTEMImage.exitWaves(built, optics: optics, specimen: specimen) }
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
    private func land(_ result: Result<HRTEMExitWaves, any Error>, key: ExitKey, run number: Int) {
        guard running?.number == number else { return }
        running = nil
        isComputing = false
        switch result {
        case .success(let waves):
            exitWaves = waves
            wavesRevision += 1
            exitKey = key
            computeFailure = nil
            if let thicknessIndex, thicknessIndex >= waves.waves.count { self.thicknessIndex = nil }
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            exitWaves = nil
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

    private func exitKeyFor(crystal: DiffractionCrystal, zoneAxis: SIMD3<Int>) -> ExitKey {
        let periods: Int? = if case .success(let built) = specimen(crystal: crystal, zoneAxis: zoneAxis) { built.periods } else { nil }
        return ExitKey(crystal: crystal.identity, zoneAxis: zoneAxis, periods: periods,
                       maximumStrain: maximumStrain(crystal: crystal, zoneAxis: zoneAxis), volts: optics.volts,
                       apertureMrad: optics.apertureMrad)
    }

    // MARK: Specimen

    /// The specimen of `crystal` along `zoneAxis` at the thickness, or why there is none. Nil crystal: "Add a phase to simulate."
    /// Cached; it writes no observed state, so a view may call it while drawing.
    package func specimen(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal> {
        guard let crystal else { return .failure(.noPhase) }
        let limit = maximumStrain(crystal: crystal, zoneAxis: zoneAxis)
        let key = Key(crystal: crystal.identity, zoneAxis: zoneAxis, thicknessNM: thicknessNM, maximumStrain: limit)
        if let cache, cache.key == key { return cache.result }
        let result = SimulationSpecimen.build(crystal.structure, zoneAxis: zoneAxis, thicknessNM: thicknessNM, maximumStrain: limit)
        cache = (key, result)
        return result
    }
}

extension DiffractionAnalysis {
    /// The phase a Simulation document simulates: the shown library phase; nil while the room uses a calibration standard or a loose
    /// CIF ("Add a phase to simulate.").
    package var simulatedPhase: DiffractionCrystal? { crystal.phaseID == nil ? nil : crystal }
}
