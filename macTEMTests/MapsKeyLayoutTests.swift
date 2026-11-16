//
//  MapsKeyLayoutTests.swift
//  The Maps room's IPF key: no corner label covers the key (macEMSuite/macEM#725: "[1̄11]" sat on the m-3m triangle's top). Red
//  before: `MapsKeyLayout` did not exist and the labels sat 8 pt below their corner, inside the key for a corner on its top edge.
//

import CoreGraphics
import TEMCore
import XCTest
@testable import macTEM

nonisolated final class MapsKeyLayoutTests: XCTestCase {
    /// Every m-3m corner label's line (caption2, about 13 pt) lies wholly above or below the key and inside the cell.
    @MainActor func testNoCornerLabelCoversTheKey() throws {
        let (image, labels) = OrientationMaps.keyImage(for: try XCTUnwrap(PointGroup.named("m-3m")))
        XCTAssertEqual(labels.count, 3)
        let layout = MapsKeyLayout(imageWidth: image.width, imageHeight: image.height)
        let top = layout.keyOrigin.y, bottom = layout.keyOrigin.y + layout.keySize.height
        let half: CGFloat = 6.5
        for label in labels {
            let centre = layout.labelCentre(column: label.column, row: label.row)
            let outside = centre.y + half <= top || centre.y - half >= bottom
            XCTAssertTrue(outside, "\(label.text) at y \(centre.y) overlaps the key \(top)...\(bottom)")
            XCTAssertGreaterThanOrEqual(centre.y - half, 0, label.text)
            XCTAssertLessThanOrEqual(centre.y + half, layout.cellSize.height, label.text)
            XCTAssertGreaterThanOrEqual(centre.x, 0, label.text)
            XCTAssertLessThanOrEqual(centre.x, layout.cellSize.width, label.text)
        }
        XCTAssertTrue(labels.contains { layout.labelCentre(column: $0.column, row: $0.row).y < top }, "the top corner's label is above")
    }
}
