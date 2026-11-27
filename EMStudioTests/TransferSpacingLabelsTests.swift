//
//  TransferSpacingLabelsTests.swift
//  #1085: under the HRTEM transfer function, a spacing's label that would overlap a stronger one's is left out, as the pattern's
//  hkl labels are (#1045). Red before: `TransferSpacingLabels` did not exist and every label was drawn, {220} over {311}'s on Si [110].
//

import XCTest
@testable import EMStudio

nonisolated final class TransferSpacingLabelsTests: XCTestCase {
    func testALabelThatWouldOverlapAStrongerOneIsLeftOut() {
        // Si: {111} 3.135 Å, {220} 1.920 Å, {311} 1.637 Å, strongest first; an axis to 10 1/nm.
        let f = [10 / 3.135, 10 / 1.920, 10 / 1.637]
        XCTAssertEqual(TransferSpacingLabels.labelled(f, across: 10), [0, 1], "{311} sits 0.9 1/nm from {220}: its label goes")
        XCTAssertEqual(TransferSpacingLabels.labelled([1, 5, 9], across: 10), [0, 1, 2], "apart, all stay")
        XCTAssertEqual(TransferSpacingLabels.labelled([], across: 10), [])
    }
}
