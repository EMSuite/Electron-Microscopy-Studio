//
//  DiffractionRoom.swift
//  Role: the Diffraction room's centre: the pattern (log display), the centre, the
//        annulus being dragged, the fitted rings and the clicked spots drawn over it, and the room's tables (the readout, the spots),
//        which are tabs of the shell's bottom area (`DiffractionTablePane`, #1094, #1112). The selected file
//        is the pattern; the state is `DiffractionAnalysis` (TEMSession, `OpenItem.diffraction`), every number DiffractoKit's.
//
//        The centre is the shell's (`WorkspaceCentre`, EMSuiteUI): the side pane of the part (the crystal, the zone-axis map, the
//        powder pattern) beside the pattern with one divider the person drags, or the pattern alone, and each is a `CentrePanel`, the
//        frame's one panel header. The pattern's header names the file, sets the scale's summary in the readout slot and holds Index's
//        verdict, the hand-set orientation, the view's half-side and the figure handle at its right.
//        Pure SwiftUI. Zoom (control placement §6): the wheel and a pinch zoom about the pattern's centre, a double-click (Ring tool) fits again,
//        and View > Zoom In, Zoom Out and Zoom to Fit (⌘+, ⌘−, ⌘0) do the same from the menu (`DiffractionZoomCommands`);
//        the view stays centred on the pattern, so there is no pan, and the drag belongs to the Ring tool. The R · q · d under the pointer is the
//        status line's (§7); a fit in flight is the infobar's, with Stop (WorkspaceView). Not here yet (open-items): Find Spots, the predicted
//        rings, the centre handle drag.
//
//  The annulus is a drag in the Ring tool: press at the inner radius, release at the outer (or the reverse); the fields in the inspector
//  type it. A click in the Spot tool measures a spot. Gesture-rate values (the drag, the pointer) are `@State` here and never touch the
//  owner until the gesture ends.
//
//  The click's keyboard and VoiceOver twin (macTEM#262, macEM#509, #510): in the Spot tool, an element of its own at a cursor
//  (`MarkCursor`, shared with the Image room's marks) with "Place point at centre", the coarse and the one-pixel "Move point …" and
//  "Add spot here", which makes the click's own `addSpot` call on the cursor's pixel (`SpotCursorActions`); the keys are ⌥ and an
//  arrow (⌥⇧ the coarse step) and Return (`DiffractionKeyedPane`, App/PaneKeys.swift). The cursor starts at the pattern's centre,
//  where the view is centred, and is spoken as the status line reads the pointer's pixel (R, q and d). Once moved it is drawn and
//  the status line reads its pixel, until the pointer moves over the pattern. It takes no hits.
//

import ShellControls
import ShellLayout
import ShellMetal
import ShellSpectroscopy
import SwiftUI
import ImagoCore
import TEMCore
import TEMSession
import DiffractoCore
import DiffractoGeometry

struct DiffractionRoom: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    /// The part the window showed, restored with the scene (#1044).
    @SceneStorage("diffraction.part") private var storedPart = ""
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }

    /// The pattern's display is built again for another item, a Log switch, or new pixels (`ImageSession.generation`: a frame, a CBED
    /// pattern at another thickness, #1003), whatever their size.
    private struct DisplayKey: Equatable {
        var id: OpenItem.ID
        var log: Bool
        // periphery:ignore - read by the synthesized ==
        var generation: Int
    }

    var body: some View {
        // The root reads only what a change of the RESULTS (or the log toggle) must redraw: the pointer, the zoom and the annulus drag live in
        // the leaf views that draw them, so a mouse move re-evaluates one small view and nothing above it.
        let analysis = item.diffraction
        let view = item.diffractionView
        let rows = analysis.readout(image: image)
        // The part shown (#1044) decides the pane beside the pattern and the tables in the bottom area; the pattern itself, its zoom,
        // selection and overlays, are the same in every part.
        let part = appState.diffractionPart
        // The pane beside the pattern, by the part (#921, #1044): the crystal down the same beam in Index and Simulate (#790; one
        // orientation drives both; it appears once simulated spots are drawn and View > Hide Crystal hides it, #789), the zone-axis
        // map in Tilt Plan (#814), the powder pattern in Powder (#810); none, and the pattern alone fills the centre, in Calibrate and
        // Thickness. The centre is the shell's (#1094): the divider's place is the window's (scene storage under the key the split
        // had, which held the side pane's share too, so a place dragged in an earlier version is kept), the pane takes a third and
        // the pattern, the data, two thirds until the person drags it (#1046, `DiffractionCrystalSplit`), and a double click on the
        // divider puts it back there.
        Group {
            if let pane = DiffractionSidePaneView.shown(part: part, view: view, analysis: analysis) {
                WorkspaceCentre(storageKey: DiffractionCrystalSplit.storageKey, defaultFraction: DiffractionCrystalSplit.defaultCrystalFraction,
                                resizeLabel: "Resize the side pane and the pattern", leadingName: DiffractionPaneWords.title(pane)) {
                    DiffractionSidePaneView(item: item, analysis: analysis, view: view, pane: pane)
                } trailing: {
                    patternPanel(analysis: analysis, view: view, rows: rows)
                }
            } else {
                WorkspaceCentre {
                    patternPanel(analysis: analysis, view: view, rows: rows)
                }
            }
        }
        // The part: the scene's when the window comes back, else the one the document opens on; another document opens on its own.
        // The part's tables are the bottom area's tabs (`WorkspaceView`): the table the strip under the pattern showed is selected the
        // first time a part asks for it, once the part is settled, and the person's choice of tab rules after that (`DiffractionRoomState.offer`).
        .onAppear {
            appState.settleDiffractionPart(restored: DiffractionPart(rawValue: storedPart))
            offerTable()
        }
        .onChange(of: DiffractionPart.openingTable(part, hasSpots: Self.hasSpots(item))) { offerTable() }
        .onChange(of: item.id) { appState.diffractionDocumentChanged() }
        .onChange(of: part) { storedPart = part.rawValue }
        // The pattern is shown by its owner (the bind, the extent and the canvas, off the main actor); a quick Log toggle or another
        // file cancels the pass in flight.
        .task(id: DisplayKey(id: item.id, log: view.useLog, generation: item.session.generation)) {
            await view.show(image: image, generation: item.session.generation, analysis: analysis)
        }
        // The ring or spot just added is the selected row.
        .onChange(of: analysis.lastAdded) { if let id = analysis.lastAdded { view.selection = id } }
        // The room's display canvas (the pattern, log or linear, 4 B/px) goes when the room does; the task above builds it again on
        // return, keeping the window. 12 Nov: the room held 1.4 GB more than the Image room on the 187 MP alite image for as long as it was open.
        .onDisappear { view.presentation.releaseCanvas() }
        // The Add Phase sheet is the room's (#788): Add Phase… in the Phases section or on the empty state, and New Simulation.
        .modifier(DiffractionAddPhaseSheet(item: item))
    }
}

extension DiffractionRoom {
    /// The part's spots can be listed: a Simulation document's, or Index's once it answers (the strip showed its Spots table then).
    private static func hasSpots(_ item: OpenItem) -> Bool {
        DemoDocuments.isSimulation(item.url) || item.diffraction.indexOutcome != nil
    }

    /// Selects the part's opening table in the bottom area if the window has not selected it on its own before.
    private func offerTable() {
        appState.diffractionRoom.offer(DiffractionPart.openingTable(appState.diffractionPart, hasSpots: Self.hasSpots(item)),
                                       in: appState.navigation.panels)
    }

    /// The pattern in the frame's panel: its header names the file, the scale's summary is the readout slot's (it gives way first),
    /// and Index's verdict, the hand-set orientation, the view's half-side and the figure handle sit at its right.
    private func patternPanel(analysis: DiffractionAnalysis, view: DiffractionViewState, rows: [DiffractionReadoutRow]) -> some View {
        CentrePanel(title: image.fileName) {
            DiffractionPatternPane(item: item, analysis: analysis, view: view, rows: rows)
                .modifier(DiffractionZoomCommands(item: item, view: view))
        } controls: {
            DiffractionHeaderFacts(item: item, analysis: analysis, view: view)
        } readout: {
            DiffractionHeaderScale(item: item, analysis: analysis)
        }
    }
}

// MARK: - Header

/// The pattern panel's readout slot (`CentrePanel`): the fullest summary of the pattern that fits, the least needed parts dropped
/// first (#1090), never a word cut mid-way, and none at all when Index's verdict at the right needs the room (#1113). The panel sets it
/// in the caption, secondary, on one line.
private struct DiffractionHeaderScale: View {
    let item: OpenItem
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }
    let analysis: DiffractionAnalysis

    var body: some View {
        let calibration = analysis.calibration(for: image)
        let volts = analysis.volts(for: image)
        let levels = DiffractionHeaderText.readoutLevels(width: image.width, height: image.height, volts: volts, voltsFromFile: image.voltage != nil,
                                                         calibration: calibration)
        ViewThatFits(in: .horizontal) {
            ForEach(levels.indices, id: \.self) { i in
                Text(levels[i]).lineLimit(1).truncationMode(.tail)
            }
        }
        .help(levels.first ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levels.first ?? "")
        .accessibilityIdentifier("diffraction.scale")
        .accessibilityValue(DiffractionValueFormat.scale(calibration?.deltaQ))
    }
}

/// The pattern panel's right end (`CentrePanel`'s controls): Index's verdict, the hand-set orientation, the view's half-side and the
/// figure handle, as the room's header row had them. It is laid out before the readout slot beside it (#1113): the scale's summary
/// gives way, whole, before the verdict is shortened, and the verdict drops its spot count, whole, before it is ever cut.
private struct DiffractionHeaderFacts: View {
    @Environment(AppState.self) private var appState
    let item: OpenItem
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState

    var body: some View {
        HStack(spacing: 8) {
            // Index's verdict in words (#783): "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %".
            // At each length (#1113): the whole line, then without the spot count and the solution's number.
            if let outcome = analysis.indexOutcome, let line = analysis.indexHeaderLine(locale: .autoupdatingCurrent) {
                let levels = analysis.indexHeaderLevels(locale: .autoupdatingCurrent)
                ViewThatFits(in: .horizontal) {
                    ForEach(levels.indices, id: \.self) { i in
                        Text(levels[i]).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.callout.monospacedDigit()).layoutPriority(2)
                .foregroundStyle(outcome.verdict == .found && !outcome.zoneAxisOnly && !analysis.indexIsStale && !analysis.indexSpotsChanged
                                 ? Color.primary : Color.orange)
                .help(line)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("diffraction.index.verdict")
                .accessibilityLabel("Index, \(outcome.verdict.word)")
                .accessibilityValue(line)
            }
            // The drawn orientation's nearest zone axis once it was tilted, turned or flipped by hand, or while no Index answer is
            // shown (#787): "Al · 2.1° from [001] · set by hand".
            if !SimulationEmptyState.isShown(for: item), let line = analysis.orientationHeaderLine(locale: .autoupdatingCurrent) {
                Text(line)
                    .font(.callout.monospacedDigit()).lineLimit(1).truncationMode(.tail).layoutPriority(2)
                    .help(line)
                    .accessibilityIdentifier("diffraction.simulation.place")
                    .accessibilityLabel("Simulated orientation")
                    .accessibilityValue(line)
            }
            // What the pane shows about the centre, in words (a header holds words only); its value is the half-side to three decimals,
            // which a journey maps its drags by.
            let half = view.viewHalfSide(for: image)
            Text("view ±\(Num.fixed(half, 0)) px")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                .accessibilityIdentifier("diffraction.view")
                .accessibilityValue(DiffractionValueFormat.halfSide(half))
            // The figure handle (#823): dragged out, the figure as a PDF file; the pattern's own drags are the Ring tool's annulus.
            Image(systemName: "photo.on.rectangle")
                .foregroundStyle(.secondary)
                .onDrag { ExportPanels.diffractionFigureDrag(appState: appState) }
                .help("Drag the figure out as a PDF file; Edit > Copy Figure puts it on the clipboard")
                .accessibilityLabel("Figure")
                .accessibilityIdentifier("diffraction.figureDrag")
                .accessibilityAction(named: "Copy Figure") { ExportPanels.copyDiffractionFigure(appState: appState) }
        }
        // Above the readout slot's 0 (#1113): the panel's header offers these their width first, and the slot keeps what is left.
        .layoutPriority(1)
    }
}

/// The pattern header's summary at each length (#1090): the whole line first, then the ring's camera length, the "(file)" mark, the
/// pixel size and Δq left out in that order, so a narrow window keeps the beam energy and where the scale came from.
nonisolated enum DiffractionHeaderText {
    static func levels(width: Int, height: Int, volts: Double?, voltsFromFile: Bool, calibration: DiffractionCalibration?) -> [String] {
        func line(lengths: Bool, fileMark: Bool, size: Bool, deltaQ: Bool) -> String {
            var parts: [String] = []
            if size { parts.append("\(width) × \(height) px") }
            if let volts { parts.append("\(Num.sig(volts / 1000, 4)) kV\(fileMark && voltsFromFile ? " (file)" : "")") }
            if let calibration {
                parts.append("scale: \(calibration.sourceText)")
                if deltaQ { parts.append("Δq \(Num.fixed(calibration.deltaQ, 5)) Å⁻¹/px") }
                if lengths, let l = calibration.ring?.lengthPixels { parts.append("L \(Num.fixed(l, 0)) px") }
                if lengths, let mm = calibration.ring?.lengthMillimetres { parts.append("L \(Num.fixed(mm, 0)) mm") }
            } else {
                parts.append("no scale yet")
            }
            return parts.joined(separator: " · ")
        }
        let all = [line(lengths: true, fileMark: true, size: true, deltaQ: true),
                   line(lengths: false, fileMark: true, size: true, deltaQ: true),
                   line(lengths: false, fileMark: false, size: true, deltaQ: true),
                   line(lengths: false, fileMark: false, size: false, deltaQ: true),
                   line(lengths: false, fileMark: false, size: false, deltaQ: false)]
        return all.reduce(into: [String]()) { out, l in if out.last != l { out.append(l) } }
    }

    /// The readout slot's lines (#1113): `levels`, then none. The slot keeps what the header's right end leaves (Index's verdict comes
    /// first), so when even the shortest summary does not fit it is left out whole, never cut.
    static func readoutLevels(width: Int, height: Int, volts: Double?, voltsFromFile: Bool, calibration: DiffractionCalibration?) -> [String] {
        levels(width: width, height: height, volts: volts, voltsFromFile: voltsFromFile, calibration: calibration) + [""]
    }
}

// MARK: - The pattern

/// How the pattern is laid in its box: the image fills the box at `scale` points per pixel, then is magnified `zoom` times about the box
/// centre and moved so the pattern centre sits at the box centre. One map for the picture, the overlays and the gestures.
private nonisolated struct DiffractionLayout {
    let box: CGSize
    let width: Int
    let height: Int
    let centre: DiffractionCentre
    let halfSide: Double

    var scaleX: CGFloat { box.width / CGFloat(width) }
    var scaleY: CGFloat { box.height / CGFloat(height) }
    /// Box points per image point: the image's own half-side over the half-side wanted.
    var zoom: CGFloat { CGFloat(Double(min(width, height)) / 2 / halfSide) }
    private var middle: CGPoint { CGPoint(x: box.width / 2, y: box.height / 2) }
    private var unzoomedCentre: CGPoint { CGPoint(x: (centre.column + 0.5) * scaleX, y: (centre.row + 0.5) * scaleY) }
    var offset: CGSize { CGSize(width: (middle.x - unzoomedCentre.x) * zoom, height: (middle.y - unzoomedCentre.y) * zoom) }

    /// The point of a (column, row) pixel in the box.
    func point(column: Double, row: Double) -> CGPoint {
        let p = CGPoint(x: (column + 0.5) * scaleX, y: (row + 0.5) * scaleY)
        return CGPoint(x: middle.x + (p.x - middle.x) * zoom + offset.width, y: middle.y + (p.y - middle.y) * zoom + offset.height)
    }

    /// The (column, row) under a point of the box.
    func pixel(at p: CGPoint) -> (column: Double, row: Double) {
        let ux = (p.x - offset.width - middle.x) / zoom + middle.x, uy = (p.y - offset.height - middle.y) / zoom + middle.y
        return (Double(ux / scaleX) - 0.5, Double(uy / scaleY) - 0.5)
    }

    /// Box points per pixel after the zoom (x).
    var pointsPerPixel: CGFloat { scaleX * zoom }
}

private struct DiffractionPatternPane: View {
    let item: OpenItem
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    let rows: [DiffractionReadoutRow]
    @Environment(AppState.self) private var appState
    @State private var drag: (start: CGPoint, end: CGPoint)?
    /// A Tilt-tool drag in flight (#787): the orientation it started from, and whether ⌥ was down at its start (it turns, not tilts).
    @State private var handDrag: (base: CrystalOrientation, turns: Bool)?
    /// The half-side while a pinch is running; committed to the view state once, when it ends.
    @State private var liveHalf: Double?
    @State private var pinchStart: Double?
    /// The Spot tool's VoiceOver cursor (`SpotCursorAccessibility`): nil until moved (it starts at the pattern's centre). Drawn
    /// nowhere.
    @State private var spotCursor: MarkCursor.Pixel?
    /// The spot cursor is drawn and the status line reads its pixel: a key or an action moved it, and the pointer has not moved over
    /// the pattern since.
    @State private var spotCursorShown = false
    /// Where the pointer was last reported over the pattern: a report at the same place (a redraw re-reports a resting pointer) is no
    /// move, so it leaves the spot cursor shown (`ImagePane.lastHover`).
    @State private var lastHover: CGPoint?

    /// The Spot tool's twin on the image the owner holds now (read at each use, never held).
    private var spotActions: SpotCursorActions { SpotCursorActions(image: image, analysis: analysis) }

    /// The pattern's keys: a stack's frames, and in the Spot tool the spot cursor's ⌥-arrows and Return.
    private var patternKeys: DiffractionPatternKeys {
        var keys = DiffractionPatternKeys(frames: StackFrameKeys.of(item, in: appState.openItems))
        if SpotCursorActions.addsSpots(view) {
            keys.cursor = CursorKeys(move: { direction, fine in
                                         guard let step = MarkCursor.Move(direction) else { return }
                                         moveSpotCursor(step, fine: fine)
                                     },
                                     set: { addSpotAtCursor() })
        }
        if view.tool == .tilt, analysis.drawnOrientation != nil {
            keys.tilt = { direction, coarse in tilt(direction, degrees: coarse ? Self.coarseTiltDegrees : Self.fineTiltDegrees) }
        }
        return keys
    }

    /// The Tilt tool's key steps (#787): ⌥ and an arrow tilt 0.1°, ⌥⇧ 1°; VoiceOver's Tilt actions take the coarse step.
    private static let fineTiltDegrees = 0.1
    private static let coarseTiltDegrees = 1.0

    /// Tilts the simulated spots as a drag that way would: ↑ and ↓ up and down the rows, ← and → along the columns.
    private func tilt(_ direction: MoveCommandDirection, degrees: Double) {
        switch direction {
        case .up: analysis.tilt(down: -degrees, across: 0)
        case .down: analysis.tilt(down: degrees, across: 0)
        case .left: analysis.tilt(down: 0, across: -degrees)
        case .right: analysis.tilt(down: 0, across: degrees)
        @unknown default: break
        }
    }

    private func moveSpotCursor(_ step: MarkCursor.Move, fine: Bool) {
        spotCursor = spotActions.moved(spotCursor, by: step, fine: fine)
        showSpotCursor()
    }

    private func addSpotAtCursor() {
        let actions = spotActions
        let spot = actions.addSpotHere(spotCursor)
        showSpotCursor()
        AccessibilityNotification.Announcement(actions.announcement(for: spot)).post()
    }

    /// The cursor is drawn, and the status line reads its pixel as it reads the pointer's (this pane is the readout's one writer).
    private func showSpotCursor() {
        if !spotCursorShown { spotCursorShown = true }
        appState.diffractionRoom.readout = spotActions.spokenValue(spotCursor)
    }

    var body: some View {
        GeometryReader { geo in
            let box = LayoutPolicy.fitted(in: geo.size, aspect: CGFloat(image.width) / CGFloat(image.height))
            let centre = analysis.centre ?? .imageCentre(width: image.width, height: image.height)
            let half = liveHalf ?? view.viewHalfSide(for: image)
            let layout = DiffractionLayout(box: box, width: image.width, height: image.height, centre: centre, halfSide: half)
            ZStack {
                Color.black
                if let canvas = view.presentation.canvas {
                    let display = view.presentation
                    MetalImageView(pixels: canvas.values, width: canvas.width, height: canvas.height, contentVersion: canvas.contentVersion,
                                   colormap: display.colormap, displayLo: display.displayFractions.low, displayHi: display.displayFractions.high,
                                   gamma: Float(display.gamma), pixelScale: canvas.scale, nativePixels: canvas.metalNative,
                                   transfer: canvas.transfer)
                        .displayTransform(MetalDisplayTransform(paneSize: box, imageBox: box, zoom: layout.zoom, offset: layout.offset))
                        .allowsHitTesting(false)
                }
                // The simulated spots of the typed zone axis (#782), under the measured marks; redrawn whenever the zone axis, its turn,
                // the crystal, the centre or the scale changes (`DiffractionAnalysis.simulatedSpots`), and a Simulation document's Dynamical
                // beams at its thickness (#911).
                if let simulated = try? item.simulatedSpots(image: image)?.get() {
                    SimulatedSpotsOverlay(spots: simulated, labelMode: analysis.simulation.labelMode,
                                          beam: analysis.centre.map { layout.point(column: $0.column, row: $0.row) }, layout: layout)
                        .allowsHitTesting(false)
                }
                // The shown variants of a precipitate (#808), pink diamonds, under the measured marks; placed off the main actor, the last
                // placement drawn until the next lands.
                if item.diffractionVariants.isShown {
                    let variants = item.diffractionVariants
                    Group {
                        if case .success(let set)? = variants.variants(analysis: analysis, image: image) {
                            VariantSpotsOverlay(pixels: variants.pixels(of: set, analysis: analysis, image: image), layout: layout)
                            if case .success(let added)? = variants.addedSpots(analysis: analysis, image: image) {
                                VariantSpotsOverlay(pixels: variants.pixels(of: added, analysis: analysis, image: image), layout: layout,
                                                    dashed: true)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .task(id: variants.inputs(analysis: analysis, image: image)) {
                        if let inputs = variants.inputs(analysis: analysis, image: image) { await variants.place(inputs) }
                    }
                }
                DiffractionOverlay(analysis: analysis, view: view, rows: rows, layout: layout, drag: drag.flatMap { radii(from: $0.start, to: $0.end, layout: layout) },
                                   pointer: lastHover)
                    .allowsHitTesting(false)
                // What the marks are (#1045): one chip in the top-leading corner while the simulated spots are drawn.
                let legend = DiffractionLegend.entries(
                    overlayShown: !((try? item.simulatedSpots(image: image)?.get()) ?? []).isEmpty, phase: analysis.crystal.name,
                    hasFound: analysis.spots.contains { $0.row != nil && $0.column != nil },
                    hasUnexplained: analysis.indexSpotRows.contains { $0.hkl == nil })
                if !legend.isEmpty {
                    DiffractionLegendChip(entries: legend)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
                // The spot cursor, for the eyes, once a key or an action has moved it.
                if spotCursorShown, SpotCursorActions.addsSpots(view) {
                    let pixel = spotActions.pixel(spotCursor)
                    MarkCursorMarker(cursor: layout.point(column: Double(pixel.x), row: Double(pixel.y)), held: nil)
                }
            }
            .frame(width: box.width, height: box.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    switch view.tool {
                    case .ring: drag = (value.startLocation, value.location)
                    case .tilt: turnByHand(value, layout: layout)
                    case .spot: break
                    }
                }
                .onEnded { value in
                    defer { drag = nil; handDrag = nil }
                    guard view.tool == .ring, let radii = radii(from: value.startLocation, to: value.location, layout: layout) else { return }
                    view.setAnnulus(inner: radii.0, outer: radii.1)
                })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in
                    let start = pinchStart ?? half
                    if pinchStart == nil { pinchStart = start }
                    liveHalf = min(max(start / v.magnification, 8), Double(min(image.width, image.height)) / 2)
                }
                .onEnded { _ in
                    if let liveHalf { view.zoomHalfSide = liveHalf }
                    liveHalf = nil
                    pinchStart = nil
                })
            // The wheel zooms about the pattern's centre (the view is centred on it); the application-wide monitor stays gone.
            // DEPARTURE from control-placement §6 (#629): the pattern has its own zoom, not the shared container, because the view is
            // centred on the beam (rings and spots are read about it), so a zoom about the pointer or a pan would move what is measured
            // off centre. The wheel, pinch, double-click (Ring tool) and View > Zoom (`DiffractionZoomCommands`) act as elsewhere.
            .onScrollWheel { event in
                guard event.delta != 0 else { return }
                view.zoom(by: Double(ScrollZoom.factor(delta: event.delta, isPrecise: event.isPrecise)), image: image)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { view.fitView() }, isEnabled: view.tool == .ring)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    guard p != lastHover else { return }
                    lastHover = p
                    // The pointer is back over the pattern: the cursor's square goes and the readout is the pointer's again.
                    if spotCursorShown { spotCursorShown = false }
                    let q = layout.pixel(at: p)
                    appState.diffractionRoom.readout = DiffractionReadoutText.text(column: q.column, row: q.row, centre: analysis.centre,
                                                                                    calibration: analysis.calibration(for: image))
                case .ended:
                    lastHover = nil
                    appState.diffractionRoom.readout = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { p in
                guard SpotCursorActions.addsSpots(view) else { return }
                let q = layout.pixel(at: p)
                analysis.addSpot(image: image, row: q.row, column: q.column)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("diffraction.pane")
            .accessibilityLabel("Diffraction pattern")
            // q and d under the pointer, as the status line reads them; else the pattern's size, rings and spots. This pane is the readout's one writer.
            .modifier(ReadoutAccessibilityValue(readout: { appState.diffractionRoom.readout },
                                                fallback: "\(image.width) by \(image.height) pixels, \(UnitDisplay.count(analysis.rings.count, "ring", "rings")), \(UnitDisplay.count(analysis.spots.count, "spot", "spots"))" + DiffractionSimulationText.spoken(item.simulatedSpots(image: image), zoneAxis: analysis.simulation.zoneAxis) + DiffractionIndexText.spoken(analysis.indexHeaderLine(locale: .autoupdatingCurrent), rows: analysis.indexSpotRows.count)))
            .accessibilityAction(named: "Zoom in") { view.zoom(by: 2, image: image) }
            .accessibilityAction(named: "Zoom out") { view.zoom(by: 0.5, image: image) }
            .accessibilityAction(named: "Reset zoom") { view.fitView() }
            .accessibilityAction(named: "Copy Figure") { ExportPanels.copyDiffractionFigure(appState: appState) }
            // The Tilt tool's drag for VoiceOver (#787): one coarse step each way, as ⌥⇧ and an arrow.
            .accessibilityActions {
                if view.tool == .tilt, analysis.drawnOrientation != nil {
                    Button("Tilt up") { tilt(.up, degrees: Self.coarseTiltDegrees) }
                    Button("Tilt down") { tilt(.down, degrees: Self.coarseTiltDegrees) }
                    Button("Tilt left") { tilt(.left, degrees: Self.coarseTiltDegrees) }
                    Button("Tilt right") { tilt(.right, degrees: Self.coarseTiltDegrees) }
                }
            }
            .contextMenu {
                Button("Copy Figure") { ExportPanels.copyDiffractionFigure(appState: appState) }
            }
            // The click's twin while a click adds a spot: an element of its own at the cursor, beside the pattern's (whose children
            // are ignored), so the pattern keeps its label, its readout value and its zoom actions.
            .modifier(SpotCursorAccessibility(active: SpotCursorActions.addsSpots(view), layout: layout,
                                              pixel: spotActions.pixel(spotCursor), spoken: spotActions.spokenValue(spotCursor),
                                              place: { spotCursor = spotActions.centre(); showSpotCursor() },
                                              move: { step, fine in moveSpotCursor(step, fine: fine) },
                                              add: { addSpotAtCursor() }))
            .overlay(alignment: .bottomTrailing) {
                // The zoom against the pattern's own extent, once it is not 1× (§6).
                let fit = view.fitHalfSide(for: image)
                if let text = ZoomPan.badgeText(zoom: CGFloat(fit / half)), let spoken = ZoomPan.badgeSpoken(zoom: CGFloat(fit / half)) {
                    Text(text)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule()).padding(6)
                        .help("\(spoken). Double-click with the Ring tool to see the whole pattern again.")
                        .accessibilityLabel(spoken)
                        .accessibilityIdentifier("diffraction.zoomBadge")
                }
            }
            // A Simulation document with no phase shown (#907): the empty state covers the pattern, where Cancel in Add Phase leaves it.
            .overlay {
                if SimulationEmptyState.isShown(for: item) { SimulationEmptyStateView(view: view) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // No margin: the pattern is fitted to the pane's whole width and height, centred (#1046).
        // The pattern's keyboard: a stack's frames, and the spot cursor's keys in the Spot tool.
        .modifier(DiffractionKeyedPane(keys: patternKeys))
        // The pane going (another file, another room) leaves the readout naming a point of a pattern that is not shown: it goes until the
        // pointer moves (the status line and VoiceOver read it).
        .onDisappear { appState.diffractionRoom.readout = nil }
    }

    /// The Tilt tool's drag (#787): the simulated spots tilt with the drag, or turn about the beam with the pointer on an ⌥ drag, from
    /// the orientation drawn when the drag started (`ZoneAxisOverlay.tilted`, `.turned`). ⌥ is read once, at the start
    /// (`ModifierKeys`: a SwiftUI drag carries no modifier keys).
    private func turnByHand(_ value: DragGesture.Value, layout: DiffractionLayout) {
        if handDrag == nil {
            guard let base = analysis.drawnOrientation else { return }
            handDrag = (base, ModifierKeys.optionIsDown)
        }
        guard let handDrag else { return }
        if handDrag.turns {
            guard let c = analysis.centre else { return }
            let centre = layout.point(column: c.column, row: c.row)
            func offset(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.y - centre.y), Double(p.x - centre.x)) }
            if let o = ZoneAxisOverlay.turned(handDrag.base, start: offset(value.startLocation), now: offset(value.location)) {
                analysis.turnByHand(to: o)
            }
        } else {
            analysis.turnByHand(to: ZoneAxisOverlay.tilted(handDrag.base, drag: SIMD2(Double(value.translation.height), Double(value.translation.width))))
        }
    }

    /// The annulus the drag would make, in pixels: the distances of its two ends from the centre.
    private func radii(from a: CGPoint, to b: CGPoint, layout: DiffractionLayout) -> (Double, Double)? {
        guard let centre = analysis.centre else { return nil }
        func r(_ p: CGPoint) -> Double {
            let q = layout.pixel(at: p)
            let dy = q.row - centre.row, dx = q.column - centre.column
            return (dx * dx + dy * dy).squareRoot()
        }
        let (ra, rb) = (r(a), r(b))
        guard abs(ra - rb) >= 1 else { return nil }
        return (min(ra, rb), max(ra, rb))
    }
}

// MARK: - The Spot tool's twin

/// The VoiceOver twin of a click in the Spot tool (mac4DSTEM's "Label centre here"): the shared cursor and "Add spot here", which
/// makes the click's own call with the cursor's row and column. On the owners at the moment of use, as `ImageRoomKeys`; the
/// modifier below only forwards to it, so a test drives these same calls.
@MainActor
struct SpotCursorActions {
    let image: CalibratedImage
    let analysis: DiffractionAnalysis

    static let addActionName = "Add spot here"

    /// Whether a click on the pattern adds a spot: in the Spot tool. The click and the twin ask the same.
    static func addsSpots(_ view: DiffractionViewState) -> Bool { view.tool == .spot }

    /// The centre the room draws and centres its view on, the pattern's (`analysis.centre`), at its nearest pixel; the picture's
    /// middle before there is one. Where the cursor starts, and where "Place point at centre" takes it.
    func centre() -> MarkCursor.Pixel {
        analysis.centre.flatMap { MarkCursor.nearest(column: $0.column, row: $0.row, width: image.width, height: image.height) }
            ?? MarkCursor.centre(width: image.width, height: image.height)
    }

    /// Where the cursor is, on this pattern: where it was moved, else the pattern's centre.
    func pixel(_ cursor: MarkCursor.Pixel?) -> MarkCursor.Pixel {
        guard let cursor else { return centre() }
        return MarkCursor.clamped(cursor, width: image.width, height: image.height)
    }

    /// One step that way (`fine`: one pixel), held on the pattern.
    func moved(_ cursor: MarkCursor.Pixel?, by step: MarkCursor.Move, fine: Bool = false) -> MarkCursor.Pixel {
        MarkCursor.moved(pixel(cursor), by: step, fine: fine, width: image.width, height: image.height)
    }

    /// The element's value: the status line's readout of the cursor's pixel, in the pointer's words ("x 241, y 311 · R 57.0 px ·
    /// q … · d …").
    func spokenValue(_ cursor: MarkCursor.Pixel?) -> String {
        let p = pixel(cursor)
        return DiffractionReadoutText.text(column: Double(p.x), row: Double(p.y), centre: analysis.centre,
                                           calibration: analysis.calibration(for: image))
    }

    /// "Add spot here": the click's `addSpot` on the cursor's pixel, at its centre, where a click on that pixel's centre reads
    /// (`DiffractionLayout.pixel(at:)`). The spot it listed.
    @discardableResult
    func addSpotHere(_ cursor: MarkCursor.Pixel?) -> MeasuredSpot? {
        let p = pixel(cursor)
        analysis.addSpot(image: image, row: Double(p.y), column: Double(p.x))
        return analysis.spots.last
    }

    /// What VoiceOver hears after "Add spot here": the spot's row as the readout table lists it (`announcement(_:)` of the row).
    func announcement(for spot: MeasuredSpot?) -> String {
        guard let spot else { return "No spot added" }
        guard let row = analysis.readout(image: image).first(where: { $0.id == spot.id }) else { return "Spot added" }
        return Self.announcement(row)
    }

    /// A new spot's row in the table's words: its name, d and family ("Added Spot 2, d 1.4419 ångströms, {220}"), the verdict where
    /// there is no family, and the verdict alone where there is no d (no centre found, no scale yet), as the table shows them.
    static func announcement(_ row: DiffractionReadoutRow) -> String {
        var parts = ["Added " + DiffractionReadoutFormat.spokenName(row)]
        if row.d != nil { parts.append("d " + DiffractionReadoutFormat.cell(.d, row) + " ångströms") }
        parts.append(row.family ?? row.verdictWords)
        return parts.joined(separator: ", ")
    }
}

/// The Spot tool's named actions on an element of their own at the cursor, while a click adds a spot. Beside the pattern's element
/// (which ignores its children), so the pattern keeps its label, its readout value and its zoom actions; nothing here is drawn, and
/// it takes no hits. The work is the pane's (`place`, `move`, `add`), which the keys share; it holds no image (#577).
private struct SpotCursorAccessibility: ViewModifier {
    let active: Bool
    /// The pattern's map, which places the element on the cursor's pixel at the pane's zoom.
    let layout: DiffractionLayout
    let pixel: MarkCursor.Pixel
    let spoken: String
    let place: @MainActor () -> Void
    let move: @MainActor (MarkCursor.Move, Bool) -> Void
    let add: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if active { element }
        }
    }

    private var element: some View {
        Color.clear
            .frame(width: MarkCursor.elementSide, height: MarkCursor.elementSide)
            .accessibilityElement()
            .accessibilityLabel("Spot point")
            .accessibilityValue(spoken)
            .accessibilityHint("Add spot here measures the spot at this point.")
            .accessibilityAction(named: MarkCursor.placeActionName) { place() }
            // The coarse and the one-pixel moves (macEM#510).
            .modifier(MarkCursorMoveActions(move: move))
            .accessibilityAction(named: SpotCursorActions.addActionName) { add() }
            .accessibilityIdentifier("diffraction.spotCursor")
            .position(MarkCursor.elementCentre(layout.point(column: Double(pixel.x), row: Double(pixel.y)), in: layout.box))
            .allowsHitTesting(false)
    }
}

// MARK: - View > Zoom

/// What View > Zoom In, Zoom Out or Zoom to Fit asks of the pattern. The commands act on a `PaneZoomModel` (ShellControls) and on
/// nothing else, and the pattern's zoom is a half-side about its centre (`DiffractionViewState`), not a `ZoomPan`. So the room publishes
/// a model of its own that follows the pane's zoom (the badge's number) and reads what the menu did to it, as MacEMUI's maps keep a
/// model beside their shared transform. The rules are pure; the three steps below them are the whole round, on the real owners.
nonisolated enum DiffractionZoomCommand: Equatable {
    /// The half-side divided by this factor (`DiffractionViewState.zoom(by:image:)`).
    case zoom(by: Double)
    /// The pattern's own extent again (`DiffractionViewState.fitView`).
    case fit

    /// The zoom the menu's model holds while the pane shows `halfSide` and a fit shows `fitHalfSide`: the badge's number, held to the
    /// model's own range (`ZoomPan.clampZoom`); 1 when either is not a positive number.
    static func mirrored(fitHalfSide: Double, halfSide: Double) -> CGFloat {
        guard fitHalfSide.isFinite, halfSide.isFinite, fitHalfSide > 0, halfSide > 0 else { return 1 }
        return ZoomPan.clampZoom(CGFloat(fitHalfSide / halfSide))
    }

    /// What the menu asked for, from the model's zoom and the pane's (`mirrored`): nil when they agree (the model only followed the
    /// pane, or the menu's step stopped at the model's limit), the fit at 1×, else the step as a factor on the pane's zoom.
    static func asked(model: CGFloat, mirrored: CGFloat) -> DiffractionZoomCommand? {
        guard model.isFinite, model > 0, mirrored > 0, model != mirrored else { return nil }
        return model == 1 ? .fit : .zoom(by: Double(model / mirrored))
    }

    /// The pane's zoom as the model holds it.
    @MainActor
    static func mirrored(_ view: DiffractionViewState, image: CalibratedImage) -> CGFloat {
        mirrored(fitHalfSide: view.fitHalfSide(for: image), halfSide: view.viewHalfSide(for: image))
    }

    /// The pane zoomed (the wheel, a pinch, a double-click, the pattern's extent found) or a menu step was performed: the model follows
    /// what the pane shows, written only when it differs.
    @MainActor
    static func follow(_ view: DiffractionViewState, image: CalibratedImage, with model: PaneZoomModel) {
        let shown = mirrored(view, image: image)
        if model.state.zoom != shown { model.update { $0.zoom = shown } }
    }

    /// The model changed: when the menu did it, the same step on the pattern (the VoiceOver actions' step, a factor of 2).
    @MainActor
    static func perform(from model: PaneZoomModel, on view: DiffractionViewState, image: CalibratedImage) {
        guard let command = asked(model: model.state.zoom, mirrored: mirrored(view, image: image)) else { return }
        switch command {
        case .zoom(let factor): view.zoom(by: factor, image: image)
        case .fit: view.fitView()
        }
    }
}

/// Publishes the pattern's zoom to View > Zoom In, Zoom Out and Zoom to Fit while the room is shown. Its own modifier with the model as
/// its state, so a zoom step re-evaluates this and not the room around it.
private struct DiffractionZoomCommands: ViewModifier {
    let item: OpenItem
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }
    let view: DiffractionViewState
    @State private var model = PaneZoomModel()

    func body(content: Content) -> some View {
        content
            .zoomCommandTarget(model, isTarget: true)
            .onChange(of: DiffractionZoomCommand.mirrored(view, image: image), initial: true) {
                DiffractionZoomCommand.follow(view, image: image, with: model)
            }
            // The step is performed, then the model is put back on what the pane shows: a step the pane takes in part or not at all
            // (its 8 px limit, the whole image, a zoom past the model's range) changes no mirrored value, so the half above would not
            // run and the model would stay off the pane's zoom, where the next step the other way does nothing.
            .onChange(of: model.state.zoom) {
                DiffractionZoomCommand.perform(from: model, on: view, image: image)
                DiffractionZoomCommand.follow(view, image: image, with: model)
            }
    }
}

/// The status line's readout over the pattern (control placement §7): "x 290, y 256 · R 54,8 px · q 0,6848 Å⁻¹ · d 1,460 Å", the pixel
/// alone until there is a centre and a scale. nil off the image is the caller's (the hover ends).
nonisolated enum DiffractionReadoutText {
    static func text(column: Double, row: Double, centre: DiffractionCentre?, calibration: DiffractionCalibration?) -> String {
        let pixel = "x \(Int(column.rounded())), y \(Int(row.rounded()))"
        guard let centre, let calibration else { return pixel }
        let r = ((row - centre.row) * (row - centre.row) + (column - centre.column) * (column - centre.column)).squareRoot()
        let q = calibration.q(radius: r)
        guard q.isFinite, q > 0 else { return "\(pixel) · R \(Num.fixed(r, 1)) px" }
        return "\(pixel) · R \(Num.fixed(r, 1)) px · q \(Num.fixed(q, 4)) Å⁻¹ · d \(Num.fixed(1 / q, 3)) Å"
    }
}

// MARK: - Overlays

private struct DiffractionOverlay: View {
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    let rows: [DiffractionReadoutRow]
    let layout: DiffractionLayout
    let drag: (Double, Double)?
    /// Where the pointer is over the pattern: the found spot under it carries its d label (#1045).
    let pointer: CGPoint?
    /// Increase Contrast thickens the overlay lines (#799).
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let centre = analysis.centre
        let high = contrast == .increased
        let line = OverlaySignal.width(1.5, increasedContrast: high)
        let rings = analysis.rings
        let spots = analysis.spots
        let labels = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, label(for: $0)) })
        // A found spot's d label only on the selected row and under the pointer (#1045); every ring keeps its own.
        let shown = DiffractionMarkLabels.labelled(
            rings: rings.map(\.id),
            spots: spots.compactMap { spot in
                guard let r = spot.row, let c = spot.column else { return nil }
                let p = layout.point(column: c, row: r)
                return (spot.id, SIMD2(Double(p.x), Double(p.y)))
            },
            selection: view.selection, pointer: pointer.map { SIMD2(Double($0.x), Double($0.y)) })
        Canvas { ctx, size in
            func point(column: Double, row: Double) -> CGPoint { layout.point(column: column, row: row) }
            let ppp = layout.pointsPerPixel
            if let centre {
                let c = point(column: centre.column, row: centre.row)
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - 8, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 8, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - 8)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 8))
                ctx.stroke(cross, with: .color(.white), lineWidth: line)
                let (inner, outer) = drag ?? (view.annulusInner, view.annulusOuter)
                for r in [inner, outer] {
                    let rect = CGRect(x: c.x - CGFloat(r) * ppp, y: c.y - CGFloat(r) * ppp, width: 2 * CGFloat(r) * ppp, height: 2 * CGFloat(r) * ppp)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            for ring in rings {
                guard let ellipse = ring.ellipse else { continue }
                var path = Path()
                let points = RingOverlay.polyline(ellipse)
                for (i, p) in points.enumerated() {
                    let q = point(column: p.x, row: p.y)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.closeSubpath()
                // The calibrating ring is dashed as well as orange (#799).
                let signal = OverlaySignal.diffractionRing(calibrating: ring.isCalibrating)
                ctx.stroke(path, with: .color(ring.isCalibrating ? .orange : .yellow), style: StrokeStyle(lineWidth: line, dash: signal.dash))
                if shown.contains(ring.id), let text = labels[ring.id], let first = points.first {
                    let at = point(column: first.x, row: first.y)
                    let label = Text(text).font(.caption).foregroundStyle(.white)
                    let place = DiffractionHalo.beside(at, width: ctx.resolve(label).measure(in: size).width, within: size.width)
                    DiffractionHalo.draw(label, at: place.point, anchor: place.anchor, in: ctx)
                }
            }
            for spot in spots {
                guard let r = spot.row, let c = spot.column else { continue }
                let p = point(column: c, row: r)
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - 6, y: p.y - 6)); cross.addLine(to: CGPoint(x: p.x + 6, y: p.y + 6))
                cross.move(to: CGPoint(x: p.x - 6, y: p.y + 6)); cross.addLine(to: CGPoint(x: p.x + 6, y: p.y - 6))
                ctx.stroke(cross, with: .color(.red), lineWidth: line)
                if shown.contains(spot.id), let text = labels[spot.id] {
                    DiffractionHalo.draw(Text(text).font(.caption).foregroundStyle(.white), at: CGPoint(x: p.x + 8, y: p.y - 6),
                                         anchor: .leading, in: ctx)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func label(for row: DiffractionReadoutRow) -> String {
        guard let d = row.d else { return "" }
        return "d \(Num.fixed(d, 3)) Å" + (row.family.map { " · \($0)" } ?? "")
    }
}

/// The simulated spots of a typed zone axis (#782): a ring per spot, its size growing with the square root of its intensity
/// against the strongest, in cyan (the measured spots are red crosses, the rings yellow), and the hkl of those the `hkl labels`
/// pop-up asks for (#1045): Strongest up to 16 from the brightest down, All, or None, each label only where it meets no other and
/// not the centre's mark, and where it clears every other ring (#1030), placed by `HKLLabelPlacement` on a dark halo. The caption
/// font is 10 pt.
/// A spot double diffraction adds (#786) is a dashed ring of the smallest size, labelled after the others.
private struct SimulatedSpotsOverlay: View {
    let spots: [ZoneAxisOverlay.Spot]
    let labelMode: HKLLabelMode
    /// The central beam's mark, in points: no label covers it.
    let beam: CGPoint?
    let layout: DiffractionLayout

    private nonisolated static func radius(_ spot: ZoneAxisOverlay.Spot) -> Double { 3 + 6 * spot.relative.squareRoot() }

    var body: some View {
        let layout = layout
        let placed = HKLLabelPlacement.place(
            spots, mode: labelMode,
            point: { spot in
                let p = layout.point(column: spot.column, row: spot.row)
                return SIMD2(Double(p.x), Double(p.y))
            },
            radius: { Self.radius($0) }, beam: beam.map { SIMD2(Double($0.x), Double($0.y)) })
        Canvas { ctx, _ in
            for spot in spots {
                let p = layout.point(column: spot.column, row: spot.row)
                let r = CGFloat(Self.radius(spot))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.cyan),
                           style: StrokeStyle(lineWidth: 1.5, dash: spot.isDoubleDiffraction ? [2, 2] : []))
            }
            for label in placed {
                DiffractionHalo.draw(Text(label.spot.label).font(.caption).foregroundStyle(.cyan),
                                     at: CGPoint(x: label.low.x, y: label.low.y), anchor: .topLeading, in: ctx)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A label on the pattern with a dark halo, so it reads over a bright spot in every colormap (#1045).
nonisolated enum DiffractionHalo {
    /// Where a ring's label sits beside the ring's point `at` (#1090): to its right, or to its left, ending there, where a label of
    /// `width` would run past the pattern's right edge (`limit`), so "d 2.355 Å · {111}" is never cut by the edge.
    static func beside(_ at: CGPoint, width: CGFloat, within limit: CGFloat) -> (point: CGPoint, anchor: UnitPoint) {
        if at.x + 6 + width <= limit { return (CGPoint(x: at.x + 6, y: at.y - 8), .leading) }
        return (CGPoint(x: at.x - 6, y: at.y - 8), .trailing)
    }

    static func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint, in ctx: GraphicsContext) {
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
            layer.draw(text, at: point, anchor: anchor)
        }
    }
}

/// The pattern's legend (#1045): one row per kind of mark, the mark drawn by shape as well as colour (#923).
private struct DiffractionLegendChip: View {
    let entries: [DiffractionLegend.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 5) {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        switch entry.mark {
                        case .simulated(let mark):
                            ctx.stroke(Path(OverlaySignal.outline(mark, centre: c, radius: 4.5)), with: .color(.cyan), lineWidth: 1.5)
                        case .found, .unexplained:
                            var cross = Path()
                            cross.move(to: CGPoint(x: c.x - 4, y: c.y - 4)); cross.addLine(to: CGPoint(x: c.x + 4, y: c.y + 4))
                            cross.move(to: CGPoint(x: c.x - 4, y: c.y + 4)); cross.addLine(to: CGPoint(x: c.x + 4, y: c.y - 4))
                            ctx.stroke(cross, with: .color(.red),
                                       style: StrokeStyle(lineWidth: 1.5, dash: entry.mark == .unexplained ? [2, 1.5] : []))
                        }
                    }
                    .frame(width: 12, height: 12) // science: the legend chip drawn on the pattern
                    Text(entry.text).font(.caption).foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}

/// The shown variants' spots (#808): a pink diamond per merged spot, its size growing with the square root of its intensity against
/// the strongest, as the simulated spots are drawn; a spot several variants predict is one diamond. A diamond, not the matrix's ring,
/// so the two are told apart without colour (#923, `OverlaySignal.simulatedSpot`).
private struct VariantSpotsOverlay: View {
    let pixels: [VariantPixel]
    let layout: DiffractionLayout
    /// Spots double diffraction adds (#809): dashed diamonds of the smallest size.
    var dashed = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { ctx, _ in
            let mark = OverlaySignal.simulatedSpot(variant: true)
            let width = OverlaySignal.width(1.5, increasedContrast: contrast == .increased)
            for spot in pixels {
                let p = layout.point(column: spot.column, row: spot.row)
                let r = 3 + 6 * CGFloat(spot.relative.squareRoot())
                ctx.stroke(Path(OverlaySignal.outline(mark, centre: p, radius: r)), with: .color(.pink),
                           style: StrokeStyle(lineWidth: width, dash: dashed ? [2, 2] : []))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The tables, tabs of the bottom area

/// One of the room's tables as a tab of the shell's bottom area (#1094, #1112): `WorkspaceView` registers one `ProcessTab` per table
/// of the part (`DiffractionPart.tables`) beside Output, under the bar the person drags; the area's header picks the one shown, at
/// the area's full width. The selected document is read here, at each draw, and never held by the tab. Readout and Spots are two
/// tabs, where the strip under the pattern switched between them; Powder lists its peaks.
struct DiffractionTablePane: View {
    let table: DiffractionTable
    @Environment(AppState.self) private var appState

    var body: some View {
        if let item = appState.openItems.selected {
            DiffractionTableContent(item: item, table: table)
        }
    }
}

private struct DiffractionTableContent: View {
    let item: OpenItem
    let table: DiffractionTable
    @Environment(AppState.self) private var appState
    /// Read from the item, never stored: SwiftUI keeps a view's closures (hover, gestures, commands) after the view is gone, and a stored
    /// image kept its pixels alive after its tab closed (macTEM#574, `ImagePane.image`).
    private var image: CalibratedImage { item.session.image ?? ImagePane.blankImage }

    var body: some View {
        let analysis = item.diffraction
        let view = item.diffractionView
        switch table {
        case .readout:
            DiffractionReadoutTable(analysis: analysis, view: view, rows: analysis.readout(image: image))
        case .spots:
            // A Simulation document lists its simulated spots (#907); a measured pattern Index's once it answers (#785: hkl, expected d
            // and misfit per spot).
            if DemoDocuments.isSimulation(item.url) {
                DiffractionSpotTable(view: view, rows: SimulationEmptyState.spotRows(of: item, image: image),
                                     empty: "Add a phase and show the simulated spots to list them.", selectsMarks: false,
                                     showsDynamical: item.dynamicalBeams != nil)
            } else if analysis.indexOutcome == nil {
                DiffractionSpotTable(view: view, rows: [], empty: "Index the pattern to list its spots with their hkl.")
            } else {
                DiffractionSpotTable(view: view, rows: analysis.indexSpotRows)
            }
        case .peaks:
            // The Powder part lists the powder pattern's peaks (#921), strongest first, with ⌘C.
            DiffractionPowderPeakTable(table: DiffractionPowderSection.table(of: item, openItems: appState.openItems))
        }
    }
}

// MARK: - The readout

/// The rings and spots as a system `Table` with a selection: arrow keys, ⌫ (removes the selected row), ⌘C (copies it, tab-separated under
/// the column titles), column resizing and VoiceOver rows come with it. The titles and the cells are `DiffractionReadoutFormat`'s, so the
/// copied text is what the table shows. A value a journey reads is a cell's accessibility value (`diffraction.row.<kind><n>.<column>`);
/// the d there has one decimal more than the cell (`DiffractionValueFormat.spacing`). A header is drawn as its title and spoken as
/// words (`Column.spoken`: the titles are symbols and units, and the first is empty), and the ring that sets the scale says so, not
/// "●" (whether the system's table header speaks a `Text`'s accessibility label is unverified on screen).
private struct DiffractionReadoutTable: View {
    let analysis: DiffractionAnalysis
    let view: DiffractionViewState
    let rows: [DiffractionReadoutRow]
    @Environment(\.undoManager) private var undoManager

    private typealias Column = DiffractionReadoutFormat.Column

    var body: some View {
        // The selection is read here, in the leaf: handed to the table as a binding to the view state, and to Edit > Copy as a value.
        let selection = Binding<UUID?>(get: { view.selection }, set: { view.selection = $0 })
        let selected = view.selection
        Table(rows, selection: selection) {
            TableColumn(header(.name)) { row in
                Text(DiffractionReadoutFormat.cell(.name, row)).help(row.isCalibrating ? "Set the scale" : "")
                    .accessibilityLabel(DiffractionReadoutFormat.spokenName(row))
                    .accessibilityValue(DiffractionReadoutFormat.spokenMark(row))
            }.width(min: 52, ideal: 58)
            TableColumn(header(.radius)) { row in Text(DiffractionReadoutFormat.cell(.radius, row)).monospacedDigit() }.width(min: 44, ideal: 50)
            TableColumn(header(.q)) { row in Text(DiffractionReadoutFormat.cell(.q, row)).monospacedDigit() }.width(min: 56, ideal: 62)
            TableColumn(header(.d)) { row in
                Text(DiffractionReadoutFormat.cell(.d, row)).monospacedDigit()
                    .accessibilityIdentifier("diffraction.row.\(row.kind.rawValue)\(row.number).d")
                    .accessibilityValue(DiffractionValueFormat.spacing(row.d))
            }.width(min: 52, ideal: 56)
            TableColumn(header(.family)) { row in
                Text(DiffractionReadoutFormat.cell(.family, row))
                    .accessibilityIdentifier("diffraction.row.\(row.kind.rawValue)\(row.number).family")
                    .accessibilityValue(row.family ?? "")
            }.width(min: 46, ideal: 52)
            TableColumn(header(.dListed)) { row in Text(DiffractionReadoutFormat.cell(.dListed, row)).monospacedDigit() }.width(min: 52, ideal: 58)
            TableColumn(header(.intensity)) { row in Text(DiffractionReadoutFormat.cell(.intensity, row)).monospacedDigit() }.width(min: 40, ideal: 46)
            TableColumn(header(.delta)) { row in Text(DiffractionReadoutFormat.cell(.delta, row)).monospacedDigit() }.width(min: 48, ideal: 54)
            TableColumn(header(.odds)) { row in Text(DiffractionReadoutFormat.cell(.odds, row)).monospacedDigit() }.width(min: 60, ideal: 68)
            TableColumn(header(.verdict)) { row in
                Text(DiffractionReadoutFormat.cell(.verdict, row)).lineLimit(1)
                    .help(row.verdictDetail ?? row.verdictWords)
                    .accessibilityIdentifier("diffraction.row.\(row.kind.rawValue)\(row.number).verdict")
                    .accessibilityValue(row.verdictWords)
            }.width(min: 70, ideal: 90)
        }
        .onDeleteCommand { if let id = view.selection { DiffractionUndo.remove(id, in: analysis, undoManager: undoManager); view.selection = nil } }
        // ⌘C and Edit > Copy: the selected ring or spot; dimmed with no row selected.
        .onCopyCommand(perform: rows.contains(where: { $0.id == selected }) ? { copied(selected) } : nil)
        .overlay {
            if rows.isEmpty {
                Text("Drag an annulus over a ring (Ring tool) or click a spot (Spot tool). A scale comes first: Calibrate on a standard's ring, or use the file's.")
                    .font(.callout).foregroundStyle(.secondary).padding(10).allowsHitTesting(false)
            }
        }
        // Empty, the hint sits on the plain background under the header row, never across striped bars (#1041).
        .alternatingRowBackgrounds(TableStripes.shown(rowCount: rows.count) ? .automatic : .disabled)
        .accessibilityIdentifier("diffraction.readout")
    }

    /// A column's header: the title as drawn, with the column's words as what VoiceOver calls it.
    private func header(_ column: Column) -> Text {
        Text(column.title).accessibilityLabel(column.spoken)
    }

    /// What ⌘C hands the system: the selected row as the table shows it (`DiffractionReadoutFormat.copyText`), nothing when none is.
    private func copied(_ selected: UUID?) -> [NSItemProvider] {
        let picked = rows.filter { $0.id == selected }
        guard !picked.isEmpty else { return [] }
        return [NSItemProvider(object: DiffractionReadoutFormat.copyText(picked) as NSString)]
    }
}

// MARK: - The Spots table

/// Index's spots (#785), or a Simulation document's (#907): Spot, hkl, R px, R mm, q, d, d expected, Δd/d % and Phase and, with Dynamical on (#911), I dyn %, sortable by
/// any column (ties by the spot's number, so the rows keep their order). A row's selection is the mark's: selecting it selects the spot on the pattern and in the readout.
/// The table is the pattern's text alternative: VoiceOver reads each row's cells, and the pane says the spots are listed here.
private struct DiffractionSpotTable: View {
    let view: DiffractionViewState
    let rows: [PatternIndexing.SpotRow]
    /// What the empty table says.
    var empty = "Index found no spot still marked: Index again."
    /// A row is a mark (Index's spots): selecting it selects the spot. A Simulation document's rows are no marks, so they keep a
    /// selection of their own and never reach the Rings section's Remove (#907).
    var selectsMarks = true
    @State private var ownSelection: UUID?
    /// A Simulation document with Dynamical on (#911): the I dyn % column, each spot's beam at the shown thickness.
    var showsDynamical = false
    @State private var sortOrder = [KeyPathComparator(\PatternIndexing.SpotRow.number)]

    private typealias Column = DiffractionSpotFormat.Column

    var body: some View {
        let selection = selectsMarks ? Binding<UUID?>(get: { view.selection }, set: { view.selection = $0 }) : $ownSelection
        let sorted = DiffractionSpotFormat.sorted(rows, by: sortOrder)
        Table(sorted, selection: selection, sortOrder: $sortOrder) {
            TableColumn(header(.spot), value: \.number) { row in
                Text(DiffractionSpotFormat.cell(.spot, row)).accessibilityIdentifier("diffraction.spots.\(row.number).spot")
            }.width(min: 44, ideal: 52)
            TableColumn(header(.hkl), value: \.hklText) { row in
                Text(DiffractionSpotFormat.cell(.hkl, row)).monospacedDigit()
                    .accessibilityIdentifier("diffraction.spots.\(row.number).hkl")
                    .accessibilityValue(DiffractionSpotFormat.spokenHKL(row))
            }.width(min: 44, ideal: 52)
            TableColumn(header(.radius), value: \.radiusPx) { row in Text(DiffractionSpotFormat.cell(.radius, row)).monospacedDigit() }
                .width(min: 44, ideal: 50)
            TableColumn(header(.radiusMM), value: \.radiusMMKey) { row in Text(DiffractionSpotFormat.cell(.radiusMM, row)).monospacedDigit() }
                .width(min: 44, ideal: 52)
            TableColumn(header(.q), value: \.q) { row in Text(DiffractionSpotFormat.cell(.q, row)).monospacedDigit() }.width(min: 56, ideal: 62)
            TableColumn(header(.d), value: \.d) { row in Text(DiffractionSpotFormat.cell(.d, row)).monospacedDigit() }.width(min: 52, ideal: 56)
            TableColumn(header(.dExpected), value: \.dExpectedKey) { row in
                Text(DiffractionSpotFormat.cell(.dExpected, row)).monospacedDigit()
            }.width(min: 56, ideal: 64)
            TableColumn(header(.delta), value: \.deltaKey) { row in
                Text(DiffractionSpotFormat.cell(.delta, row)).monospacedDigit()
                    .accessibilityIdentifier("diffraction.spots.\(row.number).delta")
            }.width(min: 48, ideal: 54)
            TableColumn(header(.phase), value: \.phase) { row in Text(DiffractionSpotFormat.cell(.phase, row)) }.width(min: 44, ideal: 60)
            if showsDynamical {
                TableColumn(header(.dynamical), value: \.dynamicalKey) { row in
                    Text(DiffractionSpotFormat.cell(.dynamical, row)).monospacedDigit()
                        .accessibilityIdentifier("diffraction.spots.\(row.number).dynamical")
                }.width(min: 52, ideal: 60)
            }
        }
        .overlay {
            if rows.isEmpty {
                Text(empty)
                    .font(.callout).foregroundStyle(.secondary).padding(10).allowsHitTesting(false)
            }
        }
        .alternatingRowBackgrounds(TableStripes.shown(rowCount: rows.count) ? .automatic : .disabled)
        .accessibilityIdentifier("diffraction.spots")
        .accessibilityLabel("Spots")
    }

    private func header(_ column: Column) -> Text { Text(column.title).accessibilityLabel(column.spoken) }
}

// MARK: - The values beside the words

/// The numbers the room hands accessibility beside the text it draws: the scale (Δq, Å⁻¹ per pixel), the half-side the pane shows (px)
/// and a row's d (Å). Each is one number with more decimals than the text, written in the reader's locale as the text is (#329:
/// VoiceOver spoke "0.01250" under a header that read "0,01250"), never grouped. A UI journey reads them and parses the reader's
/// decimal mark. Pure.
nonisolated enum DiffractionValueFormat {
    /// Δq to five decimals, "0,01250" in a comma locale; "" while there is no scale.
    static func scale(_ deltaQ: Double?, locale: Locale = .autoupdatingCurrent) -> String {
        deltaQ.map { Num.fixed($0, 5, locale: locale) } ?? ""
    }

    /// The half-side to three decimals, "79,412".
    static func halfSide(_ half: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Num.fixed(half, 3, locale: locale)
    }

    /// A row's d to five decimals, "2,03910"; "" for a row that has none.
    static func spacing(_ d: Double?, locale: Locale = .autoupdatingCurrent) -> String {
        d.map { Num.fixed($0, 5, locale: locale) } ?? ""
    }
}

/// The crystal pane's share of the centre beside the pattern (#1046): a third, so the pattern, the data, has two thirds. The centre
/// (`WorkspaceCentre`, #1094) keeps the key the split had under `HorizontalPaneSplit` and `PaneSplit`, whose stored value was the
/// crystal's share too, so a place dragged in an earlier version is read back and only the default changes. Pure.
nonisolated enum DiffractionCrystalSplit {
    static let storageKey = "diffraction.crystalSplit"
    static let defaultCrystalFraction = 1.0 / 3

    /// The pattern's side, points, in a centre `width` × `height` (the infobar and the bottom area already taken off the height): the
    /// crystal pane takes `crystalFraction` of the width less the divider, held to `minimumPane` each side as the centre holds it
    /// (`CentreSplitModel.widths`), the pattern's panel takes its inset and its header off what is left, and the square pattern is the
    /// smaller of the two sides of the panel's content. No margin of the room's own.
    static func patternSide(width: CGFloat, height: CGFloat, crystalFraction: Double, minimumPane: CGFloat) -> CGFloat {
        let model = CentreSplitModel(arrangement: .split, defaultFraction: defaultCrystalFraction,
                                     minimumLeading: minimumPane, minimumTrailing: minimumPane)
        let panel = model.widths(fraction: crystalFraction, total: width).trailing
        let across = panel - 2 * LayoutPolicy.centrePanelPadding
        let down = height - 2 * LayoutPolicy.centrePanelPadding - LayoutPolicy.paneHeaderHeight - LayoutPolicy.centrePanelHeaderSpacing
        return max(min(across, down), 0)
    }
}
