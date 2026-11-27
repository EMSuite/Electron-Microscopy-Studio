//
//  FFTSpectrumPeakTests.swift
//  The FFT room's spectrum job at its memory peak (#686): on the 375 MP alite SEM image the app peaked at 5.15 GiB. The job widens
//  the image to Float32 (one full-size array, N) and the kit transformed it beside two more, then drew the display beside the
//  power: about 3N above the image at the peak. Now the widened pixels go to the kit as a temporary, which frees them after the
//  transform's row step (ImagoKit#101), and the display takes the power's storage: about 2⅛N.
//  A sampler reads malloc's bytes in use while the job runs; the least peak of three runs is kept (anything else allocating in
//  the process only raises a run's peak).
//

import Darwin
import Foundation
import Synchronization
import XCTest
import TEMCore
import TEMSession

nonisolated final class FFTSpectrumPeakTests: XCTestCase {

    /// The live heap (malloc's bytes in use over every zone).
    private static func heapInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    private final class Sampler: Sendable {
        let peak: Atomic<Int>
        let running = Atomic<Bool>(true)
        let done = DispatchSemaphore(value: 0)
        init(_ start: Int) { peak = Atomic(start) }
    }

    /// The most the live heap rose above its level at the start while `body` ran, sampled every 100 µs on another thread.
    private static func peakRise<T>(_ body: () async throws -> T) async rethrows -> (rise: Int, result: T) {
        let start = heapInUse()
        let sampler = Sampler(start)
        Thread.detachNewThread {
            while sampler.running.load(ordering: .acquiring) {
                let now = heapInUse()
                if now > sampler.peak.load(ordering: .relaxed) { sampler.peak.store(now, ordering: .relaxed) }
                usleep(100)
            }
            sampler.done.signal()
        }
        let result = try await body()
        let end = heapInUse()
        sampler.running.store(false, ordering: .releasing)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { sampler.done.wait(); c.resume() }
        }
        return (max(sampler.peak.load(ordering: .relaxed), end) - start, result)
    }

    /// A 6144 × 4096 16-bit image (48 MiB as stored; one full-size Float32 array is 96 MiB).
    private static func image() -> CalibratedImage {
        let w = 6144, h = 4096
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        let pixels = [UInt16](unsafeUninitializedCapacity: w * h) { p, n in
            for i in 0..<(w * h) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                p[i] = 1000 + UInt16(truncatingIfNeeded: state >> 52) + UInt16((i % w) / 64)
            }
            n = w * h
        }
        return CalibratedImage(width: w, height: h, stored: .uint16(pixels), x: nil, y: nil, fileName: "peak.tif",
                               source: "test", voltage: nil)
    }

    /// Red before: the widened pixels stayed beside the kit's half spectrum and full-size scratch (about 3 full-size arrays above
    /// the image). Now about 2⅛.
    func testTheWholeImageSpectrumPeaksBelowTwoAndAHalfFullSizeArrays() async throws {
        let image = Self.image()
        let fullSize = image.width * image.height * MemoryLayout<Float>.stride
        let compute = FFTCompute.live
        var rises: [Int] = []
        for run in 0..<3 {
            let (rise, product) = try await Self.peakRise {
                try await compute.spectrum(image, FFTSpectrumKey(contentVersion: run, crop: nil))
            }
            XCTAssertEqual(product.width, image.width)
            XCTAssertNil(product.region)
            rises.append(rise)
        }
        let least = Double(rises.min()!) / Double(fullSize)
        XCTAssertLessThan(least, 2.5, "the spectrum job rose \(least) full-size arrays above the image (was about 3)")
    }
}
