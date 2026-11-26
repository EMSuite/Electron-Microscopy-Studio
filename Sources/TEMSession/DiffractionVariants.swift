//
//  DiffractionVariants.swift
//  Role: a precipitate in the Diffraction room's crystal for one open pattern (plan row R9, #808): the precipitate, its relationship
//        to the room's crystal (the matrix), which variants are hidden, and whether they are drawn. The variants themselves
//        (`VariantPlacement.place`: every orientation from Index's matrix orientation and the two pairs, the groups, the merged
//        spots) are derived from the inputs off the main actor (`place`), and the last placement is kept for the views.
//        Nothing is chosen for the person (#1137): the precipitate is any phase the room can use (a library phase from a CIF or
//        the Materials Project, a standard, another open pattern's crystal) and the relationship is typed as a paper states it,
//        as orix builds one (`Misorientation.from_align_vectors` on two parallel pairs). A literature example (`Example`) fills
//        both at once and names its paper; the room says so when the matrix is not the one the paper states it for.
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

        /// β″ (Mg5Si6), the kit's preset from Andersen et al. (1998): only through its literature example.
        package static let betaDoublePrime = Precipitate(name: "β″", structure: CrystalPresets.betaDoublePrime)
    }

    /// A precipitate and its relationship as one paper states them, for the matrix it states them for: picked by the person,
    /// never a default.
    package nonisolated struct Example: Sendable, Equatable, Identifiable {
        /// The door's name for it.
        package let id: String
        /// The menu's words: "β″ (Mg₅Si₆) in Al".
        package let title: String
        /// The paper: "Andersen et al., Acta Mater. 46 (1998) 3283".
        package let citation: String
        package let precipitate: Precipitate
        package let relationship: PrecipitateRelationship
        /// The matrix the paper states it for, as its name and its elements (atomic numbers).
        package let matrixName: String
        package let matrixElements: Set<Int>

        /// True when `matrix` is made of the paper's matrix elements only.
        package func fits(matrix: CrystalStructure) -> Bool {
            let elements = Set(matrix.sites.map(\.z))
            return !elements.isEmpty && elements == matrixElements
        }

        /// β″ in Al as Andersen et al. (1998) state it: [1 0 0] ∥ [3 2 0] Al, kept exact, and [0 0 1] ∥ [1 -3 0] Al.
        package static let betaDoublePrimeInAluminium = Example(
            id: "beta_double_prime_in_al", title: "β″ (Mg₅Si₆) in Al",
            citation: "Andersen et al., Acta Mater. 46 (1998) 3283", precipitate: .betaDoublePrime,
            relationship: VariantPlacement.betaDoublePrimeInAluminium, matrixName: "Al", matrixElements: [13])

        /// The examples the section and the door offer.
        package static let all: [Example] = [betaDoublePrimeInAluminium]
    }

    /// The variants' spots drawn over the pattern.
    package var isShown = false
    /// None until the person chooses one.
    package private(set) var precipitate: Precipitate?
    /// None until the person types both pairs or picks an example.
    package private(set) var relationship: PrecipitateRelationship?
    /// The example the precipitate and relationship came from, while both are still its own.
    package private(set) var example: Example?
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
        package var precipitate: Precipitate?
        package var matrix: String
        package var matrixStructure: CrystalStructure
        package var relationship: PrecipitateRelationship?
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

    /// A new precipitate (nil: none) shows every variant again. A typed relationship stays; an example's relationship belongs to
    /// its precipitate and goes with it, so no paper's pairs are kept silently for another crystal.
    package func setPrecipitate(_ new: Precipitate?) {
        guard new != precipitate else { return }
        if let example, relationship == example.relationship { relationship = nil }
        example = nil
        precipitate = new
        hidden = []
    }

    /// A new relationship shows every variant again: the numbering is the kit's for these pairs.
    package func setRelationship(_ new: PrecipitateRelationship?) {
        guard new != relationship else { return }
        if new != example?.relationship { example = nil }
        relationship = new
        hidden = []
    }

    /// The example's precipitate and relationship, both at once, with every variant shown.
    package func use(_ new: Example) {
        precipitate = new.precipitate
        relationship = new.relationship
        example = new
        hidden = []
    }

    /// The sentence the section and the door say when the example's paper states it for another matrix; nil when it fits or no
    /// example is in use.
    package func exampleWarning(matrix: String, matrixStructure: CrystalStructure) -> String? {
        guard let example, !example.fits(matrix: matrixStructure) else { return nil }
        return "\(example.citation.components(separatedBy: ",").first ?? example.citation) state this relationship for "
            + "\(example.precipitate.name) in \(example.matrixName); the crystal here is \(matrix). Type the relationship a paper states "
            + "for this matrix."
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

    /// Places `inputs` off the main actor (a simulated pattern per variant, 12 for β″ in Al, and the double-diffraction sum) and keeps the answer.
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
        guard let precipitate = inputs.precipitate else { return Placed(inputs: inputs, set: .failure(.noPrecipitate), added: nil) }
        guard precipitate.name != inputs.matrix else { return Placed(inputs: inputs, set: .failure(.precipitateIsMatrix), added: nil) }
        guard let relationship = inputs.relationship else { return Placed(inputs: inputs, set: .failure(.noRelationship), added: nil) }
        let set = VariantPlacement.place(precipitate: precipitate.name, precipitateStructure: precipitate.structure,
                                         matrix: inputs.matrix, matrixStructure: inputs.matrixStructure,
                                         relationship: relationship, matrixOrientation: inputs.orientation,
                                         volts: inputs.volts, hidden: inputs.hidden)
        var added: Result<VariantDoubleDiffraction, DoubleDiffractionRefusal>?
        if inputs.doubleDiffraction, case .success(let placed) = set, let orientation = inputs.orientation {
            do {
                added = .success(try VariantPlacement.doubleDiffraction(set: placed, matrixStructure: inputs.matrixStructure,
                                                                        matrixOrientation: orientation,
                                                                        precipitateStructure: precipitate.structure,
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
