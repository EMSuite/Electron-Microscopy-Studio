//
//  DiffractionVariants.swift
//  Role: a precipitate in the Diffraction room's crystal for one open pattern (plan row R9, #808): the precipitate, its relationship
//        to the room's crystal (the matrix), which variants are hidden, and whether they are drawn. The variants themselves
//        (`VariantPlacement.place`: every orientation from Index's matrix orientation and the two pairs, the groups, the merged
//        spots) are derived each time and cached by their inputs, never stored. Until the multi-phase room (A2) holds the
//        precipitate as a phase of its own, it is β″ or a standard or the crystal of another open pattern.
//

import Foundation
import Observation
import ImagoCore
import DiffractoCore
import TEMCore

@Observable
package final class DiffractionVariants {
    /// One precipitate the room can place: a name and its structure.
    package struct Precipitate: Sendable, Equatable {
        package let name: String
        package let structure: CrystalStructure
        package init(name: String, structure: CrystalStructure) { self.name = name; self.structure = structure }

        /// β″ (Mg5Si6), the kit's preset from Andersen et al. (1998).
        package static let betaDoublePrime = Precipitate(name: "β″", structure: CrystalPresets.betaDoublePrime)
    }

    /// The variants' spots drawn over the pattern.
    package var isShown = false
    package private(set) var precipitate = Precipitate.betaDoublePrime
    package private(set) var relationship = VariantPlacement.betaDoublePrimeInAluminium
    /// The hidden variants, 0-based.
    package private(set) var hidden: Set<Int> = []

    @ObservationIgnored private var cache: (key: Key, result: Result<VariantSet, VariantRefusal>)?
    private struct Key: Equatable {
        var precipitate: Precipitate
        var matrix: String
        var matrixStructure: CrystalStructure
        var relationship: PrecipitateRelationship
        var orientation: CrystalOrientation?
        var volts: Double
        var hidden: Set<Int>
    }

    package init() {}

    /// A new precipitate keeps the relationship and shows every variant again.
    package func setPrecipitate(_ new: Precipitate) {
        guard new != precipitate else { return }
        precipitate = new
        hidden = []
    }

    /// A new relationship shows every variant again: the numbering is the kit's for these pairs.
    package func setRelationship(_ new: PrecipitateRelationship) {
        guard new != relationship else { return }
        relationship = new
        hidden = []
    }

    package func setHidden(_ variant: Int, _ isHidden: Bool) {
        if isHidden { hidden.insert(variant) } else { hidden.remove(variant) }
    }

    /// The variants in the room's crystal at Index's orientation; nil without a beam energy.
    package func variants(analysis: DiffractionAnalysis, image: CalibratedImage) -> Result<VariantSet, VariantRefusal>? {
        guard let volts = analysis.volts(for: image) else { return nil }
        let key = Key(precipitate: precipitate, matrix: analysis.crystal.name, matrixStructure: analysis.crystal.structure,
                      relationship: relationship, orientation: analysis.indexOutcome?.orientation, volts: volts, hidden: hidden)
        if let cache, cache.key == key { return cache.result }
        let result = VariantPlacement.place(precipitate: key.precipitate.name, precipitateStructure: key.precipitate.structure,
                                            matrix: key.matrix, matrixStructure: key.matrixStructure, relationship: key.relationship,
                                            matrixOrientation: key.orientation, volts: volts, hidden: hidden)
        cache = (key, result)
        return result
    }

    /// The shown variants' spots as pixels of the pattern, with each spot's intensity against the strongest; off the image left out.
    package func pixels(of set: VariantSet, analysis: DiffractionAnalysis, image: CalibratedImage) -> [VariantPixel] {
        guard let centre = analysis.centre, let calibration = analysis.calibration(for: image) else { return [] }
        let strongest = set.spots.map(\.intensity).max() ?? 0
        return set.spots.compactMap { s in
            let q = (s.position.x * s.position.x + s.position.y * s.position.y).squareRoot()
            guard q > 0, strongest > 0 else { return nil }
            let r = ZoneAxisOverlay.radius(q: q, calibration: calibration)
            let row = centre.row + r * s.position.x / q, column = centre.column + r * s.position.y / q
            guard row.isFinite, column.isFinite, row >= -0.5, row <= Double(image.height) - 0.5,
                  column >= -0.5, column <= Double(image.width) - 0.5 else { return nil }
            return VariantPixel(row: row, column: column, relative: s.intensity / strongest, variants: s.members.map(\.variant))
        }
    }
}

/// One merged variant spot on the pattern.
package struct VariantPixel: Sendable, Equatable {
    package let row: Double
    package let column: Double
    package let relative: Double
    /// The variants (0-based) that predict it.
    package let variants: [Int]
}
