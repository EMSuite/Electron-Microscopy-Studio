//
//  PhaseFinding.swift
//  Role: Find Phases as the Diffraction room's sheet and the agent door read it (plan rows R13 and R14, #812, #813): the
//        candidate phases ranked against the room's measured rings or marked spots by the kit (`PhaseFinder.rank`, S11), as
//        rows with the counts the kit returns (explains, strong rings not seen, misfit, scale, ties) and the sentences the sheet
//        says. The finder shows no number of its own: every number per candidate is the ring indexing's or the zone-axis solver's
//        for that phase, and the order and the ties are the kit's rule. It says "explains", never "is".
//        Pure and nonisolated: the sheet and the door call the same `PhaseFinding.rank`, off the main actor.
//
//        The design (EMSuite docs/design/diffraction-indexing.md, B6): Index's tolerance and scale window (3 %) by default; Fit
//        scale off holds the room's calibration (scale window 0), which is how a user with a trusted calibration tells two
//        phases with nearly equal lattices apart.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation

/// Where a candidate phase came from.
package nonisolated enum PhaseSource: String, Sendable, Codable, CaseIterable, Equatable {
    case myPhases
    case materialsProject

    /// "My Phases", "Materials Project".
    package var name: String {
        switch self {
        case .myPhases: "My Phases"
        case .materialsProject: "Materials Project"
        }
    }
}

/// One phase Find Phases ranks.
package nonisolated struct PhaseCandidate: Sendable, Equatable {
    package let name: String
    package let structure: CrystalStructure
    package let source: PhaseSource
    /// The formula as its source states it ("Mg2Si"); nil: the cell content.
    package let formula: String?
    /// The space group as its source states it ("Fm-3m"); nil: the one the atoms show, when the kit names one.
    package let spaceGroup: String?

    package init(name: String, structure: CrystalStructure, source: PhaseSource, formula: String? = nil, spaceGroup: String? = nil) {
        self.name = name; self.structure = structure; self.source = source; self.formula = formula; self.spaceGroup = spaceGroup
    }
}

/// What Find Phases ranks the candidates against.
package nonisolated enum PhaseFindingPattern: Sendable, Equatable {
    /// Measured ring positions, Å⁻¹ (no 2π).
    case rings([Double])
    /// Marked spots in the pattern plane, (qx, qy) Å⁻¹ from the centre, and the beam energy in volts.
    case spots([SIMD2<Double>], volts: Double)

    package var count: Int {
        switch self {
        case .rings(let q): q.count
        case .spots(let s, _): s.count
        }
    }

    /// "rings" or "spots".
    package var noun: String {
        switch self {
        case .rings: "rings"
        case .spots: "spots"
        }
    }
}

/// One row of the candidate table.
package nonisolated struct PhaseFindingRow: Sendable, Equatable, Identifiable {
    /// The candidate's position in the input.
    package let id: Int
    package let name: String
    package let formula: String
    package let spaceGroup: String
    package let source: PhaseSource
    /// Measured rings or spots the candidate explains, of `measured`.
    package let explained: Int
    package let measured: Int
    /// Rings: the candidate's strong rings inside the measured range that were not seen, of `strongExpected`. nil for spots.
    package let strongMissing: Int?
    package let strongExpected: Int?
    /// Rings: the rms of (q − s g) / q over the explained rings, percent.
    package let misfitPercent: Double?
    /// Spots: the solver's rms distance of the explained spots, Å⁻¹.
    package let rmsDistance: Double?
    /// Measured |q| over the candidate's |g|.
    package let scale: Double
    /// Spots: the zone axis of the solver's best orientation.
    package let zoneAxis: ZoneAxis?
    /// Rows with the same tie number are one tie; numbered from 0 in rank order.
    package let tie: Int
    /// The kit could not score this candidate, and why.
    package let refusal: String?
}

/// Find Phases' answer: the ranked rows and the sentences.
package nonisolated struct PhaseFindingResult: Sendable, Equatable {
    package let pattern: PhaseFindingPattern
    package let fitScale: Bool
    /// In the kit's rank order; a tie's rows together.
    package let rows: [PhaseFindingRow]

    /// The rows of one tie, in rank order.
    package func tie(_ number: Int) -> [PhaseFindingRow] { rows.filter { $0.tie == number } }

    /// The row's tie holds two or more rows.
    package func isTied(_ row: PhaseFindingRow) -> Bool { tie(row.tie).count > 1 }

    /// "14 phases from Materials Project, 3 from My Phases" (the larger source first).
    package var sourceSentence: String {
        let counts = PhaseSource.allCases.map { s in (s, rows.filter { $0.source == s }.count) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let first = counts.first else { return "No phases to rank." }
        var parts = ["\(first.1) \(first.1 == 1 ? "phase" : "phases") from \(first.0.name)"]
        parts += counts.dropFirst().map { "\($0.1) from \($0.0.name)" }
        return parts.joined(separator: ", ")
    }

    /// The selected row's sentence: "Mg2Si explains 8 of 9 rings; 1 of its strong rings was not seen; misfit 0.4 %", or for spots
    /// "Al explains 12 of 14 spots at [0 1 1]; rms distance 0.004 Å⁻¹". A refused candidate gives the kit's reason.
    package func sentence(for row: PhaseFindingRow) -> String {
        if let refusal = row.refusal { return "\(row.name) could not be ranked: \(refusal)" }
        var text = "\(row.name) explains \(row.explained) of \(row.measured) \(pattern.noun)"
        if let missing = row.strongMissing, let expected = row.strongExpected {
            if expected == 0 {
                text += "; none of its strong rings falls in the measured range"
            } else if missing == 0 {
                text += "; all \(expected) of its strong rings were seen"
            } else {
                text += "; \(missing) of its strong rings \(missing == 1 ? "was" : "were") not seen"
            }
        }
        if let axis = row.zoneAxis, row.explained > 0 { text += " at [\(axis.u) \(axis.v) \(axis.w)]" }
        if let misfit = row.misfitPercent, row.explained > 0 { text += String(format: "; misfit %.1f %%", misfit) }
        if let rms = row.rmsDistance, row.explained > 0 { text += String(format: "; rms distance %.3f Å⁻¹", rms) }
        if fitScale, row.explained > 0, abs(row.scale - 1) >= 0.0005 { text += String(format: "; scale %+.1f %%", 100 * (row.scale - 1)) }
        return text
    }

    /// For a tie of two or more: "Al and Au fit equally well. This pattern cannot tell them apart: their scales differ by
    /// 0.7 %, inside the scale window." With the scale fixed, or scales that agree, only the first two sentences. nil for one row.
    package func tieSentence(_ number: Int) -> String? {
        let members = tie(number)
        guard members.count > 1, members.allSatisfy({ $0.refusal == nil }) else { return nil }
        let names = members.map(\.name)
        let list = names.count == 2 ? "\(names[0]) and \(names[1])"
            : names.dropLast().joined(separator: ", ") + " and " + names.last!
        var text = "\(list) fit equally well. This pattern cannot tell them apart"
        let scales = members.map(\.scale)
        if fitScale, let lo = scales.min(), let hi = scales.max(), lo > 0, hi / lo - 1 >= 0.0005 {
            text += String(format: ": their scales differ by %.1f %%, inside the scale window.", 100 * (hi / lo - 1))
        } else {
            text += "."
        }
        return text
    }

    /// When even the best candidate explains under half: "No candidate explains more than 3 of 9 rings". nil otherwise.
    package var weakSentence: String? {
        let best = rows.filter { $0.refusal == nil }.map(\.explained).max() ?? 0
        guard pattern.count > 0, 2 * best < pattern.count else { return nil }
        return "No candidate explains more than \(best) of \(pattern.count) \(pattern.noun)."
    }

    /// Said whenever Materials Project phases are among the candidates.
    package var materialsProjectNote: String? {
        guard rows.contains(where: { $0.source == .materialsProject }) else { return nil }
        return "Materials Project holds calculated, mostly stable phases. A metastable precipitate is usually not in it: add its CIF to My Phases."
    }
}

package nonisolated enum PhaseFinding {

    /// The kit's ring settings at Index's tolerance; Fit scale off holds the calibration (window 0).
    package static func ringSettings(fitScale: Bool) -> PhaseFinder.RingSettings {
        var s = PhaseFinder.RingSettings()
        if !fitScale { s.scaleWindow = 0 }
        return s
    }

    /// The solver's settings; Fit scale off holds the calibration (window 0).
    package static func solverSettings(fitScale: Bool) -> ZoneAxisSolver.Settings {
        var s = ZoneAxisSolver.Settings()
        if !fitScale { s.scaleWindow = 0 }
        return s
    }

    /// Ranks `candidates` against `pattern` with the kit's rule. Throws the kit's error for a pattern it cannot rank (no ring, one
    /// spot).
    package static func rank(_ pattern: PhaseFindingPattern, candidates: [PhaseCandidate], fitScale: Bool = true,
                             reach: Double = PatternIndexing.reach) throws(PhaseFinderError) -> PhaseFindingResult {
        let structures = candidates.map(\.structure)
        var rows: [PhaseFindingRow] = []
        switch pattern {
        case .rings(let q):
            let scores = try PhaseFinder.rank(rings: q, candidates: structures, settings: ringSettings(fitScale: fitScale))
            rows = scores.map { s in
                row(candidates[s.candidate], id: s.candidate, explained: s.explained, measured: s.measured,
                    strongMissing: s.strongMissing, strongExpected: s.strongExpected, misfitPercent: 100 * s.misfit, rmsDistance: nil,
                    scale: s.scale, zoneAxis: nil, tie: s.tie, refusal: s.refusal)
            }
        case .spots(let spots, let volts):
            let scores = try PhaseFinder.rank(spots: spots, candidates: structures, volts: volts, kMax: reach,
                                              solverSettings: solverSettings(fitScale: fitScale))
            rows = scores.map { s in
                row(candidates[s.candidate], id: s.candidate, explained: s.explained, measured: s.measured, strongMissing: nil,
                    strongExpected: nil, misfitPercent: nil, rmsDistance: s.best == nil ? nil : s.rmsDistance, scale: s.scale,
                    zoneAxis: s.best?.zoneAxis, tie: s.tie, refusal: s.refusal)
            }
        }
        return PhaseFindingResult(pattern: pattern, fitScale: fitScale, rows: rows)
    }

    private static func row(_ c: PhaseCandidate, id: Int, explained: Int, measured: Int, strongMissing: Int?, strongExpected: Int?,
                            misfitPercent: Double?, rmsDistance: Double?, scale: Double, zoneAxis: ZoneAxis?,
                            tie: Int, refusal: String?) -> PhaseFindingRow {
        PhaseFindingRow(id: id, name: c.name, formula: c.formula ?? c.structure.formula,
                        spaceGroup: c.spaceGroup ?? c.structure.spaceGroupType?.internationalSymbol ?? "", source: c.source,
                        explained: explained, measured: measured, strongMissing: strongMissing, strongExpected: strongExpected,
                        misfitPercent: misfitPercent, rmsDistance: rmsDistance, scale: scale, zoneAxis: zoneAxis,
                        tie: tie, refusal: refusal)
    }
}
