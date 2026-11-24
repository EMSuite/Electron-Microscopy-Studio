//
//  SimulationModel.swift
//  Role: a Simulation document's multislice state (2.5): the specimen's thickness and the strain the person accepted (#893, MA1). The
//        phase and the zone axis stay the Diffraction room's (`DiffractionAnalysis.crystal`, `simulation.zoneAxis`), so the pattern and
//        the specimen are always built from the same crystal and axis. The slab is built by `SimulationSpecimen` (SimulatoKit's
//        slab builder) and cached on the crystal's identity, the axis, the thickness and the strain limit. No pixels.
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
