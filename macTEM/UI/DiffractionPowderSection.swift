//
//  DiffractionPowderSection.swift
//  Role: the Diffraction room's Powder section (plan row R11, #810): the powder pattern of the room's crystal, and of one more phase
//        to compare with, as rings against q at the pattern's beam energy or as an X-ray pattern against 2θ at a chosen line. The
//        section holds the settings; the stick chart (one colour a phase, the strongest peak of a phase at 100) with the headline of
//        each phase and the overlap and diagnostic marks is the Powder Pattern pane, the peaks the Peaks table under the pattern
//        (#921, `DiffractionSidePane`); its two files are the Export section's (#922). Presentation only: every number is `PowderTable`'s over
//        DiffractoKit's `PowderPattern`. The Simulation document (R6, #788) takes the same table when it lands.
//

import Charts
import ShellInspector
import ShellLayout
import ShellPhaseLibrary
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
            if table.phases.count > 1 {
                InspectorRow("Mark overlaps") {
                    Toggle("Mark overlaps", isOn: Binding(get: { settings.markOverlaps }, set: { powder.setMarkOverlaps($0) }))
                        .toggleStyle(.switch).labelsHidden()
                        .help("Marks the peaks one phase shares with the other, and each phase's strongest peak that no other phase has")
                        .accessibilityIdentifier("diffraction.powder.markOverlaps")
                }
            }
            // The pattern, its headlines and its peaks are results: the Powder Pattern pane beside the pattern and the peaks table
            // under it in Powder, the part this section is shown in (#921, #1044).
            if table.patterns.contains(where: { $0 == nil }) {
                InspectorWarning("No pattern could be computed for a phase: the pane says why.")
            }
            InspectorNote("A line pattern for planning and comparison: no instrument profile, no texture, no absorption, no thermal motion.")
        }
    }

    /// The powder pattern the section draws and the Export section writes: the room's crystal and the phase it is compared with; none
    /// in a Simulation document that shows no phase (`SimulationEmptyState`), whose crystal is only the calibration standard.
    static func table(of item: OpenItem, openItems: OpenItems) -> PowderTable {
        let analysis = item.diffraction
        let phases = SimulationEmptyState.isShown(for: item) ? []
            : item.diffractionPowder.phases(crystal: analysis.crystal, others: comparable(for: item, openItems: openItems))
        return item.diffractionPowder.table(phases: phases, volts: analysis.volts(for: item.session.imageOrBlank))
    }

    /// The phases this crystal can be compared with: the library's phases (#1137), the room's standards, then the crystals of the
    /// other open patterns, each name once.
    static func comparable(for item: OpenItem, openItems: OpenItems, library: [Phase] = PhaseServices.library.phases) -> [PowderPhase] {
        var seen: Set<String> = [item.diffraction.crystal.name]
        var out: [PowderPhase] = []
        for p in DiffractionPhases.ordered(library) where seen.insert(p.name).inserted { out.append(PowderPhase(name: p.name, structure: p.structure())) }
        for s in StandardCrystals.all where seen.insert(s.name).inserted { out.append(PowderPhase(name: s.name, structure: s.structure)) }
        for other in openItems.items where other.id != item.id {
            let c = other.diffraction.crystal
            if seen.insert(c.name).inserted { out.append(PowderPhase(name: c.name, structure: c.structure)) }
        }
        return out
    }
}

/// The sticks: each peak from 0 to its intensity at its position, one colour and one dash a phase; the strongest of each phase is 100.
struct DiffractionPowderChart: View {
    let table: PowderTable

    private struct Stick: Identifiable {
        let id: String
        /// The phase's place in the table: 0 the room's crystal, 1 the one compared with.
        let phaseIndex: Int
        let position: Double
        let intensity: Double
    }

    private var xTitle: String { table.settings.kind == .xray ? "2θ (°)" : "q (Å⁻¹)" }

    /// The phases' colours, in the table's order; each phase has its dash as well (`OverlaySignal.powderPhase`, #923).
    static let phaseColours: [Color] = [.blue, .orange]

    var body: some View {
        let names = table.phases.map(\.name)
        let sticks = table.rows.map {
            Stick(id: $0.id, phaseIndex: $0.phaseIndex, position: $0.position, intensity: $0.intensity)
        }
        let range = table.settings.range
        VStack(alignment: .leading, spacing: 4) {
            Chart(sticks) { stick in
                RuleMark(x: .value(xTitle, stick.position), yStart: .value("Intensity", 0), yEnd: .value("Intensity", stick.intensity))
                    .foregroundStyle(Self.phaseColours[stick.phaseIndex % Self.phaseColours.count])
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: OverlaySignal.powderPhase(stick.phaseIndex).dash))
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: 0...100)
            .chartXAxisLabel(xTitle, alignment: .center)
            .chartYAxisLabel("I (of 100)")
            .frame(minHeight: LayoutPolicy.powderChartHeight)
            .accessibilityLabel("Powder pattern")
            .accessibilityValue(table.phases.indices.map { table.headline(phase: $0, locale: .autoupdatingCurrent) }.joined(separator: ". "))
            // The key: each phase's name beside a line in its colour and its dash, never a colour swatch alone.
            if names.count > 1 {
                HStack(spacing: 10) {
                    ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                        Label {
                            Text(name).font(.caption)
                        } icon: {
                            LegendLine(colour: Self.phaseColours[i % Self.phaseColours.count], dash: OverlaySignal.powderPhase(i).dash)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}

/// The words of a peak line. Pure.
nonisolated enum DiffractionPowderText {
    /// "Al 111  d 2.338 Å  38.51°  100 ◆", or "… ⧉ Au" for a peak another phase overlaps.
    static func line(_ row: PowderRow, table: PowderTable, locale: Locale = .autoupdatingCurrent) -> String {
        var parts = ["\(row.phase) \(row.hkl)", "d \(Num.fixed(row.d, 3, locale: locale)) Å", table.positionText(row.position, locale: locale),
                     Num.fixed(row.intensity, 0, locale: locale)]
        if row.isDiagnostic { parts.append("◆") }
        if row.isOverlapped { parts.append("⧉ " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: "  ")
    }

    /// The line for VoiceOver: "Al 111, d 2.338 ångström, at 38.51°, intensity 100, diagnostic".
    static func spoken(_ row: PowderRow, table: PowderTable) -> String {
        var parts = ["\(row.phase) \(row.hkl)", "d \(Num.fixed(row.d, 3)) ångström", "at " + table.positionText(row.position, locale: .autoupdatingCurrent),
                     "intensity \(Num.fixed(row.intensity, 0))"]
        if row.isDiagnostic { parts.append("diagnostic") }
        if row.isOverlapped { parts.append("overlapped by " + row.overlaps.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
