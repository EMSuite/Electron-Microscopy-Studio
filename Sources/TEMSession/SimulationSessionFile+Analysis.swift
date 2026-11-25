//
//  SimulationSessionFile+Analysis.swift
//  Role: a Simulation document's Diffraction owner to and from its session file (#908, `SimulationSessionFile`): what ⌘S takes from
//        `DiffractionAnalysis`, and how a reopened file sets it again through the owner's own setters, in the order the room's controls
//        would (the phase first, since a new crystal drops a hand-set orientation; the orientation last).
//

import Foundation
import DiffractoCore
import TEMCore

extension SimulationSessionFile {
    /// The session of a Simulation document's owner now: its shown library phase as the frozen copy (none while it uses a
    /// calibration standard or a loose CIF), and its settings.
    @MainActor package init(analysis: DiffractionAnalysis) {
        var phase: SavedPhase?
        if case .phase(let p) = analysis.crystal {
            phase = SavedPhase(id: p.id, name: p.name, structure: CrystalStructure.Snapshot(p.structure))
        }
        let settings = analysis.simulation
        self.init(phase: phase, beamKV: analysis.typedBeamKV, cameraLengthMM: analysis.cameraLengthMM, kMax: analysis.kMax,
                  zoneAxis: settings.zoneAxis, turnDegrees: settings.inPlaneDegrees,
                  orientation: analysis.isTurnedByHand ? settings.indexed : nil, showsLabels: settings.showsLabels,
                  doubleDiffraction: settings.doubleDiffraction, excitationError: settings.excitationError)
    }

    /// Sets `analysis` to this session. The owner is bound to its canvas first (`DiffractionAnalysis.bind`), so the view's bind does
    /// not set k_max again.
    @MainActor package func apply(to analysis: DiffractionAnalysis) {
        if let phase {
            analysis.setCrystal(.phase(PhaseCrystal(id: phase.id, name: phase.name, structure: phase.structure.structure())))
        }
        analysis.typedBeamKV = beamKV
        analysis.setCameraLength(mm: cameraLengthMM)
        analysis.setKMax(kMax)
        analysis.setExcitationError(excitationError)
        analysis.simulation.showsLabels = showsLabels
        analysis.simulation.doubleDiffraction = doubleDiffraction
        analysis.setZoneAxis(zoneAxisVector)
        analysis.setTurn(degrees: turnDegrees)
        if let orientation { analysis.turnByHand(to: orientation) }
    }
}
