//
//  DiffractionFigureSnapshot.swift
//  Role: File > Export Figure… in the Diffraction room (#822, plan row X6): the pattern on screen as a figure, PDF or SVG with live
//        text or PNG at 300 dpi, through `FigureExport.patternScene` (TEMCore): the picture as the room displays it (its log, window,
//        gamma and colormap), the measured rings and spots with their d, the simulated spots of the zone axis or of Index's
//        orientation with their hkl (the 60 strongest, `ZoneAxisOverlay.labelled`, with hkl labels not None: the room places its own
//        on screen since #1045), the centre, and a scale bar in Å⁻¹
//        from the room's scale. Taken when the panel opens, so the figure is what was on screen then.
//        A figure carries its key and its spot table (#823, plan row X7): Legend draws one row per kind of mark under the picture, Spot
//        table the readout's rows (number, family, d, listed d, misfit). Edit > Copy Figure, ⌘C on the pattern and its context menu put
//        the figure on the clipboard as PDF and PNG; the header's figure handle drags it out as a file; `get_diffraction_figure` gives
//        an agent the same figure as PNG. Those three draw it as the panel's defaults do: 90 mm, bar, labels, legend and table.
//

import DiffractoGeometry
import Foundation
import ImagoCore
import ShellExport
import TEMCore
import TEMSession

/// Everything the Diffraction room's Export Figure… needs.
nonisolated struct DiffractionFigureSnapshot: Sendable {
    let source: ExportSource
    let display: ImageExport.Display
    let overlay: FigureExport.PatternOverlay
    let defaultName: String
    let directory: URL?
    let hasLabels: Bool
    /// The readout as the figure's spot table (`FigureExport.tableRows`); empty without a ring or spot.
    let table: [[String]]
    /// The pattern's methods record, its export kind and drawn set made at the write; nil for a pattern read from no file.
    var methods: MethodsRecord?

    /// Whether the figure has a key to draw: a ring, a spot or a simulated spot.
    var hasLegend: Bool { !FigureExport.legendEntries(overlay).isEmpty }

    /// What the panel's OK does: the figure of this snapshot, `format` and `width` as chosen, the labels, the bar, the legend and the
    /// table as asked.
    func write(to url: URL, format: FigureExport.Format, width: FigureStyle.Width, scaleBar: Bool, labels: Bool, legend: Bool = false,
               table: Bool = false, leaveOutFileNames: Bool = false) async throws -> (scene: FigureScene, barLeftOut: Bool) {
        let named = ExportSnapshot.named(source: source, methods: methods, leaveOutFileNames: leaveOutFileNames)
        let record = methodsRecord(named.methods, kind: format.rawValue, scaleBar: scaleBar, labels: labels, legend: legend, table: table)
        return try await FigureExport.exportPattern(source: named.source, display: display, overlay: overlay, scaleBar: scaleBar, labels: labels,
                                                    width: width, extras: extras(legend: legend, table: table), format: format,
                                                    methods: record, to: url)
    }

    /// Copy Figure's and the drag's figure as PDF and PNG, drawn as the panel's defaults draw it (90 mm, bar, labels, legend, table);
    /// file names left out, since the copy goes wherever the person pastes it.
    func pictures() async throws -> (pdf: Data, png: Data) {
        let named = ExportSnapshot.named(source: source, methods: methods, leaveOutFileNames: true)
        let record = methodsRecord(named.methods, kind: "copy", scaleBar: true, labels: true, legend: true, table: true)
        return try await FigureExport.patternClipboard(source: named.source, display: display, overlay: overlay, scaleBar: true, labels: true,
                                                       width: .mm90, extras: extras(legend: true, table: true), methods: record)
    }

    /// The same figure as PNG at 300 dpi, drawn on the caller's actor: the agent door's `get_diffraction_figure`, whose tools answer
    /// at once. Bounded by the snapshot's refusal of a side a figure cannot take; a 90 mm figure is about 1063 px wide.
    func png() throws -> Data {
        let made = try FigureExport.patternScene(source: source, display: display, overlay: overlay, scaleBar: true, labels: true, width: .mm90,
                                                 extras: extras(legend: true, table: true))
        return try FigureExport.data(made.scene, format: .png, metadata: FigureMetadata(title: source.fileName, creator: source.software))
    }

    private func extras(legend: Bool, table: Bool) -> FigureExport.PatternExtras {
        FigureExport.PatternExtras(legend: legend, table: table ? self.table : [])
    }

    /// The figure's methods record: its export kind, and what it draws as asked.
    private func methodsRecord(_ methods: MethodsRecord?, kind: String, scaleBar: Bool, labels: Bool, legend: Bool, table: Bool) -> MethodsRecord? {
        var record = methods
        record?.exportKind = "diffraction-figure-\(kind)"
        var drawn = ["the pattern as displayed (log, window, gamma and colormap)", "the measured rings and spots", "the simulated spots"]
        if labels { drawn.append("the d of each ring and spot and the hkl of the simulated spots") }
        if scaleBar { drawn.append("the scale bar") }
        if legend, hasLegend { drawn.append("the legend") }
        if table, !self.table.isEmpty { drawn.append("the spot table") }
        record?.drawn = drawn
        return record
    }
}

extension ExportSnapshot {
    /// The Diffraction room's figure of the selected file; nil outside the room, without a pattern on screen, or above the side a
    /// figure takes.
    static func diffractionFigureSnapshot(of appState: AppState, software: String = softwareName()) -> DiffractionFigureSnapshot? {
        guard appState.navigation.workspaceArea == .diffraction, !appState.imageSession.isLoading, let item = appState.openItems.selected,
              let image = item.session.image, let canvas = item.diffractionView.presentation.canvas,
              canvas.width == image.width, canvas.height == image.height, refusal(width: image.width, height: image.height) == nil else {
            return nil
        }
        let analysis = item.diffraction
        let header = analysis.exportHeader(image: image)
        var source = ExportSource(image: image, software: software)
        // The room's scale, zero at its centre: the bar reads in Å⁻¹ as the room's readout does.
        if let deltaQ = header.deltaQ {
            source.x = AxisCalibration(scale: deltaQ, unit: "Å⁻¹", origin: header.centreColumn)
            source.y = AxisCalibration(scale: deltaQ, unit: "Å⁻¹", origin: header.centreRow)
        }
        let rows = analysis.readout(image: image)
        let labels = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, figureLabel($0)) })
        let rings = analysis.rings.compactMap { ring -> FigureExport.PatternOverlay.Measured? in
            guard let ellipse = ring.ellipse else { return nil }
            return FigureExport.PatternOverlay.Measured(points: RingOverlay.polyline(ellipse).map { ImagePoint(x: $0.x, y: $0.y) },
                                                        label: labels[ring.id] ?? "")
        }
        let spots = analysis.spots.compactMap { spot -> FigureExport.PatternOverlay.Measured? in
            guard let row = spot.row, let column = spot.column else { return nil }
            return FigureExport.PatternOverlay.Measured(points: [ImagePoint(x: column, y: row)], label: labels[spot.id] ?? "")
        }
        let simulated = (try? analysis.simulatedSpots(image: image)?.get()) ?? []
        let labelled = analysis.simulation.showsLabels ? ZoneAxisOverlay.labelled(simulated) : []
        let overlay = FigureExport.PatternOverlay(centre: analysis.centre.map { ImagePoint(x: $0.column, y: $0.row) }, rings: rings, spots: spots,
                                                  simulated: simulated, labelled: labelled)
        var snapshot = DiffractionFigureSnapshot(
            source: source, display: display(canvas: canvas, presentation: item.diffractionView.presentation), overlay: overlay,
            defaultName: imageName(fileName: image.fileName), directory: ExportPanels.defaultFolder(for: item.url),
            hasLabels: !rows.isEmpty || !labelled.isEmpty, table: FigureExport.tableRows(rows))
        if let identity = item.openedIdentity {
            let methodsSource = ExportMethods.source(ExportSource(image: image, software: software), byteCount: Int(identity.byteSize),
                                                     fingerprint: identity.pixelSHA256, kind: "image")
            snapshot.methods = ExportMethods.diffractionRecord(app: methodsApp(), source: methodsSource, header: header, rows: rows,
                                                               exportKind: "diffraction-figure")
        }
        return snapshot
    }

    /// Whether the Diffraction room's Export Figure… can act: a pattern on screen with its display built, no read running. Asked by
    /// the menu on every update, so it reads the state without building a snapshot.
    static func diffractionFigureAvailable(in appState: AppState) -> Bool {
        guard appState.navigation.workspaceArea == .diffraction, !appState.imageSession.isLoading, let item = appState.openItems.selected,
              let image = item.session.image, let canvas = item.diffractionView.presentation.canvas else { return false }
        return canvas.width == image.width && canvas.height == image.height
    }

    /// A ring's or spot's label in the figure: its d in Å, three decimals, and its family when indexed, as the room draws it.
    nonisolated static func figureLabel(_ row: DiffractionReadoutRow) -> String {
        guard let d = row.d else { return "" }
        let posix = Locale(identifier: "en_US_POSIX")
        return String(format: "d %.3f Å", locale: posix, d) + (row.family.map { " · \($0)" } ?? "")
    }
}
