//
//  DiscSpots.swift
//  Role: Index's spot finder for a pattern of discs (#1153): a nanobeam (NBED) or convergent-beam pattern, where every reflection is a
//        disc as wide as the direct beam. The SAED finder (`PatternSpots.find`, py4DSTEM's get_maxima_2D on the pattern smoothed by
//        σ 2 px) is made for sharp spots: on a disc 20 px across it takes the Poisson ripples of the disc's flat top and the weak
//        features between the discs, and misses the disc centres (pyxem's α-Zr ZrNbPercipitate cut: 41 found, mostly between the
//        discs). Disc patterns are found as py4DSTEM's `find_Bragg_disks` finds them: the pattern cross-correlated with a probe
//        template (here the synthetic one of the direct beam's own radius, `get_probe_synthetic`, with a zero-sum ring as
//        `get_probe_kernel_edge_sigmoid` makes it), then get_maxima_2D on the correlation at py4DSTEM's values (σ_cc 2, 0.005 of the
//        brightest, edge 20, 70 peaks), the spacing at least 1.5 disc radii. pyxem's `template_match_disk` + `find_peaks` is the same
//        route. A pattern whose direct beam is under `discRadiusThreshold`, or whose brightest spots are sharp (a saturated SAED
//        beam, `reflectionsAreDiscs`), keeps the SAED finder, unchanged.
//

import Foundation
import DiffractoGeometry

package nonisolated enum DiscSpots {
    /// A direct beam at least this wide (radius, px) makes the pattern one of discs. A selected-area pattern's beam (and its
    /// saturation) is a few pixels; an NBED disc at the usual 0.5 to 2 mrad is ten or more.
    package static let discRadiusThreshold = 6.0
    /// The farthest the direct beam's profile is read, px.
    package static let profileReach = 96

    /// The direct beam's radius about `centre`, px: where its ring-mean profile falls to half way between its centre and the lowest
    /// ring within `profileReach` (py4DSTEM's `get_probe_size` reads the same disc as the area above a threshold). nil when the
    /// profile does not fall (no beam, a flat pattern).
    package static func beamRadius(pattern: DiffractionPattern, centre: SIMD2<Double>, reach wanted: Int = profileReach) -> Double? {
        let rows = pattern.height, columns = pattern.width
        let reach = min(max(4, wanted), max(rows, columns))
        var sum = [Double](repeating: 0, count: reach), count = [Int](repeating: 0, count: reach)
        let r0 = max(0, Int(centre.x) - reach), r1 = min(rows - 1, Int(centre.x) + reach)
        let c0 = max(0, Int(centre.y) - reach), c1 = min(columns - 1, Int(centre.y) + reach)
        guard r0 <= r1, c0 <= c1 else { return nil }
        for r in r0...r1 {
            for c in c0...c1 {
                let k = Int(hypot(Double(r) - centre.x, Double(c) - centre.y))
                guard k < reach else { continue }
                sum[k] += Double(pattern.pixels[r * columns + c]); count[k] += 1
            }
        }
        let profile = (0..<reach).compactMap { count[$0] > 0 ? sum[$0] / Double(count[$0]) : nil }
        guard profile.count >= 4 else { return nil }
        let top = (profile[0] + profile[1]) / 2
        guard let floor = profile.min(), top > floor, top.isFinite else { return nil }
        let half = floor + (top - floor) / 2
        for k in 1..<profile.count where profile[k] < half {
            let step = profile[k - 1] - profile[k]
            let into = step > 0 ? (profile[k - 1] - half) / step : 0
            return Double(k - 1) + into + 0.5
        }
        return nil
    }

    /// Whether the reflections are discs too, not only the direct beam: a selected-area pattern whose beam is saturated or bloomed
    /// has a wide beam and sharp spots. The brightest spots the SAED finder took (up to five) are read as the beam is, within twice
    /// the beam's radius; the pattern is one of discs when their median radius is at least half the beam's and at least 4 px (a
    /// sharp SAED spot reads about 2 px, an NBED disc its own radius).
    package static func reflectionsAreDiscs(pattern: DiffractionPattern, brightest: [FoundSpot], beamRadius: Double) -> Bool {
        let reach = Int((2 * beamRadius).rounded(.up))
        let radii = brightest.prefix(5).compactMap { spot -> Double? in
            guard spot.row.isFinite, spot.column.isFinite else { return nil }
            return Self.beamRadius(pattern: pattern, centre: SIMD2(spot.row, spot.column), reach: reach)
        }.sorted()
        guard !radii.isEmpty else { return false }
        let median = radii.count % 2 == 1 ? radii[radii.count / 2] : (radii[radii.count / 2 - 1] + radii[radii.count / 2]) / 2
        return median >= max(4, beamRadius / 2)
    }

    /// The pattern cross-correlated with a disc of `radius` px less the mean of the ring just outside it (width `radius` / 2, at
    /// least 2 px): each pixel's background-free disc sum. Pixels off the image are left out of both, so an edge disc is not biased.
    package static func correlation(pattern: DiffractionPattern, radius: Double) -> [Double] {
        let rows = pattern.height, columns = pattern.width
        // Row prefix sums: span sums in O(1).
        var prefix = [Double](repeating: 0, count: rows * (columns + 1))
        for r in 0..<rows {
            var s = 0.0
            for c in 0..<columns {
                s += Double(pattern.pixels[r * columns + c])
                prefix[r * (columns + 1) + c + 1] = s
            }
        }
        let outer = radius + max(2, radius / 2)
        func halfWidths(_ R: Double) -> [Int] {
            let n = Int(R)
            return (-n...n).map { dy in Int((R * R - Double(dy * dy)).squareRoot()) }
        }
        let inner = halfWidths(radius), wide = halfWidths(outer)
        let ni = Int(radius), nw = Int(outer)
        var out = [Double](repeating: 0, count: rows * columns)
        func disc(_ r: Int, _ c: Int, _ widths: [Int], _ n: Int) -> (sum: Double, area: Int) {
            var sum = 0.0, area = 0
            for (i, hw) in widths.enumerated() {
                let rr = r + i - n
                guard rr >= 0, rr < rows else { continue }
                let lo = max(0, c - hw), hi = min(columns - 1, c + hw)
                guard lo <= hi else { continue }
                sum += prefix[rr * (columns + 1) + hi + 1] - prefix[rr * (columns + 1) + lo]
                area += hi - lo + 1
            }
            return (sum, area)
        }
        for r in 0..<rows {
            for c in 0..<columns {
                let a = disc(r, c, inner, ni), b = disc(r, c, wide, nw)
                let ringArea = b.area - a.area
                let ringMean = ringArea > 0 ? (b.sum - a.sum) / Double(ringArea) : 0
                out[r * columns + c] = a.sum - Double(a.area) * ringMean
            }
        }
        return out
    }

    /// The discs of a pattern whose direct beam has `radius` px: the maxima of `correlation` at py4DSTEM's get_maxima_2D values,
    /// the spacing at least 1.5 radii, the edge at least a radius, those nearer the centre than `beamExclusionRadius` (and than a
    /// radius) dropped. Brightest first; the intensity is the disc's background-free sum, smoothed as the maxima are.
    package static func find(pattern: DiffractionPattern, centre: SIMD2<Double>, radius: Double,
                             beamExclusionRadius: Double) throws -> [FoundSpot] {
        let correlated = correlation(pattern: pattern, radius: radius)
        let map = DiffractionPattern(width: pattern.width, height: pattern.height, pixels: correlated.map { Float($0) })
        var settings = PatternSpots.Settings()
        settings.minimumSpacing = max(settings.minimumSpacing, 1.5 * radius)
        settings.edgeBoundary = max(settings.edgeBoundary, Int(radius.rounded(.up)))
        let exclusion = max(beamExclusionRadius, radius)
        return try PatternSpots.maxima(in: map, settings: settings).filter {
            hypot($0.row - centre.x, $0.column - centre.y) >= exclusion
        }
    }
}
