//
//  SimulationSpecimen.swift
//  Role: the Simulation document's specimen (#893, plan row MA1): a phase turned to its zone axis and built into the slab the
//        multislice takes, by SimulatoKit's slab builder (a port of abTEM 1.0.10's `orthogonalize_cell`). This file maps the phase's
//        cell and its complete sites into the kit's `CrystalCell` (the design's "about ten lines": SimulatoKit imports no DiffractoKit),
//        says the kit's refusals in the room's words, and reads the box, the atom count and the strain for the Specimen section.
//        Every number is the kit's.
//
//  Orientation: DiffractoKit's `CrystalOrientation(zoneAxis:inPlaneAngle:cell:)` and the slab's `orientation` are both written as
//  "columns are the lab (box) axes in the crystal's Cartesian frame", and both put the zone axis in the third column. They differ only
//  by a turn about the beam: the pattern's x reference is py4DSTEM's, the slab's x is the shortest lattice row at right angles to the
//  zone axis (so the box repeats exactly). `inPlaneAngle` is that turn, so the pattern drawn at it and the slab show the same crystal.
//

import DiffractoCore
import Foundation
import SimulatoCore
import simd

package nonisolated enum SimulationSpecimen {
    /// The thickness a new Simulation document starts at, nm: abTEM's HRTEM examples, and enough for the exit planes of the reference
    /// recipe (about 2, 5 and 10 nm of Si [1 1 0]).
    package static let defaultThicknessNM = 10.0
    /// The thickness range the field accepts, nm.
    package static let thicknessRangeNM = 0.5 ... 200.0
    /// The slice thickness, Å: abTEM's default.
    package static let sliceThickness = 1.0
    /// The strain a box may carry before the room asks: the kit's 0.1 %, the precision an indexed pattern resolves.
    package static let defaultMaximumStrain = SlabBuilder.defaultMaximumStrain

    /// What the section reads for a built specimen.
    package struct Built: Sendable, Equatable {
        /// The slab: the orthogonal unit repeated to the thickness (one unit across, which a static plane-wave run needs).
        package let slab: Slab
        /// The turn about the beam, radians, that brings the pattern's frame onto the slab's (`CrystalOrientation` at this in-plane
        /// angle equals `slab.orientation`).
        package let inPlaneAngle: Double

        /// The orthogonal unit's box, Å: x and y across the beam, z the period along it.
        package var box: SIMD3<Double> { slab.unit.structure.box }
        /// Atoms in one orthogonal unit (one period).
        package var unitAtoms: Int { slab.unit.structure.atoms.count }
        /// Atoms in the whole slab.
        package var slabAtoms: Int { slab.structure.atoms.count }
        /// Whole periods along the beam.
        package var periods: Int { slab.repeats.z }
        /// The thickness built, nm (whole periods).
        package var thicknessNM: Double { Double(periods) * box.z / 10 }
        /// The strain the unit carries (0.001 is 0.1 %).
        package var strain: Double { slab.strain }
    }

    /// Why no specimen was built, in the room's words.
    package enum Refusal: Error, Sendable, Equatable {
        /// No phase is shown.
        case noPhase
        /// A site holds its atom in only part of the cells; 2.5 builds fully occupied sites only.
        case partialOccupancy(site: String, occupancy: Double)
        /// The nearest orthogonal box strains the cell more than the limit; Build with Strain accepts `strain`.
        case strain(strain: Double, limit: Double, repetitions: Int)
        /// Anything else the kit refused, in its words.
        case refused(String)

        package var sentence: String {
            switch self {
            case .noPhase:
                "Add a phase to simulate."
            case .partialOccupancy(let site, let occupancy):
                "Site \(site) is occupied \(UnitDisplay.number(occupancy * 100, digits: 3)) % of the time; a simulation needs every site "
                    + "fully occupied, so this phase cannot be built yet."
            case .strain(let strain, let limit, let repetitions):
                "The closest box that repeats along this zone axis strains the crystal by \(SimulationSpecimen.percent(strain)) "
                    + "(searched to \(repetitions) repetitions), more than the \(SimulationSpecimen.percent(limit)) limit. "
                    + "Build with Strain builds it strained so."
            case .refused(let words):
                "The specimen cannot be built: \(words)."
            }
        }

        /// The strain Build with Strain would accept; nil unless the refusal is the strain limit.
        package var acceptableStrain: Double? {
            if case .strain(let strain, _, _) = self { return strain }
            return nil
        }
    }

    /// The kit's crystal for a phase: the cell from its lengths and angles (ASE's `cellpar_to_cell`, the same frame as DiffractoKit's
    /// `UnitCell`), and every site of the cell (DiffractoKit's `sites` hold the expanded cell, the space group already applied).
    package static func cell(of structure: CrystalStructure) throws -> CrystalCell {
        let c = structure.cell
        let sites = structure.sites.map {
            CrystalCell.Site(atomicNumber: $0.z, fractional: $0.fractional, occupancy: $0.occupancy)
        }
        return try CrystalCell(a: c.a, b: c.b, c: c.c, alpha: c.alphaDeg, beta: c.betaDeg, gamma: c.gammaDeg, sites: sites)
    }

    /// Builds the slab of `structure` along `zoneAxis` at `thicknessNM` (whole periods, at least one), with at most `maximumStrain`.
    package static func build(_ structure: CrystalStructure, zoneAxis: SIMD3<Int>, thicknessNM: Double,
                              maximumStrain: Double = defaultMaximumStrain) -> Result<Built, Refusal> {
        do {
            let crystalCell = try cell(of: structure)
            let slab = try SlabBuilder.slab(of: crystalCell, zoneAxis: zoneAxis, thickness: thicknessNM * 10,
                                            sliceThickness: sliceThickness, maximumStrain: maximumStrain)
            let angle = try inPlaneAngle(slab.orientation, zoneAxis: zoneAxis, cell: structure.cell)
            return .success(Built(slab: slab, inPlaneAngle: angle))
        } catch let error as SimulatoError {
            switch error {
            case .partialOccupancy(let i, let occupancy):
                return .failure(.partialOccupancy(site: siteName(structure, i), occupancy: occupancy))
            case .strainTooLarge(let strain, let maximum, let repetitions):
                return .failure(.strain(strain: strain, limit: maximum, repetitions: repetitions))
            default:
                return .failure(.refused(error.description))
            }
        } catch {
            return .failure(.refused(String(describing: error)))
        }
    }

    /// The turn about the beam, radians, from the pattern's frame at `zoneAxis` (in-plane angle 0) to `orientation` (the slab's).
    /// Both share the zone axis as their third column, so R₀ᵀ · R is a turn about z: [[c, s, 0], [−s, c, 0], [0, 0, 1]] in
    /// py4DSTEM's m3z, whose first column is (c, −s, 0).
    package static func inPlaneAngle(_ orientation: simd_double3x3, zoneAxis: SIMD3<Int>, cell: UnitCell) throws -> Double {
        let r0 = try CrystalOrientation(zoneAxis: zoneAxis, inPlaneAngle: 0, cell: cell).matrix
        let m = r0.transpose * orientation
        return atan2(-m.columns.0.y, m.columns.0.x)
    }

    /// "5.43 × 7.68 Å across, 7.68 Å a period" for the box.
    package static func boxText(_ box: SIMD3<Double>) -> String {
        "\(UnitDisplay.number(box.x, digits: 3)) × \(UnitDisplay.number(box.y, digits: 3)) Å across, "
            + "\(UnitDisplay.number(box.z, digits: 3)) Å a period"
    }

    /// "0 %", "0.03 %": the strain as a percentage.
    package static func percent(_ strain: Double) -> String {
        strain < 5e-7 ? "0 %" : "\(UnitDisplay.number(strain * 100, digits: 2)) %"
    }

    /// The Specimen section's summary line: "Si [1 1 0]: 16 atoms a period, 13 periods (9.98 nm), 208 atoms, strain 0 %."
    package static func summary(_ built: Built, phase: String, zoneAxis: SIMD3<Int>) -> String {
        "\(phase) \(ZoneAxisText.text(zoneAxis)): \(UnitDisplay.count(built.unitAtoms, "atom", "atoms")) a period, "
            + "\(UnitDisplay.count(built.periods, "period", "periods")) (\(UnitDisplay.number(built.thicknessNM, digits: 3)) nm), "
            + "\(UnitDisplay.count(built.slabAtoms, "atom", "atoms")), strain \(percent(built.strain))."
    }

    /// "Si1 (Si)" from the site's label, else "3 (Si)" by its place in the cell.
    static func siteName(_ structure: CrystalStructure, _ index: Int) -> String {
        guard structure.sites.indices.contains(index) else { return "\(index + 1)" }
        let site = structure.sites[index]
        let element = Element.symbol(forAtomicNumber: site.z) ?? "Z \(site.z)"
        if let label = site.label, !label.isEmpty, label != element { return "\(label) (\(element))" }
        return "\(index + 1) (\(element))"
    }
}
