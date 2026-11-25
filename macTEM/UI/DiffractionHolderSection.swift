//
//  DiffractionHolderSection.swift
//  Role: the Diffraction room's Holder section (plan row R16, #815; mockup brief 6 of the 2.4 design), after Index: α and β now
//        (from the file's stage tilts when it has both, else typed), the limits, the tilt axis (typed, or calibrated from another
//        open indexed pattern of the same crystal), a zone axis near the beam and the sentence for it. The Tilt List CSV is the Export section's (#922).
//        Presentation only: the numbers are `TiltPlanning`'s over DiffractoKit's holder and zone-axis map. Uncalibrated it says so
//        and shows no α or β for a zone axis. The zone-axis map (#814) above the picker picks the same `selected` zone axis.
//

import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct DiffractionHolderSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    /// The other pattern the tilt axis is calibrated from.
    @State private var partner: UUID?

    private static let degrees = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    /// The zone axes the picker offers: the nearest ones to the beam.
    private static let offeredCount = 16

    /// The nearest zone axes the picker offers, and the picked one when the map picked one further out: a selection always has its tag.
    static func offered(_ plan: TiltPlan, selected: SIMD3<Int>?) -> [TiltListRow] {
        var rows = Array(plan.rows.prefix(offeredCount))
        if let uvw = selected, !rows.contains(where: { $0.uvw == uvw }), let row = plan.row(uvw) { rows.append(row) }
        return rows
    }

    var body: some View {
        let analysis = item.diffraction
        let holder = item.diffractionHolder
        let image = item.session.imageOrBlank
        let settings = holder.settings
        let plan = holder.plan(analysis: analysis, image: image)
        let partners = partners(of: analysis)
        InspectorSection("Holder", startsExpanded: false) {
            InspectorRow("α now") {
                OptionalNumericField(title: "Alpha tilt now", value: settings.alphaDeg, format: Self.degrees, unit: "°") {
                    holder.setTilts(alphaDeg: $0, betaDeg: settings.betaDeg)
                }
                .help("The stage's α tilt when this pattern was recorded")
                .accessibilityIdentifier("diffraction.holder.alpha")
            }
            InspectorRow("β now") {
                OptionalNumericField(title: "Beta tilt now", value: settings.betaDeg, format: Self.degrees, unit: "°") {
                    holder.setTilts(alphaDeg: settings.alphaDeg, betaDeg: $0)
                }
                .help("The stage's β tilt when this pattern was recorded")
                .accessibilityIdentifier("diffraction.holder.beta")
            }
            InspectorNote(settings.source == .file ? "α and β from the file's stage readout." : "α and β typed.")
            InspectorRow("α limit") {
                OptionalNumericField(title: "Alpha limit", value: settings.alphaLimitDeg, format: Self.degrees, unit: "°") {
                    holder.setLimits(alphaDeg: $0, betaDeg: settings.betaLimitDeg)
                }
                .help("How far the holder tilts in α either way (30° by default)")
                .accessibilityIdentifier("diffraction.holder.alphaLimit")
            }
            InspectorRow("β limit") {
                OptionalNumericField(title: "Beta limit", value: settings.betaLimitDeg, format: Self.degrees, unit: "°") {
                    holder.setLimits(alphaDeg: settings.alphaLimitDeg, betaDeg: $0)
                }
                .help("How far the holder tilts in β either way (30° by default)")
                .accessibilityIdentifier("diffraction.holder.betaLimit")
            }
            InspectorRow("Tilt axis") {
                OptionalNumericField(title: "Tilt axis", value: settings.axisAngleDeg, format: Self.degrees, unit: "°",
                                     prompt: "Not calibrated") { holder.setAxis(degrees: $0) }
                    .help("The α axis in the pattern, degrees from down the rows toward along the columns; calibrate it from a second pattern")
                    .accessibilityIdentifier("diffraction.holder.axis")
            }
            InspectorRow("Calibrate from") {
                Picker("Calibrate from", selection: $partner) {
                    Text("None").tag(UUID?.none)
                    ForEach(partners, id: \.id) { other in Text(other.session.imageOrBlank.fileName).tag(Optional(other.id)) }
                }
                .labelsHidden().fixedSize()
                .disabled(partners.isEmpty)
                .help("Another open pattern of this crystal, indexed, at other stage tilts (10° or more apart is best)")
                .accessibilityIdentifier("diffraction.holder.partner")
            }
            InspectorActionRow {
                Button("Calibrate") {
                    guard let other = partners.first(where: { $0.id == partner }) else { return }
                    holder.calibrate(analysis: analysis, other: other.diffraction, otherHolder: other.diffractionHolder,
                                     otherName: other.session.imageOrBlank.fileName)
                }
                .disabled(analysis.indexOutcome?.orientation == nil || !partners.contains { $0.id == partner })
                .help("Finds the tilt axis from this pattern and the one chosen above")
                .accessibilityIdentifier("diffraction.holder.calibrate")
                Button("Clear") { holder.forgetAxis() }
                    .disabled(settings.axisAngleDeg == nil)
                    .help("Clears the tilt axis; α and β are then not said")
                    .accessibilityIdentifier("diffraction.holder.forget")
            }
            if let refusal = holder.calibrationRefusal { InspectorWarning(refusal) }
            if let plan {
                InspectorNote(plan.calibrationSentence)
                DiffractionZoneAxisMap(plan: plan, selected: Binding(get: { holder.selected }, set: { holder.selected = $0 }))
                    .frame(maxWidth: .infinity)
                InspectorRow("Zone axis") {
                    Picker("Zone axis", selection: Binding(get: { holder.selected.map(TiltPlanning.zoneText) ?? "" },
                                                           set: { id in holder.selected = plan.rows.first { $0.id == id }?.uvw })) {
                        Text("None").tag("")
                        ForEach(Self.offered(plan, selected: holder.selected)) { row in
                            Text("\(row.id)  \(Num.fixed(row.angleFromBeamDeg, 1))°").tag(row.id)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .help("A zone axis near the beam, nearest first: its angle from the beam and, with a calibrated axis, the tilts that bring it on")
                    .accessibilityIdentifier("diffraction.holder.zoneAxis")
                }
                if let uvw = holder.selected, let row = plan.row(uvw) { InspectorNote(plan.sentence(for: row)) }
            } else {
                InspectorNote("Index the pattern first: the zone axes and the tilts to them are placed from its orientation.")
            }
        }
    }

    /// The other open patterns indexed on the same crystal, each a calibration partner.
    /// The other open patterns of this crystal that Index found an orientation for.
    private func partners(of analysis: DiffractionAnalysis) -> [OpenItem] {
        appState.openItems.items.filter { other in
            other.id != item.id && other.diffraction.indexOutcome?.orientation != nil && other.diffraction.crystal.name == analysis.crystal.name
        }
    }
}
