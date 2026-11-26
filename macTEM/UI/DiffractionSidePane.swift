//
//  DiffractionSidePane.swift
//  Role: the pane beside the Diffraction room's pattern (#921): the crystal down the beam (#790) in Index and Simulate, the zone-axis
//        map (#814) in Tilt Plan, the powder pattern (#810) in Powder. The part in the sidebar picks it (#1044, `DiffractionPart.sidePane`).
//        They are results of the room, so they sit beside the data and never in an inspector section (control placement §1; design DNA:
//        a live or interactive view is a pane). It is the leading panel of the room's centre (`WorkspaceCentre`, #1094), a `CentrePanel`
//        whose header names it; its width is the centre's divider. The sentences that describe a result (the
//        tilt to the picked zone axis, the powder headlines) are the pane's words above it; the inspector keeps the settings. The powder
//        peaks are a table in the shell's bottom area (`DiffractionPowderPeakTable`, `DiffractionTablePane`) in the Powder part. Presentation only: the numbers are
//        `TiltPlanning`'s and `PowderTable`'s over DiffractoKit.
//

import ShellControls
import ShellInspector
import ShellLayout
import SwiftUI
import TEMCore
import TEMSession

/// The words of the side pane. Pure; main-actor, as the view state's pane enums are.
enum DiffractionPaneWords {
    static func title(_ pane: DiffractionViewState.SidePane) -> String {
        switch pane {
        case .crystal: "Crystal"
        case .zoneAxisMap: "Zone-axis Map"
        case .powder: "Powder Pattern"
        }
    }

    /// The zone-axis map before Index.
    static let mapBlocker = "Index the pattern first: the zone axes and the tilts to them are placed from its orientation."
    /// What the powder pattern leaves out: the pane's last words.
    static let powderDisclaimer = "A line pattern for planning and comparison: no instrument profile, no texture, no absorption, no thermal motion."
}

/// The side pane: the frame's panel (`CentrePanel`), its header the pane's name, and the pane.
struct DiffractionSidePaneView: View {
    let item: OpenItem
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    let pane: DiffractionViewState.SidePane

    /// The pane on screen in `part`, or nil: the part's pane; the crystal only while View > Show Crystal has it and once simulated
    /// spots are drawn (before, the pattern has the room).
    static func shown(part: DiffractionPart, view: DiffractionViewState, analysis: DiffractionAnalysis) -> DiffractionViewState.SidePane? {
        guard let pane = DiffractionPart.sidePane(part) else { return nil }
        if pane == .crystal && !(view.showsCrystal && analysis.simulation.isShown) { return nil }
        return pane
    }

    var body: some View {
        // The pane's name in the frame's panel header, as the pattern's panel beside it has one (#1094).
        CentrePanel(title: DiffractionPaneWords.title(pane)) {
            switch pane {
            case .crystal where SimulationEmptyState.isShown(for: item):
                DiffractionPaneEmpty(text: SimulationEmptyState.paneSentence)
            case .powder where SimulationEmptyState.isShown(for: item):
                DiffractionPaneEmpty(text: SimulationEmptyState.paneSentence)
            case .crystal:
                // A Simulation document draws the slab its multislice runs on (#897).
                DiffractionCrystalPane(analysis: analysis, showsUnitCell: view.showsUnitCell,
                                       slab: DemoDocuments.isSimulation(item.url)
                                           ? item.multislice.drawnSlab(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis)
                                           : nil)
            case .zoneAxisMap:
                DiffractionZoneAxisPane(item: item)
            case .powder:
                DiffractionPowderPane(item: item)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diffraction.sidePane")
    }
}

/// A pane with nothing to draw yet: what to do, centred.
struct DiffractionPaneEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("diffraction.sidePane.empty")
    }
}

/// A result's sentences above its pane: secondary words, two lines at most, the whole sentence as help.
private struct DiffractionPaneSentence: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(text)
    }
}

/// The zone-axis map (#814) as a pane: the calibration's sentence and the picked zone axis's tilts above the map, which a click picks
/// from, as the Holder section's Zone axis pop-up does.
struct DiffractionZoneAxisPane: View {
    let item: OpenItem

    var body: some View {
        let analysis = item.diffraction
        let holder = item.diffractionHolder
        if let plan = holder.plan(analysis: analysis, image: item.session.imageOrBlank) {
            VStack(alignment: .leading, spacing: 6) {
                DiffractionPaneSentence(text: plan.calibrationSentence)
                if let uvw = holder.selected, let row = plan.row(uvw) {
                    DiffractionPaneSentence(text: plan.sentence(for: row))
                        .accessibilityIdentifier("diffraction.holder.sentence")
                }
                DiffractionZoneAxisMap(plan: plan, selected: Binding(get: { holder.selected }, set: { holder.selected = $0 }))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        } else {
            Text(DiffractionPaneWords.mapBlocker)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The powder pattern (#810) as a pane: each phase's headline and marks above the chart, the disclaimer under it. Its peaks are the
/// Peaks table under the pattern.
struct DiffractionPowderPane: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        let table = DiffractionPowderSection.table(of: item, openItems: appState.openItems)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(table.phases.indices, id: \.self) { i in
                // A phase the kit refused: its reason, in its words, with the glyph.
                if table.patterns[i] == nil {
                    InspectorWarning(table.headline(phase: i, locale: .autoupdatingCurrent), font: .callout)
                } else {
                    DiffractionPaneSentence(text: table.headline(phase: i, locale: .autoupdatingCurrent))
                }
                if let marks = table.marksSentence(phase: i, locale: .autoupdatingCurrent) { DiffractionPaneSentence(text: marks) }
                if let lattice = table.calculatedLatticeSentence(phase: i) { DiffractionPaneSentence(text: lattice) }
            }
            DiffractionPowderChart(table: table)
                .frame(maxHeight: .infinity)
            Text(DiffractionPaneWords.powderDisclaimer)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .accessibilityIdentifier("diffraction.powder.pane")
    }
}

/// The powder peaks (#810) as a system `Table` under the pattern, strongest first: phase, hkl, d, position, intensity and the marks
/// (◆ diagnostic, ⧉ overlapped and by what). ⌘C copies the selected rows as the other tables do (`DiffractionPowderPeakFormat`).
struct DiffractionPowderPeakTable: View {
    let table: PowderTable
    @State private var selection: Set<PowderRow.ID> = []

    private typealias Column = DiffractionPowderPeakFormat.Column

    var body: some View {
        let rows = DiffractionPowderPeakFormat.ordered(table)
        Table(rows, selection: $selection) {
            TableColumn(Column.phase.title(table)) { row in Text(DiffractionPowderPeakFormat.cell(.phase, row, table: table)) }
                .width(min: 44, ideal: 64)
            TableColumn(Column.hkl.title(table)) { row in
                Text(DiffractionPowderPeakFormat.cell(.hkl, row, table: table)).monospacedDigit()
                    .help(DiffractionPowderText.line(row, table: table))
                    .accessibilityLabel(DiffractionPowderText.spoken(row, table: table))
            }.width(min: 44, ideal: 60)
            TableColumn(Column.d.title(table)) { row in Text(DiffractionPowderPeakFormat.cell(.d, row, table: table)).monospacedDigit() }
                .width(min: 52, ideal: 60)
            TableColumn(Column.position.title(table)) { row in
                Text(DiffractionPowderPeakFormat.cell(.position, row, table: table)).monospacedDigit()
            }.width(min: 56, ideal: 64)
            TableColumn(Column.intensity.title(table)) { row in
                Text(DiffractionPowderPeakFormat.cell(.intensity, row, table: table)).monospacedDigit()
            }.width(min: 40, ideal: 48)
            TableColumn(Column.marks.title(table)) { row in Text(DiffractionPowderPeakFormat.cell(.marks, row, table: table)) }
                .width(min: 60, ideal: 120)
        }
        // ⌘C and Edit > Copy: the selected peaks; dimmed with none selected.
        .onCopyCommand(perform: selection.isEmpty ? nil : {
            [NSItemProvider(object: DiffractionPowderPeakFormat.copyText(rows.filter { selection.contains($0.id) }, table: table) as NSString)]
        })
        .overlay {
            if rows.isEmpty {
                Text("No powder pattern could be computed for these phases.")
                    .font(.callout).foregroundStyle(.secondary).padding(10).allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("diffraction.powder.peaks")
        .accessibilityLabel("Powder peaks")
    }
}

/// The Peaks table's columns, cells and ⌘C text. Pure.
nonisolated enum DiffractionPowderPeakFormat {
    nonisolated enum Column: CaseIterable, Sendable {
        case phase, hkl, d, position, intensity, marks

        /// The column's title: the position's is 2θ for X-rays, q for rings.
        func title(_ table: PowderTable) -> String {
            switch self {
            case .phase: "Phase"
            case .hkl: "hkl"
            case .d: "d (Å)"
            case .position: table.settings.kind == .xray ? "2θ (°)" : "q (Å⁻¹)"
            case .intensity: "I"
            case .marks: "Marks"
            }
        }
    }

    /// Strongest first, as the section listed them.
    static func ordered(_ table: PowderTable) -> [PowderRow] { table.rows.sorted { $0.intensity > $1.intensity } }

    static func cell(_ column: Column, _ row: PowderRow, table: PowderTable, locale: Locale = .autoupdatingCurrent) -> String {
        switch column {
        case .phase: row.phase
        case .hkl: row.hkl
        case .d: Num.fixed(row.d, 3, locale: locale)
        case .position: Num.fixed(row.position, table.settings.kind == .xray ? 2 : 3, locale: locale)
        case .intensity: Num.fixed(row.intensity, 0, locale: locale)
        case .marks:
            ([row.isDiagnostic ? "◆ diagnostic" : nil] + [row.isOverlapped ? "⧉ " + row.overlaps.joined(separator: ", ") : nil])
                .compactMap { $0 }.joined(separator: " ")
        }
    }

    /// The header line and one line per row, tab-separated, cells as the table shows them; "" for no rows.
    static func copyText(_ rows: [PowderRow], table: PowderTable, locale: Locale = .autoupdatingCurrent) -> String {
        TableCopyText.text(titles: Column.allCases.map { $0.title(table) },
                           rows: rows.map { row in Column.allCases.map { cell($0, row, table: table, locale: locale) } })
    }
}
