//
//  DiffractionPrecipitateSection.swift
//  Role: the Diffraction room's Precipitate section (plan row R9, #808): a precipitate in the room's crystal, its relationship as a
//        paper states it (two parallel pairs, the first kept exact), every variant placed from Index's matrix orientation with
//        the ones that look alike in this view grouped, a Show switch per variant, and the shown variants' spots over the pattern.
//        Without a matrix orientation the section says so. Presentation only: the variants are `VariantPlacement`'s over
//        DiffractoKit. Until the multi-phase room (A2) holds the precipitate as a phase, it is chosen here.
//

import ShellInspector
import SwiftUI
import DiffractoCore
import TEMCore
import TEMSession

struct DiffractionPrecipitateSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        let analysis = item.diffraction
        let variants = item.diffractionVariants
        let options = precipitates(besides: analysis.crystal.name)
        let result = variants.variants(analysis: analysis, image: item.session.imageOrBlank)
        InspectorSection("Precipitate", startsExpanded: false) {
            InspectorRow("Show") {
                Toggle("Show variants", isOn: Binding(get: { variants.isShown }, set: { variants.isShown = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Draws the shown variants' spots over the pattern, in magenta")
                    .accessibilityIdentifier("diffraction.precipitate.show")
            }
            InspectorRow("Precipitate") {
                Picker("Precipitate", selection: Binding(get: { variants.precipitate.name },
                                                         set: { name in if let chosen = options.first(where: { $0.name == name }) { variants.setPrecipitate(chosen) } })) {
                    ForEach(options, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden().fixedSize()
                .help("The precipitate placed in this crystal: β″, a standard, or the crystal of another open pattern")
                .accessibilityIdentifier("diffraction.precipitate.phase")
            }
            DiffractionRelationshipFields(relationship: variants.relationship, matrix: analysis.crystal.name) { variants.setRelationship($0) }
            switch result {
            case nil:
                InspectorNote("Variants need the beam energy: type it under Calibration.")
            case .failure(let refusal)?:
                InspectorWarning(refusal.sentence)
            case .success(let set)?:
                InspectorNote(set.summarySentence)
                InspectorNote(set.sheetSentence)
                ForEach(set.lookAlikeSentences, id: \.self) { InspectorNote($0) }
                ForEach(set.rows) { row in
                    InspectorRow("Variant \(row.number)") {
                        Toggle(row.label, isOn: Binding(get: { !row.isHidden }, set: { variants.setHidden(row.id, !$0) }))
                            .toggleStyle(.checkbox)
                            .help("Group \(row.group + 1): variants of one group predict the same spots in this view")
                            .accessibilityIdentifier("diffraction.precipitate.variant\(row.number)")
                    }
                }
            }
        }
    }

    /// β″ first, then the room's standards and the crystals of the other open patterns, the matrix itself left out.
    private func precipitates(besides matrix: String) -> [DiffractionVariants.Precipitate] {
        var seen: Set<String> = [matrix]
        var out: [DiffractionVariants.Precipitate] = []
        func add(_ p: DiffractionVariants.Precipitate) { if seen.insert(p.name).inserted { out.append(p) } }
        add(.betaDoublePrime)
        StandardCrystals.all.forEach { add(.init(name: $0.name, structure: $0.structure)) }
        appState.openItems.items.filter { $0.id != item.id }.forEach {
            add(.init(name: $0.diffraction.crystal.name, structure: $0.diffraction.crystal.structure))
        }
        // The chosen one stays offered even when nothing else names it any more.
        add(item.diffractionVariants.precipitate)
        return out
    }
}

/// The relationship's two pairs as four fields, "(h k l)" or "[u v w]" each, committed on Return. A field that is not a plane or a
/// direction is named and the last relationship stays.
private struct DiffractionRelationshipFields: View {
    let relationship: PrecipitateRelationship
    let matrix: String
    let commit: (PrecipitateRelationship) -> Void
    @State private var texts: [String] = []
    @State private var refusal: String?

    private var current: [String] {
        [relationship.firstPrecipitate.text, relationship.firstMatrix.text, relationship.secondPrecipitate.text, relationship.secondMatrix.text]
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
        }))
        .textFieldStyle(.roundedBorder)
        .frame(width: 72)
        .onSubmit(apply)
        .accessibilityLabel(name)
        .accessibilityIdentifier("diffraction.precipitate.pair\(i)")
    }

    private func apply() {
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
