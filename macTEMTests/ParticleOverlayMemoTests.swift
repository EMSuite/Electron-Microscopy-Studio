//
//  ParticleOverlayMemoTests.swift
//  The particle overlay and the object table do their work once per change, not per frame (#623): the ellipses are built once per objects
//  and selection in image coordinates and placed on the pane by one affine map (`MarkGeometry.imageToPane`), and the table's rows are
//  made once per objects, filter and order, not on every selection.
//

import XCTest
import ImagoCore
import ShellMetal
import TEMCore
@testable import macTEM

nonisolated final class ParticleOverlayMemoTests: XCTestCase {

    private static func report() throws -> ParticleReport {
        try ParticleCompute.analyse(pixels: ParticleTests.planted(), width: ParticleTests.width, height: ParticleTests.height,
                                    settings: ParticleSettings())
    }

    /// The affine map lands every image point where `panePoint(of:)` does, at any zoom and offset, on a pane wider than the image's box.
    /// Red under: the map dropping the half-pixel shift, the offset or the zoom.
    func testTheAffineMapIsThePanePoint() {
        let geometry = MarkGeometry(transform: MetalDisplayTransform(paneSize: CGSize(width: 500, height: 300), imageBox: CGSize(width: 240, height: 180),
                                                                     zoom: 2.5, offset: CGSize(width: -31, height: 17)),
                                    imageWidth: 120, imageHeight: 90)
        let map = geometry.imageToPane
        for q in [ImagePoint(x: -0.5, y: -0.5), ImagePoint(x: 0, y: 0), ImagePoint(x: 37.25, y: 81.5), ImagePoint(x: 119.5, y: 89.5)] {
            let a = geometry.panePoint(of: q), b = CGPoint(x: q.x, y: q.y).applying(map)
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    /// The ellipses are built once for the same objects and selection (a pan or zoom frame), again when the selection changes. Red under:
    /// the overlay building every ellipse per frame.
    @MainActor func testTheEllipsesAreBuiltOncePerObjectsAndSelection() throws {
        let objects = try Self.report().objects
        XCTAssertFalse(objects.isEmpty)
        let memo = ParticleEllipseMemo()
        let first = memo.paths(objects, selected: nil)
        for _ in 0..<5 { _ = memo.paths(objects, selected: nil) }
        XCTAssertEqual(memo.builds, 1, "a frame with the same objects and selection builds nothing")
        XCTAssertTrue(first.selected.isEmpty)
        let picked = memo.paths(objects, selected: objects[0].id)
        XCTAssertEqual(memo.builds, 2)
        XCTAssertFalse(picked.selected.isEmpty, "the selected object's ellipse has its own path")
    }

    /// The table's rows are made once for the same objects, filter and order; a selection does not make them again. Red under: the rows
    /// made and sorted on every body.
    @MainActor func testTheTableRowsAreMadeOncePerObjectsFilterAndOrder() throws {
        let objects = try Self.report().objects
        let scale = ParticleScale(perPixel: 0.5, unit: "nm")
        let memo = ParticleRowsMemo()
        let order = [KeyPathComparator(\ParticleRow.area, order: .reverse)]
        let rows = memo.rows(objects, scale: scale, countedOnly: false, sortOrder: order)
        for _ in 0..<5 { _ = memo.rows(objects, scale: scale, countedOnly: false, sortOrder: order) }
        XCTAssertEqual(memo.builds, 1)
        XCTAssertEqual(rows, objects.map { ParticleRow($0, scale: scale) }.sorted(using: order))
        _ = memo.rows(objects, scale: scale, countedOnly: true, sortOrder: order)
        XCTAssertEqual(memo.builds, 2, "the filter changes the rows")
    }
}
