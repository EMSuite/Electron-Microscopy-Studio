//
//  OverlaySignals.swift
//  Role: The rooms' overlays never tell two things apart by colour alone (#799, plan row Q9 of 2.3; the shared EDS views did it in
//        EMSuiteUI#196). Each pair that differed only in hue now also differs by a dash, a width, a shape or a word, and every overlay
//        line thickens under Increase Contrast (System Settings > Accessibility > Display). By room:
//        - Imaging: the selected mark is heavier as well as accent-coloured (ImageRoomMarks); profiles and regions are marks.
//        - Diffraction: the ring a calibration runs on is dashed, the fitted rings solid; measured spots are crosses, simulated spots
//          rings (dashed for double diffraction), the centre a plus with a dashed annulus.
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

        /// Differs from `other` by something a reader sees without colour.
        func differs(from other: Stroke) -> Bool { dash != other.dash || widthScale != other.widthScale || word != other.word }
    }

    /// An overlay line's width: Increase Contrast thickens every line by half (as EMSuiteUI's spectrum does).
    static func width(_ base: CGFloat, increasedContrast: Bool) -> CGFloat { increasedContrast ? base * 1.5 : base }

    // MARK: Diffraction

    /// A fitted ring: solid; the one a calibration runs on (orange): dashed.
    static func diffractionRing(calibrating: Bool) -> Stroke { calibrating ? Stroke(dash: [6, 3]) : Stroke() }

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
