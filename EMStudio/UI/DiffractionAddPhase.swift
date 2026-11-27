//
//  DiffractionAddPhase.swift
//  Role: the Diffraction room's Add Phase sheet, held by the room itself rather than by the Phases section (#788), so File > New
//        Simulation can open its document with the sheet in front whether or not the inspector is shown; and a Simulation document's
//        empty state (#907): until a library phase is shown, the pattern is black with one sentence and the one button Add Phase…,
//        which is where Cancel in the sheet leaves it. EMSuiteUI's sheet (search the Materials Project, or Open CIF…); `isAddingPhase`
//        on the room's view state says whether it is up.
//
//  DEPARTURE from control-placement §1 (the centre holds no buttons): the empty state's one button is the Simulation document's
//  behaviour table (suite docs/brainstorm/2026-11-23-ems.md, "Cancel leaves an empty state with the one button, Add Phase…"); the
//  same action stays in the Phases section.
//
//  The empty state is the screen's only: the owner still simulates the calibration standard's spots without a phase (the door's
//  tools and their tests read them), and the Spots table lists none while the empty state is up.
//

import ShellPhaseLibrary
import ShellPhaseViews
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession

/// When a Simulation document shows its empty state, and what it says.
@MainActor
enum SimulationEmptyState {
    static let sentence = "No phase yet. Add a phase to simulate its pattern."
    /// The Crystal and Powder Pattern panes while no phase is shown: they draw the phase, never the calibration standard the room
    /// falls back to (Au), which a Simulation document has no use for.
    static let paneSentence = "No phase shown. Show a phase in the Phases section, or add one, to see it here."

    /// A Simulation document with no library phase shown (`DiffractionAnalysis.simulatedPhase`); never a measured pattern.
    static func isShown(for item: OpenItem) -> Bool {
        DemoDocuments.isSimulation(item.url) && item.diffraction.simulatedPhase == nil
    }

    /// The Spots table's rows: none while the empty state is up, else the simulated spots.
    static func spotRows(of item: OpenItem, image: CalibratedImage) -> [PatternIndexing.SpotRow] {
        isShown(for: item) ? [] : item.simulatedSpotRows(image: image)
    }

    /// Add Phase…, from the Phases section or the empty state: the sheet comes to the front.
    static func addPhase(_ view: DiffractionViewState) { view.isAddingPhase = true }

    /// The sheet went without a phase (Cancel, Esc): the document keeps its empty state.
    static func cancel(_ view: DiffractionViewState) { view.isAddingPhase = false }
}

/// The empty pattern of a Simulation document: one sentence and the one button. Drawn on the pattern's black in the dark scheme,
/// so it reads the same in a light window.
struct SimulationEmptyStateView: View {
    let view: DiffractionViewState

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Text(SimulationEmptyState.sentence)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Add Phase…") { SimulationEmptyState.addPhase(view) }
                    .controlSize(.large)
                    .help("Find a phase on the Materials Project, or open a CIF: its pattern is simulated here")
                    .accessibilityIdentifier("diffraction.empty.addPhase")
            }
            .padding(24)
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulation, no phase")
    }
}

/// The Add Phase sheet and its Open CIF… file dialog, on the room: up while `isAddingPhase` is. A phase shown by any other way (the
/// door's add_phase, the Phases section's checkbox) takes the sheet down.
struct DiffractionAddPhaseSheet: ViewModifier {
    let item: OpenItem
    @State private var importing = false
    @State private var addModel = AddPhaseModel(library: PhaseServices.library, client: PhaseServices.client,
                                                keyStore: PhaseServices.keyStore)

    func body(content: Content) -> some View {
        let analysis = item.diffraction
        let view = item.diffractionView
        content
            .sheet(isPresented: Binding(get: { view.isAddingPhase },
                                        set: { if !$0 { SimulationEmptyState.cancel(view) } })) {
                AddPhaseSheet(model: addModel, onOpenCIF: { importing = true }) { phase in
                    DiffractionPhases.set(phase, shown: true, in: analysis)
                }
            }
            .onChange(of: analysis.crystal.phaseID) { _, id in
                if id != nil, view.isAddingPhase { view.isAddingPhase = false }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cif") ?? .plainText, .plainText]) { result in
                switch result {
                case .success(let url):
                    Task {
                        do {
                            let (loaded, bytes) = try await DiffractionCIF.loadWithBytes(url)
                            let phase = try DiffractionPhases.addCIF(loaded, bytes: bytes, fileName: url.lastPathComponent,
                                                                     to: PhaseServices.library)
                            DiffractionPhases.set(phase, shown: true, in: analysis)
                        } catch {
                            analysis.crystalRefused(error.localizedDescription)
                        }
                    }
                case .failure(let error): analysis.crystalRefused(error.localizedDescription)
                }
            }
    }
}
