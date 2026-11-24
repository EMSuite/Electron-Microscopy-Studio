//
//  AtomModelSpecimen.swift
//  Role: an atom model another tool built (a grain boundary from atomsk, a precipitate in a matrix from ASE, a relaxed cell from VASP)
//        as a Simulation document's specimen (#914, plan row MA14). The file is read once and kept: the document holds
//        what the file parses to, so it simulates without the file. CIF through DiffractoKit's `CrystalLoading` (a CIF with symmetry is
//        expanded), extended and plain XYZ and POSCAR or CONTCAR through its `AtomModel` (ASE 3.29.0's readers, pinned there); anything
//        else is refused by name with the converters' hint. The slab is SimulatoKit's (`SlabBuilder.slab(ofModel:beamAlong:lateralSize:thickness:…)`): the beam runs
//        along the model's c (or a, or b), one period is the model's own thickness, a model without a cell gets 5 Å of vacuum as ASE's
//        `center(vacuum=)`, and a cell that is not rectangular is cut as abTEM's `orthogonalize_cell` or refused with its angle.
//        This file adds the design's limits and sentences and the section's readouts. Every number of the slab is the kit's.
//

import DiffractoCore
import Foundation
import SimulatoCore

package nonisolated struct AtomModelSpecimen: Sendable, Equatable {
    /// The most atoms a model may have (the design's limit).
    package static let atomLimit = 1_000_000
    /// The vacuum around a model without a cell, Å.
    package static let vacuum = 5.0
    /// Atoms closer than this, Å, are counted for the section's chip (abTEM does not check; a model with overlaps is usually a mistake).
    package static let closeDistance = 0.5
    /// The largest grid side a run may have.
    package static let largestGrid = 4096
    /// The file extensions the Atom Model… panel offers; POSCAR and CONTCAR are read by name too.
    package static let extensions = ["cif", "xyz", "extxyz", "vasp", "poscar", "contcar"]

    /// The beam's direction in the model: along c (the default), a or b, the model's Cartesian z, x or y.
    package enum BeamAxis: String, Sendable, CaseIterable, Identifiable {
        case c, a, b
        package var id: String { rawValue }
        package var kit: SlabBuilder.BeamAxis {
            switch self {
            case .a: .x
            case .b: .y
            case .c: .z
            }
        }
    }

    /// What the file held.
    package enum Contents: Sendable, Equatable {
        case model(AtomModel)
        case cif(CrystalStructure)
    }

    /// Why a model is not simulated, in the design's words.
    package enum Refusal: Error, Sendable, Equatable {
        case format(file: String)
        case unreadable(file: String, reason: String)
        case tooManyAtoms(Int)
        case partialCell
        case notRectangular(angle: String, limit: Double)
        case gridTooLarge(nx: Int, ny: Int, sampling: Double)

        package var sentence: String {
            switch self {
            case .format(let file):
                "\(file) is not a CIF, XYZ or POSCAR file. LAMMPS, PDB and CFG models open after atomsk or ASE converts them to one."
            case .unreadable(let file, let reason):
                "\(file) cannot be read: \(reason)"
            case .tooManyAtoms(let count):
                "This model has \(AtomModelSpecimen.grouped(count)) atoms. The limit is \(AtomModelSpecimen.grouped(atomLimit))."
            case .partialCell:
                "This file gives only part of a cell. Export the model with all three cell vectors, or with none."
            case .notRectangular(let angle, let limit):
                "This model's cell is not rectangular (\(angle)) and does not fit a rectangular box within "
                    + "\(SimulationSpecimen.percent(limit)). Export it with an orthogonal cell."
            case .gridTooLarge(let nx, let ny, let sampling):
                "This model needs a grid of \(nx) x \(ny) at \(UnitDisplay.number(sampling, digits: 3)) Å. The largest is "
                    + "\(AtomModelSpecimen.largestGrid). Cut the model smaller across the beam."
            }
        }
    }

    /// The file's name, and what it held as read: the document's frozen copy (the bytes are not kept).
    package let fileName: String
    package let contents: Contents
    /// The model as the kit's cell, made once: a CIF's expanded cell; a model's cell, or 5 Å of vacuum around a model without one.
    package let cell: CrystalCell
    /// Atoms outside the cell (the slab builder wraps them) and pairs closer than `closeDistance`, counted once at import.
    package let wrappedCount: Int
    package let closePairCount: Int

    /// Reads the model in `bytes`, by the file's name, and counts what the section notes: run it off the main actor. Throws `Refusal`.
    package init(bytes: Data, fileName: String) throws {
        let contents = try Self.read(bytes: bytes, fileName: fileName)
        let count = switch contents {
        case .model(let model): model.count
        case .cif(let structure): structure.sites.count
        }
        guard count <= Self.atomLimit else { throw Refusal.tooManyAtoms(count) }
        let cell: CrystalCell
        do {
            cell = try Self.cell(of: contents)
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.unreadable(file: fileName, reason: (error as? CustomStringConvertible)?.description ?? "\(error)")
        }
        self.fileName = fileName
        self.contents = contents
        self.cell = cell
        wrappedCount = Self.outsideCount(cell)
        closePairCount = Self.closePairs(cell)
        identity = "model:\(fileName):\(UUID().uuidString)"
    }

    private static func read(bytes: Data, fileName: String) throws -> Contents {
        do {
            if (fileName as NSString).pathExtension.lowercased() == "cif" {
                return .cif(try CrystalLoading.load(bytes: bytes, fileName: fileName).structure)
            }
            guard AtomModel.format(forFileName: fileName) != nil else { throw Refusal.format(file: fileName) }
            return .model(try AtomModel.read(bytes: bytes, fileName: fileName))
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.unreadable(file: fileName, reason: (error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// Reads the file at `url` once; the document keeps what it read.
    package init(contentsOf url: URL) throws {
        try self.init(bytes: try Data(contentsOf: url), fileName: url.lastPathComponent)
    }

    /// What the section and the method line call it: the file's name without its extension ("Al-Mg-Si model").
    package var name: String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? fileName : stem
    }

    /// The document's key for this model, made at import: each import is its own frozen copy, and the bytes are never hashed.
    package let identity: String

    /// Every atom's atomic number: a CIF's expanded sites, a model's atoms.
    package var atomicNumbers: [Int] {
        switch contents {
        case .model(let model): model.atomicNumbers
        case .cif(let structure): structure.sites.map(\.z)
        }
    }

    /// Whether the file gives a cell (a plain XYZ gives none).
    package var hasCell: Bool {
        if case .model(let model) = contents { return model.hasCell }
        return true
    }

    /// "Al 84 992, Mg 704, Si 704": atoms per element, most first.
    package var countsText: String {
        var counts: [Int: Int] = [:]
        for z in atomicNumbers { counts[z, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\(Element.symbol(forAtomicNumber: $0.key) ?? "Z \($0.key)") \(Self.grouped($0.value))" }
            .joined(separator: ", ")
    }

    private static func cell(of contents: Contents) throws -> CrystalCell {
        switch contents {
        case .cif(let structure):
            return try SimulationSpecimen.cell(of: structure)
        case .model(let model):
            guard model.hasCell else {
                return try CrystalCell.padded(atomicNumbers: model.atomicNumbers, positions: model.positions, box: nil, vacuum: Self.vacuum)
            }
            guard !model.cell.contains(SIMD3(0, 0, 0)) else { throw Refusal.partialCell }
            return try CrystalCell(cellRows: model.cell, atomicNumbers: model.atomicNumbers, positions: model.positions)
        }
    }

    /// The slab of the model with the beam along `axis` (one unit across, or whole units to at least `lateralSize` Å for frozen
    /// phonons), as the HRTEM image takes it.
    package func build(beamAlong axis: BeamAxis, lateralSize: SIMD2<Double>? = nil,
                       maximumStrain: Double = SimulationSpecimen.defaultMaximumStrain) -> Result<SimulationSpecimen.Built, SimulationSpecimen.Refusal> {
        do {
            // No thickness: one period, the model's own.
            let slab = try SlabBuilder.slab(ofModel: cell, beamAlong: axis.kit, lateralSize: lateralSize, thickness: nil,
                                            sliceThickness: SimulationSpecimen.sliceThickness, maximumStrain: maximumStrain,
                                            maximumAtomCount: Self.atomLimit)
            let built = SimulationSpecimen.Built(slab: slab, inPlaneAngle: 0)
            // The grid at the finest sampling (no aperture), the design's limit: a model too wide across is refused before any run.
            let optics = HRTEMOptics()
            let grid = try lateralSize == nil ? HRTEMImage.grid(built, optics: optics) : HRTEMImage.thermalGrid(built, optics: optics)
            if max(grid.nx, grid.ny) > Self.largestGrid {
                return .failure(.model(Refusal.gridTooLarge(nx: grid.nx, ny: grid.ny, sampling: HRTEMImage.finestSampling).sentence))
            }
            return .success(built)
        } catch let refusal as Refusal {
            return .failure(.model(refusal.sentence))
        } catch SimulatoError.strainTooLarge(_, let maximum, _) {
            return .failure(.model(Refusal.notRectangular(angle: angleText, limit: maximum).sentence))
        } catch SimulatoError.tooManyAtoms(let count, _) {
            return .failure(.model(Refusal.tooManyAtoms(count).sentence))
        } catch SimulatoError.partialOccupancy(let site, let occupancy) {
            return .failure(.partialOccupancy(site: "\(site + 1)", occupancy: occupancy))
        } catch {
            return .failure(.refused((error as? CustomStringConvertible)?.description ?? "\(error)"))
        }
    }

    /// What the section says about a model as read, each only when it applies: no cell, atoms outside the cell (wrapped), atoms
    /// closer than 0.5 Å, a cell made rectangular with its strain, more than one frame.
    package func notes(_ built: SimulationSpecimen.Built?) -> [String] {
        var notes: [String] = []
        if !hasCell {
            notes.append("This file has no cell. The model is simulated as an isolated object with "
                         + "\(UnitDisplay.number(Self.vacuum, digits: 2)) Å of vacuum around it.")
        }
        let outside = wrappedCount
        if outside > 0 {
            notes.append("\(UnitDisplay.count(outside, "atom lies", "atoms lie")) outside the cell and \(outside == 1 ? "is" : "are") wrapped into it.")
        }
        let close = closePairCount
        if close > 0 {
            notes.append("\(UnitDisplay.count(close, "pair of atoms is", "pairs of atoms are")) closer than "
                         + "\(UnitDisplay.number(Self.closeDistance, digits: 2)) Å: check the model.")
        }
        if let built, built.strain >= 5e-7 {
            notes.append("The cell is not rectangular (\(angleText)); it is made rectangular with \(SimulationSpecimen.percent(built.strain)) strain.")
        }
        if case .model(let model) = contents, model.frameCount > 1 {
            notes.append("The file holds \(model.frameCount) frames; the last is used, as ASE reads it.")
        }
        return notes
    }

    /// The section's summary: "Al-Mg-Si model: 86 400 atoms (Al 84 992, Mg 704, Si 704), box 81 × 81 Å across, 121.5 Å thick, beam along c."
    package func summary(_ built: SimulationSpecimen.Built, beam: BeamAxis) -> String {
        let box = built.box
        let n = atomicNumbers.count
        return "\(name): \(Self.grouped(n)) \(n == 1 ? "atom" : "atoms") (\(countsText)), box "
            + "\(UnitDisplay.number(box.x, digits: 4)) × \(UnitDisplay.number(box.y, digits: 4)) Å across, "
            + "\(UnitDisplay.number(box.z, digits: 4)) Å thick, beam along \(beam.rawValue)."
    }

    /// "γ = 60°": the first angle of the cell that is not a right angle; "the cell is skewed" when none reads as one.
    package var angleText: String {
        let rows = [cell.a, cell.b, cell.c]
        func angle(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double {
            acos(min(max(Self.dot(u, v) / (Self.dot(u, u) * Self.dot(v, v)).squareRoot(), -1), 1)) * 180 / .pi
        }
        for (symbol, value) in [("α", angle(rows[1], rows[2])), ("β", angle(rows[0], rows[2])), ("γ", angle(rows[0], rows[1]))]
        where abs(value - 90) > 1e-3 {
            return "\(symbol) = \(UnitDisplay.number(value, digits: 4))°"
        }
        return "the cell is skewed"
    }

    /// Atoms whose fractional coordinates lie outside [0, 1) along a periodic axis: the slab builder wraps them.
    static func outsideCount(_ cell: CrystalCell) -> Int {
        cell.sites.reduce(0) { n, site in
            let f = site.fractional
            return n + ((0 ..< 3).contains { f[$0] < -1e-9 || f[$0] >= 1 + 1e-9 } ? 1 : 0)
        }
    }

    static func dot(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double { (u * v).sum() }

    /// Pairs of atoms closer than `closeDistance` across the periodic cell (each atom wrapped into it, the nearest image of each
    /// other), counted once each. Fractional bins at least `closeDistance` wide perpendicular to each face, so a pair lies in the
    /// same or a neighbouring bin: linear in the atoms.
    static func closePairs(_ cell: CrystalCell) -> Int {
        let rows = [cell.a, cell.b, cell.c]
        func cross(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
        }
        let volume = abs(dot(rows[0], cross(rows[1], rows[2])))
        guard volume > 0, !cell.sites.isEmpty else { return 0 }
        let normals = [cross(rows[1], rows[2]), cross(rows[2], rows[0]), cross(rows[0], rows[1])]
        let bins = (0 ..< 3).map { max(1, Int(volume / dot(normals[$0], normals[$0]).squareRoot() / closeDistance)) }
        let f = cell.sites.map { site in site.fractional - site.fractional.rounded(.down) }
        func bin(_ p: SIMD3<Double>) -> SIMD3<Int> {
            SIMD3((0 ..< 3).map { min(Int(p[$0] * Double(bins[$0])), bins[$0] - 1) })
        }
        var grid: [SIMD3<Int>: [Int]] = [:]
        for (i, p) in f.enumerated() { grid[bin(p), default: []].append(i) }
        let limit = closeDistance * closeDistance
        var pairs = 0
        for (i, p) in f.enumerated() {
            let b = bin(p)
            var neighbours = Set<SIMD3<Int>>()
            for dx in -1 ... 1 { for dy in -1 ... 1 { for dz in -1 ... 1 {
                let n = b &+ SIMD3(dx, dy, dz)
                neighbours.insert(SIMD3((0 ..< 3).map { (n[$0] % bins[$0] + bins[$0]) % bins[$0] }))
            } } }
            for n in neighbours {
                for j in grid[n] ?? [] where j > i {
                    var d = f[j] - p
                    d -= d.rounded(.toNearestOrAwayFromZero)
                    let r = d.x * rows[0] + d.y * rows[1] + d.z * rows[2]
                    if dot(r, r) < limit { pairs += 1 }
                }
            }
        }
        return pairs
    }

    /// "1 000 000": a count with a space between thousands, as the design writes it, in every locale.
    package static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        let groups = stride(from: digits.count, to: 0, by: -3).reversed().map { String(digits[max($0 - 3, 0) ..< $0]) }
        return (n < 0 ? "-" : "") + groups.joined(separator: " ")
    }

    package static func == (l: AtomModelSpecimen, r: AtomModelSpecimen) -> Bool { l.identity == r.identity }
}
