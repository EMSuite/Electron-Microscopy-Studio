//
//  IndexingRowLookupTests.swift
//  The Indexing room's Results table finds a picked point's row without a search of the rows (#623): a row's id is its point's index in
//  map order, and `IndexingResult.hasRow` says in O(1) whether the run has reached it.
//

import XCTest
import TEMCore

nonisolated final class IndexingRowLookupTests: XCTestCase {

    private static let ni = IndexingPhase(name: "ni", spaceGroup: 225, lattice: [3.52, 3.52, 3.52, 90, 90, 90], source: .preset)

    /// A 3 × 4 scan with its first row landed: the points of that row have rows, the others and the indices outside the scan do not; every
    /// row's id gives its own position. Red under: `hasRow` true for a point not reached or off the scan; an id that is not the map index.
    func testHasRowIsTheReachedPointsAndAnIdIsItsPosition() {
        var result = IndexingResult(scanRows: 3, scanColumns: 4, phases: [Self.ni])
        result.land([HoughIndexer.Solution](repeating: HoughIndexer.Solution(), count: 4), at: 0)
        XCTAssertEqual((0..<12).filter { result.hasRow($0) }, [0, 1, 2, 3])
        XCTAssertFalse(result.hasRow(-1))
        XCTAssertFalse(result.hasRow(12))
        for row in result.rows {
            XCTAssertTrue(result.hasRow(row.id))
            XCTAssertEqual(EBSDPosition(row: row.id / 4, column: row.id % 4), row.position)
        }
    }
}
