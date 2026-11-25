//
//  OpenItem+Dynamical.swift
//  Role: a Simulation document's Dynamical switch reaching the Diffraction room's simulated spots (#911, plan row MA8): the beams
//        of its stored exit waves at the shown thickness, in place of the kinematical intensities. One call for the pattern, its
//        spoken words and the Simulation section, so the three can never disagree.
//

import Foundation
import TEMCore
import DiffractoCore

extension OpenItem {
    /// The beams the Diffraction room draws: a Simulation document's with Dynamical on and its waves current; nil otherwise (the
    /// kinematical pattern, every measured file).
    package var dynamicalBeams: DynamicalBeams? {
        guard DemoDocuments.isSimulation(url), dynamicalOffAxis == nil else { return nil }
        return multislice.dynamicalBeams(crystal: diffraction.simulatedPhase, zoneAxis: diffraction.simulation.zoneAxis)
    }

    /// What a change of runs the Dynamical multislice again (the HRTEM section's key, and the switch): the specimen is
    /// `SimulationModel.sourceIdentity`, so a new atom model or beam axis is a new run (#953).
    package var dynamicalRunKey: DynamicalRunKey {
        let model = multislice, crystal = diffraction.simulatedPhase, zoneAxis = diffraction.simulation.zoneAxis
        return DynamicalRunKey(on: model.isDynamical, source: model.sourceIdentity(crystal: crystal), zoneAxis: model.sourceZoneAxis(zoneAxis),
                               thicknessNM: model.thicknessNM, beamKV: diffraction.typedBeamKV, apertureMrad: model.optics.apertureMrad,
                               strain: model.maximumStrain(crystal: crystal, zoneAxis: zoneAxis), thermal: model.thermal?.sigmas)
    }

    /// Why Dynamical draws the kinematical spots: the overlay's beam is tilted off the zone axis (the Tilt tool, Index), while the
    /// multislice's beams are those of the exact axis. Nil on the axis, with Dynamical off, and for a measured file.
    package var dynamicalOffAxis: String? {
        guard DemoDocuments.isSimulation(url), multislice.isDynamical, let phase = diffraction.simulatedPhase,
              let drawn = diffraction.drawnOrientation else { return nil }
        let axis = diffraction.simulation.zoneAxis
        guard !ZoneAxisOverlay.isAlong(drawn, zoneAxis: axis, cell: phase.structure.cell) else { return nil }
        return "The pattern is tilted off \(ZoneAxisText.text(axis)): the dynamical beams are those of the exact axis, so the kinematical spots are drawn."
    }

    /// Index's spot rows (`DiffractionAnalysis.indexSpotRows`), each with its hkl's dynamical intensity where Dynamical is on (#911).
    package var indexSpotRows: [PatternIndexing.SpotRow] {
        let beams = dynamicalBeams
        return diffraction.indexSpotRows.map { $0.withDynamical(beams) }
    }

    /// A Simulation document's Spots table (`DiffractionAnalysis.simulatedSpotRows`), each row with its hkl's dynamical intensity
    /// where Dynamical is on (#911).
    package func simulatedSpotRows(image: CalibratedImage) -> [PatternIndexing.SpotRow] {
        let beams = dynamicalBeams
        return diffraction.simulatedSpotRows(image: image).map { $0.withDynamical(beams) }
    }

    /// The simulated spots the room draws for this item (`DiffractionAnalysis.simulatedSpots`), dynamical where it is.
    package func simulatedSpots(image: CalibratedImage) -> DiffractionAnalysis.SimulatedSpots? {
        diffraction.simulatedSpots(image: image, dynamical: dynamicalBeams)
    }
}

/// What a change of runs a Simulation document's Dynamical multislice again (`OpenItem.dynamicalRunKey`).
package nonisolated struct DynamicalRunKey: Equatable, Sendable {
    let on: Bool
    let source: String?
    let zoneAxis: SIMD3<Int>
    let thicknessNM: Double
    let beamKV: Double?
    let apertureMrad: Double?
    let strain: Double
    let thermal: [Int: Double]?
}
