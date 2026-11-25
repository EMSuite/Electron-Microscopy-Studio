//
//  DiffractionPowder.swift
//  Role: the powder pattern of the Diffraction room's crystal, and of one more phase to compare with (plan row R11, #810): rings
//        against q at the pattern's beam energy, or an X-ray pattern against 2θ at a chosen line. The settings are stored; the
//        table (`PowderTable.make`: the kit's peaks, overlaps and diagnostic peaks) is derived each time and cached by its inputs.
//        Until the Simulation document (R6, #788) holds several phases, the second phase is a standard of the room or the crystal
//        of another open pattern.
//

import Foundation
import Observation
import ImagoCore
import DiffractoCore
import DiffractoScattering
import TEMCore

@Observable
package final class DiffractionPowder {
    /// Rings or X-rays, the line, the range and the marks.
    package private(set) var settings = PowderSettings()
    /// The second phase's name, nil for none.
    package private(set) var compareWith: String?

    @ObservationIgnored private var cache: (key: Key, table: PowderTable)?
    private struct Key: Equatable {
        var names: [String]
        var structures: [CrystalStructure]
        var settings: PowderSettings

        // Spelled out, so every input is read where the cache compares it.
        static func == (a: Key, b: Key) -> Bool {
            a.names == b.names && a.structures == b.structures && a.settings == b.settings
        }
    }

    package init() {}

    package func setKind(_ kind: PowderKind) { settings.kind = kind }

    package func setRadiation(_ radiation: XRayRadiation) { settings.radiation = radiation }

    /// The 2θ range shown and computed: from 1° to 179°, the lower end first.
    package func setTwoTheta(from: Double, to: Double) {
        guard from.isFinite, to.isFinite, from != to else { return }
        let lo = min(from, to), hi = max(from, to)
        guard lo >= 1, hi <= 179 else { return }
        settings.twoThetaFrom = lo; settings.twoThetaTo = hi
    }

    /// The rings' reach, 0.2 to 4 Å⁻¹ (the room's k_max bounds).
    package func setReach(_ reach: Double) {
        guard reach.isFinite else { return }
        settings.ringReach = min(max(reach, 0.2), 4)
    }

    package func setMarkOverlaps(_ on: Bool) { settings.markOverlaps = on }

    package func setCompareWith(_ name: String?) { compareWith = name }

    /// The shown phases: the room's crystal, then the second one when it is another phase.
    package func phases(crystal: DiffractionCrystal, others: [PowderPhase]) -> [PowderPhase] {
        var phases = [PowderPhase(name: crystal.name, structure: crystal.structure)]
        if let name = compareWith, name != crystal.name, let other = others.first(where: { $0.name == name }) {
            phases.append(other)
        }
        return phases
    }

    /// The table of the shown phases; rings at the pattern's beam energy when it has one, else 200 kV.
    package func table(phases: [PowderPhase], volts: Double?) -> PowderTable {
        var s = settings
        if let volts, volts.isFinite, volts > 0 { s.volts = volts }
        let key = Key(names: phases.map(\.name), structures: phases.map(\.structure), settings: s)
        if let cache, cache.key == key { return cache.table }
        let table = PowderTable.make(phases: phases, settings: s)
        cache = (key, table)
        return table
    }
}
