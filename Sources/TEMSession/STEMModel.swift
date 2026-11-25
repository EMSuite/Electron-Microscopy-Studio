//
//  STEMModel.swift
//  Role: a Simulation document's STEM image (#913, plan row MA10): the STEM settings, the detector band (a preset or custom, moved
//        after the run with no new run), and the run: prepared from the document's specimen (at least 20 Å across), optics' Cs and
//        thermal vibrations, advanced off the main actor a slice at a time so the image fills as it is computed, holding this Mac's
//        one simulation (`SimulationGate`) while it goes. Stop keeps every finished configuration and position; Simulate again
//        continues the same run while its settings are unchanged. The numbers are `STEMImage`'s.
//

import Foundation
import Observation
import TEMCore

@Observable
package final class STEMModel {
    package private(set) var settings = STEMSettings()
    /// The detector preset shown; nil with a custom band.
    package private(set) var detector: STEMDetector? = .haadf
    /// The band typed for Custom, mrad.
    package private(set) var customBand = STEMBand(inner: 60, outer: 200)
    /// The run so far (done, stopped or going); nil before the first run or after a setting that needs a new one.
    package private(set) var scan: STEMScan?
    package private(set) var isRunning = false
    /// The fraction of the whole run done, while one goes and the kit reports one.
    package private(set) var progress: Double?
    /// Why the last run gave no image, in the kit's or the plan's words.
    package private(set) var failure: String?
    @ObservationIgnored private var scanKey: RunKey?
    @ObservationIgnored private var running: (number: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var runNumber = 0

    /// What a run is of: the specimen, the optics' Cs and voltage, the vibrations and the settings. Another key needs a new run.
    package nonisolated struct RunKey: Equatable, Sendable {
        /// The specimen: `SimulationModel.sourceIdentity`, the phase's or the atom model's with its beam axis (#953).
        // periphery:ignore - read by the synthesized == (and hash)
        let source: String
        // periphery:ignore - read by the synthesized == (and hash)
        let zoneAxis: SIMD3<Int>
        // periphery:ignore - read by the synthesized == (and hash)
        let thicknessNM: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let maximumStrain: Double
        package let volts: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let csMM: Double
        // periphery:ignore - read by the synthesized == (and hash)
        let thermal: HRTEMThermal?
        // periphery:ignore - read by the synthesized == (and hash)
        let settings: STEMSettings
    }

    package init() {}

    /// The band summed for the image, on the rings' edges: the preset's at the run's semiangle (the settings' before a run), or the
    /// custom one.
    package var band: STEMBand {
        detector?.band(semiangleMrad: scan?.settings.semiangleMrad ?? settings.semiangleMrad).snapped() ?? customBand
    }

    /// The largest angle the band can reach: the run's collection angle, or the settings' before a run.
    package var collectedMrad: Double { scan?.settings.collectMrad ?? settings.collectMrad }

    /// Why the band gives no image: it runs past the angles collected (a preset after Collect to was lowered). Nil when it fits.
    package var bandRefusal: String? {
        let band = band, collected = collectedMrad
        guard band.outer > collected else { return nil }
        func n(_ v: Double) -> String { UnitDisplay.number(v, digits: 3) }
        return "\(detector?.title ?? "The band") runs to \(n(band.outer)) mrad, past the \(n(collected)) mrad collected: choose a band "
            + "inside it, or raise Collect to and simulate again."
    }

    /// Edits the settings; kept only when every value is in its range. Returns whether it was kept. A run of other settings stays
    /// until a new one replaces it.
    @discardableResult
    package func changeSettings(_ edit: (inout STEMSettings) -> Void) -> Bool {
        var new = settings
        edit(&new)
        let valid = STEMSettings.semiangleRangeMrad.contains(new.semiangleMrad)
            && (new.defocusNM.map(\.isFinite) ?? true)
            && (new.scanStepAngstrom.map { STEMSettings.scanStepRangeAngstrom.contains($0) } ?? true)
            && STEMSettings.collectRangeMrad.contains(new.collectMrad)
        guard valid else { return false }
        // The collection angle is whole rings, so every band edge is a ring edge.
        new.collectMrad = (new.collectMrad / STEMSettings.ringMrad).rounded() * STEMSettings.ringMrad
        settings = new
        return true
    }

    /// A preset band, or Custom (nil) with the band shown. A preset that runs past the angles collected (by the run, and by the
    /// settings) is not kept. Returns whether it was kept.
    @discardableResult
    package func setDetector(_ preset: STEMDetector?) -> Bool {
        if let preset {
            guard fits(preset) else { return false }
        } else {
            customBand = band
        }
        detector = preset
        return true
    }

    /// Whether `preset`'s band fits inside the angles collected by the run held and by `settings` (the settings now by default).
    package func fits(_ preset: STEMDetector, settings: STEMSettings? = nil) -> Bool {
        let settings = settings ?? self.settings
        let outer = preset.band(semiangleMrad: scan?.settings.semiangleMrad ?? settings.semiangleMrad).snapped().outer
        return outer <= min(scan?.settings.collectMrad ?? settings.collectMrad, settings.collectMrad)
    }

    /// A band typed or dragged, snapped to the rings: Custom, kept when it is inside the collected angles with its inner edge
    /// below its outer one.
    @discardableResult
    package func setBand(_ typed: STEMBand) -> Bool {
        guard typed.inner.isFinite, typed.outer.isFinite, typed.outer > typed.inner else { return false }
        let band = typed.snapped()
        guard band.inner >= 0, band.outer > band.inner, band.outer <= settings.collectMrad else { return false }
        customBand = band
        detector = STEMDetector.matching(band, semiangleMrad: scan?.settings.semiangleMrad ?? settings.semiangleMrad)
        return true
    }

    /// Why Simulate cannot run now: another document's simulation holds this Mac.
    package var blocker: String? {
        guard let owner = SimulationGate.shared.owner, owner != ObjectIdentifier(self) else { return nil }
        return SimulationGate.busySentence
    }

    /// Whether the run held is of `key` (Simulate continues it rather than starting again).
    package func holds(_ key: RunKey) -> Bool { scan != nil && scanKey == key }

    /// The key of a run for this specimen (`SimulationModel.sourceIdentity`), optics and vibrations with the settings now.
    package func key(source: String, zoneAxis: SIMD3<Int>, thicknessNM: Double, maximumStrain: Double, volts: Double,
                     csMM: Double, thermal: HRTEMThermal?) -> RunKey {
        RunKey(source: source, zoneAxis: zoneAxis, thicknessNM: thicknessNM, maximumStrain: maximumStrain, volts: volts,
               csMM: csMM, thermal: thermal, settings: settings)
    }

    /// Simulate (and Continue): prepares a run of `key` with `prepare` unless the one held is of it, then advances it off the main
    /// actor a slice at a time until it is complete, calling `landed` after each slice so the image fills. Returns when the run
    /// ends (done, stopped or failed); nothing while another document's run holds this Mac.
    package func simulate(_ key: RunKey, prepare: @escaping @Sendable () throws -> STEMScan, landed: @escaping () -> Void = {}) async {
        guard !isRunning else { return }
        guard SimulationGate.shared.acquire(ObjectIdentifier(self)) else {
            failure = SimulationGate.busySentence
            return
        }
        runNumber += 1
        let number = runNumber
        isRunning = true
        progress = nil
        failure = nil
        let held = holds(key) ? scan : nil
        let report: @Sendable (Double?) -> Void = { [weak self] fraction in
            guard let fraction else { return }
            Task { @MainActor in if self?.running?.number == number { self?.progress = fraction } }
        }
        let task = Task { [weak self] in
            do {
                var current: STEMScan
                if let held { current = held } else {
                    current = try await offMainActor { Result { try prepare() } }.get()
                    guard let self, self.running?.number == number else { return }
                    self.scan = current
                    self.scanKey = key
                    landed()
                }
                // Every resume sets its configuration up again, so a slice grows (`STEMImage.nextSlice`) rather than resetting.
                var slice = Duration.seconds(1)
                while !current.isComplete, !Task.isCancelled {
                    let before = (current.completedConfigurations, current.completedPositions)
                    current = try await STEMImage.advance(current, slice: slice, progress: report)
                    guard let self, self.running?.number == number else { return }
                    self.scan = current
                    landed()
                    slice = STEMImage.nextSlice(after: slice,
                                                progressed: before != (current.completedConfigurations, current.completedPositions))
                }
                self?.end(number, failure: nil)
            } catch {
                self?.end(number, failure: ErrorDetail.text(error))
            }
        }
        running = (number, task)
        await task.value
    }

    /// Stop: the run going ends after its current round of positions; what it finished stays, and Simulate continues it.
    package func stop() { running?.task.cancel() }

    /// The document closes: the run ends now and this Mac's one simulation is free at once (the task's own end would never run
    /// once the model is gone).
    package func close() {
        running?.task.cancel()
        running = nil
        isRunning = false
        progress = nil
        SimulationGate.shared.release(ObjectIdentifier(self))
    }

    private func end(_ number: Int, failure: String?) {
        guard running?.number == number else { return }
        running = nil
        isRunning = false
        progress = nil
        self.failure = failure
        SimulationGate.shared.release(ObjectIdentifier(self))
    }

    /// The image of the band now, or nil before a run; the kit's refusal of the band as the failure.
    package func image(fieldOfViewNM: Double, name: String) -> Result<CalibratedImage, any Error>? {
        guard let scan, !scan.isEmpty, bandRefusal == nil else { return nil }
        return Result { try scan.image(band: band, fieldOfViewNM: fieldOfViewNM, name: name) }
    }
}
