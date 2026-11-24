//
//  SEMProcessingComputeTests.swift
//  The #624 processing speed-ups keep their numbers and their contracts: the FFT filter's plans are built once per shape and
//  shared, the cached transfer function is the one the stage builds (and a changed stage or shape builds a new one), and NLPAR's
//  noise estimate, now run in parallel rows, is the same on every run and still stops on a flag. The values against the Python
//  references stay with SEMNLPARParityTests and SEMPatternFilterParityTests.
//

import Foundation
import Synchronization
import TEMCore
import XCTest

nonisolated final class SEMProcessingComputeTests: XCTestCase {

    // MARK: - FFT filter plans

    /// One plan per shape, shared by every caller; a filtered pattern is the same through the shared plan, run after run.
    func testFilterPlansAreBuiltOncePerShapeAndShared() throws {
        let a = try XCTUnwrap(PatternFilters.plan(nx: 60, ny: 60))
        let b = try XCTUnwrap(PatternFilters.plan(nx: 60, ny: 60))
        XCTAssertTrue(a === b, "the same shape builds its plan once")
        let c = try XCTUnwrap(PatternFilters.plan(nx: 64, ny: 59))
        XCTAssertFalse(a === c, "another shape gets its own plan")

        let pattern: [Double] = (0 ..< 3600).map { k in Double((k * 37) % 251) }
        let h = try PatternWindow.lowpass(rows: 60, columns: 60, cutoff: 22, cutoffWidth: 10)
        let first = try PatternFilters.frequencyFiltered(pattern, rows: 60, columns: 60, transferFunction: h, shift: true)
        let again = try PatternFilters.frequencyFiltered(pattern, rows: 60, columns: 60, transferFunction: h, shift: true)
        XCTAssertEqual(first, again)
        let kernel = try PatternWindow.gaussian(rows: 3, columns: 3, std: 1)
        XCTAssertEqual(try PatternFilters.spatialFiltered(pattern, rows: 60, columns: 60, kernel: kernel),
                       try PatternFilters.spatialFiltered(pattern, rows: 60, columns: 60, kernel: kernel))
    }

    /// The cached transfer function is the stage's own, and a changed cutoff, pass or shape gets its own function, never the
    /// one cached before. Red if the cache keyed on the shape alone.
    func testTheCachedTransferFunctionFollowsTheStageAndTheShape() throws {
        var stage = PatternPipeline.FFTFilterStage()
        stage.isOn = true
        XCTAssertEqual(try stage.cachedTransferFunction(rows: 60, columns: 60), try stage.transferFunction(rows: 60, columns: 60))
        XCTAssertEqual(try stage.cachedTransferFunction(rows: 60, columns: 60), try stage.transferFunction(rows: 60, columns: 60))
        stage.lowCutoff = 15
        XCTAssertEqual(try stage.cachedTransferFunction(rows: 60, columns: 60), try stage.transferFunction(rows: 60, columns: 60))
        stage.pass = .high
        XCTAssertEqual(try stage.cachedTransferFunction(rows: 60, columns: 60), try stage.transferFunction(rows: 60, columns: 60))
        XCTAssertEqual(try stage.cachedTransferFunction(rows: 30, columns: 40), try stage.transferFunction(rows: 30, columns: 40))
        stage.highWidth = -1
        XCTAssertThrowsError(try stage.cachedTransferFunction(rows: 30, columns: 40))
    }

    // MARK: - NLPAR noise estimate

    /// A 9 × 11 scan of 8 × 8 noisy patterns.
    private static func scan() throws -> NLPAR.Scan {
        var state: UInt64 = 624
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        let count = 9 * 11 * 64
        var values = [Float](repeating: 0, count: count)
        for k in 0 ..< count {
            let ramp = Float(100 + (k % 64) * 2)
            values[k] = ramp + 40 * next()
        }
        return try NLPAR.Scan(rows: 9, columns: 11, patternRows: 8, patternColumns: 8, values: values)
    }

    /// The parallel rows give the same σ, distances and λ on every run (each pattern writes only its own slots), and every σ is
    /// set: positive and finite on a scan with noise.
    func testTheParallelNoiseEstimateIsTheSameOnEveryRun() throws {
        let s = try Self.scan()
        let first = try NLPAR.estimateNoise(s)
        for _ in 0 ..< 3 {
            let again = try NLPAR.estimateNoise(s)
            XCTAssertEqual(again.sigma, first.sigma)
            XCTAssertEqual(again.distances, first.distances)
        }
        XCTAssertTrue(first.sigma.allSatisfy { $0 > 0 && $0.isFinite })
        let later = try NLPAR.estimateNoise(s)
        XCTAssertEqual(NLPAR.optimiseLambda(first), NLPAR.optimiseLambda(later))
    }

    /// A flag that says yes stops the estimate with `CancellationError`, from the parallel rows as from the tiles.
    func testTheNoiseEstimateStopsOnTheFlag() throws {
        let s = try Self.scan()
        XCTAssertThrowsError(try NLPAR.estimateNoise(s, isCancelled: { true })) { XCTAssertTrue($0 is CancellationError) }
        let flag = CancellationFlag()
        flag.raise()
        XCTAssertThrowsError(try NLPAR.run(s, searchRadius: 1, isCancelled: { flag.isRaised })) { XCTAssertTrue($0 is CancellationError) }
    }

    /// A yes that only one parallel row hears (the tile's own question before it says no, every question after it says no) still
    /// ends the estimate: that row's patterns were skipped, so the tile is never handed on with σ = 0. Red if the rows' yes were
    /// read back from the check instead of from the rows.
    func testAYesHeardByOneRowStopsTheEstimate() throws {
        let s = try Self.scan()
        let once = YesOnce(at: 2)
        XCTAssertThrowsError(try NLPAR.estimateNoise(s, isCancelled: { once.check() })) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertGreaterThan(once.count, 2, "the rows were asked")
    }
}

/// A cancellation check that says yes only the `at`th time it is asked.
private nonisolated final class YesOnce: Sendable {
    private let asked = Mutex(0)
    private let at: Int

    init(at: Int) { self.at = at }

    func check() -> Bool {
        let target = at
        return asked.withLock { n -> Bool in
            n += 1
            return n == target
        }
    }

    var count: Int { asked.withLock { $0 } }
}
