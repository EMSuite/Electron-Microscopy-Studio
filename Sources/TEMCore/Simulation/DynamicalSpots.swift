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
import TEMBase

/// Each zone-axis beam's intensity at every stored thickness of a Simulation document's exit waves.
package nonisolated struct DynamicalSpots: Sendable, Equatable {
    /// `intensities[t]`: each beam of the zero-order Laue zone at the stored thickness t, by the crystal's hkl, as a fraction of the
    /// incident beam. The direct beam (000) is left out: it is not a spot the overlay draws. The kit lists reflections of the
    /// lattice only (SimulatoKit 0.8.1, #1150), as abTEM's `index_diffraction_spots` with the lattice's centring.
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
        intensities = beams.intensities.map { row in
            var byHKL: [MillerIndex: Double] = [:]
            for (beam, value) in zip(beams.beams, row) where beam.hkl != .zero {
                byHKL[MillerIndex(beam.hkl.x, beam.hkl.y, beam.hkl.z)] = value
            }
            return byHKL
        }
        thicknessesNM = exit.planePeriods.indices.map { exit.thicknessNM(at: $0) }
        specimen = exit.specimen
        volts = exit.volts
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
