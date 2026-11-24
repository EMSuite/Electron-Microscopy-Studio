//
//  DiffractionVariants.swift
//  Role: a precipitate in the Diffraction room's crystal for one open pattern (plan row R9, #808): the precipitate, its relationship
//        to the room's crystal (the matrix), which variants are hidden, and whether they are drawn. The variants themselves
//        (`VariantPlacement.place`: every orientation from Index's matrix orientation and the two pairs, the groups, the merged
//        spots) are derived from the inputs off the main actor (`place`), and the last placement is kept for the views. Until the multi-phase room (A2) holds the
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
    package nonisolated struct Precipitate: Sendable, Equatable {
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
    /// Also draws the spots double diffraction adds between the matrix and the shown variants (#809).
    package var doubleDiffraction = false

    /// The last placement that landed, with the inputs it was placed for. Views draw it until a newer one lands.
    package private(set) var placed: Placed?
    /// The inputs being placed off the main actor; nil when nothing is in flight.
    package private(set) var placing: Inputs?
    /// The newest inputs asked for while another placement runs; placed next.
    @ObservationIgnored private var pending: Inputs?

    /// What a placement reads: the precipitate, the matrix and Index's orientation of it, the beam energy, the hidden variants
    /// and whether double diffraction is asked for.
    package nonisolated struct Inputs: Sendable, Equatable {
        package var precipitate: Precipitate
        package var matrix: String
        package var matrixStructure: CrystalStructure
        package var relationship: PrecipitateRelationship
        package var orientation: CrystalOrientation?
        package var volts: Double
        package var hidden: Set<Int>
        package var doubleDiffraction: Bool
    }

    /// The variants placed for `inputs`, and with double diffraction on and a variant placed, the spots it adds.
    package nonisolated struct Placed: Sendable, Equatable {
        package let inputs: Inputs
        package let set: Result<VariantSet, VariantRefusal>
        package let added: Result<VariantDoubleDiffraction, DoubleDiffractionRefusal>?
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

    /// The inputs of the room as it is now; nil without a beam energy.
    package func inputs(analysis: DiffractionAnalysis, image: CalibratedImage) -> Inputs? {
        guard let volts = analysis.volts(for: image) else { return nil }
        return Inputs(precipitate: precipitate, matrix: analysis.crystal.name, matrixStructure: analysis.crystal.structure,
                      relationship: relationship, orientation: analysis.indexOutcome?.orientation, volts: volts, hidden: hidden,
                      doubleDiffraction: doubleDiffraction)
    }

    /// Places `inputs` off the main actor (12 simulated patterns for β″, and the double-diffraction sum) and keeps the answer.
    /// A view calls it from `.task(id:)` with the room's inputs; the last answer stays on screen until the new one lands. One
    /// placement runs at a time and only the newest asked waits behind it, so a drag computes the first and the last inputs, not
    /// each one between. Asking again for what is already placed drops what is in flight and waiting.
    package func place(_ inputs: Inputs) async {
        if placed?.inputs == inputs { placing = nil; pending = nil; return }
        if let running = placing {
            pending = running == inputs ? nil : inputs
            return
        }
        var next: Inputs? = inputs
        while let asked = next {
            placing = asked
            let landed = await Task.detached(priority: .userInitiated) { Self.compute(asked) }.value
            // `placing` cleared meanwhile: the room went back to what was placed, and this answer is stale.
            if placing == asked { placed = landed }
            next = placing == asked ? pending : nil
            pending = nil
        }
        placing = nil
    }

    /// Places `inputs` now, on the caller's actor: for the agent door, whose answer must be the placement it describes.
    package func placeNow(_ inputs: Inputs) {
        guard placed?.inputs != inputs else { return }
        placing = nil
        placed = Self.compute(inputs)
    }

    /// The kit's placement, and the added spots when asked for. Pure.
    nonisolated package static func compute(_ inputs: Inputs) -> Placed {
        let set = VariantPlacement.place(precipitate: inputs.precipitate.name, precipitateStructure: inputs.precipitate.structure,
                                         matrix: inputs.matrix, matrixStructure: inputs.matrixStructure,
                                         relationship: inputs.relationship, matrixOrientation: inputs.orientation,
                                         volts: inputs.volts, hidden: inputs.hidden)
        var added: Result<VariantDoubleDiffraction, DoubleDiffractionRefusal>?
        if inputs.doubleDiffraction, case .success(let placed) = set, let orientation = inputs.orientation {
            do {
                added = .success(try VariantPlacement.doubleDiffraction(set: placed, matrixStructure: inputs.matrixStructure,
                                                                        matrixOrientation: orientation,
                                                                        precipitateStructure: inputs.precipitate.structure,
                                                                        volts: inputs.volts, hidden: inputs.hidden))
            } catch {
                added = .failure(DoubleDiffractionRefusal(sentence: String(describing: error)))
            }
        }
        return Placed(inputs: inputs, set: set, added: added)
    }

    /// The variants as last placed; nil without a beam energy or before the first placement lands.
    package func variants(analysis: DiffractionAnalysis, image: CalibratedImage) -> Result<VariantSet, VariantRefusal>? {
        guard inputs(analysis: analysis, image: image) != nil else { return nil }
        return placed?.set
    }

    /// The added spots as last placed; nil while the switch is off or no variant is placed.
    package func addedSpots(analysis: DiffractionAnalysis, image: CalibratedImage) -> Result<VariantDoubleDiffraction, DoubleDiffractionRefusal>? {
        guard doubleDiffraction, inputs(analysis: analysis, image: image) != nil else { return nil }
        return placed?.added
    }

    /// The added spots as pixels of the pattern; off the image left out.
    package func pixels(of added: VariantDoubleDiffraction, analysis: DiffractionAnalysis, image: CalibratedImage) -> [VariantPixel] {
        added.spots.compactMap { pixel($0.position, relative: 0, variants: [], analysis: analysis, image: image) }
    }

    /// The pixel of (qx, qy) Å⁻¹ at the room's scale, nil off the image or without a scale.
    private func pixel(_ position: SIMD2<Double>, relative: Double, variants: [Int], analysis: DiffractionAnalysis,
                       image: CalibratedImage) -> VariantPixel? {
        guard let centre = analysis.centre, let calibration = analysis.calibration(for: image) else { return nil }
        let q = (position.x * position.x + position.y * position.y).squareRoot()
        guard q > 0 else { return nil }
        let r = ZoneAxisOverlay.radius(q: q, calibration: calibration)
        let row = centre.row + r * position.x / q, column = centre.column + r * position.y / q
        guard row.isFinite, column.isFinite, row >= -0.5, row <= Double(image.height) - 0.5,
              column >= -0.5, column <= Double(image.width) - 0.5 else { return nil }
        return VariantPixel(row: row, column: column, relative: relative, variants: variants)
    }

    /// The shown variants' spots as pixels of the pattern, with each spot's intensity against the strongest; off the image left out.
    package func pixels(of set: VariantSet, analysis: DiffractionAnalysis, image: CalibratedImage) -> [VariantPixel] {
        let strongest = set.spots.map(\.intensity).max() ?? 0
        guard strongest > 0 else { return [] }
        return set.spots.compactMap { s in
            pixel(s.position, relative: s.intensity / strongest, variants: s.members.map(\.variant), analysis: analysis, image: image)
        }
    }
}

/// Why the added spots could not be computed, in the kit's words.
package nonisolated struct DoubleDiffractionRefusal: Error, Sendable, Equatable {
    package let sentence: String
}

/// One merged variant spot on the pattern.
package nonisolated struct VariantPixel: Sendable, Equatable {
    package let row: Double
    package let column: Double
    package let relative: Double
    /// The variants (0-based) that predict it.
    package let variants: [Int]
}
