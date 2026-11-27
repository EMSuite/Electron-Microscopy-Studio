//
//  OverlaySignals.swift
//  Role: The rooms' overlays never tell two things apart by colour alone (#799, plan row Q9 of 2.3; the shared EDS views did it in
//        EMSuiteUI#196). Each pair that differed only in hue now also differs by a dash, a width, a shape or a word, and every overlay
//        line thickens under Increase Contrast (System Settings > Accessibility > Display). By room:
//        - Imaging: the selected mark is heavier as well as accent-coloured (ImageRoomMarks); profiles and regions are marks.
//        - Diffraction: the ring a calibration runs on is dashed, the fitted rings solid; measured spots are crosses, simulated spots
//          rings (dashed for double diffraction), the centre a plus with a dashed annulus. A precipitate's variants are diamonds
//          against the matrix's rings (dashed for double diffraction), and the zone-axis map's plane families are solid, dashed and
//          dotted in the map and its legend (#923).
//        - Powder: the compared phase's sticks are dashed, the room's crystal's solid, in the chart and its legend (#923).
//        - HRTEM: the transfer chart's aperture rule is dashed and named "aperture", the point resolution solid and named, the
//          strong spacings short rules in the secondary colour, each named by its hkl (#923).
//        - EBSD: matched Kikuchi bands solid and labelled, unmatched dashed (SEMOverlayStyle); phase boundaries twice the width of
//          grain boundaries; each slip trace carries its plane's label at its end; the phase colours sit beside their names in the
//          legend.
//        - Spectroscopy: EELS background windows have dashed edges, signal windows solid; a refused edge's windows and background
//          are dotted and say "refused"; the element maps carry their element's name (EMSuiteUI).
//        `OverlaySignalTests` holds each pair apart by something other than colour.
//

import CoreGraphics

nonisolated enum OverlaySignal {
    /// How a line is drawn besides its colour.
    nonisolated struct Stroke: Equatable, Sendable {
        var dash: [CGFloat] = []
        /// Times the room's base width.
        var widthScale: CGFloat = 1
        /// A word drawn beside it, where the state needs one.
        var word: String?
    }

    /// An overlay line's width: Increase Contrast thickens every line by half (as EMSuiteUI's spectrum does).
    static func width(_ base: CGFloat, increasedContrast: Bool) -> CGFloat { increasedContrast ? base * 1.5 : base }

    // MARK: Diffraction

    /// A fitted ring: solid; the one a calibration runs on (orange): dashed.
    static func diffractionRing(calibrating: Bool) -> Stroke { calibrating ? Stroke(dash: [6, 3]) : Stroke() }

    /// The mark a simulated spot is drawn as.
    nonisolated enum SpotMark: Equatable, Sendable { case ring, diamond }

    /// A simulated spot (cyan) is a ring; a precipitate variant's (pink) is a diamond, so the two never differ by colour alone.
    static func simulatedSpot(variant: Bool) -> SpotMark { variant ? .diamond : .ring }

    /// The outline of a spot's mark of `radius` about `centre`: a circle, or a square on its point reaching as far.
    static func outline(_ mark: SpotMark, centre: CGPoint, radius r: CGFloat) -> CGPath {
        switch mark {
        case .ring:
            return CGPath(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r), transform: nil)
        case .diamond:
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: centre.x, y: centre.y - r), CGPoint(x: centre.x + r, y: centre.y),
                                    CGPoint(x: centre.x, y: centre.y + r), CGPoint(x: centre.x - r, y: centre.y)])
            path.closeSubpath()
            return path
        }
    }

    /// The zone-axis map's plane families, in the kit's order (orange, green, purple): solid, dashed and dotted, in the map and
    /// in its legend.
    static func zoneAxisFamily(_ index: Int) -> Stroke { familyStrokes[index % familyStrokes.count] }
    private static let familyStrokes = [Stroke(), Stroke(dash: [4, 3]), Stroke(dash: [1.5, 2.5])]

    // MARK: Powder

    /// A powder pattern's phases (one colour each): the room's crystal solid, the phase it is compared with dashed.
    static func powderPhase(_ index: Int) -> Stroke { index == 0 ? Stroke() : Stroke(dash: [3, 2]) }

    // MARK: EBSD

    /// Grain boundaries (white) and phase boundaries (black): a phase boundary is twice as wide.
    static let grainBoundary = Stroke()
    static let phaseBoundary = Stroke(widthScale: 2)

    // MARK: EELS

    nonisolated enum EELSWindow: Sendable { case background, signal }

    /// An edge's window edges: background (orange) dashed, signal (the accent) solid; a refused edge's (red) dotted and named.
    static func eelsWindow(_ window: EELSWindow, refused: Bool) -> Stroke {
        if refused { return Stroke(dash: [1.5, 2.5], word: window == .signal ? "refused" : nil) }
        return window == .background ? Stroke(dash: [4, 3]) : Stroke()
    }

    /// The power-law background under a signal window: dashed, dotted when its edge is refused.
    static func eelsBackground(refused: Bool) -> Stroke { Stroke(dash: refused ? [1.5, 2.5] : [4, 3]) }
}
