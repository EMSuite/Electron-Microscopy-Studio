//
//  EBSDOverlayLabels.swift
//  Role: where the EBSD rooms put a label they draw over a picture (#1059): the Indexing room's band families on the pattern and the
//        Maps room's slip-trace planes on the map. The rule is the Diffraction room's (#1045): place from the strongest down, each at
//        the first of its spots where its plate lies inside the picture and meets no plate already placed and nothing to keep clear
//        (the picked point's marker); a label with no such spot is left out rather than drawn over another. Pure, so a test pins it.
//

import CoreGraphics

nonisolated enum EBSDOverlayLabels {
    /// The space kept between two plates, and between a plate and what it keeps clear of.
    static let gap: CGFloat = 2

    /// One placed label: its index in the list given, and its plate in the picture's coordinates.
    struct Placed: Equatable {
        let index: Int
        let frame: CGRect
    }

    /// Places `sizes[i]` at the first centre of `spots[i]` that fits, in the order given (the strongest first), inside `bounds` and clear
    /// of every placed plate and of `obstacles`; a label none of whose spots fits is left out.
    static func place(sizes: [CGSize], spots: [[CGPoint]], in bounds: CGRect, avoiding obstacles: [CGRect] = []) -> [Placed] {
        var placed: [Placed] = []
        for (i, size) in sizes.enumerated() where spots.indices.contains(i) {
            for centre in spots[i] {
                let frame = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
                guard bounds.contains(frame) else { continue }
                let padded = frame.insetBy(dx: -gap, dy: -gap)
                guard !placed.contains(where: { $0.frame.intersects(padded) }), !obstacles.contains(where: { $0.intersects(padded) }) else { continue }
                placed.append(Placed(index: i, frame: frame))
                break
            }
        }
        return placed
    }

    /// A band's spots: on its centre line, the middle first, then outward towards both ends (a band's label names the line it sits on).
    static func bandSpots(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        ([0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.12, 0.88] as [CGFloat]).map { t in CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    }

    /// A slip trace's spots for a plate of `size`: beside the trace or beyond its ends along its line, never on it, every 4 pt out to
    /// 160 pt past the trace's middle and up to four steps away from its side, nearest the trace first and, as near, nearest its far
    /// end `b`. So a label sits by its own trace, and the traces of a small grain in a corner still find room inside the map rather than
    /// piling their labels on one point.
    static func traceSpots(from a: CGPoint, to b: CGPoint, size: CGSize) -> [CGPoint] {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        let u = length > 0 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 1, y: 0)
        let n = CGPoint(x: -u.y, y: u.x)
        // Half the plate's extent along a direction: how far its centre sits from a line it must clear.
        let reach = { (d: CGPoint) -> CGFloat in abs(d.x) * size.width / 2 + abs(d.y) * size.height / 2 }
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let pastTheEnd = length / 2 + reach(u) + 3, side = reach(n) + 3
        var spots: [CGPoint] = []
        var along: CGFloat = 0
        while along <= length / 2 + 160 {
            for sign in [CGFloat(1), -1] {
                let q = CGPoint(x: middle.x + sign * u.x * along, y: middle.y + sign * u.y * along)
                if along >= pastTheEnd { spots.append(q) }
                for away in [side, side + 10, side + 22, side + 36] {
                    for flank in [CGFloat(1), -1] {
                        spots.append(CGPoint(x: q.x + flank * n.x * away, y: q.y + flank * n.y * away))
                    }
                }
            }
            along += 4
        }
        let keyed = spots.map { p in (p, distance(p, toSegment: a, b).rounded(), norm(p.x - b.x, p.y - b.y)) }
        return keyed.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }.map { $0.0 }
    }

    /// The distance from `p` to the segment from `a` to `b`.
    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        let t = squared > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / squared, 0), 1) : 0
        return norm(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    private static func norm(_ x: CGFloat, _ y: CGFloat) -> CGFloat { (x * x + y * y).squareRoot() }
}
