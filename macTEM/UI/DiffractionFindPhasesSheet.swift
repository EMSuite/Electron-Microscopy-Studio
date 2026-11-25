//
//  DiffractionFindPhasesSheet.swift
//  Role: the Diffraction room's Find Phases sheet (plan row R13, #812): the candidate phases ranked by how many of the measured rings
//        (or marked spots) each explains, the strong rings it predicts that were not seen, its misfit and the scale it took, and the
//        kit's ties, with the selected row's sentence. Use Phase makes the selected phase the room's crystal, so its indexing is
//        the room's. Presentation only: every number is `PhaseFindingResult`'s; the sheet says "explains", never "is".
//        Candidates: My Phases (the room's crystal, your library, the standards and the crystals of the open patterns) and, once
//        searched (R14, #813), the Materials Project's entries for the elements typed or taken from the EDS room
//        (`MaterialsProjectPhaseSearch`); the sheet says how many came from each and which limits applied.
//

import ShellInspector
import ShellLayout
import ShellPhaseLibrary
import SwiftUI
import DiffractoCore
import TEMCore
import TEMSession

/// One candidate as the room holds it: the crystal Use Phase sets, and where it came from.
struct DiffractionPhaseCandidate: Identifiable {
    let crystal: DiffractionCrystal
    var source: TEMCore.PhaseSource = .myPhases
    /// The formula as the source states it (the Materials Project's reduced formula); nil: the cell content.
    var formula: String? = nil
    var id: String { crystal.name }

    var candidate: PhaseCandidate { PhaseCandidate(name: crystal.name, structure: crystal.structure, source: source, formula: formula) }

    /// My Phases: the room's crystal, the library's phases, the standards, then the crystals of the other open patterns, each name once.
    @MainActor static func all(for item: OpenItem, openItems: OpenItems, library: [Phase] = PhaseServices.library.phases) -> [DiffractionPhaseCandidate] {
        var seen: Set<String> = []
        var out: [DiffractionPhaseCandidate] = []
        func add(_ c: DiffractionCrystal) { if seen.insert(c.name).inserted { out.append(DiffractionPhaseCandidate(crystal: c)) } }
        add(item.diffraction.crystal)
        DiffractionPhases.ordered(library).forEach { add(DiffractionPhases.crystal(for: $0)) }
        StandardCrystals.all.forEach { add(.preset($0)) }
        openItems.items.filter { $0.id != item.id }.forEach { add($0.diffraction.crystal) }
        return out
    }

    /// My Phases, then the Materials Project's candidates of the window's last search (a name already there is not added twice).
    @MainActor static func all(for item: OpenItem, appState: AppState) -> [DiffractionPhaseCandidate] {
        let mine = all(for: item, openItems: appState.openItems)
        let names = Set(mine.map(\.id))
        return mine + appState.phaseSearch.candidates.filter { !names.contains($0.id) }
    }
}

struct DiffractionFindPhasesSheet: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhaseFindingRow.ID?

    var body: some View {
        let finder = item.diffractionPhases
        let image = item.session.imageOrBlank
        let candidates = DiffractionPhaseCandidate.all(for: item, appState: appState)
        let mpCount = candidates.filter { $0.source == .materialsProject }.count
        let blocker = DiffractionPhaseFinder.blocker(analysis: item.diffraction, image: image)
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Phases").font(.title3.weight(.semibold))
            materialsProject(myPhases: candidates.count - mpCount, materialsProject: mpCount)
            HStack {
                Toggle("Fit scale", isOn: Binding(get: { finder.fitScale }, set: { finder.fitScale = $0 }))
                    .help("On, each phase takes the scale that suits it, within 3 %. Off, the room's calibration holds, which tells two phases with nearly equal lattices apart.")
                    .accessibilityIdentifier("diffraction.findPhases.fitScale")
                Spacer()
                if finder.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { finder.stop() }
                        .accessibilityIdentifier("diffraction.findPhases.stop")
                }
                Button("Rank") { finder.run(analysis: item.diffraction, image: image, candidates: candidates.map(\.candidate)) }
                    .disabled(blocker != nil || finder.isRunning)
                    .help(blocker ?? "Ranks \(candidates.count) phases, My Phases and the Materials Project's candidates, by how many of the measured rings (or the marked spots) each explains")
                    .accessibilityIdentifier("diffraction.findPhases.rank")
            }
            if let blocker { Label(blocker, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            // The glyph carries the colour, the sentence stays primary (#923: orange text on a light sheet is about 2:1).
            if let refusal = finder.refusal { InspectorWarning(refusal, font: .callout) }
            if let result = finder.result {
                if result.pattern == DiffractionPhaseFinder.pattern(analysis: item.diffraction, image: image) {
                    DiffractionPhaseTable(result: result, selection: $selection)
                        .frame(minHeight: LayoutPolicy.findPhasesTableMinimum)
                    notes(result)
                } else {
                    Label(DiffractionPhaseFinder.staleSentence, systemImage: "arrow.clockwise").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Phase") { use(candidates); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCandidate(candidates) == nil)
                    .help("Makes the selected phase the room's crystal: the rings and spots are indexed against it")
                    .accessibilityIdentifier("diffraction.findPhases.use")
            }
        }
        .padding(20)
        .frame(minWidth: LayoutPolicy.findPhasesSheet.min.width, idealWidth: LayoutPolicy.findPhasesSheet.idealWidth,
               minHeight: LayoutPolicy.findPhasesSheet.min.height)
    }

    /// The Materials Project row: the elements (typed or from the EDS room), Search and Stop, and what the candidates are.
    @ViewBuilder
    private func materialsProject(myPhases: Int, materialsProject: Int) -> some View {
        let search = appState.phaseSearch
        let eds = MaterialsProjectPhaseSearch.edsElements(appState.edx)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Elements", text: Binding(get: { search.elementsText }, set: { search.elementsText = $0 }), prompt: Text("Al, Cu, Mg"))
                    .onSubmit { search.run() }
                    .help("The elements of the phases to look for on the Materials Project, at most \(MaterialsProjectSearch.maximumElements)")
                    .accessibilityLabel("Elements to search the Materials Project for")
                    .accessibilityIdentifier("diffraction.findPhases.elements")
                Button("From EDS") { search.takeFromEDS(appState.edx) }
                    .disabled(eds == nil || search.isRunning)
                    .help(eds.map { "Takes the EDS room's quantified elements: \($0.joined(separator: ", "))" } ?? MaterialsProjectPhaseSearch.noEDSReason)
                    .accessibilityLabel("Take the elements from the EDS room")
                    .accessibilityIdentifier("diffraction.findPhases.fromEDS")
                if search.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { search.stop() }
                        .accessibilityLabel("Stop the Materials Project search")
                        .accessibilityIdentifier("diffraction.findPhases.searchStop")
                } else {
                    Button("Search Materials Project") { search.run() }
                        .help("Searches the Materials Project (open data, no key) for the phases of every combination of these elements")
                        .accessibilityIdentifier("diffraction.findPhases.search")
                }
            }
            Text(MaterialsProjectSearch.sourcesSentence(myPhases: myPhases, materialsProject: materialsProject))
                .foregroundStyle(.secondary)
            switch search.state {
            case .idle: EmptyView()
            case .searching(let elements):
                Text("Searching the Materials Project for \(elements.joined(separator: ", "))…").foregroundStyle(.secondary)
            case .done(let summary): Text(summary.sentence).foregroundStyle(.secondary)
            case .refused(let why), .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func notes(_ result: PhaseFindingResult) -> some View {
        let selected = result.rows.first { $0.id == selection } ?? result.rows.first
        VStack(alignment: .leading, spacing: 4) {
            if let selected { Text(result.sentence(for: selected)) }
            if let selected, let tie = result.tieSentence(selected.tie) { Text(tie) }
            if let weak = result.weakSentence { InspectorWarning(weak, font: .callout) }
            if let note = result.materialsProjectNote { Text(note).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectedCandidate(_ candidates: [DiffractionPhaseCandidate]) -> DiffractionPhaseCandidate? {
        guard let result = item.diffractionPhases.current(analysis: item.diffraction, image: item.session.imageOrBlank),
              let row = result.rows.first(where: { $0.id == selection }), row.refusal == nil else { return nil }
        return candidates.first { $0.id == row.name }
    }

    private func use(_ candidates: [DiffractionPhaseCandidate]) {
        guard let chosen = selectedCandidate(candidates) else { return }
        item.diffraction.setCrystal(chosen.crystal)
        appState.statusText = "\(chosen.crystal.name) is the room's crystal"
    }
}

/// The ranked candidates: one row a phase, in the kit's order, ties numbered.
struct DiffractionPhaseTable: View {
    let result: PhaseFindingResult
    @Binding var selection: PhaseFindingRow.ID?

    var body: some View {
        Table(result.rows, selection: $selection) {
            TableColumn("Phase") { row in Text(row.name) }.width(min: 60, ideal: 90)
            TableColumn("Formula") { row in Text(row.formula) }.width(min: 50, ideal: 70)
            TableColumn("Space group") { row in Text(row.spaceGroup) }.width(min: 60, ideal: 80)
            TableColumn("Explains") { row in Text(DiffractionPhaseText.explains(row)).monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn("Strong not seen") { row in Text(DiffractionPhaseText.strongMissing(row)).monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Misfit") { row in Text(DiffractionPhaseText.misfit(row)).monospacedDigit() }.width(min: 50, ideal: 60)
            TableColumn("Scale") { row in Text(DiffractionPhaseText.scale(row, fitScale: result.fitScale)).monospacedDigit() }
                .width(min: 50, ideal: 60)
            TableColumn("Tie") { row in Text(result.isTied(row) ? "\(row.tie + 1)" : "") }.width(min: 28, ideal: 34)
        }
        .accessibilityIdentifier("diffraction.findPhases.table")
    }
}

/// The cells of the candidate table. Pure.
nonisolated enum DiffractionPhaseText {
    /// "8 of 9"; a dash for a refused candidate.
    static func explains(_ row: PhaseFindingRow) -> String {
        row.refusal == nil ? "\(row.explained) of \(row.measured)" : UnitDisplay.noValue
    }

    /// "1 of 4" for rings; a dash for spots or a refused candidate.
    static func strongMissing(_ row: PhaseFindingRow) -> String {
        guard row.refusal == nil, let missing = row.strongMissing, let expected = row.strongExpected else { return UnitDisplay.noValue }
        return "\(missing) of \(expected)"
    }

    /// "0.4 %" for rings, "0.004 Å⁻¹" rms for spots; a dash with nothing explained.
    static func misfit(_ row: PhaseFindingRow) -> String {
        guard row.refusal == nil, row.explained > 0 else { return UnitDisplay.noValue }
        if let misfit = row.misfitPercent { return Num.fixed(misfit, 1) + " %" }
        if let rms = row.rmsDistance { return Num.fixed(rms, 3) + " Å⁻¹" }
        return UnitDisplay.noValue
    }

    /// "+0.7 %" with Fit scale on; "fixed" with it off.
    static func scale(_ row: PhaseFindingRow, fitScale: Bool) -> String {
        guard fitScale else { return "fixed" }
        guard row.refusal == nil, row.explained > 0 else { return UnitDisplay.noValue }
        return Num.signed(100 * (row.scale - 1), 1) + " %"
    }
}
