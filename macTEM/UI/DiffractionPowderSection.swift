//
//  DiffractionPowderSection.swift
//  Role: the Diffraction room's Powder section (plan row R11, #810): the powder pattern of the room's crystal, and of one more phase
//        to compare with, as rings against q at the pattern's beam energy or as an X-ray pattern against 2θ at a chosen line. A
//        stick chart (one colour a phase, the strongest peak of a phase at 100), the headline of each phase, the overlap and
//        diagnostic marks with two phases, and the peaks in a short table. Presentation only: every number is `PowderTable`'s over
//        DiffractoKit's `PowderPattern`. The Simulation document (R6, #788) takes the same table when it lands.
//

import Charts
import ShellInspector
import SwiftUI
import DiffractoCore
import DiffractoScattering
import TEMCore
import TEMSession

struct DiffractionPowderSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    private static let degrees = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    private static let reach = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
    /// The rows the section lists; the CSV has them all.
    private static let listed = 12

    var body: some View {
        let analysis = item.diffraction
        let powder = item.diffractionPowder
        let settings = powder.settings
        let others = comparable(besides: analysis.crystal.name)
        let phases = powder.phases(crystal: analysis.crystal, others: others)
        let table = powder.table(phases: phases, volts: analysis.volts(for: item.session.imageOrBlank))
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
                InspectorRow("Reach") {
                    OptionalNumericField(title: "Ring reach", value: settings.ringReach, format: Self.reach, unit: "Å⁻¹") {
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
            DiffractionPowderChart(table: table)
            ForEach(table.phases.indices, id: \.self) { i in
                if table.patterns[i] == nil { InspectorWarning(table.headline(phase: i)) } else { InspectorNote(table.headline(phase: i)) }
                if let marks = table.marksSentence(phase: i) { InspectorNote(marks) }
                if let lattice = table.calculatedLatticeSentence(phase: i) { InspectorNote(lattice) }
            }
            DiffractionPowderPeakList(table: table, limit: Self.listed)
            InspectorNote("A line pattern for planning and comparison: no instrument profile, no texture, no absorption, no thermal motion.")
        }
    }

    /// The phases this crystal can be compared with: the room's standards, then the crystals of the other open patterns, each name once.
    private func comparable(besides name: String) -> [PowderPhase] {
        var seen: Set<String> = [name]
        var out: [PowderPhase] = []
        for s in StandardCrystals.all where seen.insert(s.name).inserted { out.append(PowderPhase(name: s.name, structure: s.structure)) }
        for other in appState.openItems.items where other.id != item.id {
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
        .frame(height: 140)
        .accessibilityLabel("Powder pattern")
        .accessibilityValue(table.phases.indices.map { table.headline(phase: $0) }.joined(separator: ". "))
    }
}

/// The strongest peaks, strongest first: hkl, d, position and intensity, with ⧉ for an overlapped peak and ◆ for a diagnostic one.
struct DiffractionPowderPeakList: View {
    let table: PowderTable
    let limit: Int

    var body: some View {
        let rows = table.rows.sorted { $0.intensity > $1.intensity }
        let shown = rows.prefix(limit)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown), id: \.id) { row in
                Text(DiffractionPowderText.line(row, table: table))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(row.isDiagnostic ? .primary : .secondary)
                    .accessibilityLabel(DiffractionPowderText.spoken(row, table: table))
            }
            if rows.count > shown.count {
                InspectorNote("\(rows.count - shown.count) weaker peaks are in the CSV.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The words of a peak line. Pure.
nonisolated enum DiffractionPowderText {
    /// "Al 111  d 2.338 Å  38.51°  100 ◆", or "… ⧉ Au" for a peak another phase overlaps.
    static func line(_ row: PowderRow, table: PowderTable) -> String {
        var parts = ["\(row.phase) \(row.hkl)", String(format: "d %.3f Å", row.d), table.positionText(row.position), String(format: "%.0f", row.intensity)]
        if row.isDiagnostic { parts.append("◆") }
        if row.isOverlapped { parts.append("⧉ " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: "  ")
    }

    /// The line for VoiceOver: "Al 111, d 2.338 ångström, at 38.51°, intensity 100, diagnostic".
    static func spoken(_ row: PowderRow, table: PowderTable) -> String {
        var parts = ["\(row.phase) \(row.hkl)", String(format: "d %.3f ångström", row.d), "at " + table.positionText(row.position),
                     String(format: "intensity %.0f", row.intensity)]
        if row.isDiagnostic { parts.append("diagnostic") }
        if row.isOverlapped { parts.append("overlapped by " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
