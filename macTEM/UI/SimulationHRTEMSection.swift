//
//  SimulationHRTEMSection.swift
//  Role: the HRTEM section of the Image room for a Simulation document's image (#894, plan row MA2): Defocus and Thickness, live,
//        with no Simulate button (a static crystal needs one orthogonal unit, computed once), Scherzer, and the method line that
//        names every setting. The section's task runs the multislice when the specimen, the beam energy or the aperture changes, and
//        each move puts a new image into the item. Presentation only; the state is `SimulationModel` and every number SimulatoKit's.
//        MA3 (#895) adds the objective aperture, the field of view, the Potential readout and the Table… sheet, and puts the
//        Microscope section and the transfer function strip under it. MA4 (#896) adds the Thermal Vibrations section under it,
//        MA6 (#898) the Beside Measured section.
//

import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationHRTEMSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    @State private var showsTable = false

    var body: some View {
        if let simulation = appState.simulationDocument(ofHRTEM: item) {
            content(simulation)
        } else {
            InspectorSection("HRTEM") {
                InspectorWarning("Its Simulation document is closed: this image no longer changes.")
            }
        }
    }

    @ViewBuilder
    private func content(_ simulation: OpenItem) -> some View {
        let model = simulation.multislice
        let analysis = simulation.diffraction
        let crystal = analysis.simulatedPhase
        let zoneAxis = analysis.simulation.zoneAxis
        let waves = model.exitWaves
        InspectorSection("HRTEM") {
            InspectorRow("Defocus") {
                OptionalNumericField(title: "Defocus", value: model.effectiveDefocusNM, format: defocusFormat, unit: "nm") {
                    model.setDefocus(nm: $0)
                    appState.refreshHRTEMImage(of: simulation)
                }
                .help("Positive is underfocus (abTEM's sign); Scherzer is \(scherzerText(model))")
                .accessibilityIdentifier("simulation.hrtem.defocusField")
                Button("Scherzer") { model.useScherzerDefocus(); appState.refreshHRTEMImage(of: simulation) }
                    .help("Sets the defocus to Scherzer defocus, √(3/2 Cs λ): \(scherzerText(model))")
                    .accessibilityIdentifier("simulation.hrtem.scherzer")
            }
            Slider(value: Binding(get: { model.effectiveDefocusNM },
                                  set: { model.setDefocus(nm: $0); appState.refreshHRTEMImage(of: simulation) }),
                   in: Self.defocusRange, step: 0.5) {
                Text("Defocus")
            }
            .labelsHidden()
            .accessibilityValue("\(UnitDisplay.number(model.effectiveDefocusNM, digits: 4)) nanometres")
            .accessibilityIdentifier("simulation.hrtem.defocus")
            // Said beside the field, not only on hover: Williams and Carter write underfocus negative (#931's review).
            Text("Positive is underfocus.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let waves, waves.waves.count > 1, let index = model.shownThicknessIndex {
                InspectorRow("Thickness") {
                    Text("\(UnitDisplay.number(waves.thicknessNM(at: index), digits: 3)) nm")
                        .monospacedDigit()
                        .accessibilityIdentifier("simulation.hrtem.thicknessValue")
                }
                Slider(value: Binding(get: { Double(index) },
                                      set: { model.setThicknessIndex(Int($0.rounded())); appState.refreshHRTEMImage(of: simulation) }),
                       in: 0 ... Double(waves.waves.count - 1), step: 1) {
                    Text("Thickness")
                }
                .labelsHidden()
                .help("Steps through the exit waves stored at whole periods of the specimen")
                .accessibilityValue("\(UnitDisplay.number(waves.thicknessNM(at: index), digits: 3)) nanometres, "
                                    + "\(index + 1) of \(waves.waves.count) stored thicknesses")
                .accessibilityIdentifier("simulation.hrtem.thickness")
            }
            InspectorRow("Aperture") {
                Toggle("Objective aperture", isOn: Binding(get: { model.optics.apertureMrad != nil },
                                                           set: { on in change(simulation) { $0.apertureMrad = on ? Self.defaultApertureMrad : nil } }))
                    .help("An objective aperture cuts the transfer at its semiangle; a new aperture computes the exit waves again")
                    .accessibilityIdentifier("simulation.hrtem.aperture")
            }
            if let aperture = model.optics.apertureMrad {
                InspectorRow("Semiangle") {
                    OptionalNumericField(title: "Aperture semiangle", value: aperture, format: defocusFormat, unit: "mrad") { mrad in
                        change(simulation) { $0.apertureMrad = mrad }
                    }
                    .accessibilityIdentifier("simulation.hrtem.apertureSemiangle")
                }
            }
            InspectorRow("Field of view") {
                OptionalNumericField(title: "Field of view", value: model.optics.fieldOfViewNM, format: defocusFormat, unit: "nm") { nm in
                    change(simulation) { $0.fieldOfViewNM = nm }
                }
                .help("The image's width and height, up to \(UnitDisplay.number(SimulationModel.largestFieldOfViewNM, digits: 3)) nm: whole units of the specimen are tiled to cover it")
                .accessibilityIdentifier("simulation.hrtem.fieldOfView")
            }
            InspectorRow("Potential") {
                Text(HRTEMImage.potentialName).foregroundStyle(.secondary)
                    .accessibilityIdentifier("simulation.hrtem.potential")
            }
            InspectorActionRow {
                Button("Defocus and Thickness Table…") { showsTable = true }
                    .disabled(waves == nil)
                    .help("Images of the specimen at five defocus values and five thicknesses; a click picks one")
                    .accessibilityIdentifier("simulation.hrtem.table")
            }
            if model.isComputing {
                InspectorNote("Computing the exit waves…")
            } else if let failure = model.computeFailure {
                InspectorWarning("No exit waves: \(failure)")
            } else if let failure = model.imageFailure {
                InspectorWarning("No image: \(failure)")
            } else if case .failure(let refusal) = model.specimen(crystal: crystal, zoneAxis: zoneAxis) {
                InspectorWarning(refusal.sentence)
            } else if let waves, let index = model.shownThicknessIndex {
                InspectorNote(HRTEMImage.methodLine(waves, thicknessIndex: index,
                                                    defocusNM: model.effectiveDefocusNM, optics: model.optics))
                    .accessibilityIdentifier("simulation.hrtem.method")
            }
        }
        .sheet(isPresented: $showsTable) {
            SimulationHRTEMTableSheet(model: model) { appState.refreshHRTEMImage(of: simulation) }
        }
        .task(id: RunKey(crystal: crystal?.identity, zoneAxis: zoneAxis, thicknessNM: model.thicknessNM,
                         beamKV: analysis.typedBeamKV, apertureMrad: model.optics.apertureMrad,
                         strain: crystal.map { model.maximumStrain(crystal: $0, zoneAxis: zoneAxis) }, thermal: model.thermal != nil)) {
            await appState.computeHRTEMImage(of: simulation)
        }
        SimulationThermalSection(simulation: simulation)
        SimulationBesideSection(simulation: simulation)
        SimulationMicroscopeSection(model: model, analysis: analysis) { appState.refreshHRTEMImage(of: simulation) }
        switch Result(catching: { try HRTEMTransferCurve.of(model.optics, defocusNM: model.effectiveDefocusNM) }) {
        case .success(let curve):
            let reach = curve.frequencies.last ?? 0
            SimulationTransferSection(curve: curve, spacings: analysis.strongestSpacings().filter { 10 / $0.d <= reach })
        case .failure(let error):
            InspectorSection("Transfer Function") { InspectorWarning("No transfer function: \(ErrorDetail.text(error))") }
        }
    }

    /// Changes the optics through the model's one validated path and redraws the image; an aperture change also re-runs the
    /// multislice through the task.
    private func change(_ simulation: OpenItem, _ edit: (inout HRTEMOptics) -> Void) {
        if simulation.multislice.changeOptics(edit) { appState.refreshHRTEMImage(of: simulation) }
    }

    /// What a change of re-runs the multislice; every other setting only re-images the stored waves.
    private struct RunKey: Equatable {
        let crystal: String?
        let zoneAxis: SIMD3<Int>
        let thicknessNM: Double
        let beamKV: Double?
        let apertureMrad: Double?
        let strain: Double?
        /// Frozen phonons off again: the static lattice runs (on, Simulate runs).
        let thermal: Bool
    }

    static let defocusRange = -100.0 ... 200.0
    /// The semiangle an objective aperture starts at when it is turned on: abTEM's examples use 20 mrad.
    static let defaultApertureMrad = 20.0

    private func scherzerText(_ model: SimulationModel) -> String {
        (try? model.optics.scherzerDefocusNM()).map { "\(UnitDisplay.number($0, digits: 4)) nm" } ?? "not defined for these optics"
    }
}

private let defocusFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
