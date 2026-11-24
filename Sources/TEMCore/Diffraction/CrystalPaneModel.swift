//
//  CrystalPaneModel.swift
//  Role: what the Diffraction room's crystal pane (#790, plan row R7) draws of a crystal, as plain numbers for EMSuiteUI's ShellCrystal
//        (which imports no kit): the cell as a matrix, the sites, the bonds (DiffractoKit's VESTA cut-offs), and the orientation in
//        the view's frame. `simd` is imported for the matrix type alone (tools/kit-boundary.allow): no numerics happen here.
//
//  Frames: DiffractoKit's `CrystalOrientation` has lab x down the pattern's rows, lab y along its columns and lab z toward the
//  source (the columns of its matrix, in the crystal's Cartesian frame). ShellCrystal's view has x to the right, y up and z toward the
//  viewer. So the view's x is lab y, its y is −lab x and its z is lab z: the crystal is drawn the way the pattern beside it lies.
//

import Foundation
import simd
import DiffractoCore

package nonisolated enum CrystalPaneModel {

    /// One site of the full cell (the structure's sites, which the kit has already expanded by the operations).
    package struct Site: Sendable, Equatable {
        package let fractional: SIMD3<Double>
        package let atomicNumber: Int
        package let occupancy: Double
    }

    /// One bond: site `from` to site `to` moved by `image` lattice vectors (the kit's `Bond`).
    package struct Bond: Sendable, Equatable {
        package let from: Int
        package let to: Int
        package let image: SIMD3<Int>
    }

    /// The cell's lattice vectors a₁, a₂, a₃ as columns, Å, in the frame the orientation turns (the kit's `realLattice`).
    package static func cell(_ structure: CrystalStructure) -> simd_double3x3 {
        let l = structure.cell.realLattice
        return simd_double3x3(columns: (l[0], l[1], l[2]))
    }

    package static func sites(_ structure: CrystalStructure) -> [Site] {
        structure.sites.map { Site(fractional: $0.fractional, atomicNumber: $0.z, occupancy: $0.occupancy) }
    }

    /// Every bond once (the kit lists each from both of its atoms).
    package static func bonds(_ structure: CrystalStructure) -> [Bond] {
        structure.bonds.filter { b in
            b.site < b.neighbour || (b.site == b.neighbour && (b.image.x, b.image.y, b.image.z) > (0, 0, 0))
        }.map { Bond(from: $0.site, to: $0.neighbour, image: $0.image) }
    }

    /// The view's orientation of `orientation`: columns (lab y, −lab x, lab z).
    package static func view(_ orientation: CrystalOrientation) -> simd_double3x3 {
        let m = orientation.matrix
        return simd_double3x3(columns: (m.columns.1, -m.columns.0, m.columns.2))
    }

    /// The orientation of a view the person turned: the inverse of `view`; nil for a matrix that is not a rotation.
    package static func orientation(view v: simd_double3x3) -> CrystalOrientation? {
        try? CrystalOrientation(matrix: simd_double3x3(columns: (-v.columns.1, v.columns.0, v.columns.2)))
    }

    /// VoiceOver's words for the pane: "Au, zone axis [001]", or "Au, zone axis [001], tilted 2.1°" past 0.05°.
    package static func label(phase: String, orientation: CrystalOrientation, cell: UnitCell) -> String {
        guard let near = orientation.nearestZoneAxis(cell: cell) else { return phase }
        let degrees = near.angle * 180 / .pi
        let axis = PatternIndexing.zoneText(near.uvw)
        return degrees < 0.05 ? "\(phase), zone axis \(axis)" : "\(phase), zone axis \(axis), tilted \(String(format: "%.1f", degrees))°"
    }
}
