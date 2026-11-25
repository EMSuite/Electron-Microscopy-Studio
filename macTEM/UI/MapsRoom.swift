//
//  MapsRoom.swift
//  Role: the Maps room (docs/sem/design/orientation-maps-room.md §3, §6; brief P3-04; #1064): the map in the leading pane (the layer the
//        inspector's Maps section picks: IPF-Z, IPF-X, IPF-Y, Phase or a property of the file, one pixel per scan point, the marker at the
//        picked point, the scale bar from the step) with the picked point as a small inset in its top-trailing corner, opposite the scale
//        bar (the Patterns room's pattern there when the map came with its patterns, else the point's unit cell in the sample frame with
//        its Euler angles; Display › Pattern inset hides it), and the results in the trailing pane at full height (`MapsResultsPane`:
//        the colour key, Grains, Pole figures, ODF, Histogram). Presentation only: the pictures and words are `OrientationMaps`'
//        (TEMCore), the state `OrientationMapSession`'s (TEMSession).
//
//  P5-04 completes it: Segment (the toolbar's verb) adds the grain analysis' layers (Grains, KAM, GOS, GND, Schmid factor), the boundaries
//  and the selected grain's outline and slip traces over the map, and the Grains, Pole figures and ODF tabs beside the key
//  (`MapsRoomAnalysis.swift`).
//
//  ⌘-click on the map adds the grain under the pointer to the selection, or takes it out (macTEM#239).
//
//  PICK AND KEYS: as the Patterns room (`SEMMapPick.swift`, D-SEM-110): a click or a drag on the map at 1× and below picks the point under
//  it and the pattern or orientation pane follows (zoomed in, the marker's handle); the pointer over the map only writes the status line.
//  The room's root is the one focusable container, given the keyboard by any press on the map: ← → ↑ ↓ step the pick by one (⇧ by ten).
//

import ShellControls
import ShellLayout
import ShellMetal
import ShellSpectroscopy
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession

struct MapsRoom: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false

    private var importTypes: [UTType] { EBSDOpening.readableExtensions.compactMap { UTType(filenameExtension: $0) } }

    /// Whether the map is on the open EBSD dataset's scan (its own map, or an Indexing run on it): then the live pattern pane shows its
    /// patterns at the same point.
    private var patternsDataset: EBSDDataset? {
        guard let dataset = appState.ebsd.dataset, appState.maps.isOnScan(of: dataset) else { return nil }
        return dataset
    }

    /// The map with the picked point's inset: the pane the keys live on.
    private func upper(_ document: OrientationMapSession.Document) -> some View {
        MapPane(session: appState.maps, state: appState.mapsRoom, patterns: patternsDataset.map { _ in appState.ebsd }, map: document.map,
                staleness: appState.mapsStaleness)
    }

    var body: some View {
        let session = appState.maps
        let state = appState.mapsRoom
        Group {
            if session.isOpening {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(.linear).frame(maxWidth: EDXLayout.openingBarWidth)
                        .accessibilityLabel("Opening orientation map")
                    Text("Opening orientation map").font(.headline)
                    Button("Stop") { session.stop() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("maps.opening.stop")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("maps.opening")
            } else if let document = session.document {
                // The map leads; the results take the trailing pane at full height (#1064: in a strip under the map and the pattern they
                // were cut). No bottom strip.
                PaneSplit(storageKey: MapsRoomLayout.splitKey, resizeLabel: "Resize the map and the results", leadingName: "Map") {
                    upper(document)
                        // The keys live on the map; the results beside it sit outside this focusable container, so a click in the Grains
                        // table keeps the keyboard there (blue rows, ⌘C), as in the EELS room (#353).
                        .modifier(MapsKeyedRoom(session: session, patterns: patternsDataset.map { _ in appState.ebsd }))
                } trailing: {
                    MapsResultsPane(session: session, state: state)
                }
                .id(document.id)
            } else {
                ContentUnavailableView {
                    Label("No orientation map open", systemImage: "map")
                } description: {
                    Text("Open an indexed map (.ang, .ctf, an .h5oina saved without patterns, or orix's .h5) or an EBSD pattern file that carries one, or try the demo map from the Help menu.")
                } actions: {
                    Button("Open Orientation Map…") { state.requestImport() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("maps.openMap")
                }
            }
        }
        .onChange(of: state.importRequest) { showImporter = true }
        .roomImporter(isPresented: $showImporter, types: importTypes)
        .roomExporter(isPresented: Binding(get: { state.isExporting }, set: { state.isExporting = $0 }),
                      data: state.exportData, contentType: state.exportType, defaultFilename: state.exportName,
                      didWrite: { state.didWrite(to: $0) }, didFinish: { state.didFinishExport() })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maps.room")
    }
}

// MARK: - The layout

/// Where the Maps room puts what (#1064): the map in the leading pane, the results in the trailing pane at full height, nothing in a
/// strip under them; the picked point's inset in the map's top-trailing corner, opposite the scale bar in the footer's leading corner.
enum MapsRoomLayout {
    /// What a place of the room holds.
    enum Content: Equatable { case map, results }
    static let leading = Content.map
    static let trailing = Content.results
    /// The strip under the panes: none.
    static let bottom: Content? = nil
    /// The split's stored fraction: its own key, so the old map | pattern fraction does not size the results.
    static let splitKey = "maps.resultsSplit"
    static let insetAlignment = Alignment.topTrailing
    static let insetMargin: CGFloat = 6
    /// The picked point's inset side in a map box (#1089): at most a quarter of the box's shorter side, so a small map keeps most of
    /// its pixels (on the 117 × 100 duplex steel map in a narrow pane the inset and the keys hid more than half of it); never above
    /// `LayoutPolicy.mapsInsetSide`, and nil where it would be smaller than `smallestInsetSide` (the inset is then left out).
    static func insetSide(in box: CGSize) -> CGFloat? {
        let side = min(LayoutPolicy.mapsInsetSide, min(box.width, box.height) / 4 - 2 * insetMargin)
        return side >= smallestInsetSide ? side : nil
    }
    static let smallestInsetSide: CGFloat = 60
    /// Whether the map's box holds the inset (`insetSide`).
    static func fitsInset(in box: CGSize) -> Bool { insetSide(in: box) != nil }

    /// Each IPF key's width on the map (#1089): the keys of all `count` phases together take at most a third of the box's width,
    /// never above `LayoutPolicy.mapsKeyInsetWidth` each.
    static func keyWidth(in box: CGSize, count: Int) -> CGFloat {
        let share = box.width / 3 / CGFloat(max(count, 1)) - 2 * LayoutPolicy.mapsKeyLabelInset - 6
        return max(min(LayoutPolicy.mapsKeyInsetWidth, share), 32)
    }
}

// MARK: - The keys

/// The arrows step the picked point (⇧ ten), on the room's one focusable container (`SEMRoomFocus`); the pattern pane follows when the
/// map has patterns. On the Patterns room's scan the map and the pattern pane name one point: as the room shows, the map takes the point
/// picked in Patterns or Indexing, and the pane follows every change of the map's pick, whatever made it (the map, the arrows, ⌘-click,
/// a Grains-table row). A modifier of its own reads both picks, so the room's body does not run at a drag's rate.
private struct MapsKeyedRoom: ViewModifier {
    let session: OrientationMapSession
    let patterns: EBSDSession?
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .modifier(SEMRoomFocus())
            .onKeyPress(phases: .down) { press in
                guard let step = PatternsKeys.step(key: press.key, modifiers: press.modifiers) else { return .ignored }
                session.step(step.direction, by: step.count)
                patterns?.pin(session.pinned)
                return .handled
            }
            .onChange(of: patterns?.pinned, initial: true) { appState.mapsFollowPatternsPin() }
            .onChange(of: session.pinned) { appState.followMapsPin() }
    }
}

// MARK: - The map

/// The shown layer, one pixel per scan point, with the picked point's marker: a click or a drag at 1× picks the point (zoomed in, the
/// marker's handle) and the pattern or orientation pane follows; hovering only puts the point's phase, Euler angles and properties in the
/// status line.
struct MapPane: View {
    let session: OrientationMapSession
    let state: MapsRoomState
    /// The Patterns room's session when the map came with its patterns: the pick follows there too.
    let patterns: EBSDSession?
    let map: CrystalMap
    /// Why the map is stale, when it is an Indexing run the room has moved on from (D-SEM-99).
    var staleness: String? = nil
    @State var zoomModel = PaneZoomModel()
    private var zp: ZoomPan { zoomModel.state }

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geometry in
                content(in: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .clipped()
        // Any press on the pane gives the room the keyboard; an ancestor of the pick's, the pan's and ⌘-click's gestures, so it takes none.
        .modifier(SEMMapPress())
    }

    private var header: some View {
        let shape = session.gridShape
        return HStack(spacing: 8) {
            // DEPARTURE from control-placement §1 (#1065, approved by Paul 25 Nov 2026): the heading is the map picker, a menu of the
            // map kinds on the same property the inspector's Map row set; the heading names what the pane shows, and choosing it there
            // keeps the inspector to settings.
            Menu {
                Picker("Map", selection: Binding(get: { session.layer }, set: { session.setLayer($0) })) {
                    ForEach(session.layers) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(MapsRoomFormat.mapTitle(session.layer, stale: staleness != nil))
                    .font(.headline).lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.visible)
            .fixedSize()
            .help(staleness ?? "What the map draws: the IPF colours along a sample axis, the phases, a property of the file, or after Segment a grain map")
            .accessibilityIdentifier("maps.layer")
            Spacer(minLength: 8)
            if session.isDrawing {
                ProgressView().controlSize(.small).accessibilityLabel("Drawing the map")
            }
            Text(verbatim: "\(shape.columns) × \(shape.rows)")
                .help("Map columns × rows")
                .font(.caption.monospaced()).foregroundStyle(.secondary).fixedSize()
        }
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    private func content(in size: CGSize) -> some View {
        let shape = session.gridShape
        let box = LayoutPolicy.fitted(in: size, aspect: CGFloat(max(shape.columns, 1)) / CGFloat(max(shape.rows, 1)))
        let transform = MetalDisplayTransform(paneSize: box, imageBox: box, zoom: zp.drawZoom, offset: zp.effectiveOffset)
        let geometry = MarkGeometry(transform: transform, imageWidth: shape.columns, imageHeight: shape.rows)
        let mode = SEMMapPointer.mode(zoom: zp.effectiveZoom)
        let presentation = session.propertyPresentation
        let notIndexed = session.notIndexedCount
        return ZStack {
            ZStack {
                if let raster = session.raster, raster.rows == shape.rows, raster.columns == shape.columns {
                    if let rgba = session.rasterRGBA {
                        // An IPF or phase map: packed RGBA through the view's RGBA pipeline.
                        MetalImageView(pixels: [], width: raster.columns, height: raster.rows, contentVersion: session.rasterVersion, rgba: rgba)
                            .displayTransform(transform)
                            .frame(width: box.width, height: box.height)
                            .allowsHitTesting(false)
                    } else if let canvas = presentation.canvas {
                        // A property: the values through the Display section's colormap, window and gamma.
                        MetalImageView(pixels: canvas.values, width: canvas.width, height: canvas.height, contentVersion: canvas.contentVersion,
                                       colormap: presentation.colormap, displayLo: presentation.displayFractions.low,
                                       displayHi: presentation.displayFractions.high, gamma: Float(presentation.gamma), pixelScale: canvas.scale)
                            .displayTransform(transform)
                            .frame(width: box.width, height: box.height)
                            .allowsHitTesting(false)
                    }
                } else {
                    Rectangle().fill(.quaternary).frame(width: box.width, height: box.height)
                }
                if session.analysis != nil {
                    MapsAnalysisOverlay(session: session, geometry: geometry)
                        .frame(width: box.width, height: box.height)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("maps.grain.outline")
                }
                // At 1× and below a click or a drag anywhere picks, and ⌘-click is the scrub's own; zoomed in the drag is the pane's pan.
                if mode == .scrub {
                    SEMMapScrubLayer(geometry: geometry, zoomModel: zoomModel) { pick($0) } commandClick: { toggle($0) }
                }
                SEMScanMarker(position: session.pinned, geometry: geometry, isHandle: mode == .panAndGrab, identifier: "maps.map.marker",
                              pick: { pick($0) }, step: { session.step($0); patterns?.pin(session.pinned) })
            }
            .frame(width: box.width, height: box.height)
            .coordinateSpace(.named(SEMMapPointer.space))
            .clipped()
            .contentShape(Rectangle())
            // ⌘-click adds the grain under the point to the selection, or takes it out (macTEM#239). Zoomed in only, where no scrub is
            // mounted: at 1× and below it is the scrub's, so no gesture over the pick holds a plain click or drag back.
            .highPriorityGesture(SpatialTapGesture().modifiers(.command).onEnded { value in
                guard SEMMapPointer.isOnImage(value.location, geometry: geometry) else { return }
                toggle(SEMMapPointer.position(at: value.location, geometry: geometry))
            }, including: mode == .panAndGrab ? .all : .subviews)
            .border(.separator)
            .zoomPan(zoomModel, box: box, onHover: { phase in hovered(phase, geometry: geometry) })
            .zoomPanWheel(zoomModel, box: box)
            .zoomCommandTarget(zoomModel, isTarget: true)

            // The picked point beside the data it belongs to, opposite the scale bar (#1064); it takes no clicks, so the map under it
            // still picks.
            if state.showsPointInset, let side = MapsRoomLayout.insetSide(in: box) {
                MapsPointInset(session: session, patterns: patterns, side: side)
                    .padding(MapsRoomLayout.insetMargin)
                    .frame(width: box.width, height: box.height, alignment: MapsRoomLayout.insetAlignment)
                    .allowsHitTesting(false)
            }

            PaneFooter {
                if map.dx > 0 {
                    ScaleBar(unitsPerPoint: ImageScaleBar.unitsPerPoint(perPixel: map.dx, imageWidth: shape.columns, boxWidth: box.width, zoom: zp.drawZoom),
                             unitLabel: EBSDBrowsing.unitLabel(map.scanUnit))
                }
            } trailing: {
                HStack(alignment: .bottom, spacing: 8) {
                    // What the colours mean, always on the map (#1065), as the Indexing room's legend.
                    MapsKeyInset(session: session, keyWidth: MapsRoomLayout.keyWidth(in: box, count: session.keys.count))
                    if notIndexed > 0 {
                        Text(verbatim: "\(notIndexed) not indexed").font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                            .accessibilityIdentifier("maps.map.notIndexed")
                    }
                    if let text = ZoomPan.badgeText(zoom: zp.drawZoom), let spoken = ZoomPan.badgeSpoken(zoom: zp.drawZoom) {
                        Text(text).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.accentColor).fixedSize()
                            .accessibilityLabel(spoken)
                    }
                }
            }
        }
        .frame(width: box.width, height: box.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maps.map")
        .accessibilityLabel("Orientation map, \(session.layer.title)")
        .accessibilityValue(SEMMapPointer.spokenMap(rows: shape.rows, columns: shape.columns, at: session.pinned))
        .accessibilityHint(ZoomPan.accessibilityHint)
        .zoomPanAccessibilityActions(zoomModel, box: box)
    }

    /// A click, a drag or the handle picks `point`; the live pattern pane follows when the map has patterns.
    private func pick(_ point: EBSDPosition) {
        session.pin(point)
        patterns?.pin(session.pinned)
    }

    /// ⌘-click: the grain at `point` joins the selection or leaves it, and the point is picked; the live pattern pane follows.
    private func toggle(_ point: EBSDPosition) {
        session.toggleGrain(at: point)
        patterns?.pin(session.pinned)
    }

    /// The status line's readout of the point under the pointer: hovering reads, it never moves the pick (D-SEM-110).
    private func hovered(_ phase: HoverPhase, geometry: MarkGeometry) {
        switch phase {
        case .active(let p) where SEMMapPointer.isOnImage(p, geometry: geometry):
            state.readout = session.readout(at: SEMMapPointer.position(at: p, geometry: geometry))
        case .active, .ended:
            state.readout = nil
        }
    }
}

// MARK: - The picked point's inset

/// The picked point as a small inset on the map (#1064; before, half the room): the pattern there as the Patterns room shows it when the
/// map came with its patterns, else (design §3) the point's unit cell in the sample frame seen down z (x to the right, y down, as the
/// map) with its IPF colour, phase and Euler angles.
struct MapsPointInset: View {
    /// What `OrientationMapSession.orientation(at:)` gives for an indexed point.
    typealias PointOrientation = (phase: CrystalPhase, euler: SIMD3<Double>, rotation: SIMD4<Double>, rgb: SIMD3<Double>, direction: SampleDirection)

    let session: OrientationMapSession
    /// The Patterns room's session when the map is on its scan.
    let patterns: EBSDSession?
    /// The picture's side (`MapsRoomLayout.insetSide`).
    var side: CGFloat = LayoutPolicy.mapsInsetSide

    var body: some View {
        let point = session.pinned
        VStack(alignment: .leading, spacing: 3) {
            if let patterns {
                pattern(patterns, side: side)
                Text(verbatim: "row \(point.row) · col \(point.column)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(verbatim: "row \(point.row) col \(point.column)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("maps.orientation.title")
                if let found = session.orientation(at: point) {
                    cell(found, side: side)
                    // The angles' symbols are said in words (`SEMColumnSpeech`, #320); what is drawn is unchanged.
                    let euler = MapsRoomFormat.eulerValues(found.euler)
                    Text(verbatim: MapsRoomFormat.eulerLine(euler)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel(SEMColumnSpeech.spokenEuler(euler))
                        .accessibilityIdentifier("maps.orientation.values")
                } else {
                    Text("No indexed point here").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: side, height: side)
                }
            }
        }
        .frame(width: side, alignment: .leading)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(patterns == nil ? "Orientation at the picked point" : "Pattern at the picked point")
        .accessibilityIdentifier("maps.inset")
    }

    /// The Patterns room's pattern at the point, through its own Display (colormap, window, gamma).
    @ViewBuilder private func pattern(_ patterns: EBSDSession, side: CGFloat) -> some View {
        let presentation = patterns.patternPresentation
        if let canvas = presentation.canvas, canvas.width > 0, canvas.height > 0 {
            let box = LayoutPolicy.fitted(in: CGSize(width: side, height: side), aspect: CGFloat(canvas.width) / CGFloat(canvas.height))
            MetalImageView(pixels: canvas.values, width: canvas.width, height: canvas.height, contentVersion: canvas.contentVersion,
                           colormap: presentation.colormap, displayLo: presentation.displayFractions.low,
                           displayHi: presentation.displayFractions.high, gamma: Float(presentation.gamma), pixelScale: canvas.scale)
                .displayTransform(.identity(box))
                .frame(width: box.width, height: box.height)
                .frame(width: side, height: side)
                .accessibilityIdentifier("maps.inset.pattern")
        } else {
            Rectangle().fill(.quaternary).frame(width: side, height: side)
        }
    }

    /// The unit cell of the point's phase in the sample frame, far edges first and fainter, beside its IPF colour.
    private func cell(_ found: PointOrientation, side: CGFloat) -> some View {
        let edges = OrientationMaps.unitCellEdges(phase: found.phase, rotation: found.rotation)
        return Canvas { context, size in
            let scale = min(size.width, size.height) * 0.42
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // Far edges first and fainter, so the cell reads in depth (z into the sample is away from the viewer).
            for (a, b) in edges.sorted(by: { $0.0.z + $0.1.z > $1.0.z + $1.1.z }) {
                var path = Path()
                path.move(to: CGPoint(x: centre.x + a.x * scale, y: centre.y + a.y * scale))
                path.addLine(to: CGPoint(x: centre.x + b.x * scale, y: centre.y + b.y * scale))
                let depth = (a.z + b.z) / 2
                context.stroke(path, with: .color(.primary.opacity(depth > 0 ? 0.35 : 0.9)), lineWidth: depth > 0 ? 1 : 2)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: found.rgb.x, green: found.rgb.y, blue: found.rgb.z))
                .frame(width: LayoutPolicy.mapsPhaseSwatchSize, height: LayoutPolicy.mapsPhaseSwatchSize)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Unit cell of \(found.phase.name) in the sample frame, IPF-\(found.direction.rawValue.uppercased())")
        .accessibilityIdentifier("maps.orientation.cell")
    }
}

// MARK: - The colour key

/// Where an IPF key and its corner labels sit in the key cell (#725): the key between two label bands, a corner in the key's upper
/// half labelled in the band above it, one in the lower half in the band below, so no label covers the key ("[1̄11]" sat on the
/// triangle's top), and a margin either side for the corners on the key's left and right edges. The key on the map (#1065) is
/// `LayoutPolicy.mapsKeyInsetWidth` wide.
struct MapsKeyLayout {
    let imageWidth: Int
    let imageHeight: Int
    var width: CGFloat = LayoutPolicy.mapsKeyWidth

    /// A label line's height (caption2) plus a gap: the band above and below the key.
    static let band: CGFloat = 16

    var keySize: CGSize {
        CGSize(width: width, height: width * CGFloat(imageHeight) / CGFloat(max(imageWidth, 1)))
    }
    var keyOrigin: CGPoint { CGPoint(x: LayoutPolicy.mapsKeyLabelInset, y: Self.band) }
    var cellSize: CGSize {
        CGSize(width: keySize.width + 2 * LayoutPolicy.mapsKeyLabelInset, height: keySize.height + 2 * Self.band)
    }

    /// The centre of the label of the corner at key-image pixel (`column`, `row`).
    func labelCentre(column: Double, row: Double) -> CGPoint {
        let x = keyOrigin.x + CGFloat(column) * keySize.width / CGFloat(max(imageWidth, 1))
        let y = keyOrigin.y + CGFloat(row) * keySize.height / CGFloat(max(imageHeight, 1))
        let upper = row < Double(imageHeight) / 2
        return CGPoint(x: x, y: upper ? keyOrigin.y - Self.band / 2 : max(y, keyOrigin.y + keySize.height) + Self.band / 2)
    }
}

/// The colour key of the map in front, on the map's footer beside the zoom badge (#1065; it was a bottom tab that the strip cut): an
/// IPF layer's TSL key of each indexed phase with its corners labelled, Phase's colours with names and point counts, the grain map's
/// one line, or a value layer's colour bar over its window in the Display section's colormap.
struct MapsKeyInset: View {
    let session: OrientationMapSession
    /// Each IPF key's width (`MapsRoomLayout.keyWidth`).
    var keyWidth: CGFloat = LayoutPolicy.mapsKeyInsetWidth

    var body: some View {
        Group {
            switch MapsKeyKind.of(session.layer) {
            case .ipf(let direction):
                HStack(alignment: .bottom, spacing: 6) {
                    if session.keys.isEmpty, session.hasMap {
                        Text("No indexed phase with a point group: no colour key").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(session.keys) { key in
                        keyCell(key, direction: direction)
                    }
                }
                .plate()
            case .phases:
                phaseLegend.plate()
            case .grains:
                Text(verbatim: "Grains · " + (session.analysis.map { "\($0.table.count)" } ?? UnitDisplay.noValue)
                     + " · each its own colour, grey below the smallest, black not indexed")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: LayoutPolicy.mapsKeyInsetWidth * 2, alignment: .leading)
                    .plate()
            case .colourBar:
                colourBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maps.map.key")
    }

    /// The value layer's colour bar (ShellControls', on its own plate) over the window's two ends in the layer's own values.
    @ViewBuilder private var colourBar: some View {
        let presentation = session.propertyPresentation
        if let range = presentation.canvas?.rawRange {
            let span = Double(range.upperBound - range.lowerBound)
            let fractions = presentation.displayFractions
            Colorbar(colormap: presentation.colormap, low: Double(range.lowerBound) + Double(fractions.low) * span,
                     high: Double(range.lowerBound) + Double(fractions.high) * span, unitLabel: MapsRoomFormat.keyUnit(session.layer),
                     gamma: Float(presentation.gamma))
                .allowsHitTesting(false)
                .accessibilityIdentifier("maps.map.colourBar")
        }
    }

    private func keyCell(_ key: OrientationMapSession.PhaseKey, direction: SampleDirection) -> some View {
        let layout = MapsKeyLayout(imageWidth: key.image.width, imageHeight: key.image.height, width: keyWidth)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let image = MapsFigure.keyPicture(key) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layout.keySize.width, height: layout.keySize.height)
                        .offset(x: layout.keyOrigin.x, y: layout.keyOrigin.y)
                }
                ForEach(Array(key.labels.enumerated()), id: \.offset) { _, label in
                    Text(verbatim: label.text)
                        .font(.caption2.monospacedDigit())
                        .fixedSize()
                        .position(layout.labelCentre(column: label.column, row: label.row))
                }
            }
            .frame(width: layout.cellSize.width, height: layout.cellSize.height, alignment: .topLeading)
            Text(verbatim: session.keys.count > 1 ? "\(key.name) · IPF-\(direction.rawValue.uppercased())" : "IPF-\(direction.rawValue.uppercased())")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: layout.cellSize.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IPFKeySpeech.label(title: "Colour key of \(key.name), IPF-\(direction.rawValue.uppercased())",
                                               corners: key.labels.map { ($0.text, $0.colour) }))
        .accessibilityIdentifier("maps.key.\(key.phaseID)")
    }

    private var phaseLegend: some View {
        let map = session.map
        let counts = session.phasePointCounts
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(map?.phasesInData.entries ?? [], id: \.id) { entry in
                let rgb = entry.phase.colorRGB ?? .zero
                HStack(spacing: 6) {
                    Rectangle().fill(Color(red: rgb.x, green: rgb.y, blue: rgb.z))
                        .frame(width: LayoutPolicy.mapsPhaseSwatchSize, height: LayoutPolicy.mapsPhaseSwatchSize)
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
                    Text(verbatim: "\(MapsRoomFormat.phaseName(entry.phase, id: entry.id)) · "
                         + MapsRoomFormat.phasePoints(entry.phase, count: counts[entry.id] ?? 0, missing: UnitDisplay.noValue))
                        .font(.caption2.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("maps.legend.\(entry.id)")
            }
        }
    }
}

private extension View {
    /// The key's plate on the map, as the Indexing room's legend.
    func plate() -> some View {
        padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
    }
}
