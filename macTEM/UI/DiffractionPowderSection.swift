//
//  DiffractionPowderSection.swift
//  Role: the Diffraction room's Powder section (plan row R11, #810): the powder pattern of the room's crystal, and of one more phase
//        to compare with, as rings against q at the pattern's beam energy or as an X-ray pattern against 2θ at a chosen line. The
//        section holds the settings; the stick chart (one colour a phase, the strongest peak of a phase at 100) with the headline of
//        each phase and the overlap and diagnostic marks is the Powder Pattern pane, the peaks the Peaks table under the pattern
//        (#921, `DiffractionSidePane`). Presentation only: every number is `PowderTable`'s over
//        DiffractoKit's `PowderPattern`. The Simulation document (R6, #788) takes the same table when it lands.
//

import Charts
import ShellInspector
import ShellLayout
import SwiftUI
import DiffractoCore
import DiffractoScattering
import TEMCore
import TEMSession
import UniformTypeIdentifiers

struct DiffractionPowderSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var document = RoomExportFile(text: "")
    @State private var exportType: UTType = .commaSeparatedText
    @State private var exportName = ""

    private static let degrees = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    private static let reach = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))

    var body: some View {
        let powder = item.diffractionPowder
        let settings = powder.settings
        let others = Self.comparable(for: item, openItems: appState.openItems)
        let table = Self.table(of: item, openItems: appState.openItems)
        InspectorSection("Powder", startsExpanded: false) {
            InspectorRow("Pattern") {
                Picker("Pattern", selection: Binding(get: { settings.kind }, set: { powder.setKind($0) })) {
                    Text("Electron rings").tag(PowderKind.rings)
                    Text("X-ray").tag(PowderKind.xray)
                }
                .labelsHidden().fixedSize()
                .help("Rings against q at this pattern's beam energy, or an X-ray powder pattern against 2θ")
                .accessibilityIdentifier("diffraction.powder.kind")
            }
            if settings.kind == .xray {
                InspectorRow("Radiation") {
                    Picker("Radiation", selection: Binding(get: { settings.radiation.name ?? "" },
                                                           set: { name in if let line = XRayRadiation.named(name) { powder.setRadiation(line) } })) {
                        ForEach(XRayRadiation.pymatgenLines, id: \.self) { line in
                            Text(PowderTable.radiationName(line)).tag(line.name ?? "")
                        }
                    }
                    .labelsHidden().fixedSize()
                    .help("The X-ray line, pymatgen's list (Cu Kα by default)")
                    .accessibilityIdentifier("diffraction.powder.radiation")
                }
                InspectorRow("2θ from") {
                    OptionalNumericField(title: "Two theta from", value: settings.twoThetaFrom, format: Self.degrees, unit: "°") {
                        powder.setTwoTheta(from: $0, to: settings.twoThetaTo)
                    }
                    .accessibilityIdentifier("diffraction.powder.from")
                }
                InspectorRow("2θ to") {
                    OptionalNumericField(title: "Two theta to", value: settings.twoThetaTo, format: Self.degrees, unit: "°") {
                        powder.setTwoTheta(from: settings.twoThetaFrom, to: $0)
                    }
                    .accessibilityIdentifier("diffraction.powder.to")
                }
            } else {
                InspectorRow("q max") {
                    OptionalNumericField(title: "Rings to q max", value: settings.ringReach, format: Self.reach, unit: "Å⁻¹") {
                        powder.setReach($0)
                    }
                    .help("The rings out to this q (no 2π), 0.2 to 4 Å⁻¹")
                    .accessibilityIdentifier("diffraction.powder.reach")
                }
            }
            InspectorRow("Compare with") {
                Picker("Compare with", selection: Binding(get: { powder.compareWith ?? "" },
                                                          set: { powder.setCompareWith($0.isEmpty ? nil : $0) })) {
                    Text("None").tag("")
                    ForEach(others, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize()
                .help("A second phase drawn beside this crystal: a standard, or the crystal of another open pattern")
                .accessibilityIdentifier("diffraction.powder.compare")
            }
            if phases.count > 1 {
                InspectorRow("Mark overlaps") {
                    Toggle("Mark overlaps", isOn: Binding(get: { settings.markOverlaps }, set: { powder.setMarkOverlaps($0) }))
                        .toggleStyle(.switch).labelsHidden()
                        .help("Marks the peaks one phase shares with the other, and each phase's strongest peak that no other phase has")
                        .accessibilityIdentifier("diffraction.powder.markOverlaps")
                }
            }
            // The pattern, its headlines and its peaks are results: the Powder Pattern pane beside the pattern and the Peaks table
            // under it (#921). One next-step line here.
            if !item.diffractionView.isShowing(.powder) {
                InspectorNote("View › Show Powder Pattern draws it beside the pattern, its peaks in the table under it.")
            } else if table.patterns.contains(where: { $0 == nil }) {
                InspectorWarning("The kit drew no pattern for a phase: the pane says why.")
            }
            InspectorActionRow {
                Button("Export Powder CSV…") { exportCSV(table) }
                    .disabled(table.rows.isEmpty)
                    .help("The peak table of the shown phases, with how it was computed")
                    .accessibilityIdentifier("diffraction.powder.exportCSV")
                Button("Export .xy…") { exportXY(table) }
                    .disabled((table.patterns.first ?? nil) == nil)
                    .help("This crystal's drawn profile: two columns, position and intensity, a tenth of the peak width apart")
                    .accessibilityIdentifier("diffraction.powder.exportXY")
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let error) = result { appState.present(error) }
        }
    }

    private var imageName: String { item.session.imageOrBlank.fileName }

    private func exportCSV(_ table: PowderTable) {
        let text = ExportSnapshot.powderCSV(table, image: item.session.imageOrBlank, openItems: appState.openItems)
        save(text, name: DiffractionPowderExport.baseName(of: imageName), extension: "csv", type: .commaSeparatedText)
    }

    private func exportXY(_ table: PowderTable) {
        guard let text = table.xy(phase: 0) else { return }
        save(text, name: DiffractionPowderExport.baseName(of: imageName, phase: table.phases[0].name), extension: "xy",
             type: DiffractionPowderExport.xyType)
    }

    private func save(_ text: String, name: String, extension ext: String, type: UTType) {
        if let directory = appState.exportDirectory {
            do {
                let url = try DiffractionPowderExport.write(text, named: name + "." + ext, into: directory)
                appState.statusText = "Exported \(url.lastPathComponent)"
            } catch { appState.present(error) }
        } else {
            document = RoomExportFile(text: text)
            exportType = type
            exportName = name
            exporting = true
        }
    }

    /// The powder pattern the section draws and the Export section writes: the room's crystal and the phase it is compared with.
    static func table(of item: OpenItem, openItems: OpenItems) -> PowderTable {
        let analysis = item.diffraction
        let phases = item.diffractionPowder.phases(crystal: analysis.crystal, others: comparable(for: item, openItems: openItems))
        return item.diffractionPowder.table(phases: phases, volts: analysis.volts(for: item.session.imageOrBlank))
    }

    /// The phases this crystal can be compared with: the room's standards, then the crystals of the other open patterns, each name once.
    static func comparable(for item: OpenItem, openItems: OpenItems) -> [PowderPhase] {
        var seen: Set<String> = [item.diffraction.crystal.name]
        var out: [PowderPhase] = []
        for s in StandardCrystals.all where seen.insert(s.name).inserted { out.append(PowderPhase(name: s.name, structure: s.structure)) }
        for other in openItems.items where other.id != item.id {
            let c = other.diffraction.crystal
            if seen.insert(c.name).inserted { out.append(PowderPhase(name: c.name, structure: c.structure)) }
        }
        return out
    }
}

/// The sticks: each peak from 0 to its intensity at its position, one colour a phase; the strongest of each phase is 100.
struct DiffractionPowderChart: View {
    let table: PowderTable

    private struct Stick: Identifiable {
        let id: String
        let phase: String
        let position: Double
        let intensity: Double
    }

    private var xTitle: String { table.settings.kind == .xray ? "2θ (°)" : "q (Å⁻¹)" }

    var body: some View {
        let sticks = table.rows.map { Stick(id: $0.id, phase: $0.phase, position: $0.position, intensity: $0.intensity) }
        let range = table.settings.range
        Chart(sticks) { stick in
            RuleMark(x: .value(xTitle, stick.position), yStart: .value("Intensity", 0), yEnd: .value("Intensity", stick.intensity))
                .foregroundStyle(by: .value("Phase", stick.phase))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXScale(domain: range.lowerBound...range.upperBound)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel(xTitle, alignment: .center)
        .chartYAxisLabel("I (of 100)")
        .chartLegend(table.phases.count > 1 ? .visible : .hidden)
        .frame(minHeight: LayoutPolicy.powderChartHeight)
        .accessibilityLabel("Powder pattern")
        .accessibilityValue(table.phases.indices.map { table.headline(phase: $0) }.joined(separator: ". "))
    }
}

/// The words of a peak line. Pure.
nonisolated enum DiffractionPowderText {
    /// "Al 111  d 2.338 Å  38.51°  100 ◆", or "… ⧉ Au" for a peak another phase overlaps.
    static func line(_ row: PowderRow, table: PowderTable) -> String {
        var parts = ["\(row.phase) \(row.hkl)", "d \(Num.fixed(row.d, 3)) Å", table.positionText(row.position), Num.fixed(row.intensity, 0)]
        if row.isDiagnostic { parts.append("◆") }
        if row.isOverlapped { parts.append("⧉ " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: "  ")
    }

    /// The line for VoiceOver: "Al 111, d 2.338 ångström, at 38.51°, intensity 100, diagnostic".
    static func spoken(_ row: PowderRow, table: PowderTable) -> String {
        var parts = ["\(row.phase) \(row.hkl)", "d \(Num.fixed(row.d, 3)) ångström", "at " + table.positionText(row.position),
                     "intensity \(Num.fixed(row.intensity, 0))"]
        if row.isDiagnostic { parts.append("diagnostic") }
        if row.isOverlapped { parts.append("overlapped by " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
