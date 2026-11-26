//
//  DynamicalSpots.swift
//  Role: the dynamical intensity of each zone-axis spot of a Simulation document (#911, plan row MA8): SimulatoKit's
//        `BeamIntensities` (abTEM 1.0.10 `index_diffraction_spots`) read in the same exit waves the HRTEM image is made from (one
//        orthogonal unit, whole periods, the exact float64 path), so the spot pattern and the image of one document are one run. The
//        thickness slider picks a stored wave: a dictionary lookup, no compute. Every number is the kit's.
//

import DiffractoCore
import Foundation
import SimulatoCore
import SimulatoMultislice

/// Each zone-axis beam's intensity at every stored thickness of a Simulation document's exit waves.
package nonisolated struct DynamicalSpots: Sendable, Equatable {
    /// `intensities[t]`: each beam of the zero-order Laue zone at the stored thickness t, by the crystal's hkl, as a fraction of the
    /// incident beam. The direct beam (000) is left out: it is not a spot the overlay draws; so is every grid point that is no
    /// reflection of the lattice (`isReflection`, #1150).
    package let intensities: [[MillerIndex: Double]]
    /// The thickness of each stored wave, nm (`HRTEMExitWaves.thicknessNM(at:)`).
    package let thicknessesNM: [Double]
    /// What was simulated, for the method line: "Si [1 1 0]".
    package let specimen: String
    /// The beam energy, V.
    package let volts: Double

    /// The beams of `exit`, the waves of `built`'s slab at whole periods (`HRTEMImage.exitWaves`), by hkl.
    package init(_ exit: HRTEMExitWaves, built: SimulationSpecimen.Built) throws {
        let slab = built.slab
        let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
        let beams = try BeamIntensities(exitWaves: exit.waves, of: slab,
                                        exitPlanes: .afterSlices(exit.planePeriods.map { $0 * perPeriod - 1 }))
        let translations = Self.latticeTranslations(of: slab.unit.structure)
        intensities = beams.intensities.map { row in
            var byHKL: [MillerIndex: Double] = [:]
            for (beam, value) in zip(beams.beams, row)
            where beam.hkl != .zero && Self.isReflection(beam.spatialFrequency, translations: translations) {
                byHKL[MillerIndex(beam.hkl.x, beam.hkl.y, beam.hkl.z)] = value
            }
            return byHKL
        }
        thicknessesNM = exit.planePeriods.indices.map { exit.thicknessNM(at: $0) }
        specimen = exit.specimen
        volts = exit.volts
    }

    // MARK: Lattice centring (#1150; delete at the SimulatoKit release that filters `BeamIntensities` by the lattice, SimulatoKit#145)

    /// The pure translations of `unit` inside its box, Å: every shift that maps each atom onto an atom of the same element (the
    /// lattice centring an orthogonal unit holds, F's three for Si's cubic box). The box's own sides are left out.
    ///
    /// Why: the unit's box is a supercell of the crystal's primitive lattice, so its reciprocal grid has points that are no reflection
    /// of the crystal. A beam there is not a zero-order Laue zone spot: it is where a higher-order Laue zone reflection lands in
    /// projection (Si [0 0 1]: a reflection 1 2̄1 l of the first-order ring at 3.9 Å⁻¹ reads as the fcc-forbidden 1 2̄1 0). abTEM 1.0.10's
    /// `index_diffraction_spots` leaves such points out by the lattice's reflection condition (`centering`); this does the same
    /// from the atoms, so any centring is found, not only the letters.
    package static func latticeTranslations(of unit: AtomicStructure) -> [SIMD3<Double>] {
        let box = unit.box
        let atoms = unit.atoms
        guard let first = atoms.first, atoms.count > 1 else { return [] }
        let grid = 1e4   // fractional positions to 1e-4 of the box side: far below an atomic spacing, far above rounding
        func wrapped(_ f: Double) -> Double { let w = f - f.rounded(.down); return w >= 1 - 0.5 / grid ? 0 : w }
        // The element and its occupancy (to 1e-3) name a site, so an ordered phase's partly occupied sites are no translation of
        // its full ones.
        func key(_ atom: AtomicStructure.Atom, _ p: SIMD3<Double>) -> [Int] {
            [atom.atomicNumber, Int((atom.occupancy * 1000).rounded()), Int((wrapped(p.x / box.x) * grid).rounded()) % Int(grid),
             Int((wrapped(p.y / box.y) * grid).rounded()) % Int(grid), Int((wrapped(p.z / box.z) * grid).rounded()) % Int(grid)]
        }
        let sites = Set(atoms.map { key($0, $0.position) })
        // The candidates map one atom of the rarest element onto another of it.
        let counts = Dictionary(grouping: atoms, by: \.atomicNumber).mapValues(\.count)
        let rarest = counts.min { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key ?? first.atomicNumber
        let anchors = atoms.filter { $0.atomicNumber == rarest }
        let origin = anchors[0].position
        var found: [SIMD3<Double>] = []
        for other in anchors.dropFirst() {
            let shift = other.position - origin
            guard atoms.allSatisfy({ sites.contains(key($0, $0.position + shift)) }) else { continue }
            // Snapped to the key grid, so a CIF's rounded coordinates (0.3333) give g · t whole numbers within `isReflection`'s cut.
            let t = SIMD3((shift.x / box.x * grid).rounded() / grid * box.x, (shift.y / box.y * grid).rounded() / grid * box.y,
                          (shift.z / box.z * grid).rounded() / grid * box.z)
            found.append(t)
        }
        return found
    }

    /// Whether the box frequency `g` (1/Å, across the beam) is a reflection of the lattice: g · t is a whole number for every
    /// translation t of `latticeTranslations` (the beams of the zero-order Laue zone have g_z = 0).
    package static func isReflection(_ g: SIMD2<Double>, translations: [SIMD3<Double>]) -> Bool {
        translations.allSatisfy { t in
            // A point that is no reflection misses a whole number by at least 1/n (n the translation's order, 2 to 6 for the
            // centrings), so 1e-3 tells them apart and absorbs the snapping above.
            let phase = g.x * t.x + g.y * t.y
            return abs(phase - phase.rounded()) <= 1e-3
        }
    }

    /// The beams at the stored thickness `index` (kept in range).
    package func beams(at index: Int) -> DynamicalBeams {
        let i = min(max(index, 0), intensities.count - 1)
        return DynamicalBeams(intensities: intensities[i], thicknessNM: thicknessesNM[i], specimen: specimen, volts: volts)
    }
}

/// The zone-axis beams at one thickness: what the overlay draws in place of the kinematical intensities.
package nonisolated struct DynamicalBeams: Sendable, Equatable {
    package let intensities: [MillerIndex: Double]
    package let thicknessNM: Double
    package let specimen: String
    package let volts: Double

    package init(intensities: [MillerIndex: Double], thicknessNM: Double, specimen: String, volts: Double) {
        self.intensities = intensities
        self.thicknessNM = thicknessNM
        self.specimen = specimen
        self.volts = volts
    }

    /// The faintest beam the overlay draws, as a fraction of the strongest diffracted one: weaker beams are numerical floor, not
    /// spots (abTEM's `index_diffraction_spots` reports every beam inside the cutoff).
    package static let drawnFraction = 1e-4

    /// "Dynamical · Si [1 1 0] · 9.98 nm · 200 kV · Lobato, 1 Å slices · static lattice · exact (float64)": the method line names the
    /// thickness.
    package var methodLine: String {
        ["Dynamical", specimen, "\(UnitDisplay.number(thicknessNM, digits: 3)) nm", "\(UnitDisplay.number(volts / 1000, digits: 4)) kV",
         "Lobato, infinite projection, \(UnitDisplay.number(SimulationSpecimen.sliceThickness, digits: 3)) Å slices", "static lattice",
         "exact (float64)"].joined(separator: " · ")
    }
}
