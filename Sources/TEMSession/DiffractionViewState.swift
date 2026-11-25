//
//  DiffractionViewState.swift
//  Role: what the Diffraction room's views hold and the results owner must not: the tool, the log toggle, the annulus being set, the
//        selected row, the zoom, and the pattern's display (colormap, window, gamma: the Display section, control placement §5). One per open file (`OpenItem.diffractionView`), beside `DiffractionAnalysis`; a change here never
//        invalidates a reader of the results (the readout, the Results room, the exports), as the EDX room keeps `EDXRoomState`
//        apart from `EDXSession`. Display only: no number a scientist reads. Showing a pattern is asked of this owner (`show`: the
//        bind, the pattern's extent and its canvas), as the FFT room asks its own; the view's task makes the one call.
//

import Foundation
import Observation
import ShellMetal
import TEMCore
import ShellEDXModel

@Observable
package final class DiffractionViewState {
    /// Ring: drag an annulus; Spot: click a spot; Tilt (#787): drag the simulated spots to tilt them, ⌥ drag to turn them in the plane.
    package enum Tool: String, CaseIterable, Sendable { case ring, spot, tilt }

    package var tool: Tool = .ring
    /// The table under the pattern: the readout, Index's Spots table once Index has an answer (#785), or the powder pattern's peaks
    /// while the Powder Pattern pane is shown (#921). The readout when the chosen one is not offered.
    package enum LowerTable: String, CaseIterable, Sendable { case readout, spots, peaks }
    package var lowerTable: LowerTable = .spots
    package var useLog = true
    /// What the pane beside the pattern shows (#921): the crystal (#790), the zone-axis map (#814) or the powder pattern (#810). Results
    /// of the room, so a pane, never an inspector section (control placement §1).
    package enum SidePane: String, CaseIterable, Sendable { case crystal, zoneAxisMap, powder }
    package var sidePane: SidePane = .crystal
    /// The pane beside the pattern is shown: View > Show Crystal, Show Zone-axis Map and Show Powder Pattern show it with their pane.
    package var showsSidePane = true

    /// The pane beside the pattern shows `pane`.
    package func isShowing(_ pane: SidePane) -> Bool { showsSidePane && sidePane == pane }

    /// A View menu item: hides `pane` when it is shown, else shows the side pane with it.
    package func toggle(_ pane: SidePane) {
        if isShowing(pane) {
            showsSidePane = false
        } else {
            sidePane = pane
            showsSidePane = true
        }
    }

    /// The crystal pane beside the pattern (#789): shown when the side pane shows the crystal.
    package var showsCrystal: Bool {
        get { isShowing(.crystal) }
        set { if newValue != isShowing(.crystal) { toggle(.crystal) } }
    }

    /// The tables the strip under the pattern offers, in order: the readout, the Spots table with `hasSpots`, the powder peaks while
    /// the Powder Pattern pane is shown.
    package func lowerTables(hasSpots: Bool) -> [LowerTable] {
        [.readout] + (hasSpots ? [.spots] : []) + (isShowing(.powder) ? [.peaks] : [])
    }

    /// The table the strip shows: the chosen one when it is offered, else the readout.
    package func shownLowerTable(hasSpots: Bool) -> LowerTable {
        lowerTables(hasSpots: hasSpots).contains(lowerTable) ? lowerTable : .readout
    }
    /// The crystal pane draws the unit cell's edges.
    package var showsUnitCell = true
    package private(set) var annulusInner = 28.0
    package private(set) var annulusOuter = 40.0
    /// The ring or spot the readout highlights (and the ⌫ key removes).
    package var selection: UUID?
    /// The view's half-side in pixels about the centre: the user's zoom, else the pattern's own extent (`DiffractionCompute.contentRadius`),
    /// else the whole image.
    package var zoomHalfSide: Double?
    package private(set) var autoHalfSide: Double?
    /// The pattern as drawn: its canvas (the file's pixels, drawn log or linear) and the Display section's colormap, window and gamma.
    /// Its own, not the Image room's: a pattern reads in viridis where the same file's image reads in gray.
    package let presentation: ImagePresentation = {
        let p = ImagePresentation()
        p.colormap = .viridis
        return p
    }()

    package init() {}

    /// The annulus, ordered and at least 1 px from the centre; a non-finite number is refused.
    package func setAnnulus(inner: Double, outer: Double) {
        guard inner.isFinite, outer.isFinite else { return }
        annulusInner = max(min(inner, outer), 1)
        annulusOuter = max(inner, outer)
    }

    package func setAutoExtent(_ radius: Double?) { if autoHalfSide != radius { autoHalfSide = radius } }

    /// The half-side the pane shows now, never more than the image's own half-side nor less than 8 px.
    package func viewHalfSide(for image: CalibratedImage) -> Double {
        let whole = Double(min(image.width, image.height)) / 2
        return min(max(zoomHalfSide ?? autoHalfSide ?? whole, 8), whole)
    }

    package func zoom(by factor: Double, image: CalibratedImage) {
        guard factor.isFinite, factor > 0 else { return }
        zoomHalfSide = viewHalfSide(for: image) / factor
    }

    /// The half-side a fit shows: the pattern's own extent, else the whole image (the zoom badge's 1×).
    package func fitHalfSide(for image: CalibratedImage) -> Double {
        let whole = Double(min(image.width, image.height)) / 2
        return min(max(autoHalfSide ?? whole, 8), whole)
    }

    package func fitView() { zoomHalfSide = nil }

    // MARK: Showing the pattern

    /// What the canvas was drawn from: the image session's generation (`ImageSession.generation`) and the Log switch.
    package struct CanvasSource: Equatable, Sendable {
        package let generation: Int
        package let log: Bool

        package init(generation: Int, log: Bool) {
            self.generation = generation
            self.log = log
        }
    }

    /// The source of the canvas shown; nil before the first.
    package private(set) var canvasSource: CanvasSource?

    /// Whether the canvas is the one the room draws for the image of `generation` with Log as it is now: false while a pass is still
    /// to land (a new pattern of the same size, a CBED pattern at another thickness, a frame, a Log switch) or after the canvas went.
    package func showsCanvas(generation: Int) -> Bool {
        presentation.canvas != nil && canvasSource == CanvasSource(generation: generation, log: useLog)
    }

    /// The room shows this pattern: it appeared, another file took the pane, new pixels replaced it (a frame, a CBED pattern at another
    /// thickness: `generation`), or Log was switched. Binds the results owner to the image, finds how far the pattern has signal (the
    /// view opens on that) and builds the canvas of the display values, both off the main actor. A pass cancelled while it computes
    /// (a quick Log toggle, another file) writes nothing more, so the newer pass's extent and canvas are the ones left on screen.
    package func show(image: CalibratedImage, generation: Int, analysis: DiffractionAnalysis) async {
        analysis.bind(image)
        let log = useLog
        let centre = analysis.centre ?? .imageCentre(width: image.width, height: image.height)
        let radius = await Self.extent(image, centre: centre)
        guard !Task.isCancelled else { return }
        setAutoExtent(radius)
        let canvas = await Self.canvas(image, log: log)
        guard !Task.isCancelled else { return }
        place(canvas, source: CanvasSource(generation: generation, log: log))
    }

    /// The same pass as `show`, at once on the caller's actor: the agent door's picture asks for it when the room has not drawn the
    /// pattern shown (the room is off screen, or its pass is still to land), so the door draws what the room will.
    package func showNow(image: CalibratedImage, generation: Int, analysis: DiffractionAnalysis) {
        analysis.bind(image)
        let centre = analysis.centre ?? .imageCentre(width: image.width, height: image.height)
        setAutoExtent(DiffractionCompute.contentRadius(pixels: image.pixels, width: image.width, height: image.height, centre: centre))
        place(CanvasPixels.pattern(image: image, log: useLog), source: CanvasSource(generation: generation, log: useLog))
    }

    private func place(_ canvas: CanvasPixels, source: CanvasSource) {
        // A window in log values means nothing in linear ones: the range starts whole again.
        if presentation.canvas.map({ $0.contentVersion != canvas.contentVersion }) ?? false { presentation.resetWindow() }
        presentation.show(canvas)
        canvasSource = source
    }

    @concurrent
    nonisolated private static func extent(_ image: CalibratedImage, centre: DiffractionCentre) async -> Double? {
        // Float32 for this computation only, off the main actor (#566).
        DiffractionCompute.contentRadius(pixels: image.pixels, width: image.width, height: image.height, centre: centre)
    }

    @concurrent
    nonisolated private static func canvas(_ image: CalibratedImage, log: Bool) async -> CanvasPixels {
        CanvasPixels.pattern(image: image, log: log)
    }
}
