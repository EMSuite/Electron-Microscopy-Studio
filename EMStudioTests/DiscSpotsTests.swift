//
//  DiscSpotsTests.swift
//  Index's spot finder on a pattern of discs (#1153, pyxem's α-Zr ZrNbPercipitate cut in the 2.6.0 walk): a nanobeam pattern of
//  flat-topped discs 20 px across with counting noise and weak sharp features between them. The SAED finder (py4DSTEM's
//  get_maxima_2D at σ 2 px) takes the ripples of the disc tops and the features between and misses the disc centres (in a NumPy model
//  of this pattern, 54 of its 58 spots sit more than 2 px from a disc centre and 4 of 24 discs are found); the disc finder
//  (py4DSTEM's template route) finds every disc at its centre and nothing else. A selected-area pattern keeps the SAED finder.
//  Red before: `PatternIndexing.findSpots` had the SAED finder alone.
//

import XCTest
import DiffractoGeometry
import TEMCore

nonisolated final class DiscSpotsTests: XCTestCase {

    private static let side = 256, centre = SIMD2(128.3, 127.6), radius = 10.0

    /// Counting noise from a fixed seed: the normal approximation of Poisson (λ + √λ·z), z by Box–Muller from a 64-bit LCG.
    private struct Noise {
        var state: UInt64
        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }
        mutating func counts(_ lambda: Double) -> Double {
            let z = (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
            return max(0, (lambda + lambda.squareRoot() * z).rounded())
        }
    }

    /// The discs' centres and the pattern: the direct beam (1000 counts) and a lattice of discs 40 px apart (20 to 220 counts),
    /// soft-edged (0.8 px), on 3 counts of background, with 25 sharp features of 30 counts between them.
    private func discPattern() -> (pattern: DiffractionPattern, discs: [SIMD2<Double>]) {
        let n = Self.side
        var values = [Double](repeating: 3, count: n * n)
        func disc(_ at: SIMD2<Double>, _ amplitude: Double, _ r: Double) {
            for row in 0..<n { for column in 0..<n {
                let d = hypot(Double(row) - at.x, Double(column) - at.y)
                values[row * n + column] += amplitude / (1 + exp((d - r) / 0.8))
            } }
        }
        disc(Self.centre, 1000, Self.radius)
        var discs: [SIMD2<Double>] = []
        for i in -3...3 { for j in -3...3 where !(i == 0 && j == 0) {
            let at = Self.centre + SIMD2(Double(i * 40 + j * 6), Double(j * 40 - i * 6))
            guard at.x > 22, at.x < Double(n) - 22, at.y > 22, at.y < Double(n) - 22 else { continue }
            disc(at, 200 * exp(-Double(i * i + j * j) / 8) + 20, Self.radius)
            discs.append(at)
        } }
        var noise = Noise(state: 1153)
        for _ in 0..<25 {
            let at = SIMD2(25 + noise.uniform() * Double(n - 50), 25 + noise.uniform() * Double(n - 50))
            for row in 0..<n { for column in 0..<n {
                let d2 = pow(Double(row) - at.x, 2) + pow(Double(column) - at.y, 2)
                values[row * n + column] += 30 * exp(-d2 / 2)
            } }
        }
        let pixels = values.map { Float(noise.counts($0)) }
        return (DiffractionPattern(width: n, height: n, pixels: pixels), discs)
    }

    private func nearest(_ spot: FoundSpot, _ discs: [SIMD2<Double>]) -> (index: Int, distance: Double) {
        discs.indices.map { ($0, hypot(spot.row - discs[$0].x, spot.column - discs[$0].y)) }.min { $0.1 < $1.1 }!
    }

    /// The beam's radius is read from its profile, and Index's finder then finds each disc once, at its centre, and nothing between.
    /// Mutation: the SAED finder kept for discs; the correlation without its zero-sum ring; the spacing left at 10 px.
    func testIndexFindsEachDiscAtItsCentre() throws {
        let (pattern, discs) = discPattern()
        let radius = try XCTUnwrap(DiscSpots.beamRadius(pattern: pattern, centre: Self.centre))
        XCTAssertEqual(radius, Self.radius, accuracy: 1, "the direct beam's half-height radius")

        let calibration = DiffractionCalibration(source: .typed, deltaQ: 0.005, ring: nil)
        let found = try PatternIndexing.findSpots(pattern: pattern, centre: DiffractionCentre(row: Self.centre.x, column: Self.centre.y, source: .typed),
                                                  shortestG: 0.2, calibration: calibration)
        for spot in found {
            XCTAssertLessThanOrEqual(nearest(spot, discs).distance, 1.5, "a spot off every disc: \(spot.row), \(spot.column)")
        }
        let hit = Set(found.map { nearest($0, discs).index })
        XCTAssertEqual(hit.count, found.count, "one spot per disc")
        XCTAssertEqual(hit.count, discs.count, "every disc found")

        // The SAED finder on the same pattern: most of its spots are not at a disc centre (the walk's α-Zr answer).
        var saed = PatternSpots.Settings()
        saed.beamExclusionRadius = 5
        let old = try PatternSpots.find(in: pattern, centre: Self.centre, settings: saed)
        let off = old.filter { nearest($0, discs).distance > 2 }.count
        XCTAssertGreaterThan(4 * off, old.count, "the SAED finder takes the disc tops' ripples: \(off) of \(old.count) off centre")
    }

    /// A selected-area pattern whose direct beam is saturated (clipped at 1000, about 12 px across at half height) but whose spots are
    /// sharp keeps the SAED finder: the spots, not the beam, say whether the pattern is one of discs. Mutation: the beam's radius
    /// alone deciding.
    func testASaturatedSelectedAreaBeamKeepsTheSAEDFinder() throws {
        let n = 256, c = SIMD2(128.0, 128.0)
        var values = [Double](repeating: 3, count: n * n)
        for row in 0..<n { for column in 0..<n {
            let d2 = pow(Double(row) - c.x, 2) + pow(Double(column) - c.y, 2)
            values[row * n + column] = min(1000, values[row * n + column] + 4000 * exp(-d2 / 72))
        } }
        for i in -3...3 { for j in -3...3 where !(i == 0 && j == 0) {
            let at = c + SIMD2(Double(i * 30), Double(j * 30))
            guard at.x > 22, at.x < 234, at.y > 22, at.y < 234 else { continue }
            for row in 0..<n { for column in 0..<n {
                let d2 = pow(Double(row) - at.x, 2) + pow(Double(column) - at.y, 2)
                values[row * n + column] += 300 * exp(-d2 / 2.88)
            } }
        } }
        let pattern = DiffractionPattern(width: n, height: n, pixels: values.map { Float($0) })
        let beam = try XCTUnwrap(DiscSpots.beamRadius(pattern: pattern, centre: c))
        XCTAssertGreaterThanOrEqual(beam, DiscSpots.discRadiusThreshold, "the saturated beam is wide")
        let calibration = DiffractionCalibration(source: .typed, deltaQ: 0.01, ring: nil)
        let found = try PatternIndexing.findSpots(pattern: pattern, centre: DiffractionCentre(row: c.x, column: c.y, source: .typed),
                                                  shortestG: 0.2, calibration: calibration)
        var settings = PatternSpots.Settings()
        settings.beamExclusionRadius = max(5, ZoneAxisOverlay.radius(q: 0.1, calibration: calibration))
        XCTAssertEqual(found, try PatternSpots.find(in: pattern, centre: c, settings: settings), "the SAED finder's spots")
    }

    /// A selected-area pattern (a direct beam of a few pixels, the nanowire demo's is 2.3 px) keeps the SAED finder, unchanged.
    /// Mutation: the threshold below a sharp beam's radius.
    func testASelectedAreaPatternKeepsTheSAEDFinder() throws {
        let n = 128, c = SIMD2(64.0, 64.0)
        var pixels = [Float](repeating: 2, count: n * n)
        func spot(_ at: SIMD2<Double>, _ amplitude: Double) {
            for row in 0..<n { for column in 0..<n {
                let d2 = pow(Double(row) - at.x, 2) + pow(Double(column) - at.y, 2)
                pixels[row * n + column] += Float(amplitude * exp(-d2 / 2))
            } }
        }
        spot(c, 255)
        for (i, j) in [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1)] { spot(c + SIMD2(Double(i * 22), Double(j * 22)), 80) }
        let pattern = DiffractionPattern(width: n, height: n, pixels: pixels)
        let radius = try XCTUnwrap(DiscSpots.beamRadius(pattern: pattern, centre: c))
        XCTAssertLessThan(radius, DiscSpots.discRadiusThreshold)
        let found = try PatternIndexing.findSpots(pattern: pattern, centre: DiffractionCentre(row: c.x, column: c.y, source: .typed), shortestG: 0.2,
                                                  calibration: DiffractionCalibration(source: .typed, deltaQ: 0.01, ring: nil))
        var settings = PatternSpots.Settings()
        settings.beamExclusionRadius = max(5, ZoneAxisOverlay.radius(q: 0.1, calibration: DiffractionCalibration(source: .typed, deltaQ: 0.01, ring: nil)))
        XCTAssertEqual(found, try PatternSpots.find(in: pattern, centre: c, settings: settings))
    }
}
