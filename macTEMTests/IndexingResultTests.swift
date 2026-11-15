//
//  IndexingResultTests.swift
//  A dictionary run's matches as its blocks land (`IndexingResult.land(_:rows:)`): the same matches, in the same order, as the blocks
//  concatenated, and appended in place. Red before the change: each block was appended to a copy of every match landed so far, so the
//  stored arrays moved to a new buffer at every block and landing a run was quadratic in its matches.
//

import XCTest
import TEMCore

nonisolated final class IndexingResultTests: XCTestCase {

    private static let columns = 4, keep = 3

    /// 100 blocks of one to three rows give the concatenation of their matches, under the navigation shape of the rows landed.
    /// Mutation: a block's matches appended out of order or twice, the shape left at the first block's - red.
    func testLandedBlocksGiveTheirMatchesConcatenated() throws {
        let nickel = try XCTUnwrap(IndexingPhase.presets.first { $0.name == "Ni" })
        let heights = (0..<100).map { $0 % 3 + 1 }
        let scanRows = heights.reduce(0, +)
        var result = IndexingResult(scanRows: scanRows, scanColumns: Self.columns, phases: [nickel], metric: .ncc)
        var expected = DictionaryIndexing.Result(navigationShape: [scanRows, Self.columns], keepN: Self.keep, isInData: [], scores: [],
                                                 simulationIndices: [], rotations: [])
        var row = 0
        for height in heights {
            let rows = row..<(row + height)
            let block = Self.block(rows: rows)
            result.land(block, rows: rows)
            expected.isInData += block.isInData
            expected.scores += block.scores
            expected.simulationIndices += block.simulationIndices
            expected.rotations += block.rotations
            row += height
            XCTAssertEqual(result.rowsDone, row)
        }
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.dictionary, expected)
    }

    /// 1000 one-row blocks move the stored scores and rotations to a new buffer only when the arrays grow (a few dozen times at most),
    /// not at every block. Mutation: the block appended to a copy of the landed matches, as before - 1000 moves, red.
    func testLandingADictionaryBlockAppendsInPlace() throws {
        let nickel = try XCTUnwrap(IndexingPhase.presets.first { $0.name == "Ni" })
        let blocks = 1000
        var result = IndexingResult(scanRows: blocks, scanColumns: Self.columns, phases: [nickel], metric: .ncc)
        var moves = 0
        var last = (scores: UInt(0), rotations: UInt(0))
        for row in 0..<blocks {
            result.land(Self.block(rows: row..<(row + 1)), rows: row..<(row + 1))
            let now = Self.buffers(of: result)
            if now.scores != last.scores || now.rotations != last.rotations { moves += 1 }
            last = now
        }
        XCTAssertEqual(result.rowsDone, blocks)
        XCTAssertEqual(result.dictionary?.scores.count, blocks * Self.columns * Self.keep)
        XCTAssertLessThan(moves, 64, "\(moves) of \(blocks) blocks moved the landed matches to a new buffer")
    }

    /// The counts the room reads on every progress tick (#252) are kept as rows land, and equal the counts of the solutions themselves:
    /// a Hough run against two phases, row by row, a row landed twice included, and a dictionary run block by block. Red before: the
    /// counts were reductions over the scan (no stored counts to compare).
    func testTheCountsKeptAsRowsLandEqualTheSolutionsCounted() throws {
        let nickel = try XCTUnwrap(IndexingPhase.presets.first { $0.name == "Ni" })
        var second = nickel
        second.name = "Ni 2"
        func counted(_ result: IndexingResult) -> (reached: Int, indexed: Int, byPhase: [Int]) {
            var byPhase = [Int](repeating: 0, count: result.phases.count)
            for case let s? in result.solutions where result.phases.indices.contains(s.phase) { byPhase[s.phase] += 1 }
            return (result.solutions.compactMap { $0 }.count, result.solutions.filter { ($0?.phase ?? -1) >= 0 }.count, byPhase)
        }
        var hough = IndexingResult(scanRows: 6, scanColumns: Self.columns, phases: [nickel, second])
        for row in [0, 1, 2, 2, 3] {
            let solutions = (0..<Self.columns).map { c -> HoughIndexer.Solution in
                var s = HoughIndexer.Solution()
                s.phase = (row + c) % 3 - 1   // -1 (not indexed), 0 or 1
                return s
            }
            hough.land(solutions, at: row)
            let truth = counted(hough)
            XCTAssertEqual(hough.reachedCount, truth.reached, "row \(row)")
            XCTAssertEqual(hough.indexedCount, truth.indexed, "row \(row)")
            XCTAssertEqual(hough.countsByPhase, truth.byPhase, "row \(row)")
        }
        XCTAssertEqual(hough.reachedCount, 4 * Self.columns, "a row landed twice counts once")

        var dictionary = IndexingResult(scanRows: 6, scanColumns: Self.columns, phases: [nickel], metric: .ncc)
        for rows in [0..<2, 2..<3, 3..<6] {
            dictionary.land(Self.block(rows: rows), rows: rows)
            let truth = counted(dictionary)
            XCTAssertEqual(dictionary.reachedCount, truth.reached)
            XCTAssertEqual(dictionary.indexedCount, truth.indexed)
            XCTAssertEqual(dictionary.countsByPhase, truth.byPhase)
        }
        XCTAssertEqual(dictionary.reachedCount, dictionary.pointCount)
        XCTAssertLessThan(dictionary.indexedCount, dictionary.pointCount, "every seventh point is out of the data")
    }

    /// A dictionary block of scan rows `rows`: distinct finite scores, simulation indices and rotations, every seventh point out of the data.
    private static func block(rows: Range<Int>) -> DictionaryIndexing.Result {
        let points = rows.count * columns, matches = rows.count * columns * keep
        let firstPoint = rows.lowerBound * columns, firstMatch = rows.lowerBound * columns * keep
        return DictionaryIndexing.Result(navigationShape: [rows.count, columns], keepN: keep,
                                         isInData: (0..<points).map { (firstPoint + $0) % 7 != 0 },
                                         scores: (0..<matches).map { 1 - Double(firstMatch + $0) * 1e-6 },
                                         simulationIndices: (0..<matches).map { firstMatch + $0 },
                                         rotations: (0..<matches).map { SIMD4(1, 0, 0, Double(firstMatch + $0)) })
    }

    /// Where `result`'s stored scores and rotations are, read in a call of its own so that no copy of them outlives it.
    private static func buffers(of result: IndexingResult) -> (scores: UInt, rotations: UInt) {
        guard let dictionary = result.dictionary else { return (scores: 0, rotations: 0) }
        return (scores: dictionary.scores.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) },
                rotations: dictionary.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) })
    }
}
