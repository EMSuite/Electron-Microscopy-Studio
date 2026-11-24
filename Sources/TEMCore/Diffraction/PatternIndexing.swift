//
//  PatternIndexing.swift
//  Role: Index on one measured spot pattern (plan rows R2 and R2b, #783, #784): the spots DiffractoKit finds (`PatternSpots.find`) or
//        the room's marks, a clicked one giving the zone axis only (`ZoneAxisSolver.solve`, clicked), their q in the
//        room's scale and centre, and the full orientation of one crystal (`PatternOrientation.index`, the kit's S6), with the
//        verdict in words and the header's line. Every number is the kit's; this file maps pixels to q (the inverse of
//        `ZoneAxisOverlay`'s map: qx down the rows, qy along the columns, |q| the readout's `DiffractionCalibration.q(radius:)`) and
//        reads the kit's answer into the room's verdicts. Pure and nonisolated: the room runs it off the main actor.
//

import Foundation
import ImagoCore
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation

package nonisolated enum PatternIndexing {

    /// The template library's reach (Å⁻¹, the kit's default `kMax`); spots farther out are found and shown but not indexed.
    package static let reach = 1.5

    /// One spot Index reads: its centre in pixels and, for a spot the kit found, its intensity (nil: a clicked spot, #784).
    package struct Mark: Sendable, Equatable {
        /// The spot mark's id (`MeasuredSpot.id`), so a row of the Spots table selects its mark.
        package let id: UUID
        package let row: Double
        package let column: Double
        package let intensity: Double?
        package init(id: UUID, row: Double, column: Double, intensity: Double?) {
            self.id = id; self.row = row; self.column = column; self.intensity = intensity
        }
    }

    /// One spot Index read, in pixels and q, with the hkl the orientation gives it (nil: not explained, or past `reach`).
    package struct Spot: Sendable, Equatable {
        /// The mark's id.
        package let id: UUID
        package let row: Double
        package let column: Double
        package let intensity: Double?
        /// The distance from the centre Index ran about, pixels.
        package let radiusPx: Double
        /// (qx, qy), Å⁻¹.
        package let q: SIMD2<Double>
        package var hkl: MillerIndex?
        /// The listed d of `hkl`, Å.
        package var dListed: Double?
        package var qLength: Double { (q.x * q.x + q.y * q.y).squareRoot() }
        /// d = 1/|q|, Å.
        package var d: Double { 1 / qLength }
        /// (d − d_listed) / d_listed in percent, under the room's scale.
        package var deltaPercent: Double? { dListed.map { 100 * (d - $0) / $0 } }
    }

    /// What Index says about the pattern.
    package enum Verdict: Sendable, Equatable {
        /// One orientation explains the pattern.
        case found
        /// One orientation, but it explains too little of the pattern or its tilt is spread wide.
        case poor
        /// `count` orientations (2 or more) explain the pattern equally.
        case tied(count: Int)
        /// The spots lie on one row through the beam.
        case oneRow
        /// No orientation; the kit's sentence.
        case notFound(String)
        /// The orientation needs the scale at the edge of its window: the calibration (or the lattice) is off.
        case scaleAtLimit

        /// The verdict's word for the header ("found", "found but poor", ...).
        package var word: String {
            switch self {
            case .found: "found"
            case .poor: "found but poor"
            case .tied: "tied"
            case .oneRow: "one row"
            case .notFound: "not found"
            case .scaleAtLimit: "scale at its limit"
            }
        }
    }

    /// Index's answer for one crystal.
    package struct Outcome: Sendable, Equatable {
        package let phase: String
        package let verdict: Verdict
        /// Every spot Index read: the marks, in their order (found ones brightest first).
        package let spots: [Spot]
        /// How many of the spots within `reach` were indexed, and how many there were.
        package let explained: Int
        package let indexed: Int
        /// The best orientation; nil when not found or one row.
        package let orientation: CrystalOrientation?
        /// The other orientations the pattern cannot tell from the best.
        package let alternatives: [CrystalOrientation]
        /// The low-index zone axis nearest the beam (|u|, |v|, |w| ≤ 3) and the angle to it, radians.
        package let zoneAxis: SIMD3<Int>?
        package let zoneAxisAngle: Double?
        /// The measured |q| over the predicted |g| (1: the room's scale is exact for this lattice).
        package let scale: Double?
        /// The rms of the explained spots' Δd/d under the room's scale, percent.
        package let misfitPercent: Double?
        /// The spots carried no intensities (a clicked one among them): the zone axis and the turn only, the tilt unmeasured.
        package let zoneAxisOnly: Bool

        package init(phase: String, verdict: Verdict, spots: [Spot], explained: Int, indexed: Int, orientation: CrystalOrientation?,
                     alternatives: [CrystalOrientation], zoneAxis: SIMD3<Int>?, zoneAxisAngle: Double?, scale: Double?,
                     misfitPercent: Double?, zoneAxisOnly: Bool = false) {
            self.phase = phase; self.verdict = verdict; self.spots = spots; self.explained = explained; self.indexed = indexed
            self.orientation = orientation; self.alternatives = alternatives; self.zoneAxis = zoneAxis
            self.zoneAxisAngle = zoneAxisAngle; self.scale = scale; self.misfitPercent = misfitPercent; self.zoneAxisOnly = zoneAxisOnly
        }
    }

    // MARK: Finding the spots

    /// The kit's spot finder on the pattern about `centre`, at its defaults (py4DSTEM's `find_Bragg_disks` values, a 10 px
    /// spacing) but for the direct beam: maxima nearer the centre than half the crystal's shortest reflection (at least 5 px) are
    /// the beam, not a spot.
    package static func findSpots(pattern: DiffractionPattern, centre: DiffractionCentre, shortestG: Double,
                                  calibration: DiffractionCalibration) throws -> [FoundSpot] {
        var settings = PatternSpots.Settings()
        let beam = ZoneAxisOverlay.radius(q: shortestG / 2, calibration: calibration)
        settings.beamExclusionRadius = max(5, beam.isFinite ? beam : 5)
        return try PatternSpots.find(in: pattern, centre: SIMD2(centre.row, centre.column), settings: settings)
    }

    /// (qx, qy) of a pixel: its direction from the centre, its length the readout's q of its radius. nil at the centre.
    package static func q(row: Double, column: Double, centre: DiffractionCentre, calibration: DiffractionCalibration) -> SIMD2<Double>? {
        let dr = row - centre.row, dc = column - centre.column
        let r = (dr * dr + dc * dc).squareRoot()
        let length = calibration.q(radius: r)
        guard r > 0, length.isFinite, length > 0 else { return nil }
        return SIMD2(dr, dc) * (length / r)
    }

    // MARK: Indexing

    /// The orientation of the marked spots for one crystal (`indexer` built for its structure and the beam energy). Spots that all
    /// carry the kit's intensities (found ones) give the full orientation (`PatternOrientation.index`, the tilt off the zone axis
    /// from the intensities); a clicked spot among them gives the zone axis and the turn only (`ZoneAxisSolver.solve`, clicked: a
    /// subset a person picked, so a predicted spot without a mark does not count against an orientation).
    package static func index(marks: [Mark], centre: DiffractionCentre, calibration: DiffractionCalibration,
                              indexer: PatternOrientation, phase: String) -> Outcome {
        var spots = marks.compactMap { m -> Spot? in
            guard let position = Self.q(row: m.row, column: m.column, centre: centre, calibration: calibration) else { return nil }
            return Spot(id: m.id, row: m.row, column: m.column, intensity: m.intensity,
                        radiusPx: hypot(m.row - centre.row, m.column - centre.column), q: position, hkl: nil, dListed: nil)
        }
        let clicked = spots.contains { $0.intensity == nil }
        let inReach = spots.indices.filter { spots[$0].qLength <= reach }
        let measured = inReach.map { spots[$0].q }
        func refused(_ verdict: Verdict) -> Outcome {
            Outcome(phase: phase, verdict: verdict, spots: spots, explained: 0, indexed: measured.count, orientation: nil, alternatives: [],
                    zoneAxis: nil, zoneAxisAngle: nil, scale: nil, misfitPercent: nil, zoneAxisOnly: clicked)
        }
        func refusal(_ why: ZoneAxisRefusal) -> Verdict { why == .oneRow ? .oneRow : .notFound(why.description) }
        guard measured.count >= 2 else { return refused(.notFound(ZoneAxisRefusal.tooFewSpots(measured.count).description)) }

        // The best orientation, its hkl per spot in reach, its scale, the others the pattern cannot tell from it, and its zone axis.
        let orientation: CrystalOrientation, assignments: [MillerIndex?], scale: Double, agreement: Double, matched: Int
        let alternatives: [CrystalOrientation], tie: Int?, flagged: Bool
        let near: (uvw: SIMD3<Int>, angle: Double)?
        let cell = indexer.solver.structure.cell
        if clicked {
            let solution = indexer.solver.solve(measured, clicked: true)
            guard let best = solution.candidates.first else {
                if case .refused(let why) = solution.verdict { return refused(refusal(why)) }
                return refused(.notFound(ZoneAxisRefusal.noCandidate.description))
            }
            orientation = best.orientation; assignments = best.assignments; scale = best.scale
            agreement = best.agreement; matched = best.matched
            if case .tie(let count) = solution.verdict {
                tie = count
                alternatives = solution.candidates.dropFirst().prefix(count - 1).map { $0.orientation }
            } else {
                tie = nil
                alternatives = []
            }
            if case .refused = solution.verdict { flagged = true } else { flagged = false }
            near = best.zoneAxisAngle.isFinite ? (SIMD3(best.zoneAxis.u, best.zoneAxis.v, best.zoneAxis.w), best.zoneAxisAngle) : nil
        } else {
            let intensities = inReach.map { spots[$0].intensity ?? 0 }
            guard let result = indexer.index(spots: measured, intensities: intensities) else {
                // No start explains two spots: the solver says why (one row, no pair, too little).
                if case .refused(let why) = indexer.solver.solve(measured).verdict { return refused(refusal(why)) }
                return refused(.notFound(ZoneAxisRefusal.noCandidate.description))
            }
            let best = result.best
            orientation = best.orientation; assignments = best.positions.assignments; scale = best.scale
            agreement = best.positions.agreement; matched = best.positions.matched
            alternatives = result.alternatives.map { $0.orientation }
            tie = alternatives.isEmpty ? nil : alternatives.count + 1
            flagged = result.isFlagged()
            near = best.orientation.nearestZoneAxis(cell: cell)
        }

        // each indexed spot's hkl and listed d (1/|g| of the hkl in the cell)
        var squares: [Double] = []
        for (k, i) in inReach.enumerated() where k < assignments.count {
            guard let hkl = assignments[k] else { continue }
            let d = cell.d(hkl)
            guard d.isFinite, d > 0 else { continue }
            spots[i].hkl = hkl
            spots[i].dListed = d
            if let delta: Double = spots[i].deltaPercent { squares.append(delta * delta) }
        }
        let misfit = squares.isEmpty ? nil : (squares.reduce(0, +) / Double(squares.count)).squareRoot()
        let window = indexer.solver.settings.scaleWindow
        let verdict: Verdict
        if let tie {
            verdict = .tied(count: tie)
        } else if window > 0, abs(scale - 1) >= window - 1e-3 {
            verdict = .scaleAtLimit
        } else if flagged || agreement < indexer.solver.settings.minimumAgreement {
            verdict = .poor
        } else {
            verdict = .found
        }
        return Outcome(phase: phase, verdict: verdict, spots: spots, explained: matched, indexed: measured.count,
                       orientation: orientation, alternatives: alternatives, zoneAxis: near.map { $0.uvw },
                       zoneAxisAngle: near.map { $0.angle }, scale: scale, misfitPercent: misfit, zoneAxisOnly: clicked)
    }

    // MARK: The Spots table (#785)

    /// One row of the Spots table: the spot's number in the readout ("Spot 3"), its hkl, R, q, d, the expected d of its hkl, Δd/d
    /// and its phase. The sort keys are never nil (an unexplained spot sorts after every explained one).
    package struct SpotRow: Sendable, Equatable, Identifiable {
        package let id: UUID
        package let number: Int
        package let hkl: MillerIndex?
        package let radiusPx: Double
        package let q: Double
        package let d: Double
        package let dExpected: Double?
        package let deltaPercent: Double?
        /// The phase the hkl is of; "" for a spot the orientation does not explain.
        package let phase: String
        /// A Simulation document's dynamical intensity of the spot's hkl at the shown thickness, percent of the incident beam
        /// (#911); nil with Dynamical off, for an unexplained spot or an hkl that is not a zone-axis beam.
        package private(set) var dynamicalPercent: Double?

        package init(id: UUID, number: Int, hkl: MillerIndex?, radiusPx: Double, q: Double, d: Double, dExpected: Double?,
                     deltaPercent: Double?, phase: String) {
            self.id = id; self.number = number; self.hkl = hkl; self.radiusPx = radiusPx; self.q = q; self.d = d
            self.dExpected = dExpected; self.deltaPercent = deltaPercent; self.phase = phase
        }

        package var hklText: String { hkl.map { ZoneAxisText.label($0) } ?? "" }
        package var dExpectedKey: Double { dExpected ?? .infinity }
        package var deltaKey: Double { deltaPercent ?? .infinity }
        package var dynamicalKey: Double { dynamicalPercent ?? -1 }

        /// This row with the dynamical intensity of its hkl among `beams` (#911); the row as it is without beams.
        package func withDynamical(_ beams: DynamicalBeams?) -> SpotRow {
            var row = self
            row.dynamicalPercent = hkl.flatMap { beams?.intensities[$0] }.map { $0 * 100 }
            return row
        }
    }

    /// The rows of `outcome`'s spots that are still marked, numbered as the readout numbers them (`numbers`: a mark's id to its
    /// number), in the marks' order.
    package static func rows(_ outcome: Outcome, numbers: [UUID: Int]) -> [SpotRow] {
        outcome.spots.compactMap { s in
            guard let number = numbers[s.id] else { return nil }
            return SpotRow(id: s.id, number: number, hkl: s.hkl, radiusPx: s.radiusPx, q: s.qLength, d: s.d, dExpected: s.dListed,
                           deltaPercent: s.deltaPercent, phase: s.hkl == nil ? "" : outcome.phase)
        }.sorted { $0.number < $1.number }
    }

    /// The Spots CSV's columns, the table's in its order.
    package static let csvColumns = "spot,hkl,R_px,q_per_A,d_A,d_expected_A,delta_percent,phase"

    /// The Spots CSV: the file, the crystal and Index's line as `#` lines, then one line per row in the order given.
    package static func csv(rows: [SpotRow], fileName: String, line: String) -> String {
        func g(_ v: Double?) -> String { v.map { String(format: "%.9g", $0) } ?? "" }
        var lines = [
            "# \(AppName.writer) diffraction spots",
            "# file: \(CSVText.headerValue(fileName))",
            "# index: \(CSVText.headerValue(line))",
            csvColumns,
        ]
        for r in rows {
            // The hkl as plain signed integers ("1 -1 1"): a reader parses it without the overbar.
            let hkl = r.hkl.map { "\($0.h) \($0.k) \($0.l)" } ?? ""
            lines.append(["\(r.number)", hkl, g(r.radiusPx), g(r.q), g(r.d), g(r.dExpected), g(r.deltaPercent),
                          CSVText.quoted(r.phase)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Settings and solutions (#787)

    /// Fit scale's window: Index fits the measured |q| over |g| within ±3 % (the kit's default), or holds it at 1 when Fit scale is off.
    package static let scaleWindow = 0.03

    /// The solver's settings for Index: the kit's, with the scale window open (Fit scale on) or shut.
    package static func solverSettings(fitScale: Bool) -> ZoneAxisSolver.Settings {
        ZoneAxisSolver.Settings(scaleWindow: fitScale ? scaleWindow : 0)
    }

    /// The most solutions the Index section steps through.
    package static let solutionLimit = 5

    /// The orientations a person can step through: the best, then the ones the pattern cannot tell from it, at most five.
    package static func solutions(_ o: Outcome) -> [CrystalOrientation] {
        guard let best = o.orientation else { return [] }
        return Array(([best] + o.alternatives).prefix(solutionLimit))
    }

    // MARK: Words

    /// "[001]", "[1̄10]", "[10 0 1]": the zone axis as the header writes it (the hkl label's digits and bars).
    package static func zoneText(_ uvw: SIMD3<Int>) -> String { "[" + ZoneAxisText.label(MillerIndex(uvw.x, uvw.y, uvw.z)) + "]" }

    /// "Al · 2.1° from [001]", or "Al [001]" within 0.5° of the zone axis (`angle` in radians).
    package static func place(phase: String, zoneAxis uvw: SIMD3<Int>, angle: Double) -> String {
        let degrees = angle * 180 / .pi
        return degrees < 0.5 ? "\(phase) \(zoneText(uvw))" : "\(phase) · \(String(format: "%.1f", degrees))° from \(zoneText(uvw))"
    }

    /// What the header adds when clicked spots gave the answer.
    package static let zoneAxisOnlyNote = "zone axis only: clicked spots carry no intensities, so the tilt needs Index on found spots"

    /// The header's line: "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %", "Al [001] · …" within 0.5° of
    /// the zone axis, the verdict's words before it when it is not a plain find.
    package static func header(_ o: Outcome) -> String {
        var place: String?
        if let uvw = o.zoneAxis, let angle = o.zoneAxisAngle { place = Self.place(phase: o.phase, zoneAxis: uvw, angle: angle) }
        var facts: [String] = []
        if o.orientation != nil {
            facts.append("\(o.explained) of \(o.indexed) spots explained")
            if let m = o.misfitPercent { facts.append("misfit \(String(format: "%.2f", m)) %") }
        }
        if o.zoneAxisOnly, o.orientation != nil { facts.append(zoneAxisOnlyNote) }
        let tail = facts.isEmpty ? "" : " · " + facts.joined(separator: " · ")
        switch o.verdict {
        case .found:
            return (place ?? o.phase) + tail
        case .poor:
            return "\(place ?? o.phase) · found but poor" + tail
        case .tied(let n):
            return "\(place ?? o.phase) · tied: \(n) orientations explain the pattern equally" + tail
        case .scaleAtLimit:
            let percent = o.scale.map { String(format: "%+.1f", 100 * ($0 - 1)) } ?? "?"
            return "\(place ?? o.phase) · scale at its limit (\(percent) %): check the calibration" + tail
        case .oneRow:
            return "\(o.phase) · one row: the spots lie on one row through the beam, which fixes no zone axis"
        case .notFound(let why):
            return "\(o.phase) · not found: \(why)"
        }
    }
}

/// The indexers built so far (`PatternOrientation`: its template library is the costly part, about a second), by crystal and
/// beam energy, so a second Index on any open pattern of the same crystal starts at once. The four used last are kept.
package nonisolated final class PatternIndexerCache: @unchecked Sendable {
    package static let shared = PatternIndexerCache()
    private let lock = NSLock()
    private var entries: [(key: String, indexer: PatternOrientation)] = []
    private let capacity = 4

    package init() {}

    /// The indexer under `key`, built by `build` (outside the lock) when there is none.
    package func indexer(key: String, build: () throws -> PatternOrientation) throws -> PatternOrientation {
        lock.lock()
        if let i = entries.firstIndex(where: { $0.key == key }) {
            let hit = entries.remove(at: i)
            entries.append(hit)
            lock.unlock()
            return hit.indexer
        }
        lock.unlock()
        let built = try build()
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.key == key }
        entries.append((key, built))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        return built
    }
}
