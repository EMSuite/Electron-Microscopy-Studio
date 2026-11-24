//
//  PatternIndexing.swift
//  Role: Index on one measured spot pattern (plan row R2, #783): the spots DiffractoKit finds (`PatternSpots.find`), their q in the
//        room's scale and centre, and the full orientation of one crystal (`PatternOrientation.index`, the kit's S6), with the
//        verdict in words and the header's line. Every number is the kit's; this file maps pixels to q (the inverse of
//        `ZoneAxisOverlay`'s map: qx down the rows, qy along the columns, |q| the readout's `DiffractionCalibration.q(radius:)`) and
//        reads the kit's answer into the room's verdicts. Pure and nonisolated: the room runs it off the main actor.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation

package nonisolated enum PatternIndexing {

    /// The template library's reach (Å⁻¹, the kit's default `kMax`); spots farther out are found and shown but not indexed.
    package static let reach = 1.5

    /// One spot the kit found, in pixels and q, with the hkl the orientation gives it (nil: not explained, or past `reach`).
    package struct Spot: Sendable, Equatable {
        package let row: Double
        package let column: Double
        package let intensity: Double
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
        /// Every spot found, brightest first.
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

        package init(phase: String, verdict: Verdict, spots: [Spot], explained: Int, indexed: Int, orientation: CrystalOrientation?,
                     alternatives: [CrystalOrientation], zoneAxis: SIMD3<Int>?, zoneAxisAngle: Double?, scale: Double?,
                     misfitPercent: Double?) {
            self.phase = phase; self.verdict = verdict; self.spots = spots; self.explained = explained; self.indexed = indexed
            self.orientation = orientation; self.alternatives = alternatives; self.zoneAxis = zoneAxis
            self.zoneAxisAngle = zoneAxisAngle; self.scale = scale; self.misfitPercent = misfitPercent
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

    /// The full orientation of the found spots for one crystal (`indexer` built for its structure and the beam energy).
    package static func index(found: [FoundSpot], centre: DiffractionCentre, calibration: DiffractionCalibration,
                              indexer: PatternOrientation, phase: String) -> Outcome {
        var spots = found.compactMap { f -> Spot? in
            guard let position = Self.q(row: f.row, column: f.column, centre: centre, calibration: calibration) else { return nil }
            return Spot(row: f.row, column: f.column, intensity: f.intensity, q: position, hkl: nil, dListed: nil)
        }
        let inReach = spots.indices.filter { spots[$0].qLength <= reach }
        let measured = inReach.map { spots[$0].q }, intensities = inReach.map { spots[$0].intensity }
        func refused(_ verdict: Verdict) -> Outcome {
            Outcome(phase: phase, verdict: verdict, spots: spots, explained: 0, indexed: measured.count, orientation: nil, alternatives: [],
                    zoneAxis: nil, zoneAxisAngle: nil, scale: nil, misfitPercent: nil)
        }
        guard measured.count >= 2 else { return refused(.notFound(ZoneAxisRefusal.tooFewSpots(measured.count).description)) }
        guard let result = indexer.index(spots: measured, intensities: intensities) else {
            // No start explains two spots: the solver says why (one row, no pair, too little).
            if case .refused(let why) = indexer.solver.solve(measured).verdict {
                return refused(why == .oneRow ? .oneRow : .notFound(why.description))
            }
            return refused(.notFound(ZoneAxisRefusal.noCandidate.description))
        }
        let best = result.best
        let cell = indexer.solver.structure.cell
        // each indexed spot's hkl and listed d (1/|g| of the hkl in the cell)
        var squares: [Double] = []
        for (k, i) in inReach.enumerated() where k < best.positions.assignments.count {
            guard let hkl = best.positions.assignments[k] else { continue }
            let d = cell.d(hkl)
            guard d.isFinite, d > 0 else { continue }
            spots[i].hkl = hkl
            spots[i].dListed = d
            if let delta: Double = spots[i].deltaPercent { squares.append(delta * delta) }
        }
        let misfit = squares.isEmpty ? nil : (squares.reduce(0, +) / Double(squares.count)).squareRoot()
        let near = best.orientation.nearestZoneAxis(cell: cell)
        let window = indexer.solver.settings.scaleWindow
        let verdict: Verdict
        if !result.alternatives.isEmpty {
            verdict = .tied(count: result.alternatives.count + 1)
        } else if abs(best.scale - 1) >= window - 1e-3 {
            verdict = .scaleAtLimit
        } else if result.isFlagged() || best.positions.agreement < indexer.solver.settings.minimumAgreement {
            verdict = .poor
        } else {
            verdict = .found
        }
        return Outcome(phase: phase, verdict: verdict, spots: spots, explained: best.positions.matched, indexed: measured.count,
                       orientation: best.orientation, alternatives: result.alternatives.map { $0.orientation },
                       zoneAxis: near.map { $0.uvw }, zoneAxisAngle: near.map { $0.angle }, scale: best.scale, misfitPercent: misfit)
    }

    // MARK: Words

    /// "[001]", "[1̄10]", "[10 0 1]": the zone axis as the header writes it (the hkl label's digits and bars).
    package static func zoneText(_ uvw: SIMD3<Int>) -> String { "[" + ZoneAxisText.label(MillerIndex(uvw.x, uvw.y, uvw.z)) + "]" }

    /// The header's line: "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %", "Al [001] · …" within 0.5° of
    /// the zone axis, the verdict's words before it when it is not a plain find.
    package static func header(_ o: Outcome) -> String {
        var place: String?
        if let uvw = o.zoneAxis, let angle = o.zoneAxisAngle {
            let degrees = angle * 180 / .pi
            place = degrees < 0.5 ? "\(o.phase) \(zoneText(uvw))" : "\(o.phase) · \(String(format: "%.1f", degrees))° from \(zoneText(uvw))"
        }
        var facts: [String] = []
        if o.orientation != nil {
            facts.append("\(o.explained) of \(o.indexed) spots explained")
            if let m = o.misfitPercent { facts.append("misfit \(String(format: "%.2f", m)) %") }
        }
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
