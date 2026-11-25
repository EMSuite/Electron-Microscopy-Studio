//
//  SimulationThermalSection.swift
//  Role: the Thermal Vibrations section of the Image room for a Simulation document's HRTEM image (#896, plan row MA4): frozen
//        phonons on or off, σ per element, the number of configurations, the plan line before a run (grid, slices, configurations,
//        memory, and the time once this Mac's rate on the grid is measured), Simulate, Continue and Stop with the run's progress, and
//        the convergence readout. Off, the image is the static lattice and stays live; on, it waits for Simulate (⌘R). Presentation
//        only; the state is `SimulationModel` and every number SimulatoKit's.
//

import DiffractoCore
import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationThermalSection: View {
    let simulation: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        let model = simulation.multislice
        let analysis = simulation.diffraction
        let crystal = analysis.simulatedPhase
        let zoneAxis = analysis.simulation.zoneAxis
        InspectorSection("Thermal Vibrations") {
            InspectorRow("Frozen phonons") {
                Toggle("Frozen phonons", isOn: Binding(get: { model.thermal != nil },
                                                       set: { model.useThermalVibrations($0, crystal: crystal) }))
                    .disabled(model.isSimulating || crystal == nil)
                    .help("Averages images of the atoms displaced at random (Einstein model); off is the static lattice, whose image is live")
                    .accessibilityIdentifier("simulation.thermal.frozenPhonons")
            }
            if let thermal = model.thermal {
                ForEach(thermal.sigmas.keys.sorted(), id: \.self) { z in
                    let symbol = Element.symbol(forAtomicNumber: z) ?? "Z \(z)"
                    InspectorRow("σ \(symbol)") {
                        OptionalNumericField(title: "σ \(symbol)", value: thermal.sigmas[z], format: sigmaFormat, unit: "Å") { sigma in
                            var new = thermal
                            new.sigmas[z] = sigma
                            model.setThermal(new)
                        }
                        .disabled(model.isSimulating)
                        .help("The root-mean-square displacement of \(symbol) along each axis (B = 8π²σ²)")
                        .accessibilityIdentifier("simulation.thermal.sigma.\(z)")
                    }
                }
                InspectorRow("Configurations") {
                    OptionalNumericField(title: "Configurations", value: thermal.configurations, format: .number) { count in
                        var new = thermal
                        new.configurations = count
                        model.setThermal(new)
                    }
                    .disabled(model.isSimulating)
                    .help("How many displaced lattices are averaged, \(HRTEMThermal.configurationRange.lowerBound) to "
                          + "\(HRTEMThermal.configurationRange.upperBound); asking for more after a run continues it")
                    .accessibilityIdentifier("simulation.thermal.configurations")
                }
                switch model.thermalPlanLine(crystal: crystal, zoneAxis: zoneAxis) {
                case .success(let line):
                    InspectorNote(line).accessibilityIdentifier("simulation.thermal.plan")
                case .failure(let error):
                    InspectorWarning(ErrorDetail.text(error))
                case nil:
                    EmptyView()
                }
                if let progress = model.thermalProgress {
                    ProgressView(value: BusyOperation.simulationFraction(progress)) {
                        Text(BusyOperation.simulating(progress))
                    }
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("simulation.thermal.progress")
                }
                InspectorActionRow {
                    if model.isSimulating {
                        Button("Stop") { model.stop() }
                            .help("Stops after the slice running; the configurations done stay averaged")
                            .accessibilityIdentifier("simulation.thermal.stop")
                    } else {
                        let resumes = model.canContinue(crystal: crystal, zoneAxis: zoneAxis)
                        Button(resumes ? "Continue" : "Simulate") { Task { await appState.simulateHRTEM(of: simulation) } }
                            .disabled(!canRun(model, crystal: crystal, zoneAxis: zoneAxis))
                            .help(resumes ? "Runs the configurations not yet averaged" : "Runs the configurations and averages their images")
                            .accessibilityIdentifier("simulation.thermal.simulate")
                    }
                }
                if let convergence = model.convergence, let waves = model.exitWaves, waves.thermal != nil {
                    InspectorNote("The last configuration changed the image by \(UnitDisplay.number(convergence.change * 100, digits: 2)) % "
                                  + "(\(waves.configurations.count) averaged; read at \(UnitDisplay.number(convergence.defocusNM, digits: 4)) nm "
                                  + "defocus, \(UnitDisplay.number(waves.thicknessNM(at: convergence.thicknessIndex), digits: 3)) nm thick).")
                        .accessibilityIdentifier("simulation.thermal.convergence")
                } else if !model.exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis), !model.isSimulating {
                    InspectorNote("Simulate to average the configurations at these settings.")
                }
            }
        }
        .task(id: RateKey(crystal: crystal?.identity, zoneAxis: zoneAxis, thicknessNM: model.thicknessNM, volts: model.optics.volts,
                          apertureMrad: model.optics.apertureMrad, on: model.thermal != nil)) {
            await model.measureRate(crystal: crystal, zoneAxis: zoneAxis)
        }
    }

    private func canRun(_ model: SimulationModel, crystal: DiffractionCrystal?, zoneAxis: SIMD3<Int>) -> Bool {
        model.simulateBlocker(crystal: crystal, zoneAxis: zoneAxis) == nil
    }

    /// What changes the grid the plan line's time is measured on.
    // periphery:ignore - its fields are read by the synthesized == and hash, which Periphery does not see
    private struct RateKey: Equatable {
        let crystal: String?
        let zoneAxis: SIMD3<Int>
        let thicknessNM: Double
        let volts: Double
        let apertureMrad: Double?
        let on: Bool
    }
}

private let sigmaFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
