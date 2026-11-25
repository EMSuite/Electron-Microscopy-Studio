//
//  SimulationRecordSection.swift
//  Role: the Info tab's Simulation section for a Simulation document's HRTEM or STEM image (#1043): the method line that names every
//        setting ("HRTEM · mp-149 [1 1 0] · 200 kV · 9.98 nm · defocus 61.33 nm · Cs 1 mm · …") and Copy Methods Paragraph. The line
//        is a record, not a setting (control placement §9: one secondary line per section), so it left the HRTEM and STEM sections,
//        where it was five lines of the faintest text among the controls. Presentation only; the words are SimulatoKit's.
//

import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationRecordSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        if let line = methodLine {
            InspectorSection("Simulation") {
                // The identifiers the HRTEM and STEM sections gave the line, which the door's coverage names.
                if DemoDocuments.isSTEM(item.url) {
                    InspectorNote(line).accessibilityIdentifier("simulation.stem.method")
                } else {
                    InspectorNote(line).accessibilityIdentifier("simulation.hrtem.method")
                }
                InspectorActionRow {
                    Button("Copy Methods Paragraph") { MethodsRecordExport.copyParagraph(appState: appState) }
                        .disabled(!MethodsRecordExport.isAvailable(in: appState))
                        .help("The methods record of this image as a paragraph for a paper's methods section, on the pasteboard")
                        .accessibilityIdentifier("simulation.record.copyParagraph")
                }
            }
        }
    }

    /// The HRTEM image's line once its image is current, the STEM image's once positions are done; nil otherwise.
    private var methodLine: String? {
        if let simulation = appState.simulationDocument(ofHRTEM: item) {
            let model = simulation.multislice
            guard !model.isComputing, model.computeFailure == nil, model.imageFailure == nil, let waves = model.exitWaves,
                  let index = model.shownThicknessIndex else { return nil }
            return HRTEMImage.methodLine(waves, thicknessIndex: index, defocusNM: model.effectiveDefocusNM, optics: model.optics)
        }
        if let simulation = appState.simulationDocument(ofSTEM: item) {
            let model = simulation.stem
            guard let scan = model.scan, !scan.isEmpty else { return nil }
            return scan.methodLine(band: model.band)
        }
        return nil
    }
}
