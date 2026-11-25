//
//  CBEDThicknessTests.swift
//  The Diffraction room's Measure Thickness (#916, plan row MA15): the discs found on a two-beam CBED pattern, the profile across the
//  diffracted disc, and DiffractoKit's two-beam fit of it. The fit is the kit's (pinned in DiffractoKit's TwoBeamThicknessTests);
//  this file pins the app's reading of the pattern: the disc on the right ring and turn, the profile along g, the sentences. Red
//  before: there was no thickness measurement.
//
//  The synthetic pattern: Si at 200 kV, Δq = 0.004 Å⁻¹ per pixel, so 2 2 0 (|g| = 0.5208 Å⁻¹) sits 130 px from the centre; discs of
//  38 px (under half the 1 1 1 ring's 80 px), the transmitted one flat, the 2 2 0 one carrying the two-beam rocking curve of 250 nm
//  with the kit's two-beam extinction distance (about 96 nm), the Bragg position on its centre: the minima of orders 3, 4 and 5 fall
//  inside 0.9 of the radius on each side. Every other ring is dark.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import TEMCore
import DiffractoScattering

nonisolated final class CBEDThicknessTests: XCTestCase {

    private static let volts = 200_000.0
    private static let deltaQ = 0.004
    private static let size = 400
    private static let radius = 38.0
    private static let turn = 0.52 // rad, about 30° from lab x

    private static func length(_ v: SIMD2<Double>) -> Double { (v * v).sum().squareRoot() }

    /// The pattern of `thickness` Å, and the diffracted disc's centre.
    private func pattern(thickness: Double) throws -> (CalibratedImage, SIMD2<Double>) {
        let si = CrystalPresets.silicon
        let hkl = MillerIndex(2, 2, 0)
        let g = si.cell.gLength(hkl)
        let xi = try TwoBeamThickness.extinctionDistance(of: hkl, in: si, volts: Self.volts)
        let lambda = ElectronWavelength.angstroms(volts: Self.volts)
        let centre = SIMD2(Double(Self.size / 2), Double(Self.size / 2))
        let along = SIMD2(cos(Self.turn), sin(Self.turn))
        let disc = centre + g / Self.deltaQ * along
        // s per pixel along g: λ|g|² over the disc separation |g| / Δq.
        let factor = lambda * g * Self.deltaQ
        var pixels = [Float](repeating: 0, count: Self.size * Self.size)
        for r in 0 ..< Self.size {
            for c in 0 ..< Self.size {
                let p = SIMD2(Double(r), Double(c))
                if Self.length(p - centre) <= Self.radius {
                    pixels[r * Self.size + c] = 0.5
                } else if Self.length(p - disc) <= Self.radius {
                    let s = ((p - disc) * along).sum() * factor
                    pixels[r * Self.size + c] = Float(TwoBeamThickness.intensity(deviation: s, thickness: thickness, extinctionDistance: xi))
                }
            }
        }
        let image = CalibratedImage(width: Self.size, height: Self.size, pixels: pixels, x: nil, y: nil, fileName: "two-beam",
                                    source: "test", voltage: Self.volts)
        return (image, disc)
    }

    private func families() throws -> [ReflectionFamily] {
        try DiffractionCompute.list(of: CrystalPresets.silicon, kMax: 1).families.map(\.family)
    }

    /// The disc is found on the 2 2 0 ring at its turn, its radius read off the transmitted disc, and the kit's fit gives 250 nm
    /// within 3 %, one answer, a residual under the poor line. Mutation: the profile across g; the offsets signed toward the
    /// direct beam; the disc's brightest pixel taken for its centre.
    func testATwoBeamDiscGivesItsThickness() throws {
        let (image, disc) = try pattern(thickness: 2500)
        let centre = SIMD2(Double(Self.size / 2), Double(Self.size / 2))
        let m = try CBEDThickness.measure(image: image, centre: centre, deltaQ: Self.deltaQ, structure: CrystalPresets.silicon,
                                          families: try families(), phase: "Si", volts: Self.volts)
        XCTAssertEqual(Self.length(m.discs.diffracted - disc), 0, accuracy: 1.5, "the disc's centre")
        XCTAssertEqual(m.discs.radius, Self.radius, accuracy: 1.5)
        XCTAssertEqual(m.discs.gLength, CrystalPresets.silicon.cell.gLength(MillerIndex(2, 2, 0)), accuracy: 1e-12)
        XCTAssertEqual(m.verdict, "found", m.sentence)
        XCTAssertEqual(try XCTUnwrap(m.thicknessNM), 250, accuracy: 7.5)
        XCTAssertTrue(m.sentence.hasPrefix("Thickness "), m.sentence)
        XCTAssertTrue(m.methodLine.hasPrefix("Two-beam CBED thickness · Si "), m.methodLine)
        XCTAssertEqual(m.fittedCurve.count, m.discs.offsets.count)
        XCTAssertGreaterThanOrEqual(m.minima.count, 4, "two fitted minima or more on each side")
    }

    /// A recorded pattern (#978): the same discs at 1000 counts for an intensity of 1, on a background rising from 5 counts at the
    /// left edge by 0.02 counts a column, every pixel a Poisson draw (seeded). Noise and the ramp break the plateau of the highest
    /// mean, so its middle fell back to the noisy maximum, several pixels along the ring; the middle of the turns above half height
    /// stays within 1.5 px. Red before: the plateau within 1e-3 of the top.
    func testTheDiscsCentreOnANoisyPatternWithASlopingBackground() throws {
        let (clean, disc) = try pattern(thickness: 2500)
        var generator = SplitMix64(seed: 978)
        var pixels = [Float](repeating: 0, count: Self.size * Self.size)
        for r in 0 ..< Self.size {
            for c in 0 ..< Self.size {
                let i = r * Self.size + c
                let mean = 1000 * Double(clean.value(at: i)) + 5 + 0.02 * Double(c)
                pixels[i] = Float(Self.poisson(mean, using: &generator))
            }
        }
        let image = CalibratedImage(width: Self.size, height: Self.size, pixels: pixels, x: nil, y: nil, fileName: "two-beam recorded",
                                    source: "test", voltage: Self.volts)
        let centre = SIMD2(Double(Self.size / 2), Double(Self.size / 2))
        let discs = try CBEDThickness.discs(image: image, centre: centre, deltaQ: Self.deltaQ, cell: CrystalPresets.silicon.cell,
                                            families: try families())
        XCTAssertEqual(discs.hkl, MillerIndex(2, 2, 0))
        XCTAssertEqual(Self.length(discs.diffracted - disc), 0, accuracy: 1.5, "the disc's centre")
        XCTAssertEqual(discs.radius, Self.radius, accuracy: 1.5)
    }

    /// A Poisson draw of `mean` counts: Knuth's product of uniforms under 30, a rounded normal (Box-Muller) above, where the two
    /// agree to well under the test's tolerance.
    private static func poisson(_ mean: Double, using generator: inout SplitMix64) -> Double {
        if mean < 30 {
            let limit = exp(-mean)
            var k = 0.0, product = Double.random(in: 0 ..< 1, using: &generator)
            while product > limit { k += 1; product *= Double.random(in: 0 ..< 1, using: &generator) }
            return k
        }
        let u = Double.random(in: Double.leastNonzeroMagnitude ..< 1, using: &generator)
        let v = Double.random(in: 0 ..< 1, using: &generator)
        let z = (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        return max(0, (mean + mean.squareRoot() * z).rounded())
    }

    /// No scale, no disc on the rings: the design's sentences, not a number. Mutation: a fit run on an empty profile.
    func testNoScaleOrNoDiscIsRefused() throws {
        let (image, _) = try pattern(thickness: 2500)
        let centre = SIMD2(Double(Self.size / 2), Double(Self.size / 2))
        XCTAssertThrowsError(try CBEDThickness.measure(image: image, centre: centre, deltaQ: 0, structure: CrystalPresets.silicon,
                                                       families: try families(), phase: "Si", volts: Self.volts)) {
            XCTAssertEqual($0 as? CBEDThickness.Refusal, .noScale)
        }
        XCTAssertThrowsError(try CBEDThickness.measure(image: image, centre: centre, deltaQ: Self.deltaQ, structure: CrystalPresets.silicon,
                                                       families: [], phase: "Si", volts: Self.volts)) {
            XCTAssertEqual($0 as? CBEDThickness.Refusal, .noDisc)
        }
    }
}

/// A seeded generator, so the recorded pattern is the same on every run (SplitMix64, Steele et al. 2014).
private nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
