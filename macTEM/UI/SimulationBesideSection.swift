//
//  SimulationBesideSection.swift
//  Role: the Beside Measured section of the Image room for a Simulation document's HRTEM image (#898, plan row MA6): Place Beside
//        picks an open measured image, Layout is Beside or Inset, Rotation turns the simulation, Inset size counts unit cells, and the
//        readout says both are at the measured image's nanometres per pixel (or the sentence when it has no calibration, or is
//        coarser than the simulation). The pair is drawn into the HRTEM image itself, so it exports as one figure with one scale bar.
//        Presentation only; the settings are `SimulationModel.beside` and the picture is `HRTEMBeside.composite`.
//
//        Departure from the design: Place Beside is a pop-up of the open images rather than a sheet or a drop on the pane, the
//        inspector's way of picking one of a few (process/control-placement.md); the rotation is a field without the drag handle,
//        which waits for the release walk's drive.
//

import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationBesideSection: View {
    let simulation: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        let model = simulation.multislice
        let beside = model.beside
        let candidates = appState.measuredImages()
        InspectorSection("Beside Measured") {
            InspectorRow("Place Beside") {
                Picker("Place Beside", selection: Binding(get: { beside?.measured },
                                                          set: { url in
                                                              set(url.flatMap { url in candidates.first { $0.url == url } }
                                                                  .map { appState.besideNaming($0, in: beside) })
                                                          })) {
                    Text("None").tag(URL?.none)
                    ForEach(candidates, id: \.id) { item in
                        Text(item.url.lastPathComponent).tag(Optional(item.url))
                    }
                }
                .labelsHidden()
                .disabled(candidates.isEmpty && beside == nil)
                .help(candidates.isEmpty ? "Open a measured image to place the simulation beside it"
                      : "Shows the simulation beside an open measured image, at the measured image's nanometres per pixel")
                .accessibilityIdentifier("simulation.beside.measured")
            }
            if let beside {
                InspectorRow("Layout") {
                    Picker("Layout", selection: Binding(get: { beside.layout }, set: { layout in
                        var new = beside
                        new.layout = layout
                        set(new)
                    })) {
                        ForEach(HRTEMBeside.Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Beside: the measured image left, the simulation right, as large. Inset: the simulation in its top right corner")
                    .accessibilityIdentifier("simulation.beside.layout")
                }
                InspectorRow("Rotation") {
                    OptionalNumericField(title: "Rotation", value: beside.rotationDegrees, format: rotationFormat, unit: "°") { degrees in
                        var new = beside
                        new.rotationDegrees = degrees
                        set(new)
                    }
                    .help("Turns the simulation counter-clockwise on screen, to line its lattice up with the measured one")
                    .accessibilityIdentifier("simulation.beside.rotation")
                }
                if beside.layout == .inset {
                    InspectorRow("Inset size") {
                        OptionalNumericField(title: "Inset cells across", value: beside.insetCells.x, format: .number) { count in
                            var new = beside
                            new.insetCells.x = count
                            set(new)
                        }
                        .accessibilityIdentifier("simulation.beside.insetAcross")
                        Text("×").foregroundStyle(.secondary).accessibilityHidden(true)
                        OptionalNumericField(title: "Inset cells down", value: beside.insetCells.y, format: .number, unit: "cells") { count in
                            var new = beside
                            new.insetCells.y = count
                            set(new)
                        }
                        .accessibilityIdentifier("simulation.beside.insetDown")
                    }
                    .help("The inset's size in unit cells of the simulated crystal, across and down, "
                          + "\(HRTEMBeside.insetCellRange.lowerBound) to \(HRTEMBeside.insetCellRange.upperBound)")
                }
                readout
            }
        }
        // The measured image opened, closed or read again: the picture follows it.
        .task(id: appState.besideKey(of: simulation)) { appState.refreshHRTEMImage(of: simulation) }
        // Closed: where its file is now, through the app's bookmark (#824).
        .task(id: linkKey) { await appState.resolveBesideLink(of: simulation) }
    }

    /// What the link's resolution reads: the link, and whether the measured image is open.
    private var linkKey: String? {
        guard let link = simulation.multislice.beside?.link else { return nil }
        return "\(link.id) \(link.fingerprint) \(appState.besideMeasuredItem(of: simulation) == nil)"
    }

    /// The readout under the controls: the scale both share, or the sentence when the pair cannot be drawn.
    @ViewBuilder
    private var readout: some View {
        switch appState.besideStatus(of: simulation) {
        case .off: EmptyView()
        case .shown(let scale, let coarser):
            InspectorNote(scale).accessibilityIdentifier("simulation.beside.scale")
            if coarser { InspectorNote(HRTEMBeside.coarser) }
            InspectorNote(HRTEMBeside.pairNote)
        case .closed(let name, let file?):
            InspectorNote(AppState.BesideStatus.closed(name, file: file).lines.joined(separator: " "))
            InspectorActionRow {
                Button("Open \(file.lastPathComponent)") { Task { await appState.openBeside(of: simulation, at: file) } }
                    .help("Opens the measured image's file again, where its link found it")
                    .accessibilityIdentifier("simulation.beside.open")
            }
        case .unlinked(let line, let different):
            InspectorWarning(line).accessibilityIdentifier("simulation.beside.refusal")
            InspectorActionRow {
                if different {
                    Button("Link Anyway") { Task { await appState.linkBesideAnyway(of: simulation) } }
                        .help("Names this file as the measured image from now on")
                        .accessibilityIdentifier("simulation.beside.linkAnyway")
                }
                Button("Locate…") { Task { await appState.locateBesideLink(of: simulation) } }
                    .help("Pick the measured image's file; a file with other contents is named as different")
                    .accessibilityIdentifier("simulation.beside.locate")
            }
        case let status:
            InspectorWarning(status.lines.joined(separator: " ")).accessibilityIdentifier("simulation.beside.refusal")
        }
    }

    private func set(_ new: HRTEMBeside?) {
        if simulation.multislice.setBeside(new) { appState.refreshHRTEMImage(of: simulation) }
    }
}

private let rotationFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
