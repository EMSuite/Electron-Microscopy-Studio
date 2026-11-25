//
//  CBEDThicknessModel.swift
//  Role: the Diffraction room's Measure Thickness (#916, plan row MA15) for one open pattern: the inputs read from the room (the
//        centre, the scale, the phase and its first families, the beam energy), the measurement off the main actor, newest wins,
//        and its outcome until the pattern, the phase or the calibration changes. The numbers are `CBEDThickness`'s, and its fit
//        is DiffractoKit's.
//

import DiffractoCore
import DiffractoScattering
import Foundation
import Observation
import TEMCore

@Observable
package final class CBEDThicknessModel {
    /// The last measurement, or why there is none; nil before Measure Thickness or after its inputs changed.
    package private(set) var outcome: Result<CBEDThickness.Measurement, CBEDThickness.Refusal>?
    package private(set) var isMeasuring = false
    /// What the outcome was measured for: a change of any of it clears the outcome (`isCurrent`).
    @ObservationIgnored private var outcomeKey: Inputs.Key?
    @ObservationIgnored private var running: Task<Void, Never>?

    package init() {}

    /// What a measurement reads from the room.
    package struct Inputs: Sendable {
        let image: CalibratedImage
        let centre: SIMD2<Double>
        let deltaQ: Double
        let structure: CrystalStructure
        let families: [ReflectionFamily]
        let phase: String
        let volts: Double
        let key: Key

        /// The pattern's content (the canvas's version), the phase, the centre, the scale and the voltage.
        package struct Key: Equatable, Sendable {
            // periphery:ignore - read by the synthesized == (and hash)
            let contentVersion: Int
            // periphery:ignore - read by the synthesized == (and hash)
            let phase: String
            // periphery:ignore - read by the synthesized == (and hash)
            let centre: SIMD2<Double>
            // periphery:ignore - read by the synthesized == (and hash)
            let deltaQ: Double
            // periphery:ignore - read by the synthesized == (and hash)
            let volts: Double
        }
    }

    /// The inputs on `image` (shown at `contentVersion`) in `analysis`, or why none: no library phase, no scale, no beam energy.
    package static func inputs(image: CalibratedImage, contentVersion: Int, analysis: DiffractionAnalysis)
        -> Result<Inputs, CBEDThickness.Refusal> {
        guard let phase = analysis.simulatedPhase else { return .failure(.noPhase) }
        guard let deltaQ = analysis.calibration(for: image)?.deltaQ, deltaQ.isFinite, deltaQ > 0, let centre = analysis.centre
        else { return .failure(.noScale) }
        guard let volts = analysis.volts(for: image) else { return .failure(.noVoltage) }
        let families = analysis.list()?.families.map(\.family) ?? []
        let at = SIMD2(centre.row, centre.column)
        return .success(Inputs(image: image, centre: at, deltaQ: deltaQ, structure: phase.structure, families: families, phase: phase.name,
                               volts: volts, key: Inputs.Key(contentVersion: contentVersion, phase: phase.identity, centre: at, deltaQ: deltaQ,
                                                             volts: volts)))
    }

    /// Why a simulated CBED pattern gives no two-beam thickness (#1004). The run is the exact zone axis (`CBEDRun.run` sends the probe
    /// down it, untilted): every reflection meets its Bragg condition halfway to the direct beam, outside its own disc while the
    /// discs are apart, so its disc never carries the two-beam fringes on both sides of the Bragg position at any thickness.
    package static func zoneAxisPatternSentence(_ zoneAxis: SIMD3<Int>) -> String {
        "This CBED pattern is simulated on the exact zone axis \(PatternIndexing.zoneText(zoneAxis)): no reflection meets its Bragg "
            + "condition inside its disc, so there are no two-beam fringes to fit at any thickness. Measure Thickness needs a pattern "
            + "tilted until one reflection is strong; the simulation does not tilt the beam yet."
    }

    /// Whether the outcome is that of these inputs.
    package func isCurrent(_ inputs: Inputs?) -> Bool { inputs != nil && inputs?.key == outcomeKey }

    /// Measure Thickness on `inputs`, off the main actor; a newer call cancels this one's landing. Returns when it has landed.
    package func measure(_ inputs: Result<Inputs, CBEDThickness.Refusal>) async {
        running?.cancel()
        switch inputs {
        case .failure(let refusal):
            outcome = .failure(refusal)
            outcomeKey = nil
            isMeasuring = false
        case .success(let inputs):
            isMeasuring = true
            let task = Task { [weak self] in
                let result = await offMainActor {
                    Result { () throws(CBEDThickness.Refusal) in
                        try CBEDThickness.measure(image: inputs.image, centre: inputs.centre, deltaQ: inputs.deltaQ,
                                                  structure: inputs.structure, families: inputs.families, phase: inputs.phase,
                                                  volts: inputs.volts)
                    }
                }
                guard !Task.isCancelled, let self else { return }
                self.outcome = result
                self.outcomeKey = inputs.key
                self.isMeasuring = false
            }
            running = task
            await task.value
        }
    }
}

extension OpenItem {
    /// What Measure Thickness measures for this item now: its pattern, its canvas's content version, its phase, calibration,
    /// centre and beam energy; or why not. The room's section and the door read this one.
    package var thicknessInputs: Result<CBEDThicknessModel.Inputs, CBEDThickness.Refusal> {
        guard let image = session.image else { return .failure(.kit("The pattern is still loading.")) }
        // A Simulation document's CBED pattern is the exact zone axis (#1004): no thickness has fringes to fit, so say why up front.
        if DemoDocuments.isCBED(url) {
            return .failure(.kit(CBEDThicknessModel.zoneAxisPatternSentence(diffraction.simulation.zoneAxis)))
        }
        return CBEDThicknessModel.inputs(image: image, contentVersion: presentation.canvas?.contentVersion ?? 0, analysis: diffraction)
    }
}
