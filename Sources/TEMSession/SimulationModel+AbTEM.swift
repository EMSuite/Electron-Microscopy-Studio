//
//  SimulationModel+AbTEM.swift
//  Role: the HRTEM image a Simulation document shows, as an abTEM script (#915, plan row MA11): the run the stored exit waves were
//        computed for (the static unit or the frozen-phonon supercell, the configurations done), at the defocus and thickness the
//        image is at. The text is `AbTEMScript`'s.
//

import Foundation
import TEMCore

extension SimulationModel {
    /// The shown image's run as an abTEM script: its file name and text; nil before the exit waves of this specimen and optics are
    /// stored (Export abTEM Script… is off then).
    package func abTEMScript(crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>, appVersion: String) -> (name: String, text: String)? {
        guard let waves = exitWaves, let index = shownThicknessIndex, exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) else {
            return nil
        }
        let specimen = waves.thermal == nil ? specimen(crystal: crystal, zoneAxis: zoneAxis)
            : thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis)
        guard case .success(let built) = specimen else { return nil }
        // The image is the mean of the configurations done, so the script runs as many.
        let thermal = waves.thermal.map { HRTEMThermal(sigmas: $0.sigmas, configurations: waves.configurations.count) }
        let run = AbTEMScript.Run(built: built, optics: optics, defocusNM: effectiveDefocusNM, planePeriods: waves.planePeriods,
                                  planeIndex: index, thermal: thermal, specimen: waves.specimen,
                                  methodLine: HRTEMImage.methodLine(waves, thicknessIndex: index, defocusNM: effectiveDefocusNM, optics: optics),
                                  writtenBy: AbTEMScript.writtenBy(appVersion: appVersion))
        guard let text = try? AbTEMScript.text(run) else { return nil }
        return (AbTEMScript.fileName(run), text)
    }
}
