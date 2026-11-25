//
//  SimulationHRTEMTable.swift
//  Role: the defocus and thickness table of an HRTEM image (#895, plan row MA3; mockup brief section 2): defocus columns against
//        thickness rows, every cell labelled and the selected one outlined; a click selects a cell and returns its defocus and
//        thickness to the HRTEM section. Export Table writes the table, with its labels, as one PNG whose Description names every
//        setting. Each cell is `HRTEMImage.table`'s image at its settings, made at a small fixed field (`tableCellFieldNM`) off the
//        main actor once per change of the table's settings, and drawn grey with its own contrast range, as an HRTEM table is.
//        The columns are centred on the defocus the sheet opened at and stay there while cells are picked (Recentre moves them).
//
//        Departure from the brief: the table is a sheet over the Image room, not a Table view of the same pane; the image pane is
//        the room's one picture of the item, and the sheet keeps the image as it was behind it.
//

import CoreGraphics
import ShellControls
import ShellInspector
import ShellLayout
import SwiftUI
import TEMCore
import TEMSession
import UniformTypeIdentifiers

struct SimulationHRTEMTableSheet: View {
    let model: SimulationModel
    /// Called when a cell is picked, after the model takes its defocus and thickness.
    let picked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var centreNM: Double
    @State private var defocusStep = 10.0
    @State private var thicknessStep = 2.0
    @State private var columns = 5
    @State private var rows = 5
    @State private var made: Made?
    @State private var failure: String?
    @State private var exporting = false
    @State private var exportData = Data()

    init(model: SimulationModel, picked: @escaping () -> Void) {
        self.model = model
        self.picked = picked
        _centreNM = State(initialValue: model.effectiveDefocusNM)
    }

    /// What the table is made for: a change of any of these makes it again. The optics are the cells' (the document's at the
    /// cells' fixed field), so the document's field of view does not remake the table.
    private struct Key: Equatable {
        // periphery:ignore - read by the synthesized == (and hash)
        let waves: Int
        let optics: HRTEMOptics
        let centreNM: Double
        let defocusStep: Double
        let thicknessStep: Double
        let columns: Int
        let rows: Int
    }

    /// A made table: its labels, its cells as pictures (the cells' pixels are not kept), and the exported PNG's description.
    private struct Made {
        let key: Key
        let defocusNM: [Double]
        let thicknessIndices: [Int]
        let thicknessNM: [Double]
        let grey: [[CGImage?]]
        let description: String
    }

    private var key: Key {
        var cellOptics = model.optics
        cellOptics.fieldOfViewNM = HRTEMImage.tableCellFieldNM
        return Key(waves: model.wavesRevision, optics: cellOptics, centreNM: centreNM, defocusStep: defocusStep,
                   thicknessStep: thicknessStep, columns: columns, rows: rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            if let made, made.key == key {
                grid(made)
            } else if let failure {
                InspectorWarning("No table: \(failure)")
            } else if model.exitWaves == nil {
                Text("The exit waves are not computed yet.").foregroundStyle(.secondary)
            } else {
                ProgressView("Making the table…").controlSize(.small)
            }
            HStack {
                Button("Export Table…") {
                    guard let made, let data = Self.png(of: grid(made), description: made.description) else { return }
                    exportData = data
                    exporting = true
                }
                .disabled(made?.key != key)
                .accessibilityIdentifier("simulation.hrtem.table.export")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .help("Closes the table; a picked cell has already set the image")
            }
        }
        .padding(16)
        .frame(minWidth: LayoutPolicy.readableWidth, minHeight: LayoutPolicy.hrtemTableMinimumHeight)
        .roomExporter(isPresented: $exporting, data: exportData, contentType: .png, defaultFilename: "HRTEM table",
                      didWrite: { _ in }, didFinish: {})
        .task(id: key) { await make(key) }
    }

    /// Makes the table for `key` off the main actor; a newer key's task replaces this one.
    private func make(_ key: Key) async {
        guard let exit = model.exitWaves else { made = nil; return }
        failure = nil
        let defocus = HRTEMImage.defocusColumns(centreNM: key.centreNM, stepNM: key.defocusStep, count: key.columns)
        let thickness = HRTEMImage.thicknessRows(exit, stepNM: key.thicknessStep, count: key.rows)
        let cellOptics = key.optics
        let result: Result<(table: HRTEMImage.Table, cells: [[GreyCell]]), any Error> = await offMainActor {
            Result {
                let table = try HRTEMImage.table(exit, defocusNM: defocus, thicknessIndices: thickness, optics: cellOptics, name: "table")
                return (table, table.cells.map { $0.map(GreyCell.init) })
            }
        }
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let done):
            made = Made(key: key, defocusNM: done.table.defocusNM, thicknessIndices: done.table.thicknessIndices,
                        thicknessNM: done.table.thicknessNM, grey: done.cells.map { $0.map(\.image) },
                        description: HRTEMImage.tableDescription(done.table, exit: exit, optics: cellOptics))
        case .failure(let error):
            made = nil
            failure = ErrorDetail.text(error)
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Defocus step")
                OptionalNumericField(title: "Defocus step", value: defocusStep, format: stepFormat, unit: "nm") { if $0.isFinite, $0 > 0 { defocusStep = $0 } }
                    .accessibilityIdentifier("simulation.hrtem.table.defocusStep")
                Stepper("\(columns) defocus columns", value: $columns, in: HRTEMImage.tableCounts)
                    .accessibilityIdentifier("simulation.hrtem.table.columns")
                Button("Recentre") { centreNM = model.effectiveDefocusNM }
                    .disabled(centreNM == model.effectiveDefocusNM)
                    .help("Centres the columns on the defocus the image shows")
                    .accessibilityIdentifier("simulation.hrtem.table.recentre")
            }
            GridRow {
                Text("Thickness step")
                OptionalNumericField(title: "Thickness step", value: thicknessStep, format: stepFormat, unit: "nm") { if $0.isFinite, $0 > 0 { thicknessStep = $0 } }
                    .accessibilityIdentifier("simulation.hrtem.table.thicknessStep")
                Stepper("\(rows) thickness rows", value: $rows, in: HRTEMImage.tableCounts)
                    .accessibilityIdentifier("simulation.hrtem.table.rows")
            }
        }
    }

    private func grid(_ table: Made) -> some View {
        let selectedRow = table.thicknessIndices.firstIndex(of: model.shownThicknessIndex ?? -1)
        let selectedColumn = table.defocusNM.firstIndex { abs($0 - model.effectiveDefocusNM) < 1e-9 }
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("Thickness ↓ · Defocus →").font(.caption).foregroundStyle(.secondary)
                ForEach(table.defocusNM.indices, id: \.self) { c in
                    Text("\(UnitDisplay.number(table.defocusNM[c], digits: 4)) nm").font(.caption).monospacedDigit()
                }
            }
            ForEach(table.grey.indices, id: \.self) { r in
                GridRow {
                    Text("\(UnitDisplay.number(table.thicknessNM[r], digits: 3)) nm").font(.caption).monospacedDigit()
                    ForEach(table.grey[r].indices, id: \.self) { c in
                        Button {
                            model.setDefocus(nm: table.defocusNM[c])
                            model.setThicknessIndex(table.thicknessIndices[r])
                            picked()
                        } label: {
                            cell(table.grey[r][c], selected: r == selectedRow && c == selectedColumn)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Thickness \(UnitDisplay.number(table.thicknessNM[r], digits: 3)) nanometres, "
                                            + "defocus \(UnitDisplay.number(table.defocusNM[c], digits: 4)) nanometres")
                            .accessibilityIdentifier("simulation.hrtem.table.cell.\(r).\(c)")
                    }
                }
            }
        }
    }

    private func cell(_ image: CGImage?, selected: Bool) -> some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Color.black
            }
        }
        .frame(width: 88, height: 88)   // science: one image of the table, the size of a thumbnail
        .overlay { if selected { Rectangle().stroke(Color.accentColor, lineWidth: 2) } }
    }

    /// `view` rendered at twice its point size as PNG bytes through the app's one encoder, with `description` as its Description.
    static func png(of view: some View, description: String) -> Data? {
        let renderer = ImageRenderer(content: view.padding(12).background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return try? ImageExport.encodePNG(image, title: "HRTEM table", software: AppName.writer, description: description)
    }
}

/// A table cell as 8-bit grey pixels spanning its own finite minimum to maximum (a non-finite pixel draws black), made off the main
/// actor; its `CGImage` is made from them.
nonisolated struct GreyCell: Sendable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CalibratedImage) {
        let values = image.pixels
        let finite = values.filter(\.isFinite)
        let lo = finite.min() ?? 0, hi = finite.max() ?? 0
        let span = hi > lo ? hi - lo : 1
        width = image.width
        height = image.height
        bytes = values.map { v in v.isFinite ? UInt8(min(max((v - lo) / span * 255, 0), 255).rounded()) : 0 }
    }

    var image: CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

private let stepFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
