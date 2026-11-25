//
//  MapsRoomAnalysis.swift
//  Role: what the Maps room shows of its grain analysis and texture (docs/sem/design/orientation-maps-room.md §3-§4, brief P5-04): the
//        boundaries, the selected grain's outline and its slip traces over the map; the results pane's tabs beside the map (Grains,
//        Pole figures, ODF, Histogram; #1064, #1065); and the inspector's Misorientation, Grains, Slip and Texture sections. Presentation only: the numbers are `MapAnalysis` and
//        `MapTexture`'s (TEMCore), the state `OrientationMapSession`'s (TEMSession), the words `MapsRoomFormat`'s.
//

import ShellControls
import ShellInspector
import ShellLayout
import ShellMetal
import SwiftUI
import TEMCore
import TEMSession

// MARK: - The overlay on the map

/// Grain boundaries (white), phase boundaries (black), the selected grain's outline (the accent colour) and its slip traces through its
/// centroid (each plane in DefDAP's trace colour), drawn in the map's own pixel coordinates through the pane's zoom.
struct MapsAnalysisOverlay: View {
    let session: OrientationMapSession
    let geometry: MarkGeometry
    /// Increase Contrast thickens the overlay lines (#799).
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let high = contrast == .increased
        let boundary = OverlaySignal.width(LayoutPolicy.mapsBoundaryLineWidth, increasedContrast: high)
        Canvas { context, size in
            if session.showsBoundaries {
                // A phase boundary is wider as well as black (#799).
                context.stroke(path(session.grainBoundaryEdges), with: .color(.white.opacity(0.9)),
                               lineWidth: boundary * OverlaySignal.grainBoundary.widthScale)
                context.stroke(path(session.phaseBoundaryEdges), with: .color(.black),
                               lineWidth: boundary * OverlaySignal.phaseBoundary.widthScale)
            }
            if !session.selectedOutline.isEmpty {
                context.stroke(path(session.selectedOutline), with: .color(.accentColor),
                               lineWidth: OverlaySignal.width(LayoutPolicy.mapsOutlineLineWidth, increasedContrast: high))
            }
            if session.showsSlipTraces, let row = session.selectedRow, let slip = session.selectedSlip {
                let half = max(3, (Double(row.points)).squareRoot() / 2)
                let planes = slip.planes.filter { $0.traceAngle.isFinite }
                var ends: [(CGPoint, CGPoint)] = []
                for plane in planes {
                    let d = MapsRoomFormat.traceDirection(plane.traceAngle) * half
                    let start = geometry.panePoint(of: ImagePoint(x: row.centroid.x - d.x, y: row.centroid.y - d.y))
                    let end = geometry.panePoint(of: ImagePoint(x: row.centroid.x + d.x, y: row.centroid.y + d.y))
                    ends.append((start, end))
                    var p = Path()
                    p.move(to: start)
                    p.addLine(to: end)
                    context.stroke(p, with: .color(Self.traceColour(plane.colour)),
                                   lineWidth: OverlaySignal.width(LayoutPolicy.mapsTraceLineWidth, increasedContrast: high))
                }
                // Each trace names its plane beside it, so the traces are told apart without their colours (#799); the plates are
                // placed one by one inside the map, clear of each other and of the picked point's marker (#1059: a grain in the
                // corner piled them on one point).
                let words = planes.map { context.resolve(Text($0.label).font(.caption.monospacedDigit()).foregroundStyle(.white)) }
                let plates = words.map { word -> CGSize in
                    let measured = word.measure(in: CGSize(width: 200, height: 40))
                    return CGSize(width: measured.width + 6, height: measured.height + 2)
                }
                let spots = zip(ends, plates).map { EBSDOverlayLabels.traceSpots(from: $0.0.0, to: $0.0.1, size: $0.1) }
                let marker = geometry.panePoint(of: ImagePoint(x: Double(session.pinned.column), y: Double(session.pinned.row)))
                let side = SEMScanMarker.handleDiameter
                let clear = CGRect(x: marker.x - side / 2, y: marker.y - side / 2, width: side, height: side)
                for placed in EBSDOverlayLabels.place(sizes: plates, spots: spots, in: CGRect(origin: .zero, size: size), avoiding: [clear]) {
                    context.fill(Path(roundedRect: placed.frame, cornerRadius: 3), with: .color(.black.opacity(0.65)))
                    context.draw(words[placed.index], at: CGPoint(x: placed.frame.midX, y: placed.frame.midY))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(spokenLabel)
    }

    /// "Grain 12 outlined, boundaries shown (grain boundaries white, phase boundaries black), traces (111) in blue, …", "3 grains
    /// outlined, …", or the boundaries alone: what each colour on the overlay means, in words (#356).
    private var spokenLabel: String {
        let boundaries = session.showsBoundaries ? "boundaries shown (grain boundaries white, phase boundaries black)" : "boundaries hidden"
        let count = session.selectedGrains.count
        var text = "Grain " + boundaries
        if count > 1 {
            text = "\(count) grains outlined, " + boundaries
        } else if let grain = session.selectedGrain {
            text = "Grain \(grain) outlined, " + boundaries
        }
        if session.showsSlipTraces, session.selectedRow != nil, let slip = session.selectedSlip,
           let traces = MapsRoomFormat.tracesSpeech(slip.planes) {
            text += ", " + traces
        }
        return text
    }

    /// DefDAP's matplotlib trace colour names as colours.
    static func traceColour(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": .blue
        case "green": .green
        case "red": .red
        case "purple": .purple
        case "orange": .orange
        case "yellow": .yellow
        case "cyan": .cyan
        case "magenta", "m": .pink
        case "white", "w": .white
        case "gray", "grey": .gray
        case "brown": .brown
        default: .black
        }
    }

    private func path(_ edges: [(SIMD2<Double>, SIMD2<Double>)]) -> Path {
        var p = Path()
        for (a, b) in edges {
            p.move(to: geometry.panePoint(of: ImagePoint(x: a.x, y: a.y)))
            p.addLine(to: geometry.panePoint(of: ImagePoint(x: b.x, y: b.y)))
        }
        return p
    }
}

// MARK: - The results pane

/// The results pane's tabs (design §3; the trailing pane at full height since #1064): the grain table, the pole figures with the IPF
/// density, the ODF sections, the histogram. The colour key is on the map (#1065).
enum MapsResultsTab: String, CaseIterable, Identifiable {
    case grains = "Grains"
    case poleFigures = "Pole figures"
    case odf = "ODF"
    case histogram = "Histogram"
    var id: String { rawValue }
}

struct MapsResultsPane: View {
    let session: OrientationMapSession
    @Bindable var state: MapsRoomState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Full width, as every segmented control (control-placement §3, #629): MacEMUI's `SegmentedControl`, because a
                // segmented `Picker` keeps its own width whatever frame it is given (the drive of 16 Nov saw it stay 480 pt and centred).
                // Alone in its row, so the tabs keep their width whichever is chosen (#1060): a tab's one choice (the histogram's
                // kind, the texture's phase) is on that tab's own header line.
                SegmentedControl(label: "Results", segments: MapsResultsTab.allCases.map { .title($0.rawValue) },
                                 selection: Binding(get: { MapsResultsTab.allCases.firstIndex(of: state.resultsTab) ?? 0 },
                                                    set: { if MapsResultsTab.allCases.indices.contains($0) { state.resultsTab = MapsResultsTab.allCases[$0] } }))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("maps.results.tabs")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .fixedSize(horizontal: false, vertical: true)
            Group {
                switch state.resultsTab {
                case .grains: MapsGrainsTable(session: session)
                case .poleFigures: MapsTextureFigures(session: session, odf: false)
                case .odf: MapsTextureFigures(session: session, odf: true)
                case .histogram: MapsHistogramPane(session: session, state: state)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)   // science: the figures fit (#1060)
        }
        // The tabs stay at the top of the pane whatever its height: centred, they moved with each tab's content and, with the Output pane
        // open, a figure taller than the pane pushed them out of view (drive 2026-11-08). The minimum height of 0 keeps a tall figure from
        // moving the split; the texture figures size themselves to the pane (`MapsTextureLayout`, #1060).
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)   // science: no minimum, never a size
        .clipped()
    }
}

struct MapsTexturePhasePicker: View {
    let session: OrientationMapSession

    var body: some View {
        let phases = session.texturePhases
        if phases.count > 1 {
            Picker("Phase", selection: Binding(get: { session.texturePhaseID ?? phases[0].id }, set: { _ = session.showTexture(phaseID: $0) })) {
                ForEach(phases, id: \.id) { Text(MapsRoomFormat.phaseName($0.phase, id: $0.id)).tag($0.id) }
            }
            .fixedSize()
            .help("The phase whose texture the figures show")
            .accessibilityIdentifier("maps.texture.phase")
        }
    }
}

// MARK: The grain table

/// One row per grain (design §3, Grains tab): number, phase, size, equivalent diameter, mean orientation, GOS, neighbours. Selecting a row
/// outlines the grain and pins its point nearest its centroid; pinning a point selects its grain. ⌘C copies the selected rows (⌘A: all) as
/// TSV in the table's order (`GrainTableFormat`, #353); the symbol headers are said in words (`SEMColumnSpeech`, #320).
struct MapsGrainsTable: View {
    let session: OrientationMapSession
    @State private var sortOrder = [KeyPathComparator(\GrainRow.id)]
    @State private var rows: [GrainRow] = []
    @FocusState private var tableFocused: Bool
    @State private var personPicked = false

    var body: some View {
        Group {
            if let analysis = session.analysis {
                let unit = EBSDBrowsing.unitLabel(analysis.scanUnit)
                let places = MapsRoomFormat.lengthPlaces(analysis)
                VStack(alignment: .leading, spacing: 4) {
                    // The grain statistics and the settings they were made with: results in the room, not the inspector (#1066).
                    Text(verbatim: MapsRoomFormat.grainHeadline(analysis))
                        .font(.callout.monospacedDigit())
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("maps.grains.summary")
                    Text(verbatim: "Made with " + MapsRoomFormat.madeWith(analysis.settings))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityIdentifier("maps.grains.madeWith")
                    // The person's selection takes the keyboard for the table (#353); a ⌘-click on the map selects grains through the
                    // session and leaves the keys with the map.
                    Table(rows, selection: Binding(get: { session.selectedGrains }, set: { picked in
                        personPicked = true
                        session.selectGrains(picked)
                    }), sortOrder: $sortOrder) {
                        TableColumn("Grain", value: \.id) { Text(verbatim: "\($0.id)").monospacedDigit() }
                        TableColumn("Phase", value: \.phaseName)
                        TableColumn("Points", value: \.points) { Text(verbatim: "\($0.points)").monospacedDigit() }
                        TableColumn(SEMColumnSpeech.header("ECD \(unit)"), value: \.diameter) {
                            Text(MapsRoomFormat.length($0.diameter, places: places)).monospacedDigit()
                        }
                        TableColumn(SEMColumnSpeech.header("φ₁ °"), value: \.phi1) { Text(MapsRoomFormat.angle($0.phi1)).monospacedDigit() }
                        TableColumn(SEMColumnSpeech.header("Φ °"), value: \.capitalPhi) { Text(MapsRoomFormat.angle($0.capitalPhi)).monospacedDigit() }
                        TableColumn(SEMColumnSpeech.header("φ₂ °"), value: \.phi2) { Text(MapsRoomFormat.angle($0.phi2)).monospacedDigit() }
                        TableColumn(SEMColumnSpeech.header("GOS °"), value: \.gosDegrees) {
                            Text(MapsRoomFormat.angle($0.gosDegrees, digits: 2)).monospacedDigit()
                        }
                        TableColumn("Schmid") { row in Text(GrainTableFormat.schmid(row, byGrain: session.schmidByGrain)).monospacedDigit() }
                        TableColumn("Neighbours", value: \.neighbours) { Text(verbatim: "\($0.neighbours)").monospacedDigit() }
                    }
                    .focused($tableFocused)
                    .onCopyCommand(perform: session.selectedGrains.isEmpty ? nil : { copied(unit: unit, places: places) })
                    .onChange(of: session.selectedGrains) { _, picked in
                        // As the EELS edges table (294de6a), after the pick a selected grain moves has run its course (`selectGrain` pins
                        // the grain, and the panes follow): set in this turn, the keys went back to the map (drive, 2026-11-11).
                        if personPicked, !picked.isEmpty { Task { @MainActor in tableFocused = true } }
                        personPicked = false
                    }
                    .accessibilityIdentifier("maps.grains.table")
                    MapsGrainSlipRows(session: session)
                }
                .padding(10)
            } else {
                Text(session.isSegmenting ? "Segmenting…" : "Segment the map to list its grains.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("maps.grains.empty")
            }
        }
        .onAppear { refresh() }
        .onChange(of: session.analysis?.table.count) { refresh() }
        .onChange(of: session.analysis?.settings) { refresh() }
        .onChange(of: sortOrder) { rows.sort(using: sortOrder) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maps.grains")
    }

    private func refresh() { rows = (session.analysis?.table ?? []).sorted(using: sortOrder) }

    /// ⌘C: the selected grains as TSV, in the table's order (the sort on screen), under the column titles.
    private func copied(unit: String, places: Int) -> [NSItemProvider] {
        let picked = rows.filter { session.selectedGrains.contains($0.id) }
        guard !picked.isEmpty else { return [] }
        return [NSItemProvider(object: GrainTableFormat.copyText(picked, unit: unit, slip: session.slip, places: places) as NSString)]
    }
}

/// The picked grain's slip planes under the Grains table (#1066: results in the room, not the inspector): each plane's Schmid factor,
/// trace and inclination, beside a swatch in its trace's colour on the map. Nothing while no grain is picked.
struct MapsGrainSlipRows: View {
    let session: OrientationMapSession

    var body: some View {
        if let row = session.selectedRow, let slip = session.selectedSlip {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Slip in grain \(row.id) · \(row.phaseName)")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(slip.planes.enumerated()), id: \.offset) { index, plane in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MapsAnalysisOverlay.traceColour(plane.colour))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(verbatim: plane.label).font(.caption.monospaced())
                        Text(verbatim: MapsRoomFormat.planeText(plane)).font(.caption.monospacedDigit())
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("maps.grains.slip.\(index)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("maps.grains.slip")
        }
    }
}

extension GrainRow {
    var phi1: Double { euler.x }
    var capitalPhi: Double { euler.y }
    var phi2: Double { euler.z }
}

// MARK: The texture figures

/// The pole figures and the IPF-Z density (Pole figures tab), or the ODF's φ₂ sections (ODF tab), of one phase, each in the inferno
/// colormap from 0 to its largest density (multiples of a random distribution), with that maximum under it.
struct MapsTextureFigures: View {
    let session: OrientationMapSession
    let odf: Bool

    var body: some View {
        Group {
            if let texture = session.texture {
                let figures = odf ? texture.odfSections : texture.poleFigures + (texture.inversePoleFigure.map { [$0] } ?? [])
                let selected = session.selectedRows.filter { $0.phaseID == texture.phaseID }.map(\.orientation)
                let aspect = figures.map { CGFloat($0.raster.height) / CGFloat(max($0.raster.width, 1)) }.max() ?? 1
                VStack(alignment: .leading, spacing: 0) {
                    // The tab's own header line (#1060): the phase, when the map has more than one.
                    MapsTexturePhasePicker(session: session)
                        .padding(.horizontal, MapsTextureLayout.padding).padding(.top, 6)
                    // The figures take the pane's size, aspect kept, in as many columns as make them largest; the caption wraps under
                    // them (#1060: at a fixed 150 pt the strip cut their lower third and the caption mid-word).
                    GeometryReader { proxy in
                        let arrangement = MapsTextureLayout.arrangement(count: figures.count, aspect: aspect, in: proxy.size)
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: MapsTextureLayout.spacing) {
                                Grid(alignment: .topLeading, horizontalSpacing: MapsTextureLayout.spacing, verticalSpacing: MapsTextureLayout.spacing) {
                                    ForEach(Array(stride(from: 0, to: figures.count, by: arrangement.columns)), id: \.self) { start in
                                        GridRow {
                                            ForEach(start..<min(start + arrangement.columns, figures.count), id: \.self) { index in
                                                MapsTextureFigureCell(figure: figures[index], odf: odf, side: arrangement.side,
                                                                      markers: MapTexture.poleMarkers(figures[index], orientations: selected))
                                                    .accessibilityIdentifier("maps.\(odf ? "odf" : "pole").\(index)")
                                            }
                                        }
                                    }
                                }
                                Text(verbatim: MapsRoomFormat.textureCaption(texture, odf: odf))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("maps.texture.caption")
                            }
                            .padding(MapsTextureLayout.padding)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            } else if session.isTexturing {
                ProgressView("Computing the texture…").controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Never blank: no phase to make it for, refused and why, or stopped, with the inspector's Compute Texture (macTEM#410).
                let words = MapsRoomFormat.textureUnavailable(stopped: session.textureStopped, failure: session.textureFailure,
                                                              hasPhases: !session.texturePhases.isEmpty)
                ContentUnavailableView {
                    Label(words.title, systemImage: words.systemImage)
                } description: {
                    Text(words.detail)
                }
                .accessibilityIdentifier("maps.texture.empty")
            }
        }
        .task(id: session.fileName) { _ = session.showTexture() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(odf ? "maps.odf" : "maps.poleFigures")
    }
}

/// How the Pole figures and ODF tabs fit their figures to the pane (#1060): every figure the same width, aspect kept, in the number of
/// columns that makes them largest while all of them, each with its title, colour bar and maximum, and the caption under them fit the
/// pane. Below `minimumSide` they keep that width and the pane scrolls. Pure, so a test pins it.
nonisolated enum MapsTextureLayout {
    /// Between two figures, and around them.
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 10
    /// A figure's lines besides its picture: the title, the colour bar and the maximum, with the gaps between them.
    static let cellChrome: CGFloat = 16 + 4 + 8 + 4 + 14
    /// The caption under the figures: three lines of caption text.
    static let captionReserve: CGFloat = 48
    /// A figure narrower than this is not read; the pane scrolls instead.
    static let minimumSide: CGFloat = 64
    /// A figure wider than this gains nothing.
    static let maximumSide: CGFloat = 360

    struct Arrangement: Equatable {
        let columns: Int
        /// Each figure's width; its picture is `side × aspect` tall.
        let side: CGFloat
    }

    /// The largest arrangement of `count` figures, each `aspect` times as tall as wide, that fits `size`.
    static func arrangement(count: Int, aspect: CGFloat, in size: CGSize) -> Arrangement {
        guard count > 0 else { return Arrangement(columns: 1, side: minimumSide) }
        var best = Arrangement(columns: 1, side: 0)
        for columns in 1...count {
            let rows = rowCount(count, columns: columns)
            let byWidth = (size.width - 2 * padding - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let pictures = size.height - 2 * padding - captionReserve - spacing - CGFloat(rows - 1) * spacing - CGFloat(rows) * cellChrome
            let byHeight = pictures / CGFloat(rows) / max(aspect, 0.01)
            let side = min(byWidth, byHeight, maximumSide)
            if side > best.side { best = Arrangement(columns: columns, side: side) }
        }
        return best.side >= minimumSide ? best : Arrangement(columns: best.columns, side: minimumSide)
    }

    /// The size the figures and the caption take in `arrangement`, padding included.
    static func contentSize(count: Int, aspect: CGFloat, arrangement: Arrangement) -> CGSize {
        let rows = rowCount(count, columns: arrangement.columns)
        let columns = min(arrangement.columns, max(count, 1))
        return CGSize(width: 2 * padding + CGFloat(columns) * arrangement.side + CGFloat(columns - 1) * spacing,
                      height: 2 * padding + CGFloat(rows) * (arrangement.side * aspect + cellChrome) + CGFloat(rows - 1) * spacing
                          + spacing + captionReserve)
    }

    private static func rowCount(_ count: Int, columns: Int) -> Int { (max(count, 1) + columns - 1) / columns }
}

struct MapsTextureFigureCell: View {
    let figure: MapTexture.Figure
    let odf: Bool
    /// The figure's width, from `MapsTextureLayout` (#1060).
    let side: CGFloat
    /// The selected grains' poles in the figure's unit square (macTEM#239), drawn as rings over the density.
    var markers: [SIMD2<Double>] = []

    var body: some View {
        let aspect = CGFloat(figure.raster.height) / CGFloat(max(figure.raster.width, 1))
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: figure.title).font(.caption).lineLimit(1)
                .frame(width: side, alignment: .leading)
            if let image = MapsFigure.textureImage(figure.raster) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(odf ? .none : .medium)
                    .frame(width: side, height: side * aspect)
                    .overlay(alignment: .topLeading) {
                        if odf {
                            Text(verbatim: "φ₁ →  Φ ↓").font(.caption2).foregroundStyle(.white).padding(2)
                        }
                    }
                    .overlay {
                        if !markers.isEmpty {
                            Canvas { context, size in
                                let r = LayoutPolicy.mapsPoleMarkerRadius
                                for m in markers {
                                    let rect = CGRect(x: m.x * size.width - r, y: m.y * size.height - r, width: 2 * r, height: 2 * r)
                                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2.5)
                                    context.stroke(Path(ellipseIn: rect), with: .color(.accentColor), lineWidth: 1.5)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
            MapsColourBar()
                .frame(width: side, height: LayoutPolicy.mapsColourBarHeight)
            Text(verbatim: "0 to \(MapsRoomFormat.number(figure.maximum)) MRD").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: side, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(figure.title), maximum \(MapsRoomFormat.number(figure.maximum)) multiples of random"
                            + (markers.isEmpty ? "" : ", \(markers.count) poles of the selected grains marked"))
    }
}

// MARK: The histogram

/// The Histogram tab (design §3): KAM per point, GOS or equivalent circle diameter per grain, in 40 bins (`MapAnalysis.histogram`),
/// with each selected grain's value ticked under the bars. Bars in the accent colour, counts on the left, the range under them.
struct MapsHistogramPane: View {
    let session: OrientationMapSession
    @Bindable var state: MapsRoomState

    var body: some View {
        Group {
            if let analysis = session.analysis {
                let kind = state.histogramKind
                let histogram = session.histogram(kind) ?? analysis.histogram(kind)
                let ticks = session.selectedRows.compactMap { analysis.histogramValue(kind, of: $0) }
                let unit = kind == .grainSize ? EBSDBrowsing.unitLabel(analysis.scanUnit) : "°"
                VStack(alignment: .leading, spacing: 4) {
                    // The tab's own header line (#1060): what the bars count, then their caption; in the tab row it changed the tabs' width.
                    HStack(spacing: 8) {
                        Picker("Histogram of", selection: $state.histogramKind) {
                            ForEach(MapAnalysis.HistogramKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .fixedSize()
                        .help("KAM of every point, or GOS or the equivalent circle diameter of every grain")
                        .accessibilityIdentifier("maps.histogram.kind")
                        Text(verbatim: MapsRoomFormat.histogramCaption(kind, histogram: histogram, unit: unit))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                            .accessibilityIdentifier("maps.histogram.caption")
                    }
                    Canvas { context, size in
                        let counts = histogram.counts
                        guard let top = counts.max(), top > 0, let low = histogram.edges.first, let high = histogram.edges.last, high > low else { return }
                        let barArea = CGRect(x: 0, y: 0, width: size.width, height: size.height - LayoutPolicy.mapsHistogramTickHeight)
                        let w = barArea.width / CGFloat(counts.count)
                        for (k, n) in counts.enumerated() where n > 0 {
                            let h = barArea.height * CGFloat(n) / CGFloat(top)
                            context.fill(Path(CGRect(x: CGFloat(k) * w + 0.5, y: barArea.maxY - h, width: max(w - 1, 1), height: h)),
                                         with: .color(.accentColor.opacity(0.8)))
                        }
                        for v in ticks where v.isFinite {
                            let x = CGFloat((min(max(v, low), high) - low) / (high - low)) * barArea.width
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: barArea.maxY))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(p, with: .color(.primary), lineWidth: 2)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(MapsRoomFormat.histogramSpoken(kind, histogram: histogram))
                    .accessibilityValue(MapsRoomFormat.histogramSpeech(histogram, unit: unit, ticks: ticks))
                    .accessibilityIdentifier("maps.histogram.bars")
                    HStack {
                        Text(verbatim: "\(MapsRoomFormat.number(histogram.edges.first ?? 0)) \(unit)")
                        Spacer()
                        Text(verbatim: "\(MapsRoomFormat.number(histogram.edges.last ?? 0)) \(unit)")
                    }
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                Text(session.isSegmenting ? "Segmenting…" : "Segment the map for its KAM, GOS and grain-size histograms.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maps.histogram")
    }
}

/// The inferno colour bar the texture figures use.
struct MapsColourBar: View {
    var body: some View {
        if let image = MapsFigure.colourBarImage() {
            Image(decorative: image, scale: 1).resizable().interpolation(.medium)
        }
    }
}

// MARK: - Inspector sections

/// Misorientation (design §4): the KAM's neighbour cut-off. The next Segment uses it.
struct MapsMisorientationSection: View {
    let session: OrientationMapSession

    var body: some View {
        InspectorSection("Misorientation") {
            InspectorRow("KAM maximum") {
                OptionalNumericField(title: "KAM maximum", value: session.analysisSettings.kamMaxDegrees, format: MapsRoomFormat.decimal, unit: "°",
                                     prompt: "5") { v in
                    var s = session.analysisSettings; s.kamMaxDegrees = v; session.setAnalysisSettings(s)
                }
                .help("Kernel average misorientation over the first neighbours of the same phase; a neighbour more misoriented than this is left out")
                .accessibilityIdentifier("maps.kamMax")
            }
            InspectorNote("KAM, GOS and GND appear in the map heading's menu after Segment. GND is DefDAP's Nye-tensor density from the primary phase's structure.")
        }
    }
}

/// Grains (design §4): the boundary angle and the smallest grain, and whether the boundaries show; the statistics are the Grains tab's.
struct MapsGrainsSection: View {
    let session: OrientationMapSession

    var body: some View {
        InspectorSection("Grains") {
            InspectorRow("Boundary") {
                OptionalNumericField(title: "Boundary angle", value: session.analysisSettings.boundaryDegrees, format: MapsRoomFormat.decimal,
                                     unit: "°", prompt: "5") { v in
                    var s = session.analysisSettings; s.boundaryDegrees = v; session.setAnalysisSettings(s)
                }
                .help("Neighbours more misoriented than this are on different grains (DefDAP's find_grains)")
                .accessibilityIdentifier("maps.boundaryAngle")
            }
            InspectorRow("Smallest") {
                OptionalNumericField(title: "Smallest grain", value: Double(session.analysisSettings.minimumSize), format: MapsRoomFormat.whole,
                                     unit: "points", prompt: "10") { v in
                    var s = session.analysisSettings
                    s.minimumSize = v.isFinite ? Int(min(max(v.rounded(), 1), 1e9)) : 10
                    session.setAnalysisSettings(s)
                }
                .help("Regions of fewer points are not grains: they show grey and leave the table")
                .accessibilityIdentifier("maps.minimumSize")
            }
            InspectorRow("Boundaries") {
                Toggle("Show the boundaries", isOn: Binding(get: { session.showsBoundaries }, set: { session.showsBoundaries = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Grain boundaries white, phase boundaries black, over the map")
                    .accessibilityIdentifier("maps.showBoundaries")
            }
            // The statistics of the last Segment are the Grains tab's heading (#1066); the inspector keeps the settings.
            if session.analysis != nil {
                if session.analysisIsStale {
                    InspectorWarning("The settings changed: Segment again to apply them.")
                }
            } else {
                InspectorNote("Segment (the toolbar's verb) finds the grains with these settings.")
            }
        }
    }
}

/// Slip: the load axis, each phase's slip systems and whether the traces show; the picked grain's planes are under the Grains table.
struct MapsSlipSection: View {
    let session: OrientationMapSession

    var body: some View {
        InspectorSection("Slip") {
            InspectorRow("Load") {
                Picker("Load axis", selection: Binding(get: { session.loadDirection }, set: { session.setLoadDirection($0) })) {
                    ForEach(SampleDirection.allCases, id: \.self) { Text("Sample \($0.rawValue.uppercased())").tag($0) }
                }
                .labelsHidden()
                .help("The uniaxial load the Schmid factors are for, along a sample axis")
                .accessibilityIdentifier("maps.slip.load")
            }
            if let map = session.map {
                ForEach(MapsRoomFormat.indexedPhases(map), id: \.id) { entry in
                    InspectorRow(MapsRoomFormat.phaseName(entry.phase, id: entry.id)) {
                        Picker("Slip systems of \(entry.phase.name)",
                               selection: Binding(get: { session.slipFiles[entry.id] }, set: { session.setSlipFile($0, phaseID: entry.id) })) {
                            Text("None").tag(SlipSystemFile?.none)
                            ForEach(MapsRoomFormat.slipChoices(entry.phase), id: \.self) { Text(MapsRoomFormat.slipTitle($0)).tag(Optional($0)) }
                        }
                        .labelsHidden()
                        .help("DefDAP's slip-system file for this phase")
                        .accessibilityIdentifier("maps.slip.phase.\(entry.id)")
                    }
                }
            }
            InspectorRow("Traces") {
                Toggle("Show the slip traces", isOn: Binding(get: { session.showsSlipTraces }, set: { session.showsSlipTraces = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("The selected grain's slip-plane traces through its centroid, in DefDAP's colours")
                    .accessibilityIdentifier("maps.slip.traces")
            }
            // The picked grain's planes are listed under the Grains table (#1066); the inspector keeps the settings.
            if session.analysis != nil, session.selectedSlip == nil {
                InspectorNote("Pin a point in a grain, or pick a row of the Grains tab, for its Schmid factors and traces under the table.")
            }
        }
    }
}

/// Texture: which phase the Pole figures and ODF tabs show, Compute Texture to make it, and how it is made.
struct MapsTextureSection: View {
    let session: OrientationMapSession

    var body: some View {
        InspectorSection("Texture", startsExpanded: false) {
            let phases = session.texturePhases
            if phases.isEmpty {
                InspectorNote("No indexed phase with a point group.")
            } else {
                InspectorRow("Phase") {
                    Picker("Texture phase", selection: Binding(get: { session.texturePhaseID ?? phases[0].id }, set: { _ = session.showTexture(phaseID: $0) })) {
                        ForEach(phases, id: \.id) { Text(MapsRoomFormat.phaseName($0.phase, id: $0.id)).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("maps.texture.phaseInspector")
                }
                // The in-pane picker exists only with more than one phase, and this one never fires for the phase already picked:
                // after ⌘. the texture is made again here (macTEM#410). One action alone is full width.
                InspectorActionRow {
                    let canCompute = session.canComputeTexture
                    Button("Compute Texture") { _ = session.showTexture() }
                        .disabled(!canCompute)
                        .help(MapsRoomFormat.computeTextureHelp(isTexturing: session.isTexturing, failure: session.textureFailure,
                                                                canCompute: canCompute))
                        .accessibilityIdentifier("maps.texture.compute")
                }
                InspectorNote("Pole figures and the IPF-Z density: orix's pole density function, 1° bins smoothed 5°, upper hemisphere. ODF sections: a de la Vallée Poussin kernel of 10° half-width at 5° nodes.")
            }
        }
    }
}
