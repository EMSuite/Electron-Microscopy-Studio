//
//  VariantPlacement+DoubleDiffraction.swift
//  Role: double diffraction between a matrix and the shown variants of its precipitate (plan row R10, #809): a beam diffracted by
//        g₁ of one crystal and again by g₂ of another leaves along g₁ + g₂, a spot neither kinematic pattern has (the kit's
//        `DoubleDiffraction.spots(crystals:)`, DiffractoKit S3: Gjønnes & Moodie 1965). Only spots between the matrix and a
//        variant are kept (the matrix's own double diffraction is the Simulation section's; variant with variant is not this
//        feature's), each with its routes through the matrix in words, the strongest route first. At most `cap` are drawn; the sentence says how many there are. No intensity: kinematic theory gives none.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation

/// A spot double diffraction adds between two of the crystals.
package nonisolated struct VariantDoubleSpot: Sendable, Equatable {
    /// (qx, qy), Å⁻¹, as the variants' spots.
    package let position: SIMD2<Double>
    /// "Al: 111 then β″ 3: 200", the strongest route first.
    package let routes: [String]
}

/// The spots double diffraction adds between the matrix and the shown variants.
package nonisolated struct VariantDoubleDiffraction: Sendable, Equatable {
    /// The drawn spots: those with the strongest routes, at most the cap.
    package let spots: [VariantDoubleSpot]
    /// Every added spot between the matrix and a variant, drawn or not.
    package let total: Int

    /// "24 spots by double diffraction between the crystals, drawn as dashed rings." or "… 200 of 640 drawn, the strongest routes
    /// first." or "No spot by double diffraction between the crystals in this view."
    package var countSentence: String {
        if total == 0 { return "No spot by double diffraction between the crystals in this view." }
        let noun = total == 1 ? "1 spot" : "\(total) spots"
        if spots.count < total {
            return "\(noun) by double diffraction between the crystals: \(spots.count) of them drawn, the strongest routes first."
        }
        return "\(noun) by double diffraction between the crystals, drawn as dashed rings."
    }
}

extension VariantPlacement {

    /// The most added spots drawn at once.
    package static let doubleDiffractionCap = 200

    /// The added spots between `matrix` at `matrixOrientation` and the shown variants of `set` (precipitate structure
    /// `precipitateStructure`), at `volts`, reflections to `kMax`. Throws the kit's refusal.
    package static func doubleDiffraction(set: VariantSet, matrixStructure: CrystalStructure, matrixOrientation: CrystalOrientation,
                                          precipitateStructure: CrystalStructure, volts: Double, kMax: Double = PatternIndexing.reach,
                                          hidden: Set<Int>, cap: Int = doubleDiffractionCap) throws -> VariantDoubleDiffraction {
        let shown = set.variants.filter { !hidden.contains($0.index) }
        guard !shown.isEmpty else { return VariantDoubleDiffraction(spots: [], total: 0) }
        let matrixSimulator = try SpotPatternSimulator(structure: matrixStructure, kMax: kMax)
        let precipitateSimulator = try SpotPatternSimulator(structure: precipitateStructure, kMax: kMax)
        let crystals = [DiffractingCrystal(simulator: matrixSimulator, orientation: matrixOrientation)]
            + shown.map { DiffractingCrystal(simulator: precipitateSimulator, orientation: $0.orientation) }
        let result = try DoubleDiffraction.spots(crystals: crystals, volts: volts)
        /// Crystal 0 is the matrix, crystal k the k-th shown variant.
        func name(_ crystal: Int) -> String {
            crystal == 0 ? set.matrix : "\(set.precipitate) \(shown[crystal - 1].index + 1)"
        }
        func step(_ s: DoubleDiffractionRoute.Step) -> String { "\(name(s.crystal)): \(ZoneAxisText.label(s.hkl))" }
        // The kit pairs every crystal with every other; only routes through the matrix are this feature's (variant with variant
        // is not), so a spot stays when one of its routes has a step in crystal 0, with those routes alone.
        let between = result.added.filter { $0.crystal == nil }.compactMap { s -> VariantDoubleSpot? in
            let routes = s.routes.filter { $0.first.crystal == 0 || $0.second.crystal == 0 }
            guard !routes.isEmpty else { return nil }
            return VariantDoubleSpot(position: s.position, routes: routes.map { "\(step($0.first)) then \(step($0.second))" })
        }
        let spots = between.prefix(max(cap, 0))
        return VariantDoubleDiffraction(spots: Array(spots), total: between.count)
    }
}
