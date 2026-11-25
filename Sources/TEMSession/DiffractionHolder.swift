//
//  DiffractionHolder.swift
//  Role: the Diffraction room's double-tilt holder for one open pattern (plan row R16, #815): the stage tilts now (from the
//        file's stage readout when it has both, else typed), the limits, the tilt axis calibrated from a second indexed pattern,
//        and the zone axis the person picked. The tilt plan itself (`TiltPlanning.plan`: poles, traces, tilts, reach, sentences)
//        is derived from Index's orientation each time and cached by its inputs, never stored.
//

import Foundation
import Observation
import FormatoCore
import ImagoCore
import DiffractoCore
import DiffractoGeometry
import TEMCore

@Observable
package final class DiffractionHolder {
    /// The tilts now, their source, the limits and the calibrated axis.
    package private(set) var settings = HolderSettings()
    /// The zone axis picked in the Holder section (or the map), nil for none.
    package var selected: SIMD3<Int>?
    /// The last calibration the kit refused, in its words; cleared by the next try.
    package private(set) var calibrationRefusal: String?

    @ObservationIgnored private var stageRead = false
    @ObservationIgnored private var planCache: (key: PlanKey, plan: TiltPlan)?
    private struct PlanKey: Equatable {
        var phase: String
        var structure: CrystalStructure
        var orientation: CrystalOrientation
        var holder: HolderSettings
        var wavelength: Double?

        // Spelled out, so every input is read where the cache compares it.
        static func == (a: PlanKey, b: PlanKey) -> Bool {
            a.phase == b.phase && a.structure == b.structure && a.orientation == b.orientation && a.holder == b.holder
                && a.wavelength == b.wavelength
        }
    }

    package init() {}

    /// The file's stage tilts, both α and β or nothing, read when the item publishes a read of its file (`OpenItem`). Read once:
    /// a later read, or a record that states no tilts, keeps what is there, and a typed tilt is never overwritten.
    package func bindStage(_ metadata: AcquisitionMetadata) {
        guard !stageRead, let alpha = metadata.stageTiltAlphaDeg?.value, let beta = metadata.stageTiltBetaDeg?.value else { return }
        stageRead = true
        settings.readStage(alphaDeg: alpha, betaDeg: beta)
    }

    package func setTilts(alphaDeg: Double, betaDeg: Double) {
        guard alphaDeg.isFinite, betaDeg.isFinite, alphaDeg != settings.alphaDeg || betaDeg != settings.betaDeg else { return }
        settings.alphaDeg = alphaDeg; settings.betaDeg = betaDeg; settings.source = .typed
        stageRead = true
    }

    /// A limit is a positive number of degrees up to 90.
    package func setLimits(alphaDeg: Double, betaDeg: Double) {
        guard alphaDeg.isFinite, betaDeg.isFinite, alphaDeg > 0, betaDeg > 0, alphaDeg <= 90, betaDeg <= 90 else { return }
        settings.alphaLimitDeg = alphaDeg; settings.betaLimitDeg = betaDeg
    }

    /// A typed tilt axis (degrees in the pattern): it stands without a calibration record.
    package func setAxis(degrees: Double) {
        guard degrees.isFinite else { return }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        settings.axisAngleDeg = d
        settings.calibration = nil
    }

    /// Forgets the axis: α and β are no longer said.
    package func forgetAxis() {
        settings.axisAngleDeg = nil
        settings.calibration = nil
        calibrationRefusal = nil
    }

    /// The plan of the room's crystal at Index's orientation; nil before Index found one.
    package func plan(analysis: DiffractionAnalysis, image: CalibratedImage) -> TiltPlan? {
        guard let orientation = analysis.indexOutcome?.orientation else { return nil }
        let wavelength = analysis.volts(for: image).map { ElectronWavelength.angstroms(volts: $0) }
        let key = PlanKey(phase: analysis.crystal.name, structure: analysis.crystal.structure, orientation: orientation,
                          holder: settings, wavelength: wavelength)
        if let planCache, planCache.key == key { return planCache.plan }
        let plan = TiltPlanning.plan(phase: key.phase, structure: key.structure, orientation: orientation, holder: settings,
                                     wavelengthAngstroms: wavelength)
        planCache = (key, plan)
        return plan
    }

    /// Calibrates the tilt axis against another indexed pattern of the same crystal at its own tilts.
    package func calibrate(analysis: DiffractionAnalysis, other: DiffractionAnalysis, otherHolder: DiffractionHolder, otherName: String) {
        guard let mine = analysis.indexOutcome?.orientation, let theirs = other.indexOutcome?.orientation else {
            calibrationRefusal = "Both patterns need an orientation from Index."
            return
        }
        switch TiltPlanning.calibrate(settings, structure: analysis.crystal.structure, orientation: mine, other: theirs,
                                      otherTilts: otherHolder.settings.tilts, otherName: otherName) {
        case .success(let calibrated):
            settings = calibrated
            calibrationRefusal = nil
        case .failure(let why):
            calibrationRefusal = why.description
        }
    }
}
