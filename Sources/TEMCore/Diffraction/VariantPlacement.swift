//
//  VariantPlacement.swift
//  Role: a precipitate in a matrix as the Diffraction room, the Simulation document and the agent door read it (plan row R9,
//        #808): the relationship typed as a paper states it (two parallel pairs, the first exact), every variant's orientation
//        placed from the matrix's (`OrientationRelationship.variantOrientations`, kit S7, pinned against orix
//        `Misorientation.equivalent`, P36), which variants look alike in this view (the kit's grouping on the drawn spots), the
//        shown variants' spots merged so a spot several variants predict names them all, and the sentences the room says.
//        Variant orientations are derived from the matrix orientation and the pairs each time, never stored.
//        Pure and nonisolated: the room and the door call the same `VariantPlacement.place`.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation

/// One side of a parallel pair: a plane (h k l) or a direction [u v w] of one crystal. Codable, for the document.
package nonisolated struct RelationshipVector: Sendable, Codable, Equatable, Hashable {
    package enum Kind: String, Sendable, Codable, Equatable, Hashable { case plane, direction }
    package var kind: Kind
    package var indices: [Int]

    package init(_ kind: Kind, _ a: Int, _ b: Int, _ c: Int) {
        self.kind = kind; self.indices = [a, b, c]
    }

    /// The kit's vector; nil unless three indices, not all zero.
    package var latticeVector: LatticeVector? {
        guard indices.count == 3, indices.contains(where: { $0 != 0 }) else { return nil }
        let v = SIMD3(indices[0], indices[1], indices[2])
        return kind == .plane ? .plane(v) : .direction(v)
    }

    /// "(0 0 1)" or "[1 0 0]".
    package var text: String {
        let body = indices.map(String.init).joined(separator: " ")
        return kind == .plane ? "(\(body))" : "[\(body)]"
    }

    /// The text of a kit vector.
    package static func describe(_ v: LatticeVector) -> String {
        switch v {
        case .plane(let i): RelationshipVector(.plane, i.x, i.y, i.z).text
        case .direction(let i): RelationshipVector(.direction, i.x, i.y, i.z).text
        }
    }
}

/// The relationship of a precipitate to its matrix: two parallel pairs, the first kept exact, the second fixing the turn about it.
package nonisolated struct PrecipitateRelationship: Sendable, Codable, Equatable, Hashable {
    package var firstPrecipitate: RelationshipVector
    package var firstMatrix: RelationshipVector
    package var secondPrecipitate: RelationshipVector
    package var secondMatrix: RelationshipVector

    package init(first: (RelationshipVector, RelationshipVector), second: (RelationshipVector, RelationshipVector)) {
        firstPrecipitate = first.0; firstMatrix = first.1; secondPrecipitate = second.0; secondMatrix = second.1
    }

    /// The kit's two pairs; nil when a vector has no indices.
    package var pairs: (first: OrientationRelationship, second: OrientationRelationship)? {
        guard let fp = firstPrecipitate.latticeVector, let fm = firstMatrix.latticeVector,
              let sp = secondPrecipitate.latticeVector, let sm = secondMatrix.latticeVector else { return nil }
        return (OrientationRelationship(candidate: fp, matrix: fm), OrientationRelationship(candidate: sp, matrix: sm))
    }

    /// "[1 0 0] ∥ [3 2 0] Al, [0 0 1] ∥ [1 -3 0] Al".
    package func text(matrix: String) -> String {
        "\(firstPrecipitate.text) ∥ \(firstMatrix.text) \(matrix), \(secondPrecipitate.text) ∥ \(secondMatrix.text) \(matrix)"
    }
}

/// One variant as the Phases section lists it.
package nonisolated struct VariantRow: Sendable, Equatable, Identifiable {
    /// The kit's index (0-based); shown from 1.
    package let id: Int
    package var number: Int { id + 1 }
    /// Variants of one group predict the same spots in this view; groups from 0.
    package let group: Int
    /// "[1 0 0] ∥ [3 2 0] Al": where this variant puts the first pair.
    package let label: String
    package let isHidden: Bool
}

/// A predicted spot of the shown variants: spots of several variants within the grouping tolerance are one, naming each.
package nonisolated struct VariantSpot: Sendable, Equatable {
    /// (qx, qy), Å⁻¹: the first member's.
    package let position: SIMD2<Double>
    /// The strongest member's intensity, Å⁻⁴.
    package let intensity: Double
    /// The variants (0-based) and the hkl each gives it, in variant order.
    package let members: [(variant: Int, hkl: MillerIndex)]

    package static func == (a: VariantSpot, b: VariantSpot) -> Bool {
        a.position == b.position && a.intensity == b.intensity && a.members.map(\.variant) == b.members.map(\.variant)
            && a.members.map(\.hkl) == b.members.map(\.hkl)
    }
}

/// The variants of one precipitate placed on the matrix's orientation.
package nonisolated struct VariantSet: Sendable, Equatable {
    package let precipitate: String
    package let matrix: String
    /// The kit's variants, in its order.
    package let variants: [VariantOrientation]
    package let rows: [VariantRow]
    /// How far the second pair is from parallel once the first is exact, degrees.
    package let secondPairMisfitDeg: Double
    /// The spots of the shown variants, merged.
    package let spots: [VariantSpot]

    /// How many groups (looks) the variants fall into in this view.
    package var groupCount: Int { Set(rows.map(\.group)).count }

    /// "β″ in Al · 12 variants, 10 look different in this view" (or "… all look different …").
    package var summarySentence: String {
        let n = rows.count, g = groupCount
        let look = n == 1 ? "1 variant"
            : g == n ? "\(n) variants, all look different in this view" : "\(n) variants, \(g) look different in this view"
        return "\(precipitate) in \(matrix) · " + look
    }

    /// The relationship sheet's result line: "12 variants. The second pair is 0.05° from parallel. The first pair is kept exact."
    package var sheetSentence: String {
        let count = rows.count == 1 ? "1 variant." : "\(rows.count) variants."
        if secondPairMisfitDeg < 0.005 { return count + " Both pairs are exact." }
        return count + String(format: " The second pair is %.2f° from parallel. The first pair is kept exact.", secondPairMisfitDeg)
    }

    /// For each group of two or more: "Variants 2 and 3 predict the same spots in this view".
    package var lookAlikeSentences: [String] {
        let byGroup = Dictionary(grouping: rows, by: \.group)
        return byGroup.keys.sorted().compactMap { g in
            let members = byGroup[g]!.map(\.id).sorted()
            guard members.count > 1 else { return nil }
            return VariantPlacement.variantsText(members) + " predict the same spots in this view"
        }
    }
}

/// Why no variant could be placed, in the room's words.
package nonisolated enum VariantRefusal: Error, Sendable, Equatable {
    /// The matrix has no orientation yet.
    case noMatrixOrientation
    /// The pairs do not fix an orientation (a zero vector, parallel vectors on one side).
    case pairsDoNotFixAnOrientation
    /// The kit's other refusals, its sentence.
    case kit(String)

    package var sentence: String {
        switch self {
        case .noMatrixOrientation: "Index the matrix first. Variants are placed from its orientation."
        case .pairsDoNotFixAnOrientation: "These pairs do not fix an orientation."
        case .kit(let s): s
        }
    }
}

package nonisolated enum VariantPlacement {

    /// Spots under this fraction of their variant's strongest are not drawn, counted or compared (the design's display cut).
    package static let displayCut = 0.01

    /// Every variant of `precipitate` in `matrix` under `relationship`, placed from `matrixOrientation`, grouped by what this
    /// view draws, with the hidden ones (0-based indices) left out of the merged spots.
    package static func place(precipitate: String, precipitateStructure: CrystalStructure, matrix: String,
                              matrixStructure: CrystalStructure, relationship: PrecipitateRelationship,
                              matrixOrientation: CrystalOrientation?, volts: Double, kMax: Double = PatternIndexing.reach,
                              hidden: Set<Int> = []) -> Result<VariantSet, VariantRefusal> {
        guard let matrixOrientation else { return .failure(.noMatrixOrientation) }
        guard let pairs = relationship.pairs else { return .failure(.pairsDoNotFixAnOrientation) }
        let variants: [VariantOrientation], misfit: Double
        do throws(VariantOrientationError) {
            var grouping = VariantGroupingSettings()
            grouping.relativeIntensityCut = displayCut
            variants = try OrientationRelationship.variantOrientations(
                first: pairs.first, second: pairs.second, precipitate: precipitateStructure, matrix: matrixStructure,
                matrixOrientation: matrixOrientation, volts: volts, kMax: kMax, grouping: grouping)
            misfit = try OrientationRelationship.secondPairMisfit(first: pairs.first, second: pairs.second,
                                                                 precipitate: precipitateStructure, matrix: matrixStructure)
        } catch {
            if error == .invalidRelationship { return .failure(.pairsDoNotFixAnOrientation) }
            return .failure(.kit(error.description))
        }
        let rows = variants.map { v -> VariantRow in
            let label = relationship.firstPrecipitate.text + " ∥ "
                + (v.firstPairInMatrix.map { RelationshipVector.describe($0) } ?? relationship.firstMatrix.text) + " \(matrix)"
            return VariantRow(id: v.index, group: v.group, label: label, isHidden: hidden.contains(v.index))
        }
        let spots = merge(variants.filter { !hidden.contains($0.index) })
        return .success(VariantSet(precipitate: precipitate, matrix: matrix, variants: variants,
                                   rows: rows, secondPairMisfitDeg: misfit * 180 / Double.pi, spots: spots))
    }

    /// A variant's spots at the display cut.
    package static func drawn(_ pattern: SpotPattern) -> [SimulatedSpot] {
        let strongest = pattern.spots.map(\.intensity).max() ?? 0
        return pattern.spots.filter { $0.intensity >= displayCut * strongest }
    }

    /// The drawn spots of `variants` merged: a spot within `tolerance` (Å⁻¹, the kit's grouping tolerance) of an earlier one
    /// joins it.
    package static func merge(_ variants: [VariantOrientation], tolerance: Double = VariantGroupingSettings().toleranceInvAngstrom)
        -> [VariantSpot] {
        var positions: [SIMD2<Double>] = []
        var intensities: [Double] = []
        var members: [[(variant: Int, hkl: MillerIndex)]] = []
        for v in variants {
            for s in drawn(v.pattern) {
                let near = positions.firstIndex { p in
                    let d = p - s.position
                    return (d.x * d.x + d.y * d.y).squareRoot() <= tolerance
                }
                if let k = near {
                    if !members[k].contains(where: { $0.variant == v.index }) { members[k].append((v.index, s.hkl)) }
                    intensities[k] = max(intensities[k], s.intensity)
                } else {
                    positions.append(s.position); intensities.append(s.intensity); members.append([(v.index, s.hkl)])
                }
            }
        }
        return positions.indices.map { VariantSpot(position: positions[$0], intensity: intensities[$0], members: members[$0]) }
    }

    /// 0-based variant indices as words, numbered from 1: "Variant 3", "Variants 2 and 3", "Variants 1, 4 and 7".
    package static func variantsText(_ indices: [Int]) -> String {
        let n = indices.map { String($0 + 1) }
        switch n.count {
        case 0: return "No variant"
        case 1: return "Variant \(n[0])"
        case 2: return "Variants \(n[0]) and \(n[1])"
        default: return "Variants " + n.dropLast().joined(separator: ", ") + " and " + n.last!
        }
    }
}
