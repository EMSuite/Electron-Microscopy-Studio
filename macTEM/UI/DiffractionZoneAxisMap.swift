//
//  DiffractionZoneAxisMap.swift
//  Role: the zone-axis map in the Holder section (plan row R15, #814): the stereographic projection around the beam of the indexed
//        crystal, its zone axes to index 3 within 60°, the traces of its three lowest plane families, and with a calibrated axis
//        the holder's reach. A click picks the nearest zone axis, which the Holder section then names with its angle from the
//        beam and the tilts to it. The map is drawn as the pattern is: lab x (down the rows) down, lab y (along the columns)
//        right, the beam at the centre. Presentation only: every position is DiffractoKit's (`ZoneAxisMap`).
//        Until the crystal pane (R7, #790) gives the map its own tab, it lives here.
//

import SwiftUI
import DiffractoGeometry
import TEMCore

struct DiffractionZoneAxisMap: View {
    let plan: TiltPlan
    @Binding var selected: SIMD3<Int>?
    /// The canvas's size, for turning a click back into the map's units.
    @State private var size: CGSize?

    /// The map's edge: 60° from the beam, tan(30°) in projected units.
    private static let edge = tan(30 * Double.pi / 180)
    /// A click picks a pole within this many points.
    private static let pickRadius: CGFloat = 12
    /// Poles whose indices are all within this are labelled; the rest are dots.
    private static let labelledIndex = 1
    /// The plane families' colours, in the kit's order; the legend names them.
    static let familyColours: [Color] = [.orange, .green, .purple]

    var body: some View {
        VStack(spacing: 4) {
            canvas
            DiffractionZoneAxisMapLegend(families: DiffractionZoneAxisMapText.families(plan))
        }
    }

    private var canvas: some View {
        Canvas { context, canvasSize in
            let map = Mapping(size: canvasSize, edge: Self.edge)
            draw(into: &context, map: map)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 260)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in pick(at: tap.location) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone-axis map")
        .accessibilityValue(DiffractionZoneAxisMapText.spoken(plan, selected: selected))
        .accessibilityAdjustableAction { direction in step(direction) }
        .accessibilityIdentifier("diffraction.holder.map")
    }

    /// Projected (X, Y) to points, for a canvas of `size`: the 60° edge fits the shorter side.
    private struct Mapping {
        let centre: CGPoint
        let scale: CGFloat

        init(size: CGSize, edge: Double) {
            let side = min(size.width, size.height)
            centre = CGPoint(x: size.width / 2, y: size.height / 2)
            scale = (side / 2 - 6) / CGFloat(edge)
        }

        /// (lab x, lab y) to the canvas: lab x down, lab y right.
        func point(_ p: SIMD2<Double>) -> CGPoint {
            CGPoint(x: centre.x + CGFloat(p.y) * scale, y: centre.y + CGFloat(p.x) * scale)
        }
    }

    private func draw(into context: inout GraphicsContext, map: Mapping) {
        let edge = CGFloat(Self.edge) * map.scale
        let disc = Path(ellipseIn: CGRect(x: map.centre.x - edge, y: map.centre.y - edge, width: 2 * edge, height: 2 * edge))
        context.stroke(disc, with: .style(.separator), lineWidth: 1)
        // The beam.
        var cross = Path()
        cross.move(to: CGPoint(x: map.centre.x - 5, y: map.centre.y)); cross.addLine(to: CGPoint(x: map.centre.x + 5, y: map.centre.y))
        cross.move(to: CGPoint(x: map.centre.x, y: map.centre.y - 5)); cross.addLine(to: CGPoint(x: map.centre.x, y: map.centre.y + 5))
        context.stroke(cross, with: .style(.secondary), lineWidth: 1)
        // The holder's reach.
        if plan.reach.count > 2 {
            var loop = Path()
            loop.addLines(plan.reach.map(map.point))
            loop.closeSubpath()
            context.stroke(loop, with: .style(.tint), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        // The plane traces, one colour a family (the kit gives one trace a ±(hkl) pair).
        let families = DiffractionZoneAxisMapText.families(plan)
        for trace in plan.traces {
            var path = Path()
            for segment in trace.points where segment.count > 1 { path.addLines(segment.map(map.point)) }
            let i = families.firstIndex(of: trace.family) ?? 0
            context.stroke(path, with: .color(Self.familyColours[i % Self.familyColours.count].opacity(0.7)), lineWidth: 1)
        }
        // The zone axes.
        for row in plan.rows {
            let p = map.point(row.position)
            let isSelected = row.uvw == selected
            let r: CGFloat = isSelected ? 4.5 : 3
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            context.fill(dot, with: isSelected ? .style(.tint) : .style(.primary))
            if isSelected || max(abs(row.uvw.x), abs(row.uvw.y), abs(row.uvw.z)) <= Self.labelledIndex {
                context.draw(Text(row.id).font(.caption2.monospacedDigit()).foregroundStyle(isSelected ? .primary : .secondary),
                             at: CGPoint(x: p.x + 5, y: p.y - 5), anchor: .bottomLeading)
            }
        }
    }

    private func pick(at location: CGPoint) {
        // The gesture reports points in the space the canvas draws in.
        guard let size else { return }
        let map = Mapping(size: size, edge: Self.edge)
        let nearest = plan.rows.min { distance(map.point($0.position), location) < distance(map.point($1.position), location) }
        if let nearest, distance(map.point(nearest.position), location) <= Self.pickRadius { selected = nearest.uvw }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// VoiceOver's swipe up and down: the next or the previous zone axis, nearest the beam first.
    private func step(_ direction: AccessibilityAdjustmentDirection) {
        guard !plan.rows.isEmpty else { return }
        let i = plan.rows.firstIndex { $0.uvw == selected }
        switch direction {
        case .increment: selected = plan.rows[min((i ?? -1) + 1, plan.rows.count - 1)].uvw
        case .decrement: selected = plan.rows[max((i ?? 1) - 1, 0)].uvw
        @unknown default: break
        }
    }
}

/// The plane families' names, each in its trace colour, so the colours are not the only way to tell them apart.
private struct DiffractionZoneAxisMapLegend: View {
    let families: [String]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(families.enumerated()), id: \.offset) { i, name in
                Label {
                    Text(name).font(.caption2.monospacedDigit())
                } icon: {
                    Rectangle().fill(DiffractionZoneAxisMap.familyColours[i % DiffractionZoneAxisMap.familyColours.count])
                        .frame(width: 10, height: 2)
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// The map's words. Pure.
nonisolated enum DiffractionZoneAxisMapText {
    /// The plane families of the traces, each once, in the kit's order.
    static func families(_ plan: TiltPlan) -> [String] {
        var seen: Set<String> = []
        return plan.traces.map(\.family).filter { seen.insert($0).inserted }
    }

    /// "24 zone axes and 3 plane families ({1 1 1}, {2 0 0}, {2 2 0}); [1 1 0] picked, 12.4° from the beam".
    static func spoken(_ plan: TiltPlan, selected: SIMD3<Int>?) -> String {
        let names = Self.families(plan)
        var text = "\(plan.rows.count) zone \(plan.rows.count == 1 ? "axis" : "axes") and \(names.count) plane "
            + (names.count == 1 ? "family" : "families")
        if !names.isEmpty { text += " (\(names.joined(separator: ", ")))" }
        if let uvw = selected, let row = plan.row(uvw) {
            text += "; \(row.id) picked, \(Num.fixed(row.angleFromBeamDeg, 1))° from the beam"
        }
        return text
    }
}
