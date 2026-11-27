//
//  HKLLabelPlacement.swift
//  Role: where the hkl labels of the simulated spots go so they never overprint (#1045). With 52 spots after Index every spot carried
//        a label and they collided across the picture. Strongest walks the spots from the highest intensity down and places a label
//        only where its box meets no label already placed and not the central beam's mark, up to `strongestCap`; All is the same
//        rule without the cap, so it never overprints either. Each label tries the four corners of its ring, below right first (the
//        place #782 drew it), and of those prefers one that also clears every other drawn ring (#1030: near the direct beam, where
//        the spots crowd, a weaker label waits for a zoom). The strongest spot is always labelled. Pure: points in, boxes out.
//

import Foundation
import TEMBase
import TEMSEM

/// The `hkl labels` row's three choices (#1045).
package nonisolated enum HKLLabelMode: String, CaseIterable, Sendable {
    case strongest, all, off

    /// The pop-up's title.
    package var title: String {
        switch self {
        case .strongest: "Strongest"
        case .all: "All"
        case .off: "None"
        }
    }
}

package nonisolated enum HKLLabelPlacement {
    /// Strongest's cap: at most this many labels.
    package static let strongestCap = 16
    /// The gap between a spot's ring and its label, points.
    package static let labelOffset = 2.0
    /// The half-side of the central beam's mark (the centre's cross), points.
    package static let beamMarkHalfSide = 8.0

    /// A label's box in the room's caption font, points: about 6.5 a character (an index's bar rides on its digit) and one line.
    package static func estimatedLabelSize(_ label: String) -> SIMD2<Double> { SIMD2(6.5 * Double(label.count) + 2, 14) }

    /// One placed label: the spot it names and its box, top-leading `low` to bottom-trailing `high`, in points.
    package struct Placed: Sendable, Equatable {
        package let spot: ZoneAxisOverlay.Spot
        package let low: SIMD2<Double>
        package let high: SIMD2<Double>
    }

    /// Whether two boxes share any area.
    package static func meet(_ a: (low: SIMD2<Double>, high: SIMD2<Double>), _ b: (low: SIMD2<Double>, high: SIMD2<Double>)) -> Bool {
        !(a.high.x <= b.low.x || a.low.x >= b.high.x || a.high.y <= b.low.y || a.low.y >= b.high.y)
    }

    /// The labels of `spots` (strongest first, as `ZoneAxisOverlay.spots` gives them) that `mode` draws, each where its box meets no
    /// label placed before it and not the central beam's mark at `beam` (nil: no centre). `point` is a spot's place in points and
    /// `radius` its ring's.
    package static func place(_ spots: [ZoneAxisOverlay.Spot], mode: HKLLabelMode, point: (ZoneAxisOverlay.Spot) -> SIMD2<Double>,
                              radius: (ZoneAxisOverlay.Spot) -> Double, beam: SIMD2<Double>?,
                              labelSize: (String) -> SIMD2<Double> = HKLLabelPlacement.estimatedLabelSize) -> [Placed] {
        guard mode != .off else { return [] }
        let cap = mode == .strongest ? strongestCap : Int.max
        let ordered = spots.enumerated().sorted { a, b in
            a.element.intensity != b.element.intensity ? a.element.intensity > b.element.intensity : a.offset < b.offset
        }.map(\.element)
        let beamBox = beam.map { (low: $0 - SIMD2(repeating: beamMarkHalfSide), high: $0 + SIMD2(repeating: beamMarkHalfSide)) }
        let rings = spots.map { (spot: $0, centre: point($0), radius: radius($0)) }
        var placed: [Placed] = []
        for spot in ordered {
            guard placed.count < cap else { break }
            let p = point(spot), r = radius(spot) + labelOffset, size = labelSize(spot.label)
            // Below right (#782's place), above right, below left, above left.
            let corners = [SIMD2(p.x + r, p.y + r), SIMD2(p.x + r, p.y - r - size.y), SIMD2(p.x - r - size.x, p.y + r),
                           SIMD2(p.x - r - size.x, p.y - r - size.y)]
            let boxes = corners.map { (low: $0, high: $0 + size) }
            let free = boxes.filter { box in
                !placed.contains { meet(box, ($0.low, $0.high)) } && !(beamBox.map { meet(box, $0) } ?? false)
            }
            let clear = free.first { box in
                rings.allSatisfy { ring in
                    guard ring.spot != spot else { return true }
                    let nearest = pointwiseMin(pointwiseMax(ring.centre, box.low), box.high)
                    let d = nearest - ring.centre
                    return (d * d).sum() >= ring.radius * ring.radius
                }
            }
            // The strongest spot is always named: the first box clear of the beam's mark, else its own place.
            let chosen = clear ?? (placed.isEmpty ? (free.first ?? boxes[0]) : nil)
            guard let chosen else { continue }
            placed.append(Placed(spot: spot, low: chosen.low, high: chosen.high))
        }
        return placed
    }
}
