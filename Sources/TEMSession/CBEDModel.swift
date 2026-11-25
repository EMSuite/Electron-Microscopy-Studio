//
//  CBEDModel.swift
//  Role: a Simulation document's convergent-beam pattern (#912, plan row MA9): Parallel or Convergent, the CBED settings (the
//        semiangle with Fit Discs, the largest thickness, the angular step, the edge), the run with its plan, and the stored patterns
//        with the thickness the slider shows. The crystal, the zone axis and the beam energy stay the Diffraction room's, and the
//        unit is the specimen `SimulationModel` builds, so the parallel and the convergent pattern are one crystal. The run is off the
//        main actor and newest-wins, as the HRTEM exit waves are; the pattern of a thickness is a lookup in the stored ones.
//

import DiffractoCore
import DiffractoScattering
import Foundation
import Observation
import TEMCore

@Observable
package final class CBEDModel {
    /// Convergent: the pattern is the probe's discs (a run); Parallel: the plane-wave spots of the Simulation section.
    package private(set) var isConvergent = false
    package private(set) var settings = CBEDSettings()
    /// Which stored pattern is shown; nil is the stored one nearest 10 nm (the design's default thickness).
    package private(set) var thicknessIndex: Int?
    /// The last run's patterns (of `patternKey` when it is current); nil before the first run. A failed or stopped run keeps them.
    package private(set) var pattern: CBEDPattern?
    package private(set) var isComputing = false
    /// The fraction of the run done, while one runs and it reports one.
    package private(set) var progress: Double?
    /// Why the last run gave no pattern, in the kit's or the plan's words.
    package private(set) var failure: String?
    @ObservationIgnored private var patternKey: RunKey?
    /// The run going: its key, its number (told apart from a cancelled run of the same key) and its task.
    @ObservationIgnored private var running: (key: RunKey, number: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var runNumber = 0

    /// The default thickness shown, nm.
    package static let shownThicknessNM = 10.0

    package nonisolated struct RunKey: Equatable, Sendable {
        /// The specimen: `SimulationModel.sourceIdentity`, the phase's or the atom model's with its beam axis (#953).
        // periphery:ignore - read by the synthesized == (and hash)
        let source: String
        // periphery:ignore - read by the synthesized == (and hash)
        let zoneAxis: SIMD3<Int>
        // periphery:ignore - read by the synthesized == (and hash)
        let maximumStrain: Double
        package let volts: Double
        package let semiangleMrad: Double
        let settings: CBEDSettings
    }

    package init() {}

    package func setConvergent(_ on: Bool) { isConvergent = on }

    /// Edits the settings; kept only when every value is in its range. Returns whether it was kept.
    @discardableResult
    package func changeSettings(_ edit: (inout CBEDSettings) -> Void) -> Bool {
        var new = settings
        edit(&new)
        let valid = (new.semiangleMrad.map { CBEDSettings.semiangleRangeMrad.contains($0) } ?? true)
            && CBEDSettings.largestThicknessRangeNM.contains(new.largestThicknessNM)
            && new.thicknessStepNM.isFinite && new.thicknessStepNM > 0 && new.thicknessStepNM <= new.largestThicknessNM
            && CBEDSettings.angularStepRangeMrad.contains(new.angularStepMrad) && CBEDSettings.edgeRangeMrad.contains(new.edgeMrad)
        guard valid else { return false }
        settings = new
        return true
    }

    /// Fit Discs: back to the largest semiangle that keeps the discs apart.
    package func fitDiscs() { settings.semiangleMrad = nil }

    package func setThicknessIndex(_ index: Int) { thicknessIndex = max(0, index) }

    /// The stored pattern shown: the one set, kept in range, else the one nearest 10 nm; nil before a run.
    package var shownIndex: Int? {
        guard let pattern, !pattern.patterns.isEmpty else { return nil }
        if let thicknessIndex { return min(thicknessIndex, pattern.patterns.count - 1) }
        return pattern.index(nearest: Self.shownThicknessNM)
    }

    /// The semiangle a run uses for `shortestG` (1/Å, the zero-order zone's shortest reflection): the typed one, else Fit Discs'.
    package func semiangle(shortestG: Double?, volts: Double) -> Double? {
        if let typed = settings.semiangleMrad { return typed }
        guard let shortestG, shortestG > 0 else { return nil }
        return try? CBEDRun.separatedSemiangle(shortestG: shortestG, volts: volts)
    }

    /// Whether the stored patterns are those of `key`.
    package func isCurrent(_ key: RunKey?) -> Bool { key != nil && patternKey == key }

    /// The key of a run for this specimen (`SimulationModel.sourceIdentity`), axis, strain limit, voltage and semiangle.
    package func key(source: String, zoneAxis: SIMD3<Int>, maximumStrain: Double, volts: Double, semiangleMrad: Double) -> RunKey {
        RunKey(source: source, zoneAxis: zoneAxis, maximumStrain: maximumStrain, volts: volts, semiangleMrad: semiangleMrad,
               settings: settings)
    }

    /// Why Show CBED Pattern cannot run now: another document's simulation holds this Mac (one at a time, `SimulationGate`).
    package var blocker: String? {
        guard let owner = SimulationGate.shared.owner, owner != ObjectIdentifier(self) else { return nil }
        return SimulationGate.busySentence
    }

    /// Runs the probe for `key` off the main actor unless its patterns are stored, and returns when they are or the run failed. A
    /// call for the run going waits for it; a call for another key cancels it and starts its own (newest wins, whoever calls: the
    /// section's task, Show CBED Pattern, the door). It holds `SimulationGate` while it runs; with another document's run going it
    /// starts nothing and says so. `shortestG` is the first ring the edge must hold (`CBEDRun.edgeSentence`).
    package func update(_ key: RunKey, built: SimulationSpecimen.Built, specimen: String, shortestG: Double? = nil) async {
        guard !isCurrent(key) else { return }
        if let running, running.key == key {
            await running.task.value
            return
        }
        guard SimulationGate.shared.acquire(ObjectIdentifier(self)) else {
            failure = SimulationGate.busySentence
            return
        }
        running?.task.cancel()
        runNumber += 1
        let number = runNumber
        isComputing = true
        progress = nil
        let settings = key.settings
        let report: @Sendable (Double?) -> Void = { [weak self] fraction in
            guard let fraction else { return }
            Task { @MainActor in if self?.running?.number == number { self?.progress = fraction } }
        }
        let task = Task { [weak self] in
            let result: Result<CBEDPattern, any Error> = await offMainActor {
                Result { try CBEDRun.run(built, settings: settings, semiangleMrad: key.semiangleMrad, volts: key.volts, specimen: specimen,
                                         shortestG: shortestG, progress: report) }
            }
            self?.land(result, key: key, number: number)
        }
        running = (key, number, task)
        await task.value
    }

    /// Stop: the run going ends; the stored patterns stay.
    package func stop() {
        running?.task.cancel()
        running = nil
        isComputing = false
        progress = nil
        SimulationGate.shared.release(ObjectIdentifier(self))
    }

    /// Lands run `number`'s answer while it is still the run going (a stopped or replaced run's answer is dropped).
    private func land(_ result: Result<CBEDPattern, any Error>, key: RunKey, number: Int) {
        guard running?.number == number else { return }
        running = nil
        isComputing = false
        progress = nil
        SimulationGate.shared.release(ObjectIdentifier(self))
        switch result {
        case .success(let made):
            pattern = made
            patternKey = key
            failure = nil
            if let thicknessIndex, thicknessIndex >= made.patterns.count { self.thicknessIndex = nil }
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            patternKey = nil
            failure = ErrorDetail.text(error)
        }
    }

    /// The shown pattern as an image of the app, or nil before a run.
    package func image(name: String) -> CalibratedImage? {
        guard let pattern, let index = shownIndex else { return nil }
        return pattern.image(at: index, name: name)
    }
}

extension DiffractionAnalysis {
    /// The shortest reflection of the zero-order zone at the overlay's zone axis, 1/Å: the kinematic list's shortest family with a
    /// member on the zone (h u + k v + l w = 0), what Fit Discs keeps apart. Read from the list, not the drawn overlay, so it holds
    /// with the simulated spots hidden. Nil without a phase or a reflection on the zone.
    package func shortestZeroOrderG() -> Double? {
        guard simulatedPhase != nil, let list = list() else { return nil }
        let axis = simulation.zoneAxis
        return list.families.map(\.family)
            .filter { $0.g > 0 && $0.members.contains { $0.h * axis.x + $0.k * axis.y + $0.l * axis.z == 0 } }
            .map(\.g).min()
    }
}
