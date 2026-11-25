//
//  SlabDrawing.swift
//  Role: what a Simulation document shows of its slab (#897, plan row MA5), as plain numbers: the atoms the crystal pane draws (the
//        slab the multislice runs on, in the crystal's frame so the pane's one orientation turns it with the pattern), capped at the
//        design's 20 000 drawn atoms with the count named; and the atom columns marked on the HRTEM image, the slab's projected
//        positions in the image's pixels. Every position is the slab builder's; nothing here computes physics.
//
//  Frames: the slab's atoms are in its box, x and y across the beam and z the depth below the entrance face (SimulatoKit 0.7.0),
//  with `Slab.orientation` holding the box's axes in the crystal's Cartesian frame (columns), so a crystal-frame position is
//  `orientation * (x, y, depth − z)` (`crystalPosition`). The HRTEM image is drawn in the box
//  frame (`HRTEMImage.image`: lab x down the rows, lab y along the columns, grid point i at i × sampling), so a column at (x, y)
//  sits on the pixel centre (row x / row sampling, column y / column sampling); pixel centres are whole numbers.
//

import Foundation
import ImagoCore
import SimulatoCore
import simd

package nonisolated enum SlabDrawing {
    /// The most atoms the crystal pane draws of a slab: the design's "capped at about 20 000 drawn atoms".
    package static let drawnAtomLimit = 20_000
    /// Atoms closer than this across the beam, Å, are one column.
    package static let columnTolerance = 0.01

    /// One drawn atom: its position in Å in the crystal's Cartesian frame.
    package struct Atom: Sendable, Equatable {
        package let position: SIMD3<Double>
        package let atomicNumber: Int
    }

    /// The slab as the pane draws it.
    package struct Drawn: Sendable, Equatable {
        /// The atoms drawn, from the entrance face: whole periods while they fit under the limit.
        package let atoms: [Atom]
        /// The drawn part of the box as a cell (columns x, y and z in Å, in the crystal's frame): the pane draws its edges.
        package let cell: simd_double3x3
        /// Every atom of the slab.
        package let total: Int
        /// The slab's box, Å: across the beam and its whole thickness.
        package let box: SIMD3<Double>
        /// The thickness drawn, Å (the whole box unless the slab passes the limit).
        package let drawnDepth: Double

        package var isCapped: Bool { atoms.count < total }

        /// "Slab 0.384 × 0.543 × 9.98 nm, 104 atoms", or with the cap "…: 20 000 of 1 040 000 atoms drawn, the first 7.68 nm".
        package var caption: String {
            func nm(_ angstrom: Double) -> String { UnitDisplay.number(angstrom / 10, digits: 3) }
            let size = "Slab \(nm(box.x)) × \(nm(box.y)) × \(nm(box.z)) nm"
            guard isCapped else { return "\(size), \(UnitDisplay.count(total, "atom", "atoms"))" }
            return "\(size): \(atoms.count.formatted()) of \(total.formatted()) atoms drawn, the first \(nm(drawnDepth)) nm"
        }
    }

    /// The slab of `built` as the pane draws it, at most `limit` atoms: whole periods from the entrance face (z = 0) while they fit,
    /// else the `limit` atoms nearest the entrance.
    package static func drawn(_ built: SimulationSpecimen.Built, limit: Int = drawnAtomLimit) -> Drawn {
        let slab = built.slab
        let box = built.slabBox
        let atoms = slab.structure.atoms
        let rotation = slab.orientation
        var kept: [AtomicStructure.Atom]
        var depth = box.z
        if atoms.count <= limit {
            kept = atoms
        } else {
            let perPeriod = max(1, atoms.count / max(1, built.periods))
            let periods = limit / perPeriod
            if periods >= 1 {
                depth = Double(periods) * built.box.z
                kept = atoms.filter { $0.position.z < depth }
            } else {
                kept = Array(atoms.sorted { $0.position.z < $1.position.z }.prefix(limit))
                depth = kept.last?.position.z ?? 0
            }
        }
        let drawnAtoms = kept.map { Atom(position: crystalPosition($0.position, depth: depth, rotation: rotation), atomicNumber: $0.atomicNumber) }
        let cell = simd_double3x3(columns: (rotation.columns.0 * box.x, rotation.columns.1 * box.y, rotation.columns.2 * depth))
        return Drawn(atoms: drawnAtoms, cell: cell, total: atoms.count, box: box, drawnDepth: depth)
    }

    /// A slab atom's position in the crystal's Cartesian frame, for a drawing `depth` Å deep. SimulatoKit 0.7.0 stores a slab's z as
    /// the depth below the entrance face, the face nearest the source (EMSuite/SimulatoKit#126), while `Slab.orientation` keeps the
    /// suite's frame (its columns are the box's axes in the crystal's frame, the third the zone axis pointing at the source). So the
    /// height above the drawing's far face is `depth − z`, and the position is `rotation * (x, y, depth − z)`; x and y are the box's
    /// as stored. This is the one place that reads the slab's frame.
    package static func crystalPosition(_ p: SIMD3<Double>, depth: Double, rotation: simd_double3x3) -> SIMD3<Double> {
        rotation * SIMD3(p.x, p.y, depth - p.z)
    }

    /// One atom column marked on the HRTEM image: its pixel centre (row and column, whole numbers at pixel centres) and the elements
    /// it holds, lightest first.
    package struct Column: Sendable, Equatable {
        package let row: Double
        package let column: Double
        package let atomicNumbers: [Int]
    }

    /// The atom columns of one orthogonal unit, Å across the beam (x, y in [0, box)), each with its elements: the atoms of the period
    /// the multislice computes from, projected along the beam and merged within `columnTolerance` (periodically across the box).
    package static func projectedColumns(_ built: SimulationSpecimen.Built) -> [(x: Double, y: Double, atomicNumbers: [Int])] {
        let box = built.box
        var columns: [(x: Double, y: Double, atomicNumbers: Set<Int>)] = []
        func wrapped(_ v: Double, _ length: Double) -> Double {
            let w = v - (v / length).rounded(.down) * length
            return length - w < columnTolerance ? 0 : w
        }
        func distance(_ a: Double, _ b: Double, _ length: Double) -> Double {
            let d = abs(a - b)
            return min(d, length - d)
        }
        for atom in built.slab.structure.atoms where atom.position.z < box.z {
            let x = wrapped(atom.position.x, box.x), y = wrapped(atom.position.y, box.y)
            if let i = columns.firstIndex(where: { distance($0.x, x, box.x) < columnTolerance && distance($0.y, y, box.y) < columnTolerance }) {
                columns[i].atomicNumbers.insert(atom.atomicNumber)
            } else {
                columns.append((x, y, [atom.atomicNumber]))
            }
        }
        return columns.map { ($0.x, $0.y, $0.atomicNumbers.sorted()) }
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// The atom columns of `built` on an HRTEM image `rows` × `columns` pixels whose pixels are `rowSampling` and `columnSampling` Å
    /// (lab x down the rows, lab y along the columns, as `HRTEMImage.image` draws it): one mark per column of every whole unit the
    /// image tiles, each on its projected position.
    package static func columns(_ built: SimulationSpecimen.Built, rows: Int, columns: Int, rowSampling: Double,
                                columnSampling: Double) -> [Column] {
        guard rows > 0, columns > 0, rowSampling > 0, columnSampling > 0 else { return [] }
        let box = built.box
        let unit = projectedColumns(built)
        let tilesX = Int((Double(rows) * rowSampling / box.x).rounded(.up))
        let tilesY = Int((Double(columns) * columnSampling / box.y).rounded(.up))
        let lastRow = Double(rows) - 0.5, lastColumn = Double(columns) - 0.5
        var out: [Column] = []
        out.reserveCapacity(unit.count * (tilesX + 1) * (tilesY + 1))
        for i in 0...tilesX {
            for j in 0...tilesY {
                for c in unit {
                    let row = (c.x + Double(i) * box.x) / rowSampling
                    let column = (c.y + Double(j) * box.y) / columnSampling
                    guard row >= -0.5, row < lastRow, column >= -0.5, column < lastColumn else { continue }
                    out.append(Column(row: row, column: column, atomicNumbers: c.atomicNumbers))
                }
            }
        }
        return out
    }

    /// The atom columns of `built` on `image`, an HRTEM image `HRTEMImage.image` made (its calibration in nm per pixel).
    /// None for an image without both calibrations.
    package static func columns(_ built: SimulationSpecimen.Built, on image: CalibratedImage) -> [Column] {
        guard let x = image.x, let y = image.y else { return [] }
        return columns(built, rows: image.height, columns: image.width, rowSampling: y.scale * 10, columnSampling: x.scale * 10)
    }
}
