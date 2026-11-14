//
//  IndexingStoredBlockTests.swift
//  #620: dictionary indexing and refinement read a block of scan rows at the type the patterns are indexed in, and widen one
//  pattern at a time as they compute.
//  - A block of the largest size a dictionary run reads (128 MiB as float64: 62 rows of a 75-column scan of 60 x 60 px) from a
//    uint16 scan holds 33.5 MB, two bytes a pixel, where it held 134 MB of Doubles; its values are the ones the room's per-row
//    Double reading gives.
//  - The refinement's patterns are that block and the indexed points' indices, not a copy.
//  - Dictionary indexing on the stored block gives the scores and matches it gives on the block's doubles, bit for bit.
//  Red on main: `readBlock` returned `[Double]` and `EBSDRefinement.Patterns` a `[Float]` copy.
//

import Foundation
import FormatoCore
import simd
import TEMCore
import TEMSession
import XCTest

nonisolated final class IndexingStoredBlockTests: XCTestCase {

    /// A uint16 scan in memory of `rows` x `columns` patterns of 60 x 60 px, each pixel a fixed function of its place.
    private func scan(rows: Int, columns: Int) throws -> (access: EBSDMemoryPatterns, dataset: EBSDDataset) {
        let side = 60
        let dataset = EBSDDataset(format: .generated, manufacturer: "test", version: "", scanGroup: "s", scanGroups: ["s"], scanRows: rows,
                                  scanColumns: columns, patternRows: side, patternColumns: side, dataType: .uint16, stepY: 1, stepX: 1,
                                  detector: EBSDDetectorGeometry(rows: side, columns: side, projectionCenters: [SIMD3(0.4214, 0.2142, 0.5013)]),
                                  patterns: EBSDPatternSource(url: URL(fileURLWithPath: "/planted"), datasetPath: "",
                                                              fileShape: [rows, columns, side, side], dataType: .uint16))
        let n = rows * columns * side * side
        var values = [UInt16](repeating: 0, count: n)
        values.withUnsafeMutableBufferPointer { b in
            for i in 0 ..< n { b[i] = UInt16(truncatingIfNeeded: (i &* 7919) ^ (i >> 7)) }
        }
        let bytes = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (try EBSDMemoryPatterns(dataset: dataset, bytes: bytes), dataset)
    }

    private func plan(_ access: EBSDMemoryPatterns, _ dataset: EBSDDataset, rotations: [SIMD4<Double>]) throws -> DictionaryIndexingPlan {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelMasterPattern.url, "DemoData/ holds no master pattern")
        let nickel = IndexingPhase(name: "Ni", spaceGroup: 225, lattice: [3.52, 3.52, 3.52, 90, 90, 90], source: .preset)
        return try DictionaryIndexingPlan(source: IndexingSource(processed: access), phase: nickel, master: IndexingMasterPattern.load(url),
                                          settings: .roomDefault, fileDetector: dataset.detector, beamEnergy: nil, rotations: rotations)
    }

    func testABlockOfTheLargestSizeHoldsItsStoredBytes() async throws {
        let (access, dataset) = try scan(rows: 62, columns: 75)
        let plan = try plan(access, dataset, rotations: [SIMD4(1, 0, 0, 0)])
        XCTAssertEqual(plan.blocks, [0 ..< 62], "one block of the 128 MiB float64 budget")
        let block = try await plan.readBlock(0 ..< 62)
        XCTAssertEqual(block.dataType, .uint16)
        XCTAssertEqual([block.count, block.pixels], [62 * 75, 3600])
        XCTAssertEqual(block.byteCount, 33_480_000, "two bytes a pixel (134 MB as Double)")
        XCTAssertEqual(block.bytes, access.bytes)
        // The values the room's per-row Double reading gives.
        for row in [0, 31, 61] {
            let doubles = try plan.source.patterns(row: row).flatMap { $0 }
            let stored = (0 ..< 75).flatMap { block.floats(pattern: row * 75 + $0, kept: nil).map(Double.init) }
            XCTAssertEqual(stored, doubles, "row \(row)")
        }

        // The refinement takes the block and the points' indices, not a copy.
        let points = Array(stride(from: 0, to: block.count, by: 3))
        let patterns = EBSDRefinement.Patterns(stored: block, indices: points, isFloat32: false)
        XCTAssertEqual(patterns.count, points.count)
        XCTAssertEqual(patterns.stored, block)
    }

    func testDictionaryIndexingOnAStoredBlockIsItsDoublesBitForBit() throws {
        let (access, dataset) = try scan(rows: 2, columns: 3)
        let block = try StoredPatterns(dataType: .uint16, count: 6, pixels: 3600, bytes: access.bytes)
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelMasterPattern.url)
        let master = try IndexingMasterPattern.load(url).master
        let rotations: [SIMD4<Double>] = (0 ..< 12).map { k in
            let a = Double(k) * 0.13
            return simd_normalize(SIMD4(cos(a), sin(a) * 0.6, sin(a) * 0.48, sin(a) * 0.64))
        }
        var detector = dataset.detector
        detector.binning = 8
        let options = DictionaryIndexing.Options(keepN: 3, signalMask: nil, backend: .cpu)
        let stored = try DictionaryIndexing.index(experimental: block, navigationShape: [2, 3], master: master, rotations: rotations,
                                                  detector: detector, options: options)
        let doubles = try DictionaryIndexing.index(experimental: block.doubles(), navigationShape: [2, 3], master: master,
                                                   rotations: rotations, detector: detector, options: options)
        XCTAssertEqual(stored.scores, doubles.scores)
        XCTAssertEqual(stored.simulationIndices, doubles.simulationIndices)

        var masked = options
        masked.signalMask = (0 ..< 3600).map { $0 % 7 == 0 }
        let a = try DictionaryIndexing.index(experimental: block, navigationShape: [2, 3], master: master, rotations: rotations,
                                             detector: detector, options: masked)
        let b = try DictionaryIndexing.index(experimental: block.doubles(), navigationShape: [2, 3], master: master,
                                             rotations: rotations, detector: detector, options: masked)
        XCTAssertEqual(a.scores, b.scores)
    }

    func testAStoredBlockRefusesWhatItCannotHold() {
        XCTAssertThrowsError(try StoredPatterns(dataType: .rgb8, count: 1, pixels: 1, bytes: Data(count: 3)))
        XCTAssertThrowsError(try StoredPatterns(dataType: .uint8, count: 2, pixels: 3, bytes: Data(count: 5)))
        XCTAssertThrowsError(try StoredPatterns(joining: [try StoredPatterns(floats: [1], pixels: 1), try StoredPatterns(doubles: [1], pixels: 1)],
                                                pixels: 1, emptyType: .float32))
        XCTAssertEqual(try StoredPatterns(joining: [], pixels: 4, emptyType: .uint8).count, 0)
    }
}
