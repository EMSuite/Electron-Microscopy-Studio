//
//  DiffractionPrecipitateSection.swift
//  Role: the Diffraction room's Precipitate section (plan row R9, #808): a precipitate in the room's crystal, its relationship as a
//        paper states it (two parallel pairs, the first kept exact), every variant placed from Index's matrix orientation with
//        the ones that look alike in this view grouped, a Show switch per variant, and the shown variants' spots over the pattern.
//        Without a matrix orientation the section says so. Presentation only: the variants are `VariantPlacement`'s over
//        DiffractoKit. Nothing is chosen for the person (#1137): the precipitate is any phase the room can use (the library's,
//        a standard, another open pattern's crystal) and the relationship is typed as a paper states it; no literature example
//        is built in (#1147, #1152).
//

import ShellInspector
import ShellLayout
import ShellPhaseLibrary
import SwiftUI
import DiffractoCore
import TEMCore
import TEMSession

struct DiffractionPrecipitateSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    /// The added spots whose strongest route the section lists; the overlay draws up to the cap.
    private static let listedRoutes = 8

    var body: some View {
        let analysis = item.diffraction
        let variants = item.diffractionVariants
        let options = precipitates(besides: analysis.crystal.name)
        let result = variants.variants(analysis: analysis, image: item.session.imageOrBlank)
        InspectorSection("Precipitate", startsExpanded: false) {
            InspectorRow("Variants") {
                Toggle("Variants", isOn: Binding(get: { variants.isShown }, set: { variants.isShown = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Draws the shown variants' spots over the pattern as pink diamonds")
                    .accessibilityIdentifier("diffraction.precipitate.show")
            }
            InspectorRow("Precipitate") {
                Picker("Precipitate", selection: Binding(get: { variants.precipitate?.name ?? "" },
                                                         set: { name in variants.setPrecipitate(options.first { $0.name == name }) })) {
                    Text("None").tag("")
                    ForEach(options, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize()
                .help("The precipitate placed in \(analysis.crystal.name): a phase of the library, a standard, or the crystal of another open pattern")
                .accessibilityIdentifier("diffraction.precipitate.phase")
            }
            InspectorRow("Double diffraction") {
                Toggle("Double diffraction", isOn: Binding(get: { variants.doubleDiffraction }, set: { variants.doubleDiffraction = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Also draws, as dashed pink diamonds, the spots a beam diffracted by one crystal and again by another adds (g₁ + g₂ between the matrix and a variant)")
                    .accessibilityIdentifier("diffraction.precipitate.doubleDiffraction")
            }
            DiffractionRelationshipFields(relationship: variants.relationship, matrix: analysis.crystal.name) { variants.setRelationship($0) }
            switch result {
            case nil:
                if variants.inputs(analysis: analysis, image: item.session.imageOrBlank) == nil {
                    InspectorNote("Variants need the beam energy: type it under Calibration.")
                } else {
                    InspectorNote("Placing the variants…")
                }
            case .failure(let refusal)?:
                InspectorWarning(refusal.sentence)
            case .success(let set)?:
                InspectorNote(set.summarySentence)
                InspectorNote(set.sheetSentence)
                ForEach(set.lookAlikeSentences, id: \.self) { InspectorNote($0) }
                switch variants.addedSpots(analysis: analysis, image: item.session.imageOrBlank) {
                case .success(let added)?:
                    InspectorNote(added.countSentence)
                    ForEach(Array(added.spots.prefix(Self.listedRoutes).enumerated()), id: \.offset) { _, spot in
                        InspectorNote(spot.routes.first ?? "")
                    }
                case .failure(let refusal)?: InspectorWarning(refusal.sentence)
                case nil: EmptyView()
                }
                ForEach(set.rows) { row in
                    InspectorRow("Variant \(row.number)") {
                        Toggle(row.label, isOn: Binding(get: { !variants.hidden.contains(row.id) }, set: { variants.setHidden(row.id, !$0) }))
                            .toggleStyle(.checkbox)
                            .help("Group \(row.group + 1): variants of one group predict the same spots in this view")
                            .accessibilityIdentifier("diffraction.precipitate.variant\(row.number)")
                    }
                }
            }
        }
        .task(id: variants.inputs(analysis: analysis, image: item.session.imageOrBlank)) {
            if let inputs = variants.inputs(analysis: analysis, image: item.session.imageOrBlank) { await variants.place(inputs) }
        }
    }

    /// The library's phases, the standards and the crystals of the other open patterns, the matrix left out; the chosen one stays
    /// offered even when nothing else names it any more.
    private func precipitates(besides matrix: String) -> [DiffractionVariants.Precipitate] {
        var out = DiffractionPhases.precipitates(
            besides: matrix, library: PhaseServices.library.phases,
            others: appState.openItems.items.filter { $0.id != item.id }.map { ($0.diffraction.crystal.name, $0.diffraction.crystal.structure) })
        if let chosen = item.diffractionVariants.precipitate, chosen.name != matrix, !out.contains(where: { $0.name == chosen.name }) {
            out.append(chosen)
        }
        return out
    }
}

/// The relationship's two pairs as four fields, "(h k l)" or "[u v w]" each, committed on Return once all four are typed. A field
/// that is not a plane or a direction is named and the last relationship stays. Empty until the person types one or picks an
/// example.
private struct DiffractionRelationshipFields: View {
    let relationship: PrecipitateRelationship?
    let matrix: String
    let commit: (PrecipitateRelationship?) -> Void
    @State private var texts: [String] = []
    @State private var refusal: String?

    private var current: [String] {
        guard let relationship else { return ["", "", "", ""] }
        return [relationship.firstPrecipitate.text, relationship.firstMatrix.text, relationship.secondPrecipitate.text,
                relationship.secondMatrix.text]
    }

    var body: some View {
        let shown = texts.count == 4 ? texts : current
        Group {
            pair("First pair", shown, 0, help: "Kept exact: a plane or direction of the precipitate parallel to one of \(matrix)")
            pair("Second pair", shown, 2, help: "Fixes the turn about the first pair; the room says how far from parallel it lands")
            if let refusal { InspectorWarning(refusal) }
        }
        .onChange(of: relationship, initial: true) { texts = current; refusal = nil }
    }

    private func pair(_ title: String, _ shown: [String], _ i: Int, help: String) -> some View {
        InspectorRow(title) {
            HStack(spacing: 4) {
                field(shown, i, name: "\(title), precipitate")
                Text("∥").foregroundStyle(.secondary)
                field(shown, i + 1, name: "\(title), \(matrix)")
            }
            .help(help)
        }
    }

    private func field(_ shown: [String], _ i: Int, name: String) -> some View {
        TextField(name, text: Binding(get: { shown[i] }, set: { value in
            var t = shown
            t[i] = value
            texts = t
        }), prompt: Text("[u v w]"))
        .textFieldStyle(.roundedBorder)
        .frame(width: LayoutPolicy.precipitateIndexFieldWidth)
        .onSubmit(apply)
        .accessibilityLabel(name)
        .accessibilityIdentifier("diffraction.precipitate.pair\(i)")
    }

    private func apply() {
        guard texts.count == 4 else { return }
        if texts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            refusal = nil
            commit(nil)
            return
        }
        if texts.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            refusal = "Type all four: a plane (h k l) or a direction [u v w] in each field."
            return
        }
        let parsed = texts.map(RelationshipVector.parse)
        guard parsed.count == 4, let fp = parsed[0], let fm = parsed[1], let sp = parsed[2], let sm = parsed[3] else {
            let bad = zip(texts, parsed).first { $0.1 == nil }?.0 ?? ""
            refusal = "\"\(bad)\" is not a plane (h k l) or a direction [u v w]."
            return
        }
        refusal = nil
        commit(PrecipitateRelationship(first: (fp, fm), second: (sp, sm)))
    }
}
