//
//  SimulationColumnsOverlay.swift
//  Role: the atom columns of a Simulation document's specimen marked on its HRTEM image (#897, plan row MA5): a small ring on each
//        column's projected position (`SlabDrawing.columns`, the slab builder's positions), so the person sees which contrast sits
//        on which column. Drawn over the image through the marks' own geometry (`MarkGeometry`), at a fixed size on screen, under the
//        marks; it takes no hits. The HRTEM section's Atom columns switch turns it on.
//

import SwiftUI
import TEMCore

struct SimulationColumnsOverlay: View {
    let columns: [SlabDrawing.Column]
    let geometry: MarkGeometry

    /// The ring's radius on screen, points.
    private static let radius = 3.0

    var body: some View {
        Canvas { ctx, size in
            var rings = Path()
            let r = Self.radius
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -r, dy: -r)
            for c in columns {
                let p = geometry.panePoint(of: ImagePoint(x: c.column, y: c.row))
                guard bounds.contains(p) else { continue }
                rings.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
            ctx.stroke(rings, with: .color(.black.opacity(0.6)), lineWidth: 2.5)
            ctx.stroke(rings, with: .color(.orange), lineWidth: 1.25)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the HRTEM section says the columns are marked and how many
    }
}
