//
//  DiffractionLabels.swift
//  Role: what the pattern's words are once Index has run (#1045, Paul's design review of 25 Nov 2026). After Index on silicon [110]
//        every found spot carried "d 1,045 Å · (511)+(333)" and every simulated spot its hkl: 52 spots of labels collided across the
//        picture, and nothing on it said what the red crosses and the cyan rings were. Now the found spots' d labels are drawn for the
//        selected row and the spot under the pointer only (the table under the pattern lists them all; the rings keep theirs, there are
//        few), the hkl labels follow the `hkl labels` pop-up (`HKLLabelPlacement`), and one chip in the top-leading corner names the
//        marks while the simulated spots are drawn. Pure, so the tests read the policy as data.
//

import Foundation
import TEMCore

/// Which measured marks carry their d label.
nonisolated enum DiffractionMarkLabels {
    /// How near the pointer a found spot's centre must be for its label, points: the cross's half-diagonal and a little.
    static let hoverReach = 10.0

    /// The marks whose label is drawn: every ring, the selected spot, and the spot nearest the pointer within `hoverReach`.
    static func labelled(rings: [UUID], spots: [(id: UUID, point: SIMD2<Double>)], selection: UUID?,
                         pointer: SIMD2<Double>?) -> Set<UUID> {
        var out = Set(rings)
        if let selection, spots.contains(where: { $0.id == selection }) { out.insert(selection) }
        if let pointer {
            let near = spots.map { spot -> (id: UUID, distance: Double) in
                let d = spot.point - pointer
                return (spot.id, (d * d).sum().squareRoot())
            }
            .filter { $0.distance <= hoverReach }
            .min { $0.distance < $1.distance }
            if let near { out.insert(near.id) }
        }
        return out
    }
}

/// The pattern's legend chip: one row per kind of mark drawn.
nonisolated enum DiffractionLegend {
    nonisolated enum Mark: Equatable, Sendable {
        /// The simulated spots' mark (#923's ring).
        case simulated(OverlaySignal.SpotMark)
        /// A found spot's red cross.
        case found
        /// A found spot Index did not explain, where its mark differs from a found spot's.
        case unexplained
    }

    nonisolated struct Entry: Equatable, Sendable {
        let mark: Mark
        let text: String
    }

    static let foundWord = "found"
    static let unexplainedWord = "unexplained"
    /// Whether an unexplained spot has a mark of its own: today it is the same red cross as an explained one, so the chip names none.
    static let unexplainedMarkDiffers = false

    /// The chip's rows: none while no overlay is shown; the simulated mark with the phase's name, then the found cross with "found"
    /// when spots were found, then "unexplained" only where its mark differs.
    static func entries(overlayShown: Bool, phase: String, hasFound: Bool, hasUnexplained: Bool,
                        unexplainedDiffers: Bool = unexplainedMarkDiffers) -> [Entry] {
        guard overlayShown else { return [] }
        var entries = [Entry(mark: .simulated(OverlaySignal.simulatedSpot(variant: false)), text: phase)]
        if hasFound { entries.append(Entry(mark: .found, text: foundWord)) }
        if hasFound, hasUnexplained, unexplainedDiffers { entries.append(Entry(mark: .unexplained, text: unexplainedWord)) }
        return entries
    }
}

/// The `hkl labels` pop-up's words.
nonisolated enum DiffractionLabelWords {
    static let modeHelp = "Which simulated spots carry their hkl: Strongest labels up to \(HKLLabelPlacement.strongestCap) from the "
        + "brightest down, All every spot with room for it, None none. A label never covers another or the centre's mark"
}
