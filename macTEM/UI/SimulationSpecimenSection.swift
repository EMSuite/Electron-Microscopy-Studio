//
//  SimulationSpecimenSection.swift
//  Role: a Simulation document's Specimen section (#893, MA1; the design's inspector order: Phases, …, Simulation, then Specimen):
//        the thickness, and what the slab builder made of the shown phase along the typed zone axis (the box, the atoms, the strain),
//        or why it made nothing ("Add a phase to simulate.", a partly occupied site, a strain over the limit with Build with Strain).
//        Presentation only; the state is `SimulationModel` and every number SimulatoKit's.
//

import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationSpecimenSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        let analysis = item.diffraction
        let model = item.multislice
        let crystal = analysis.simulatedPhase
        let zoneAxis = analysis.simulation.zoneAxis
        let specimen = model.specimen(crystal: crystal, zoneAxis: zoneAxis)
        InspectorSection("Specimen") {
            InspectorRow("Thickness") {
                OptionalNumericField(title: "Thickness", value: model.thicknessNM, format: thicknessFormat, unit: "nm") { model.setThickness(nm: $0) }
                    .help("The specimen's thickness along the beam; it is built from whole periods of the crystal, the nearest number to this "
                          + "(0.5 to 200 nm)")
                    .accessibilityIdentifier("simulation.specimen.thickness")
            }
            switch specimen {
            case .success(let built):
                InspectorRow("Box") {
                    Text(SimulationSpecimen.boxText(built.box))
                        .accessibilityIdentifier("simulation.specimen.box")
                }
                InspectorNote(SimulationSpecimen.summary(built, phase: analysis.crystal.name, zoneAxis: zoneAxis))
                InspectorActionRow {
                    Button("Show HRTEM Image") { appState.showHRTEMImage(of: item) }
                        .help("Opens the specimen's HRTEM image in the Image room, with live Defocus and Thickness")
                        .accessibilityIdentifier("simulation.specimen.hrtem")
                    Button("Show STEM Image") { appState.showSTEMImage(of: item) }
                        .help("Opens the specimen's STEM image in the Image room; Simulate there scans the probe")
                        .accessibilityIdentifier("simulation.specimen.stem")
                }
            case .failure(let refusal):
                InspectorWarning(refusal.sentence)
                if let strain = refusal.acceptableStrain, let crystal {
                    Button("Build with Strain") { model.acceptStrain(strain, crystal: crystal, zoneAxis: zoneAxis) }
                        .help("Builds the specimen with the strain named above")
                        .accessibilityIdentifier("simulation.specimen.useAnyway")
                }
            }
        }
    }
}

private let thicknessFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
