//
//  DiffractionRoomInspector.swift
//  Role: the Diffraction room's Settings (design section 3): Centre, Calibration, Display, Tools, Phases, Index, Holder, Simulation, a Simulation document's Specimen, Crystal View, Precipitate, Powder, Rings, Export (control placement §2:
//        what I am looking at, then the job; Centre stays above Calibration, which it feeds). Presentation only;
//        the state is `DiffractionAnalysis` and every number DiffractoKit's. Every field commits on Return or blur
//        (`OptionalNumericField`), every control has an accessibility identifier for the journey.
//

import ShellControls
import ShellInspector
import ShellPhaseLibrary
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession
import DiffractoCore
import DiffractoGeometry

struct DiffractionRoomSettings: View {
    let item: OpenItem
    private var image: CalibratedImage { item.session.imageOrBlank }

    var body: some View {
        let analysis = item.diffraction
        let view = item.diffractionView
        // A Simulation document (#907) has no measured pattern: its Microscope section stands where the Centre and Calibration do,
        // and its Orientation section where Index's.
        let isSimulation = DemoDocuments.isSimulation(item.url)
        Group {
            if isSimulation {
                DiffractionMicroscopeSection(analysis: analysis)
            } else {
                DiffractionCentreSection(analysis: analysis, view: view)
                DiffractionCalibrationSection(session: item.session, analysis: analysis, view: view)
            }
            DiffractionDisplaySection(view: view)
            DiffractionToolsSection(view: view)
            DiffractionPhasesSection(item: item, analysis: analysis)
            if isSimulation {
                InspectorSection("Orientation") { DiffractionOrientationRows(analysis: analysis) }
            } else {
                DiffractionIndexSection(analysis: analysis)
            }
            DiffractionHolderSection(item: item)
            DiffractionSimulationSection(item: item)
            if isSimulation { SimulationSpecimenSection(item: item) }
            DiffractionCrystalViewSection(view: view)
            DiffractionPrecipitateSection(item: item)
            DiffractionPowderSection(item: item)
            DiffractionRingsSection(session: item.session, analysis: analysis, view: view)
            DiffractionThicknessSection(item: item)
            DiffractionExportSection(session: item.session, analysis: analysis, isSimulation: isSimulation)
        }
        .onAppear { analysis.bind(image) }
    }
}

private let pixelFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
private let excitationFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...4))
private let qFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))

private struct DiffractionCentreSection: View {
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState

    private static func sourceNote(_ source: DiffractionCentre.Source) -> String {
        switch source {
        case .fileCentre: "The image centre; a ring fit can refine it."
        case .typed: "Typed."
        case .ring: "Taken from a fitted ring."
        }
    }

    var body: some View {
        InspectorSection("Centre") {
            if let centre = analysis.centre {
                InspectorRow("Row") {
                    OptionalNumericField(title: "Centre row", value: centre.row, format: pixelFormat, unit: "px") { analysis.setCentre(row: $0, column: centre.column) }
                }
                InspectorRow("Column") {
                    OptionalNumericField(title: "Centre column", value: centre.column, format: pixelFormat, unit: "px") { analysis.setCentre(row: centre.row, column: $0) }
                }
                InspectorNote(Self.sourceNote(centre.source))
                InspectorActionRow {
                    Button("Use Ring's Centre") { if let id = view.selection { analysis.useCentre(ofRing: id) } }
                        .disabled(!(analysis.rings.first { $0.id == view.selection }?.fit?.fit != nil))
                        .help("Take the selected ring's fitted centre as the pattern's")
                        .accessibilityIdentifier("diffraction.centre.useRing")
                }
            }
        }
    }
}

private struct DiffractionCalibrationSection: View {
    let session: ImageSession
    private var image: CalibratedImage { session.imageOrBlank }
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let calibration = analysis.calibration(for: image)
        let families = analysis.standardFamilies()
        InspectorSection("Calibration") {
            InspectorValueRow("Scale", calibration.map { "\($0.sourceText) · \(Num.fixed($0.deltaQ, 5)) Å⁻¹/px" } ?? "none")
            if let fit = analysis.fitVersusFilePercent(for: image) {
                InspectorNote("The fit's Δq is \(Num.signed(fit, 2)) % from the file's axis.")
            }
            InspectorRow("Standard") {
                Picker("Standard", selection: Binding(get: { analysis.standard.name }, set: { name in if let s = StandardCrystals.named(name) { analysis.setStandard(s) } })) {
                    ForEach(StandardCrystals.all, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize().accessibilityIdentifier("diffraction.standard")
            }
            InspectorRow("Ring") {
                Picker("Family", selection: Binding(get: { analysis.familyIndex }, set: { analysis.familyIndex = $0 })) {
                    ForEach(families.indices, id: \.self) { Text("\(families[$0].name) · \(Num.fixed(families[$0].d, 3)) Å").tag($0) }
                }
                .labelsHidden().fixedSize().accessibilityIdentifier("diffraction.family")
            }
            InspectorActionRow {
                Button("Calibrate on Ring") {
                    PendingEdits.run { if families.indices.contains(analysis.familyIndex) { analysis.fitRing(image: image, inner: view.annulusInner, outer: view.annulusOuter, calibrateOn: families[analysis.familyIndex].family) } }
                }
                .disabled(analysis.isFitting || families.isEmpty)
                .help("Fit the ring in the annulus and take Δq from its radius and the family's listed spacing")
                .accessibilityIdentifier("diffraction.calibrate")
                if analysis.ringCalibrationExists { Button("Clear") { DiffractionUndo.clearCalibration(in: analysis, undoManager: undoManager) }.accessibilityIdentifier("diffraction.calibration.clear") }
            }
            if let ring = calibration?.ring {
                if let l = ring.lengthPixels { InspectorValueRow("L", "\(Num.fixed(l, 0)) px") }
                if let mm = ring.lengthMillimetres { InspectorValueRow("L", "\(Num.fixed(mm, 1)) mm") }
                else if ring.lengthPixels != nil { InspectorNote("L in mm needs the camera's pixel pitch.") }
            }
            if analysis.fileDeltaQ(image) == nil {
                InspectorRow("Δq typed") {
                    OptionalNumericField(title: "Typed delta q", value: analysis.typedDeltaQ, format: qFormat, unit: "Å⁻¹/px") { analysis.typedDeltaQ = $0 }
                }
            }
            InspectorRow("Beam") {
                if let v = image.voltage { Text("\(Num.sig(v / 1000, 4)) kV (file)").foregroundStyle(.secondary) }
                else { OptionalNumericField(title: "Beam energy", value: analysis.typedBeamKV, format: pixelFormat, unit: "kV") { analysis.typedBeamKV = $0 } }
            }
            InspectorRow("Camera") {
                Picker("Camera", selection: Binding(get: { analysis.pitchMM.flatMap { p in CameraPitches.all.first { $0.pitchMM == p }?.name } ?? "" },
                                                    set: { name in analysis.pitchMM = CameraPitches.all.first { $0.name == name }?.pitchMM })) {
                    Text("Pitch not stated").tag("")
                    ForEach(CameraPitches.all, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize().accessibilityIdentifier("diffraction.camera")
            }
            InspectorRow("Pixel pitch") {
                OptionalNumericField(title: "Pixel pitch", value: analysis.pitchMM, format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...4)), unit: "mm") { analysis.pitchMM = $0 }
            }
            if let why = analysis.failure { InspectorWarning(why) }
        }
    }
}

/// A Simulation document's microscope (#907): the beam energy and the camera length, in place of a measured pattern's Centre and
/// Calibration. The voltage is the document's own (the HRTEM image's Microscope section sets the same one); the camera length sets
/// R in mm in the Spots table and its CSV (R = λ L |g|).
private struct DiffractionMicroscopeSection: View {
    let analysis: DiffractionAnalysis

    var body: some View {
        InspectorSection("Microscope") {
            InspectorRow("Voltage") {
                OptionalNumericField(title: "Voltage", value: analysis.typedBeamKV, format: pixelFormat, unit: "kV") { kV in
                    if kV.isFinite, kV > 0 { analysis.typedBeamKV = kV }
                }
                .help("The accelerating voltage: it sets the wavelength of the simulated pattern")
                .accessibilityIdentifier("diffraction.microscope.voltage")
            }
            InspectorRow("Camera length") {
                OptionalNumericField(title: "Camera length", value: analysis.cameraLengthMM, format: pixelFormat, unit: "mm") {
                    analysis.setCameraLength(mm: $0)
                }
                .help("The distance a spot's R in mm is measured at: R = λ L |g| (\(UnitDisplay.number(DiffractionAnalysis.cameraLengthRangeMM.lowerBound, digits: 3)) to \(UnitDisplay.number(DiffractionAnalysis.cameraLengthRangeMM.upperBound, digits: 6)) mm)")
                .accessibilityIdentifier("diffraction.microscope.cameraLength")
            }
        }
    }
}

/// The Phases section (#779), in place of Crystal: the phases of the person's library, each with its marker shape and colour, shown
/// or hidden, and its lattice; Add Phase… brings the room's sheet to the front (`DiffractionAddPhaseSheet`: search the Materials
/// Project, or Open CIF…). In this first slice
/// one phase is shown at a time and is the crystal Index, the readout and the simulated spots use; with none shown the room uses
/// its calibration standard. The library is on this Mac, so a phase added once works offline.
private struct DiffractionPhasesSection: View {
    let item: OpenItem
    let analysis: DiffractionAnalysis
    @State private var findingPhases = false
    private var library: PhaseLibrary { PhaseServices.library }

    var body: some View {
        InspectorSection("Phases") {
            if library.phases.isEmpty {
                InspectorNote("No phases yet. Add Phase… searches the Materials Project or opens a CIF.")
            }
            ForEach(Array(DiffractionPhases.ordered(library.phases).enumerated()), id: \.element.id) { index, phase in
                DiffractionPhaseRow(phase: phase, index: index, analysis: analysis)
            }
            if !library.unreadable.isEmpty {
                InspectorWarning("\(library.unreadable.count) phase record\(library.unreadable.count == 1 ? "" : "s") could not be read: \(library.unreadable.joined(separator: "; "))")
            }
            InspectorActionRow {
                Button("Add Phase…") { SimulationEmptyState.addPhase(item.diffractionView) }
                    .help("Find a phase on the Materials Project, or open a CIF. Until a phase is shown, the room indexes against \(analysis.standard.name), the calibration standard.")
                    .accessibilityIdentifier("diffraction.phases.add")
                Button("Find Phases…") { findingPhases = true }
                    .help("Ranks the room's standards and the open crystals by how many of the measured rings or marked spots each explains")
                    .accessibilityIdentifier("diffraction.findPhases")
            }
            if let why = analysis.crystalFailure { InspectorWarning(why) }
            InspectorRow("k_max") {
                OptionalNumericField(title: "k max", value: analysis.kMax, format: pixelFormat, unit: "Å⁻¹") { analysis.setKMax($0) }
            }
            InspectorRow("Tolerance") {
                OptionalNumericField(title: "Indexing tolerance", value: analysis.tolerancePercent, format: pixelFormat, unit: "% of q") { analysis.setTolerance(percent: $0) }
            }
        }
        .task { await PhaseServices.loadLibrary() }
        .sheet(isPresented: $findingPhases) { DiffractionFindPhasesSheet(item: item) }
    }
}

/// One phase: its marker shape in its colour, whether it is shown, its name and source, and its lattice.
private struct DiffractionPhaseRow: View {
    let phase: Phase
    let index: Int
    let analysis: DiffractionAnalysis

    var body: some View {
        let style = DiffractionPhases.style(at: index)
        let colour = DiffractionPhases.colours[style.colourIndex]
        let shown = analysis.crystal.phaseID == phase.id
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: style.marker.systemImage)
                    .foregroundStyle(colour.color)
                    .accessibilityLabel("\(colour.name) \(style.marker.spoken) marker")
                Toggle(isOn: Binding(get: { shown }, set: { DiffractionPhases.set(phase, shown: $0, in: analysis) })) {
                    Text(phase.name).lineLimit(1)
                }
                .toggleStyle(.checkbox)
                .help(shown ? "Shown: Index, the readout and the simulated spots use this phase" : "Show this phase")
                .accessibilityLabel("Show \(phase.name)")
                .accessibilityIdentifier("diffraction.phases.show.\(phase.id)")
                Spacer(minLength: 0)
                if let attribution = phase.source.attribution {
                    Text(attribution.replacingOccurrences(of: "Materials Project · ", with: ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .help(attribution)
                }
            }
            Text(DiffractionPhases.latticeText(phase.structure().cell) + (phase.isEdited ? " (edited)" : ""))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("Lattice of \(phase.name): \(DiffractionPhases.latticeText(phase.structure().cell))")
                .accessibilityIdentifier("diffraction.phases.lattice.\(phase.id)")
            if DiffractionPhases.isOutdated(phase, in: analysis) {
                // The room keeps its own copy of the phase it uses (#780): the library's change waits for this button.
                HStack(spacing: 6) {
                    Label("Changed in your library since it was shown here.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Update from Library") { DiffractionPhases.set(phase, shown: true, in: analysis) }
                        .help("Use the library's copy of this phase; Index and the readout start again")
                        .accessibilityIdentifier("diffraction.phases.update.\(phase.id)")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The orientation the simulated spots are drawn at (#782, #783; the mockup's Index section): the zone axis ("[1 1 0]", "110",
/// "1̄10") and its turn in the plane (`DiffractionOrientationRows`), which Index fills with what it found and the person types over,
/// then Index's solutions, Flip and Fit scale. Typing either takes the drawn spots off Index's orientation.
private struct DiffractionIndexSection: View {
    let analysis: DiffractionAnalysis
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let settings = analysis.simulation
        InspectorSection("Index") {
            DiffractionOrientationRows(analysis: analysis)
            // Index's solutions, Flip and Fit scale (#787).
            let solutions = analysis.solutions.count
            InspectorRow("Solution") {
                Stepper(solutions > 1 ? "\(analysis.solutionIndex + 1) of \(solutions)" : (solutions == 1 ? "1 of 1" : "None"),
                        onIncrement: { analysis.selectSolution(analysis.solutionIndex + 1) },
                        onDecrement: { analysis.selectSolution(analysis.solutionIndex - 1) })
                    .monospacedDigit()
                    .disabled(solutions < 2)
                    .help("Steps through the orientations Index cannot tell apart (at most five), the best first")
                    .accessibilityLabel("Solution")
                    .accessibilityValue(solutions > 0 ? "\(analysis.solutionIndex + 1) of \(solutions)" : "none")
                    .accessibilityIdentifier("diffraction.index.solution")
            }
            // The section's two actions in one row of buttons (control placement §3), not buttons in label rows.
            InspectorActionRow {
                Button("Flip 180°") { analysis.flip() }
                    .disabled(!settings.isShown || analysis.drawnOrientation == nil)
                    .help("Turns the simulated spots 180° about the beam: the look-alike a centrosymmetric pattern cannot tell apart")
                    .accessibilityIdentifier("diffraction.index.flip")
                Button("Remove Spots") { DiffractionUndo.removeSpots(in: analysis, undoManager: undoManager) }
                    .disabled(analysis.spots.isEmpty)
                    .help("Removes every spot, found or clicked, and keeps the rings and their scale: Index then finds the spots again")
                    .accessibilityIdentifier("diffraction.index.removeSpots")
            }
            InspectorRow("Fit scale") {
                Toggle("Fit scale", isOn: Binding(get: { analysis.fitScale }, set: { analysis.fitScale = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Index fits the scale within ±3 % of the room's; off, it holds the room's scale. Read when Index runs.")
                    .accessibilityIdentifier("diffraction.index.fitScale")
            }
            InspectorNote(DiffractionIndexText.note(spots: analysis.spots, outcome: analysis.indexOutcome, indexed: settings.indexed != nil))
        }
    }
}

/// The zone axis and its in-plane turn the simulated spots are drawn at: the Index section's first rows, and a Simulation document's
/// Orientation section (#907). The zone axis commits on Return or when the field loses focus; a text that is not a zone axis is named
/// and the last one stays.
private struct DiffractionOrientationRows: View {
    let analysis: DiffractionAnalysis
    @State private var draft: String?
    @State private var refused: String?
    @FocusState private var editing: Bool

    var body: some View {
        let settings = analysis.simulation
        InspectorRow("Zone axis") {
            TextField("Zone axis", text: Binding(get: { draft ?? ZoneAxisText.text(settings.zoneAxis) }, set: { draft = $0 }),
                      prompt: Text("[0 0 1]"))
                .labelsHidden().textFieldStyle(.roundedBorder).monospacedDigit()
                .focused($editing)
                .onSubmit { commit() }
                .onChange(of: editing) { if !editing { commit() } }
                .help("The beam direction [u v w]: \"[1 1 0]\", \"1 1 0\", \"110\" or \"1̄10\"")
                .accessibilityIdentifier("diffraction.simulation.zone")
        }
        if let refused { InspectorWarning(refused) }
        InspectorRow("Turn") {
            OptionalNumericField(title: "In-plane turn", value: settings.inPlaneDegrees, format: pixelFormat, unit: "°") { analysis.setTurn(degrees: $0) }
                .help("The pattern's turn about the beam, counter-clockwise from down the rows toward along the columns")
                .accessibilityIdentifier("diffraction.simulation.turn")
        }
    }

    private func commit() {
        guard let text = draft else { return }
        if let uvw = ZoneAxisText.parse(text) {
            analysis.setZoneAxis(uvw)
            refused = nil
            draft = nil
        } else {
            refused = "\"\(text)\" is not a zone axis: type three whole numbers, not all 0, such as [1 1 0] or 1̄10."
        }
    }
}

/// The crystal pane beside the pattern (#789): the unit cell's edges. The pane is shown or hidden from View > Show Crystal, a
/// layout choice, not a setting.
private struct DiffractionCrystalViewSection: View {
    let view: DiffractionViewState

    var body: some View {
        InspectorSection("Crystal View") {
            InspectorRow("Unit cell") {
                Toggle("Show unit cell", isOn: Binding(get: { view.showsUnitCell }, set: { view.showsUnitCell = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!view.showsCrystal)
                    .help("Draw the unit cell's edges in the crystal pane")
                    .accessibilityIdentifier("diffraction.crystal.unitCell")
            }
        }
    }
}

/// The simulated spots over the pattern (#782): on or off, and the hkl labels. The crystal is the Phases section's, the scale and
/// beam the Calibration's, the orientation the Index section's; the overlay is drawn again on every change of any of them.
///
/// A Simulation document adds Kinematic | Dynamical (#911, MA8): Dynamical draws the multislice's zone-axis beams at the thickness the
/// slider picks (the same stored exit waves as the HRTEM image, so moving it is a lookup), forbidden reflections as open rings, and
/// the method line names the thickness.
private struct DiffractionSimulationSection: View {
    let item: OpenItem
    private var image: CalibratedImage { item.session.imageOrBlank }
    private var analysis: DiffractionAnalysis { item.diffraction }
    @Environment(AppState.self) private var appState

    var body: some View {
        let settings = analysis.simulation
        let simulated = item.simulatedSpots(image: image)
        InspectorSection("Simulation") {
            if DemoDocuments.isSimulation(item.url) {
                dynamicalRows(item.multislice)
                SimulationCBEDRows(item: item)
            } else if let simulation = appState.simulationDocument(ofCBED: item) {
                // The CBED pattern's own item: its document's rows (the slider, Stop, progress, failure), so they stay as it appears.
                SimulationCBEDRows(item: simulation)
            }
            if appState.simulationDocument(ofCBED: item)?.multislice.atomModel != nil {
                // An atom model's pattern: no reflections to draw or label (#953).
                InspectorNote(SimulationModel.modelLabelsSentence).accessibilityIdentifier("diffraction.simulation.modelLabels")
            } else {
                InspectorRow("Overlay") {
                    Toggle("Show simulated spots", isOn: Binding(get: { analysis.simulation.isShown }, set: { analysis.simulation.isShown = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                        .help("The crystal's kinematical spot pattern at the Index section's orientation, drawn over the pattern with the scale and centre in use")
                        .accessibilityIdentifier("diffraction.simulation.show")
                }
                InspectorRow("Labels") {
                    Toggle("Show hkl labels", isOn: Binding(get: { analysis.simulation.showsLabels }, set: { analysis.simulation.showsLabels = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                        .help("Each simulated spot's hkl beside it (the 60 strongest)")
                        .accessibilityIdentifier("diffraction.simulation.labels")
                }
                InspectorRow("Double diffraction") {
                    Toggle("Show double diffraction", isOn: Binding(get: { analysis.simulation.doubleDiffraction }, set: { analysis.simulation.doubleDiffraction = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                        .help("Also draws, as dashed rings, the spots a twice-diffracted beam adds (g₁ + g₂) where the crystal forbids a reflection, such as 002 in silicon down [1 1 0]")
                        .accessibilityIdentifier("diffraction.simulation.doubleDiffraction")
                }
                InspectorRow("Excitation error") {
                    OptionalNumericField(title: "Excitation error", value: settings.excitationError, format: excitationFormat, unit: "Å⁻¹") { analysis.setExcitationError($0) }
                        .help("σ of the excitation envelope; spots whose excitation error is up to three times this are kept (0.02 Å⁻¹ by default, as py4DSTEM; 0.001 to 1)")
                        .accessibilityIdentifier("diffraction.simulation.excitationError")
                }
                if let line = DiffractionSimulationText.summary(simulated, crystal: analysis.crystal.name, zoneAxis: settings.zoneAxis) {
                    switch simulated {
                    case .failure?: InspectorWarning(line)
                    default: InspectorNote(line)
                    }
                }
            }
            if let beams = item.dynamicalBeams {
                InspectorNote(beams.methodLine).accessibilityIdentifier("diffraction.simulation.method")
            }
            if settings.isShown, let offAxis = item.dynamicalOffAxis { InspectorWarning(offAxis) }
        }
    }

    /// Kinematic | Dynamical and, for Dynamical, the thickness of the stored exit waves; the run is the HRTEM image's own
    /// (`AppState.computeHRTEMImage`'s multislice, without the image), started here when Dynamical is on.
    @ViewBuilder
    private func dynamicalRows(_ model: SimulationModel) -> some View {
        let crystal = analysis.simulatedPhase
        let zoneAxis = analysis.simulation.zoneAxis
        SegmentedPicker(label: "Intensities",
                        items: [(false, .title("Kinematic", help: "The kit's |F|² with the excitation envelope")),
                                (true, .title("Dynamical", help: "The multislice's zone-axis beams at a thickness, the same run as the HRTEM image"))],
                        selection: Binding(get: { model.isDynamical }, set: { model.setDynamical($0) }))
            .disabled(model.atomModel != nil)
            .accessibilityIdentifier("diffraction.simulation.dynamical")
        .task(id: item.dynamicalRunKey) {
            guard model.isDynamical, model.atomModel == nil else { return }
            model.adoptVoltage(kV: analysis.typedBeamKV)
            await model.updateExitWaves(crystal: crystal, zoneAxis: zoneAxis)
            appState.refreshHRTEMImage(of: item)
        }
        if model.atomModel != nil { InspectorNote(SimulationModel.modelDynamicalSentence) }
        if model.isDynamical {
            if let waves = model.exitWaves, waves.waves.count > 1, let index = model.shownThicknessIndex,
               model.exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) {
                InspectorRow("Thickness") {
                    Text("\(UnitDisplay.number(waves.thicknessNM(at: index), digits: 3)) nm").monospacedDigit()
                        .accessibilityIdentifier("diffraction.simulation.thicknessValue")
                }
                Slider(value: Binding(get: { Double(index) }, set: {
                    model.setThicknessIndex(Int($0.rounded()))
                    appState.refreshHRTEMImage(of: item)
                }),
                       in: 0 ... Double(waves.waves.count - 1), step: 1) {
                    Text("Thickness")
                }
                .labelsHidden()
                .help("Steps through the exit waves stored at whole periods of the specimen; the HRTEM image shares this thickness")
                .accessibilityValue("\(UnitDisplay.number(waves.thicknessNM(at: index), digits: 3)) nanometres, "
                                    + "\(index + 1) of \(waves.waves.count) stored thicknesses")
                .accessibilityIdentifier("diffraction.simulation.thickness")
            }
            if model.isComputing {
                InspectorNote("Computing the exit waves…")
            } else if let absence = model.dynamicalAbsence(crystal: crystal, zoneAxis: zoneAxis) {
                InspectorWarning(absence)
            }
        }
    }
}

/// The Index section's note (#784): what Index will read, and what a clicked spot cannot give.
nonisolated enum DiffractionIndexText {
    static func note(spots: [MeasuredSpot], outcome: PatternIndexing.Outcome?, indexed: Bool) -> String {
        if outcome?.zoneAxisOnly == true, outcome?.orientation != nil {
            return "Clicked spots carry no intensities, so they give the zone axis and the turn only; the tilt needs Index on found spots: Remove Spots, then Index."
        }
        if spots.isEmpty {
            return "Index (⌘R) finds the spots, marks them and finds the full orientation; or type a zone axis."
        }
        if indexed { return "Found by Index. Remove or click spots and Index again, or type a zone axis to set it by hand." }
        return "Index (⌘R) reads the marked spots: found ones give the full orientation, a clicked one the zone axis only."
    }

    /// The pattern's spoken words for Index's answer (#785): its line, and that its spots are listed in the Spots table, the
    /// pattern's text alternative. "" before an answer.
    static func spoken(_ line: String?, rows: Int) -> String {
        guard let line else { return "" }
        return ", Index: \(line); \(UnitDisplay.count(rows, "spot", "spots")) in the Spots table"
    }
}

/// The Simulation section's line and the pattern's spoken words for the overlay. Pure.
nonisolated enum DiffractionSimulationText {
    /// "Al [0 1 1]: 24 spots on the pattern.", or why there are none; nil while the overlay is off.
    static func summary(_ result: DiffractionAnalysis.SimulatedSpots?, crystal: String, zoneAxis: SIMD3<Int>) -> String? {
        switch result {
        case nil: nil
        case .success(let spots)?: "\(crystal) \(ZoneAxisText.text(zoneAxis)): \(UnitDisplay.count(spots.count, "spot", "spots")) on the pattern"
            + doubleDiffraction(spots, of: " of them") + "."
        case .failure(let absence)?: absence.sentence + "."
        }
    }

    /// What VoiceOver adds to the pattern's value: ", 24 simulated spots of [0 1 1]"; nothing while the overlay is off or has none.
    static func spoken(_ result: DiffractionAnalysis.SimulatedSpots?, zoneAxis: SIMD3<Int>) -> String {
        guard case .success(let spots)? = result else { return "" }
        return ", \(UnitDisplay.count(spots.count, "simulated spot", "simulated spots")) of \(ZoneAxisText.text(zoneAxis))" + doubleDiffraction(spots, of: "")
    }

    /// ", 4 of them by double diffraction"; nothing when none is.
    static func doubleDiffraction(_ spots: [ZoneAxisOverlay.Spot], of: String) -> String {
        let n = spots.filter(\.isDoubleDiffraction).count
        return n == 0 ? "" : ", \(n)\(of) by double diffraction"
    }
}

private struct DiffractionRingsSection: View {
    let session: ImageSession
    private var image: CalibratedImage { session.imageOrBlank }
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        InspectorSection("Rings and Spots") {
            InspectorNote("Ring tool: drag from the inner to the outer edge of a ring. Spot tool: click a spot.")
            InspectorRow("Inner") {
                OptionalNumericField(title: "Inner radius", value: view.annulusInner, format: pixelFormat, unit: "px") { view.setAnnulus(inner: $0, outer: view.annulusOuter) }
            }
            InspectorRow("Outer") {
                OptionalNumericField(title: "Outer radius", value: view.annulusOuter, format: pixelFormat, unit: "px") { view.setAnnulus(inner: view.annulusInner, outer: $0) }
            }
            InspectorActionRow {
                Button("Fit Ring") { PendingEdits.run { analysis.fitRing(image: image, inner: view.annulusInner, outer: view.annulusOuter) } }
                    .disabled(analysis.isFitting).accessibilityIdentifier("diffraction.fitRing")
                Button("Remove") { if let id = view.selection { DiffractionUndo.remove(id, in: analysis, undoManager: undoManager); view.selection = nil } }.disabled(view.selection == nil).accessibilityIdentifier("diffraction.remove")
            }
            InspectorActionRow {
                Button("Remove All") { DiffractionUndo.removeAll(in: analysis, undoManager: undoManager) }.disabled(analysis.rings.isEmpty && analysis.spots.isEmpty)
            }
        }
    }
}

/// Ring, Spot or Tilt: what a click or a drag on the pattern does. A full-width segmented control in its own section, no leading label.
private struct DiffractionToolsSection: View {
    let view: DiffractionViewState

    var body: some View {
        InspectorSection("Tools") {
            SegmentedPicker(label: "Tool",
                            items: [(DiffractionViewState.Tool.ring, .title("Ring")), (.spot, .title("Spot")), (.tilt, .title("Tilt"))],
                            selection: Binding(get: { view.tool }, set: { view.tool = $0 }))
                .accessibilityIdentifier("diffraction.tool")
            if view.tool == .tilt {
                InspectorNote("Drag the pattern to tilt the simulated spots, 0.05° per point; ⌥ drag turns them about the beam. ⌥ and an arrow tilt 0.1°, ⌥⇧ 1°.")
            }
        }
    }
}

/// The image rooms' one Display section (control placement §5) for the pattern: colormap, the histogram of the drawn values with its
/// window, gamma, and the log switch. The zoom is the pane's own (the wheel, a pinch, a double-click), not buttons here (§6).
private struct DiffractionDisplaySection: View {
    let view: DiffractionViewState

    var body: some View {
        ImageRoomDisplaySection(presentation: view.presentation, colormapID: "diffraction.colormap", logID: "diffraction.log",
                                log: Binding(get: { view.useLog }, set: { view.useLog = $0 }))
    }
}

private struct DiffractionExportSection: View {
    let session: ImageSession
    private var image: CalibratedImage { session.imageOrBlank }
    let analysis: DiffractionAnalysis
    /// A Simulation document exports its simulated spots (#907).
    var isSimulation = false
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var document = RoomExportFile(text: "")
    @State private var exportName = ""

    var body: some View {
        InspectorSection("Export", startsExpanded: false) {
            InspectorActionRow {
                Button("Export Readout CSV…") { export(spots: false) }
                    .disabled(analysis.rings.isEmpty && analysis.spots.isEmpty)
                    .accessibilityIdentifier("diffraction.export")
            }
            InspectorActionRow {
                Button("Export Spots CSV…") { export(spots: true) }
                    .disabled(isSimulation ? analysis.simulatedSpotRows(image: image).isEmpty : analysis.indexSpotRows.isEmpty)
                    .help(isSimulation ? "The simulated spots as the Spots table lists them: hkl, R in px and mm, q, d and the phase"
                          : "Index's spots as the Spots table lists them: hkl, R, q, d, the expected d, Δd/d and the phase")
                    .accessibilityIdentifier("diffraction.export.spots")
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { appState.present(error) }
        }
    }

    private func export(spots: Bool) {
        let text = spots ? ExportSnapshot.diffractionSpotsCSV(analysis, image: image, openItems: appState.openItems,
                                                                       simulation: isSimulation)
                         : ExportSnapshot.diffractionCSV(analysis, image: image, openItems: appState.openItems)
        exportName = spots ? DiffractionReadoutExport.spotsBaseName(of: image.fileName) : DiffractionReadoutExport.baseName(of: image.fileName)
        if let directory = appState.exportDirectory {
            do {
                let url = try spots ? ExportDirectoryFile.write(text, named: exportName + ".csv", into: directory)
                                    : DiffractionReadoutExport.write(text, imageFileName: image.fileName, into: directory)
                appState.statusText = "Exported \(url.lastPathComponent)"
            } catch { appState.present(error) }
        } else {
            document = RoomExportFile(text: text)
            exporting = true
        }
    }
}
