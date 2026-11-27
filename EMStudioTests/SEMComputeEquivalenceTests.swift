//
//  SEMComputeEquivalenceTests.swift
//  The #624 speed-ups give the numbers of the plain forms they replace: `CrystalMap.stepSize` in one pass against numpy's
//  `sort(unique(c))[1] - [0]` written out with a set and a sort, the cached `dx` and `dy` against it, the ODF's vForce powers
//  against one `pow` per term (across batch boundaries), and the Hough triplet vote's SIMD corner table against the array one.
//  The parity suites hold each against its Python reference; these hold the new forms to the old ones, tighter than parity.
//

import Foundation
import TEMCore
import XCTest

nonisolated final class SEMComputeEquivalenceTests: XCTestCase {

    // MARK: - CrystalMap step sizes

    /// numpy's `unique` then `[1] - [0]`, as `stepSize` was written before #624.
    private static func referenceStep(_ c: [Double]) -> Double {
        let unique = Set(c).sorted()
        return unique.count > 1 ? unique[1] - unique[0] : 0
    }

    func testStepSizeInOnePassIsTheSortedUniqueDifference() {
        let cases: [[Double]] = [
            [], [3], [2, 2, 2], [0, 1.5, 3, 4.5], [4.5, 3, 1.5, 0], [5, 5, 1, 1, 3], [-0.0, 0, 0.25], [0, -0.0, -0.25],
            [-3, -1, -2, -3], [1e-9, 2e-9, 1e300], [7, 7, 7, 8], [8, 7, 7, 7], [-.infinity, 0], [0, .infinity], [1, .infinity, 2],
        ]
        for c in cases { XCTAssertEqual(CrystalMap.stepSize(c), Self.referenceStep(c), "\(c)") }
        var g = SplitMix64(seed: 624)
        for _ in 0..<200 {
            let n = Int.random(in: 0...40, using: &g)
            let step = Double(Int.random(in: 1...8, using: &g)) * 0.25
            let c = (0..<n).map { _ in Double(Int.random(in: -5...5, using: &g)) * step }
            XCTAssertEqual(CrystalMap.stepSize(c), Self.referenceStep(c), "\(c)")
        }
    }

    /// `dx` and `dy` are set with the coordinates and equal the step of all points, in or out of data; a slice keeps them, and `x`
    /// and `y` are nil exactly where the step is 0.
    func testCachedStepsAreTheCoordinatesSteps() throws {
        let (x, y) = CrystalMap.coordinates(shape: (rows: 4, columns: 5), steps: (dy: 0.5, dx: 1.5))
        let q = Array(repeating: SIMD4<Double>(1, 0, 0, 0), count: 20)
        let map = try CrystalMap(rotations: q, x: x, y: y)
        XCTAssertEqual(map.dx, Self.referenceStep(x))
        XCTAssertEqual(map.dy, Self.referenceStep(y))
        XCTAssertEqual([map.dx, map.dy], [1.5, 0.5])
        let slice = map.sliced(rows: 1..<3, columns: 2..<4)
        XCTAssertEqual([slice.dx, slice.dy], [1.5, 0.5])
        XCTAssertEqual(slice.shape, [2, 2])
        let line = try CrystalMap(rotations: Array(q.prefix(3)), x: [2, 2, 2], y: [0, 1, 2])
        XCTAssertNil(line.x)
        XCTAssertEqual(line.y, [0, 1, 2])
        XCTAssertEqual([line.dx, line.dy], [0, 1])
        let oneAxis = try CrystalMap(rotations: Array(q.prefix(3)))
        XCTAssertEqual(oneAxis.dx, 1)
        XCTAssertEqual(oneAxis.dy, 0)
    }

    // MARK: - ODF powers

    /// `OrientationDensity.values` with one `pow` per term, summed in the same order, as before #624.
    private static func referenceODF(_ o: Orientations, at grid: [SIMD4<Double>], halfWidthDegrees: Double) -> [Double] {
        let sym = o.symmetry.properSubgroup.elements.map(\.q)
        let q = o.quaternions.map { Rotation($0).q }
        let exponent = 2 * OrientationDensity.kappa(halfWidthDegrees: halfWidthDegrees)
        let scale = OrientationDensity.kernelConstant(kappa: exponent / 2) / Double(q.count * sym.count)
        return grid.map { g in
            var sum = 0.0
            for qi in q {
                let mw = qi[0] * g[0] + qi[1] * g[1] + qi[2] * g[2] + qi[3] * g[3]
                let mx = qi[1] * g[0] - qi[0] * g[1] + qi[3] * g[2] - qi[2] * g[3]
                let my = qi[2] * g[0] - qi[3] * g[1] - qi[0] * g[2] + qi[1] * g[3]
                let mz = qi[3] * g[0] + qi[2] * g[1] - qi[1] * g[2] - qi[0] * g[3]
                for s in sym { sum += pow(min(abs(mw * s[0] + mx * s[1] + my * s[2] + mz * s[3]), 1), exponent) }
            }
            return scale * sum
        }
    }

    /// 600 orientations (three batches of the vForce path, the last partial) on m-3m and 622, against one `pow` per term: equal
    /// within 1e-12 relative, far inside the parity tolerance (rtol 1e-4), since only each power's last bits can differ.
    func testODFPowersInBatchesMatchOnePowEach() {
        var g = SplitMix64(seed: 624)
        func randomUnit() -> SIMD4<Double> {
            let v = SIMD4<Double>((0..<4).map { _ in Double.random(in: -1...1, using: &g) })
            return v / (v * v).sum().squareRoot()
        }
        let quaternions = (0..<600).map { _ in randomUnit() }
        let grid = OrientationDensity.sectionGrid(phi2Degrees: 45, phi1Degrees: [0, 10, 35, 80], PhiDegrees: [0, 20, 45, 90])
            + quaternions.prefix(5)
        for (symmetry, halfWidth) in [(PointGroup.oh, 10.0), (PointGroup.d6, 5.0)] {
            let o = Orientations(quaternions: quaternions, symmetry: symmetry)
            let ours = OrientationDensity.values(o, at: grid, halfWidthDegrees: halfWidth)
            let reference = Self.referenceODF(o, at: grid, halfWidthDegrees: halfWidth)
            XCTAssertEqual(ours.count, reference.count)
            for (a, b) in zip(ours, reference) {
                XCTAssertLessThanOrEqual(abs(a - b), 1e-12 * abs(b), "\(symmetry.name ?? "unnamed"), half-width \(halfWidth): \(a) against \(b)")
            }
        }
    }

    // MARK: - Hough corner table

    func testSIMDCornerTableIsTheArrayOne() {
        for p in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            let simd = HoughReflectorLibrary.cornerPermutation(edges: SIMD3(p[0], p[1], p[2]))
            XCTAssertEqual([simd[0], simd[1], simd[2]], HoughReflectorLibrary.cornerPermutation(p), "\(p)")
        }
    }
}

/// A seeded generator, so a failing draw can be replayed (SplitMix64, Steele et al. 2014).
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
