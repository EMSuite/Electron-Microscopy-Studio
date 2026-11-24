//
//  DiffractionRoomInspector.swift
//  Role: the Diffraction room's Settings (design section 3): Centre, Calibration, Display, Tools, Phases, Index, Simulation, Rings, Export (control placement §2:
//        what I am looking at, then the job; Centre stays above Calibration, which it feeds). Presentation only;
//        the state is `DiffractionAnalysis` and every number DiffractoKit's. Every field commits on Return or blur
//        (`OptionalNumericField`), every control has an accessibility identifier for the journey.
//

import ShellControls
import ShellInspector
import ShellPhaseLibrary
import ShellPhaseViews
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
        Group {
            DiffractionCentreSection(analysis: analysis, view: view)
            DiffractionCalibrationSection(session: item.session, analysis: analysis, view: view)
            DiffractionDisplaySection(view: view)
            DiffractionToolsSection(view: view)
            DiffractionPhasesSection(analysis: analysis)
            DiffractionIndexSection(analysis: analysis)
            DiffractionSimulationSection(session: item.session, analysis: analysis)
            DiffractionRingsSection(session: item.session, analysis: analysis, view: view)
            DiffractionExportSection(session: item.session, analysis: analysis)
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

/// The Phases section (#779), in place of Crystal: the phases of the person's library, each with its marker shape and colour, shown
/// or hidden, and its lattice; Add Phase… opens EMSuiteUI's sheet (search the Materials Project, or Open CIF…). In this first slice
/// one phase is shown at a time and is the crystal Index, the readout and the simulated spots use; with none shown the room uses
/// its calibration standard. The library is on this Mac, so a phase added once works offline.
private struct DiffractionPhasesSection: View {
    let analysis: DiffractionAnalysis
    @State private var adding = false
    @State private var importing = false
    @State private var addModel = AddPhaseModel(library: PhaseServices.library, client: PhaseServices.client,
                                                keyStore: PhaseServices.keyStore)
    private var library: PhaseLibrary { PhaseServices.library }

    var body: some View {
        InspectorSection("Phases") {
            if library.phases.isEmpty {
                InspectorNote("No phases yet. Add Phase… finds one on the Materials Project or opens a CIF; until then the room indexes against \(analysis.standard.name), the calibration standard.")
            }
            ForEach(Array(DiffractionPhases.ordered(library.phases).enumerated()), id: \.element.id) { index, phase in
                DiffractionPhaseRow(phase: phase, index: index, analysis: analysis)
            }
            if !library.unreadable.isEmpty {
                InspectorWarning("\(library.unreadable.count) phase record\(library.unreadable.count == 1 ? "" : "s") could not be read: \(library.unreadable.joined(separator: "; "))")
            }
            InspectorActionRow {
                Button("Add Phase…") { adding = true }
                    .help("Find a phase on the Materials Project, or open a CIF")
                    .accessibilityIdentifier("diffraction.phases.add")
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
        .sheet(isPresented: $adding) {
            AddPhaseSheet(model: addModel, onOpenCIF: { importing = true }) { phase in
                DiffractionPhases.set(phase, shown: true, in: analysis)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cif") ?? .plainText, .plainText]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let (loaded, bytes) = try await DiffractionCIF.loadWithBytes(url)
                        let phase = try DiffractionPhases.addCIF(loaded, bytes: bytes, fileName: url.lastPathComponent, to: library)
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
        }
        .padding(.vertical, 2)
    }
}

/// The orientation the simulated spots are drawn at (#782, #783; the mockup's Index section): the zone axis ("[1 1 0]", "110",
/// "1̄10") and its turn in the plane, which Index fills with what it found and the person types over. The zone axis commits on
/// Return or when the field loses focus; a text that is not a zone axis is named and the last one stays. Typing either takes
/// the drawn spots off Index's orientation.
private struct DiffractionIndexSection: View {
    let analysis: DiffractionAnalysis
    @Environment(\.undoManager) private var undoManager
    @State private var draft: String?
    @State private var refused: String?
    @FocusState private var editing: Bool

    var body: some View {
        let settings = analysis.simulation
        InspectorSection("Index") {
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
            InspectorRow("Spots") {
                Button("Remove Spots") { DiffractionUndo.removeSpots(in: analysis, undoManager: undoManager) }
                    .disabled(analysis.spots.isEmpty)
                    .help("Removes every spot, found or clicked, and keeps the rings and their scale: Index then finds the spots again")
                    .accessibilityIdentifier("diffraction.index.removeSpots")
            }
            InspectorNote(DiffractionIndexText.note(spots: analysis.spots, outcome: analysis.indexOutcome, indexed: settings.indexed != nil))
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

/// The simulated spots over the pattern (#782): on or off, and the hkl labels. The crystal is the Phases section's, the scale and
/// beam the Calibration's, the orientation the Index section's; the overlay is drawn again on every change of any of them.
private struct DiffractionSimulationSection: View {
    let session: ImageSession
    private var image: CalibratedImage { session.imageOrBlank }
    let analysis: DiffractionAnalysis

    var body: some View {
        let settings = analysis.simulation
        let simulated = analysis.simulatedSpots(image: image)
        InspectorSection("Simulation") {
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

/// Ring or Spot: what a click on the pattern does. A full-width segmented control in its own section, no leading label.
private struct DiffractionToolsSection: View {
    let view: DiffractionViewState

    var body: some View {
        InspectorSection("Tools") {
            SegmentedPicker(label: "Tool",
                            items: [(DiffractionViewState.Tool.ring, .title("Ring")), (.spot, .title("Spot"))],
                            selection: Binding(get: { view.tool }, set: { view.tool = $0 }))
                .accessibilityIdentifier("diffraction.tool")
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
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var document = RoomExportFile(text: "")

    var body: some View {
        InspectorSection("Export", startsExpanded: false) {
            InspectorActionRow {
                Button("Export Readout CSV…") { export() }
                    .disabled(analysis.rings.isEmpty && analysis.spots.isEmpty)
                    .accessibilityIdentifier("diffraction.export")
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText,
                      defaultFilename: DiffractionReadoutExport.baseName(of: image.fileName)) { result in
            if case .failure(let error) = result { appState.present(error) }
        }
    }

    private func export() {
        let text = ExportSnapshot.diffractionCSV(analysis, image: image, openItems: appState.openItems)
        if let directory = appState.exportDirectory {
            do {
                let url = try DiffractionReadoutExport.write(text, imageFileName: image.fileName, into: directory)
                appState.statusText = "Exported \(url.lastPathComponent)"
            } catch { appState.present(error) }
        } else {
            document = RoomExportFile(text: text)
            exporting = true
        }
    }
}
