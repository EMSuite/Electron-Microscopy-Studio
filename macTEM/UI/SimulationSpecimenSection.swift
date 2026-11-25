//
//  SimulationSpecimenSection.swift
//  Role: a Simulation document's Specimen section (#893, MA1; the design's inspector order: Phases, …, Simulation, then Specimen):
//        the thickness, and what the slab builder made of the shown phase along the typed zone axis (the box, the atoms, the strain),
//        or why it made nothing ("Add a phase to simulate.", a partly occupied site, a strain over the limit with Build with Strain).
//        Source picks the phase or an atom model built elsewhere (#914, MA14: Atom Model… or a file dropped on the section; CIF, XYZ,
//        POSCAR), read once off the main actor and kept by the document; the beam then runs along the model's c, a or b and its
//        thickness is a readout. Presentation only; the state is `SimulationModel` and every number SimulatoKit's.
//

import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession
import UniformTypeIdentifiers

struct SimulationSpecimenSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    /// The Atom Model… panel is up.
    @State private var choosingModel = false
    /// Why the last model chosen was not opened, in the design's words.
    @State private var modelRefusal: String?
    @State private var readingModel = false

    private enum Source: Hashable { case phase, model }

    var body: some View {
        let analysis = item.diffraction
        let model = item.multislice
        let crystal = analysis.simulatedPhase
        let zoneAxis = analysis.simulation.zoneAxis
        let specimen = model.specimen(crystal: crystal, zoneAxis: zoneAxis)
        InspectorSection("Specimen") {
            InspectorRow("Source") {
                Picker("Source", selection: Binding(get: { model.atomModel == nil ? Source.phase : .model }, set: { source in
                    if source == .phase { model.useAtomModel(nil) } else { choosingModel = true }
                })) {
                    Text("Phase").tag(Source.phase)
                    Text(model.atomModel?.name ?? "Atom Model…").tag(Source.model)
                }
                .labelsHidden()
                .help("The shown phase along the zone axis, or an atom model built elsewhere (CIF, XYZ or POSCAR)")
                .accessibilityIdentifier("simulation.specimen.source")
            }
            if let atomModel = model.atomModel {
                InspectorRow("Beam along") {
                    SegmentedPicker(label: "Beam along", items: AtomModelSpecimen.BeamAxis.allCases.map { ($0, .title($0.rawValue)) },
                                    selection: Binding(get: { model.beamAxis }, set: { model.setBeamAxis($0) }))
                    .help("The model's cell axis the beam runs along")
                    .accessibilityIdentifier("simulation.specimen.beamAxis")
                }
                if case .success(let built) = specimen {
                    InspectorRow("Thickness") {
                        Text("\(UnitDisplay.number(built.box.z / 10, digits: 4)) nm")
                            .help("The model's own thickness along the beam")
                            .accessibilityIdentifier("simulation.specimen.modelThickness")
                    }
                }
                InspectorActionRow {
                    Button("Open Another Model…") { choosingModel = true }
                        .help("Replaces the model with another file; the document keeps the model as it was read")
                        .accessibilityIdentifier("simulation.specimen.openModel")
                }
                if case .success(let built) = specimen {
                    ForEach(atomModel.notes(built), id: \.self) { InspectorNote($0) }
                }
            } else {
                InspectorRow("Thickness") {
                    OptionalNumericField(title: "Thickness", value: model.thicknessNM, format: thicknessFormat, unit: "nm") { model.setThickness(nm: $0) }
                        .help("The specimen's thickness along the beam; it is built from whole periods of the crystal, the nearest number to this "
                              + "(0.5 to 200 nm)")
                        .accessibilityIdentifier("simulation.specimen.thickness")
                }
            }
            if readingModel {
                InspectorNote("Reading the model…")
            }
            if let modelRefusal {
                InspectorWarning(modelRefusal)
            }
            switch specimen {
            case .success(let built):
                InspectorRow("Box") {
                    Text(SimulationSpecimen.boxText(built.box))
                        .accessibilityIdentifier("simulation.specimen.box")
                }
                if let atomModel = model.atomModel {
                    InspectorNote(atomModel.summary(built, beam: model.beamAxis))
                } else {
                    InspectorNote(SimulationSpecimen.summary(built, phase: analysis.crystal.name, zoneAxis: zoneAxis))
                }
                InspectorActionRow {
                    Button("Show HRTEM Image") { appState.showHRTEMImage(of: item) }
                        .help("Opens the specimen's HRTEM image in the Image room, with live Defocus and Thickness")
                        .accessibilityIdentifier("simulation.specimen.hrtem")
                    Button("Show STEM Image") { appState.showSTEMImage(of: item) }
                        .help("Opens the specimen's STEM image in the Image room; Simulate there scans the probe")
                        .accessibilityIdentifier("simulation.specimen.stem")
                }
            case .failure(.building):
                InspectorNote(SimulationSpecimen.Refusal.building.sentence)
            case .failure(let refusal):
                InspectorWarning(refusal.sentence)
                if let strain = refusal.acceptableStrain, let crystal {
                    Button("Build with Strain") { model.acceptStrain(strain, crystal: crystal, zoneAxis: zoneAxis) }
                        .help("Builds the specimen with the strain named above")
                        .accessibilityIdentifier("simulation.specimen.useAnyway")
                }
            }
        }
        .fileImporter(isPresented: $choosingModel, allowedContentTypes: Self.modelTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { open(url, into: model) }
            case .failure(let error): modelRefusal = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            open(url, into: model)
            return true
        }
    }

    /// The types the Atom Model… panel offers: CIF, XYZ and POSCAR by extension, and any file, so a POSCAR with no extension opens and any other format is refused by name.
    private static let modelTypes: [UTType] = AtomModelSpecimen.extensions.compactMap { UTType(filenameExtension: $0) } + [.data]

    /// Reads the model at `url` off the main actor and simulates it, or says why not.
    private func open(_ url: URL, into model: SimulationModel) {
        readingModel = true
        modelRefusal = nil
        Task {
            let read: Result<AtomModelSpecimen, AtomModelSpecimen.Refusal> = await offMainActor {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    return .success(try AtomModelSpecimen(contentsOf: url))
                } catch let refusal as AtomModelSpecimen.Refusal {
                    return .failure(refusal)
                } catch {
                    return .failure(.unreadable(file: url.lastPathComponent, reason: error.localizedDescription))
                }
            }
            readingModel = false
            switch read {
            case .success(let atomModel): model.useAtomModel(atomModel)
            case .failure(let refusal): modelRefusal = refusal.sentence
            }
        }
    }
}

private let thicknessFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
