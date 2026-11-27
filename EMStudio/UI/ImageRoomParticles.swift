//
//  ImageRoomParticles.swift
//  Role: the Particles view, a section of the Image room's inspector: precipitates on
//        a 2D image, found by a threshold on the raw range (bright or dark objects), optional Gaussian smoothing, connected-component
//        labelling and the objects' moments, then counted (not on the edge, not below the minimum area). The image keeps its marks;
//        the objects are outlined over it (`ParticleOverlay`), the mask can be tinted while the settings are edited, and an object
//        table (its own window, `ParticleTableWindow`, so it stays beside the image) selects a row to outline it heavier (⌘C copies
//        the selected row, `ParticleTableFormat`); the pointer
//        readout names the object under the pointer (`ImageReadout`). Presentation only: the numbers are ImagoKit's through
//        `ParticleCompute`, held per file by `ParticleAnalysis` (TEMSession).
//

import ShellControls
import ShellInspector
import SwiftUI
import ImagoCore
import UniformTypeIdentifiers
import TEMCore
import TEMSession
import ShellEDXModel
import ShellSpectroscopy

struct ImageRoomParticlesSection: View {
    let item: OpenItem
    private var image: CalibratedImage { item.session.imageOrBlank }
    let rawRange: ClosedRange<Float>?
    /// The CSV the save panel writes: made when Export CSV… is pressed and dropped when the panel is done, so the body builds none.
    @State private var exportDocument: RoomExportFile?
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState

    private struct PreviewKey: Equatable { var settings: ParticleSettings; var on: Bool }

    var body: some View {
        let analysis = item.particles
        let settings = analysis.settings
        InspectorSection("Particles") {
            // First, under the header, so the table and the export are in view without scrolling past the settings.
            if analysis.report != nil {
                InspectorActionRow {
                    Button("Object Table…") { openWindow(id: ParticleTableWindow.id) }.accessibilityIdentifier("particles.table")
                    Button("Export CSV…") { export(analysis) }.accessibilityIdentifier("particles.export")
                }
            }
            SegmentedPicker(label: "Objects", items: ParticleSettings.Polarity.allCases.map { ($0, .title($0.title)) },
                            selection: Binding(get: { settings.polarity }, set: { new in analysis.setSettings { $0.polarity = new } }))
                .accessibilityIdentifier("particles.polarity")
            SegmentedPicker(label: "Threshold", items: ParticleSettings.Method.allCases.map { ($0, .title($0.title)) },
                            selection: Binding(get: { settings.method }, set: { new in analysis.setSettings { $0.method = new } }))
                .accessibilityIdentifier("particles.method")
            if settings.method == .otsu {
                InspectorNote(analysis.report.map { $0.settings.method == .otsu && analysis.isCurrent
                    ? "Otsu's level: \(ParticleFormat.number(Double($0.thresholdValue)))" : "Otsu's level is found with the objects." }
                    ?? "Otsu's level is found with the objects.")
            } else if let range = rawRange, range.upperBound > range.lowerBound {
                AdjustmentSlider("Level",
                                 value: Binding(get: { Double(range.lowerBound) + settings.thresholdFraction * Double(range.upperBound - range.lowerBound) },
                                                set: { v in analysis.setSettings { $0.thresholdFraction = (v - Double(range.lowerBound)) / Double(range.upperBound - range.lowerBound) } }),
                                 in: Double(range.lowerBound)...Double(range.upperBound),
                                 format: .number.precision(.significantDigits(1...5)), unit: "intensity")
                    .accessibilityIdentifier("particles.threshold")
            } else {
                InspectorWarning("The image has no range to threshold (constant or no finite value).")
            }
            InspectorRow("Smoothing σ") {
                OptionalNumericField(title: "Smoothing sigma", value: settings.sigma, format: FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...4)),
                                     unit: "px", prompt: "0") { v in analysis.setSettings { $0.sigma = v } }
                    .accessibilityIdentifier("particles.sigma")
            }
            SegmentedPicker(label: "Connectivity",
                            items: [(Segmentation.Connectivity.four, .title("4-connected")), (.eight, .title("8-connected"))],
                            selection: Binding(get: { settings.connectivity }, set: { new in analysis.setSettings { $0.connectivity = new } }))
                .accessibilityIdentifier("particles.connectivity")
            InspectorRow("Minimum area") {
                Stepper(value: Binding(get: { settings.minimumArea }, set: { new in analysis.setSettings { $0.minimumArea = new } }), in: 1...100_000) {
                    Text(verbatim: "\(settings.minimumArea) px²").monospacedDigit()
                }
                // The stepper's label is its value on screen ("12 px²"), which VoiceOver took for its name: named and valued here.
                .accessibilityLabel("Minimum area")
                .accessibilityValue(UnitDisplay.count(settings.minimumArea, "square pixel", "square pixels"))
                .accessibilityIdentifier("particles.minimumArea")
            }
            ParticleRegionRows(analysis: analysis, imageWidth: image.width, imageHeight: image.height)
            InspectorRow("Tint mask") {
                Toggle("Tint mask", isOn: Binding(get: { analysis.previewsMask }, set: { analysis.setPreviewsMask($0) }))
                    .labelsHidden().toggleStyle(.switch)
                    .help("Tint the pixels on the object side of the threshold while you edit the settings")
            }
            InspectorActionRow {
                Button(analysis.isComputing ? "Finding…" : "Show Objects") { analysis.analyse(image: image) }
                    .disabled(analysis.isComputing || rawRange == nil)
                    .accessibilityIdentifier("particles.show")
                if analysis.showsObjects { Button("Hide") { analysis.hideObjects() } }
            }
            if let failure = analysis.failure { InspectorWarning(failure, systemImage: "xmark.octagon.fill") }
            if let report = analysis.report {
                let scale = ParticleCompute.scale(of: image)
                if !analysis.isCurrent { InspectorWarning("The settings changed since these objects were found: Show Objects again.", systemImage: "arrow.triangle.2.circlepath") }
                InspectorNote(ParticleFormat.counts(report.summary))
                    .accessibilityIdentifier("particles.counts")
                    .accessibilityValue(String(report.summary.counted))
                InspectorNote(ParticleFormat.sizes(report.summary, scale: scale))
                InspectorNote(ParticleFormat.density(report.summary, scale: scale))
                    .accessibilityIdentifier("particles.density")
                if !scale.isCalibrated { InspectorNote("The image is not calibrated (or its pixels are not square): sizes are in pixels.") }
            } else if !analysis.isComputing {
                InspectorNote("Choose bright or dark objects and a threshold, then Show Objects.")
            }
            if let note = ParticleFormat.renderNote(notes: image.notes) { InspectorNote(note).accessibilityIdentifier("particles.renderNote") }
        }
        .task(id: PreviewKey(settings: settings, on: analysis.previewsMask)) {
            guard analysis.previewsMask else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { analysis.updatePreview(image: image) }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: ParticleExport.baseName(of: image.fileName)) { result in
            switch result {
            case .success(let url): appState.statusText = "Exported \(url.lastPathComponent)"
            case .failure(let error): appState.present(error)
            }
        }
    }

    /// `--export-dir` (a UI journey) writes without a panel, as the Diffraction readout does; otherwise the save panel, for the CSV
    /// as it is at this press (the one place it is built).
    private func export(_ analysis: ParticleAnalysis) {
        let text = csv(analysis)
        guard let directory = appState.exportDirectory else {
            exportDocument = RoomExportFile(text: text)
            return
        }
        do {
            let url = try ParticleExport.write(text, imageFileName: image.fileName, into: directory)
            appState.statusText = "Exported \(url.lastPathComponent)"
        } catch { appState.present(error) }
    }

    private func csv(_ analysis: ParticleAnalysis) -> String {
        analysis.report.map { ExportSnapshot.particlesCSV($0, image: image, openItems: appState.openItems) } ?? ""
    }
}

// MARK: - The table

nonisolated struct ParticleRow: Identifiable, Hashable, Sendable {
    let id: Int32
    let counted: Bool
    let note: String
    let area: Double
    let length: Double
    let width: Double
    let angle: Double

    init(_ o: ParticleObject, scale: ParticleScale) {
        id = o.id; counted = o.isCounted
        note = o.touchesEdge ? "edge" : ""
        area = Double(o.moments.area) * scale.perPixel * scale.perPixel
        length = o.moments.lengthPx * scale.perPixel
        width = o.moments.widthPx * scale.perPixel
        angle = o.moments.orientationDegrees
    }

    /// A row from its values as shown (lengths already in the scale's unit): what a test of the table's words builds without a report.
    init(id: Int32, counted: Bool, note: String, area: Double, length: Double, width: Double, angle: Double) {
        self.id = id
        self.counted = counted
        self.note = note
        self.area = area
        self.length = length
        self.width = width
        self.angle = angle
    }
}

private struct ParticleTableSheet: View {
    let analysis: ParticleAnalysis
    let report: ParticleReport
    let scale: ParticleScale
    @State private var countedOnly = false
    @State private var sortOrder = [KeyPathComparator(\ParticleRow.id)]
    @State private var rowsMemo = ParticleRowsMemo()

    var body: some View {
        // Made once per objects, filter and order, not again on every selection (#623): the body reads the selection.
        let rows = rowsMemo.rows(report.objects, scale: scale, countedOnly: countedOnly, sortOrder: sortOrder)
        // Read here, so Edit > Copy is offered and dimmed as the selection comes and goes.
        let selected = analysis.selectedLabel
        VStack(alignment: .leading, spacing: 10) {
            // A window: its title bar names it and closes it (⌘W), so no headline and no Done.
            HStack {
                Spacer()
                Toggle("Counted only", isOn: $countedOnly)
            }
            Table(rows, selection: Binding(get: { analysis.selectedLabel }, set: { analysis.selectedLabel = $0 }), sortOrder: $sortOrder) {
                TableColumn("#", value: \.id) { Text(verbatim: "\($0.id)").monospacedDigit() }.width(40)
                TableColumn("Length (\(scale.unit))", value: \.length) { Text(ParticleFormat.number($0.length)).monospacedDigit() }
                TableColumn("Width (\(scale.unit))", value: \.width) { Text(ParticleFormat.number($0.width)).monospacedDigit() }
                TableColumn("Angle (°)", value: \.angle) { Text(ParticleTableFormat.angle($0)).monospacedDigit() }
                TableColumn("Area (\(scale.unit)²)", value: \.area) { Text(ParticleFormat.number($0.area)).monospacedDigit() }
                TableColumn("Note") { Text(ParticleTableFormat.note($0)).foregroundStyle($0.counted ? Color.primary : Color.secondary) }
            }
            // ⌘C and Edit > Copy: the selected object's row under the column titles, tab-separated; dimmed with no row selected.
            .onCopyCommand(perform: rows.contains(where: { $0.id == selected }) ? { copied(rows, selected: selected) } : nil)
            .accessibilityIdentifier("particles.tableView")
            Text(ParticleFormat.counts(report.summary) + " · select a row to outline it on the image").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: EDXLayout.tableSheetMinimum.width, minHeight: EDXLayout.tableSheetMinimum.height)
    }

    /// What ⌘C hands the system: the selected row as the table shows it (`ParticleTableFormat.copyText`), nothing when none is.
    private func copied(_ rows: [ParticleRow], selected: Int32?) -> [NSItemProvider] {
        let picked = rows.filter { $0.id == selected }
        guard !picked.isEmpty else { return [] }
        return [NSItemProvider(object: ParticleTableFormat.copyText(picked, unit: scale.unit) as NSString)]
    }
}

// MARK: - The overlay

/// The tinted mask and the objects' ellipses over the image, mapped through the pane's own transform (`MarkGeometry`), so they keep
/// their stroke at any zoom. The ellipse of an object is its centroid, its major and minor axis lengths and its orientation (ImagoKit's
/// moments): counted objects solid, edge and small ones dashed and dim, the selected one heavier.
struct ParticleOverlay: View {
    let analysis: ParticleAnalysis
    let geometry: MarkGeometry
    @State private var tint: CGImage?
    @State private var pathsMemo = ParticleEllipseMemo()

    var body: some View {
        let report = analysis.showsObjects ? analysis.report : nil
        let preview = analysis.previewsMask ? analysis.maskPreview : nil
        let current = analysis.isCurrent
        let selected = analysis.selectedLabel
        // The ellipses are built once per objects and selection in image coordinates and placed per frame by one affine map (#623).
        let paths = report.map { pathsMemo.paths($0.objects, selected: selected) }
        let toPane = geometry.imageToPane
        Canvas { ctx, _ in
            if let tint, preview != nil {
                let a = geometry.panePoint(of: ImagePoint(x: -0.5, y: -0.5))
                let b = geometry.panePoint(of: ImagePoint(x: Double(geometry.imageWidth) - 0.5, y: Double(geometry.imageHeight) - 0.5))
                ctx.draw(Image(decorative: tint, scale: 1).interpolation(.none), in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
            }
            guard let paths else { return }
            let opacity = current ? 1.0 : 0.4
            ctx.stroke(paths.other.applying(toPane), with: .color(Color.gray.opacity(opacity)), style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
            ctx.stroke(paths.counted.applying(toPane), with: .color(Color.cyan.opacity(opacity)), style: StrokeStyle(lineWidth: 1.25))
            ctx.stroke(paths.selected.applying(toPane), with: .color(Color.yellow.opacity(opacity)), style: StrokeStyle(lineWidth: 2.5))
        }
        .allowsHitTesting(false)
        .task(id: preview?.version) {
            guard let preview else { tint = nil; return }
            let w = preview.width, h = preview.height, mask = preview.mask
            let made: CGImage? = await offMainActor {
                var rgba = [UInt8](repeating: 0, count: w * h * 4)
                for (i, on) in mask.enumerated() where on { rgba[4 * i] = 255; rgba[4 * i + 1] = 60; rgba[4 * i + 2] = 60; rgba[4 * i + 3] = 110 }
                guard let provider = CGDataProvider(data: Data(rgba) as CFData),
                      let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil as CGImage? }
                return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent)
            }
            // A newer preview cancelled this tint while it ran: it lands nothing over the newer one.
            guard !Task.isCancelled else { return }
            tint = made
        }
    }

    /// Adds the ellipse of `m` to `p` as its own closed subpath in image coordinates (pixel centres at whole numbers): 64 points round
    /// the centroid, the long axis turned from +x toward +y. `MarkGeometry.imageToPane` places it on the pane.
    static func addEllipse(_ o: ParticleObject, to p: inout Path) {
        let m = o.moments
        let a = m.axisMajorLength / 2, b = m.axisMinorLength / 2
        let t = m.orientationDegrees * .pi / 180
        for k in 0...64 {
            let s = Double(k) / 64 * 2 * .pi
            let u = a * cos(s), v = b * sin(s)
            let pt = CGPoint(x: o.centroidCol + u * cos(t) - v * sin(t), y: o.centroidRow + u * sin(t) + v * cos(t))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
    }
}

// MARK: - The region to analyse (#110)

/// The section's Region rows: where the region is ("Whole image" without one), Draw Region (the next drag on the image draws it, as
/// ImageJ's rectangle selection) and Whole Image (clears it). The drag itself is `ParticleRegionOverlay`'s.
struct ParticleRegionRows: View {
    let analysis: ParticleAnalysis
    /// The image's size only, never the image: a view holds no file's pixels (PixelOwnershipTests).
    let imageWidth: Int
    let imageHeight: Int

    var body: some View {
        let region = ParticleRegion.clamped(analysis.settings.region, width: imageWidth, height: imageHeight)
        let drawing = analysis.isDrawingRegion
        InspectorRow("Region") {
            Text(ParticleRegion.text(region)).monospacedDigit()
                .accessibilityIdentifier("particles.region")
        }
        InspectorActionRow {
            Button(drawing ? "Cancel Drawing" : "Draw Region") { analysis.setDrawingRegion(!drawing) }
                .help("Drag a rectangle on the image: only its pixels are analysed, and an object cut by its border is an edge object")
                .accessibilityIdentifier("particles.drawRegion")
            Button("Whole Image") { analysis.setRegion(nil); analysis.setDrawingRegion(false) }
                .disabled(region == nil)
                .help(region == nil ? "the whole image is analysed" : "Analyse the whole image again")
                .accessibilityIdentifier("particles.wholeImage")
        }
        if drawing { InspectorNote("Drag a rectangle on the image.") }
    }
}

/// The region to analyse over the image: a dashed outline on the pixel edges, and while Draw Region is on, the drag that draws it (the
/// pane's pan and zoom get every press otherwise). The region is the owner's setting; this view maps and writes.
struct ParticleRegionOverlay: View {
    let analysis: ParticleAnalysis
    let geometry: MarkGeometry

    var body: some View {
        let region = ParticleRegion.clamped(analysis.settings.region, width: geometry.imageWidth, height: geometry.imageHeight)
        let drawing = analysis.isDrawingRegion
        ZStack {
            Canvas { context, _ in
                guard let region else { return }
                let outline = Path(Self.rect(of: region, in: geometry))
                context.stroke(outline, with: .color(.black.opacity(0.6)), lineWidth: 4)
                context.stroke(outline, with: .color(.yellow), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .allowsHitTesting(false)
            if drawing {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { draw($0) }
                        .onEnded { draw($0); analysis.setDrawingRegion(false) })
                    .pointerStyle(.rectSelection)
            }
        }
        .accessibilityHidden(true)   // the section's Region row says where it is, and its buttons draw and clear it
    }

    private func draw(_ value: DragGesture.Value) {
        guard let crop = ParticleRegion.drawn(from: geometry.imagePoint(atPanePoint: value.startLocation),
                                              to: geometry.imagePoint(atPanePoint: value.location),
                                              width: geometry.imageWidth, height: geometry.imageHeight),
              crop != analysis.settings.region else { return }
        analysis.setRegion(crop)
    }

    /// The region's outline in pane points: the edges of its pixels.
    static func rect(of region: PixelCrop, in geometry: MarkGeometry) -> CGRect {
        let a = geometry.panePoint(of: ImagePoint(x: Double(region.col) - 0.5, y: Double(region.row) - 0.5))
        let b = geometry.panePoint(of: ImagePoint(x: Double(region.col + region.width) - 0.5, y: Double(region.row + region.height) - 0.5))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

/// The overlay's ellipses in image coordinates, one path per stroke style, made again only when the objects or the selection change
/// (#623), not per pan or zoom frame. Held in `@State`; not observed.
final class ParticleEllipseMemo {
    struct Paths {
        var counted = Path(), other = Path(), selected = Path()
    }
    private var objects: [ParticleObject]?
    private var selected: Int32?
    private var made = Paths()
    /// How many times the paths were built: a test pins that panning builds none.
    private(set) var builds = 0

    func paths(_ objects: [ParticleObject], selected: Int32?) -> Paths {
        if objects == self.objects, selected == self.selected { return made }
        var paths = Paths()
        for o in objects {
            if o.id == selected {
                ParticleOverlay.addEllipse(o, to: &paths.selected)
            } else if o.isCounted {
                ParticleOverlay.addEllipse(o, to: &paths.counted)
            } else {
                ParticleOverlay.addEllipse(o, to: &paths.other)
            }
        }
        self.objects = objects
        self.selected = selected
        made = paths
        builds += 1
        return paths
    }
}

/// The object table's rows, made again only when the objects, the scale, the Counted only filter or the order change (#623), not on
/// every selection. Held in `@State`; not observed.
final class ParticleRowsMemo {
    private var key: (objects: [ParticleObject], scale: ParticleScale, countedOnly: Bool, sortOrder: [KeyPathComparator<ParticleRow>])?
    private var made: [ParticleRow] = []
    /// How many times the rows were made: a test pins that a selection makes none.
    private(set) var builds = 0

    func rows(_ objects: [ParticleObject], scale: ParticleScale, countedOnly: Bool, sortOrder: [KeyPathComparator<ParticleRow>]) -> [ParticleRow] {
        if let key, key.objects == objects, key.scale == scale, key.countedOnly == countedOnly, key.sortOrder == sortOrder { return made }
        made = objects.map { ParticleRow($0, scale: scale) }.filter { !countedOnly || $0.counted }.sorted(using: sortOrder)
        key = (objects, scale, countedOnly, sortOrder)
        builds += 1
        return made
    }
}

// MARK: - The table's window

/// The object table of the selected file, in a window of its own (Window > Objects, or the section's Object Table… button): it stays
/// open beside the image while rows are selected, and follows the file selected in the main window. With no file or no objects it says so.
struct ParticleTableWindow: View {
    static let id = "particles"
    let appState: AppState

    var body: some View {
        Group {
            if let item = appState.openItems.selected, let image = item.session.image, let report = item.particles.report {
                ParticleTableSheet(analysis: item.particles, report: report, scale: ParticleCompute.scale(of: image))
            } else {
                ContentUnavailableView("No objects", systemImage: "circle.dashed",
                                       description: Text("Show Objects in the Image room's Particles section first."))
                    .frame(minWidth: EDXLayout.tableSheetMinimum.width, minHeight: EDXLayout.tableSheetMinimum.height)
            }
        }
        .environment(appState)
        // While it is key, File > Close (⌘W) and Close Window (⇧⌘W) close it (`CloseCommand`).
        .focusedSceneValue(\.isObjectsWindow, true)
    }
}
