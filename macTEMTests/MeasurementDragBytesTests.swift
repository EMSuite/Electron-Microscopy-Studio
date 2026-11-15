//
//  MeasurementDragBytesTests.swift
//  A measurement drag does not encode the whole lineage per sample (#623): a moved point replaces one node, and the lineage's size follows
//  from its known size and the two nodes' own canonical JSON (`SessionLineage.jsonBytes(of:)`); the whole lineage is encoded only near
//  the sidecar budget. The size kept is the canonical JSON's, byte for byte.
//

import ImagoCore
import XCTest
import TEMCore
import TEMSession

nonisolated final class MeasurementDragBytesTests: XCTestCase {

    private static func image() -> CalibratedImage {
        CalibratedImage(width: 40, height: 24, pixels: (0..<960).map { Float(($0 * 37) % 97) },
                        x: AxisCalibration(scale: 0.5, unit: "nm", origin: 0), y: AxisCalibration(scale: 2.0, unit: "nm", origin: 0),
                        fileName: "scan.dm4", source: "ImageList.1", voltage: nil)
    }

    /// Once the lineage's size is known, fifty drag samples on the third of three marks encode no whole lineage, and the size kept equals the canonical JSON's after every sample. Red under: a sample encoding the whole lineage; a node's size taken from
    /// another encoding than `jsonString`'s.
    @MainActor func testADragEncodesTheLineageOnceAndKeepsItsExactSize() throws {
        let image = Self.image()
        let owner = ImageMeasurements(now: { Date(timeIntervalSince1970: 1_791_900_000) })
        for k in 0..<3 {
            owner.add(ImageMark(kind: .distance, points: [ImagePoint(x: 2, y: Double(k) + 1), ImagePoint(x: 30, y: Double(k) + 9)]), on: image)
        }
        let id = owner.marks[2].id
        _ = owner.lineageByteCount
        let before = owner.lineageEncodes
        for step in 0..<50 {
            owner.move(id, point: 1, to: ImagePoint(x: 30 - Double(step) * 0.37, y: 9 + Double(step) * 0.21), on: image)
            XCTAssertEqual(owner.lineageByteCount, try owner.lineage.jsonString().utf8.count, "sample \(step)")
        }
        XCTAssertEqual(owner.lineageEncodes, before, "no drag sample encodes the whole lineage")
        XCTAssertNil(owner.recordingRefusal)
        XCTAssertEqual(owner.lineageEncodes, before, "nor does the tail's question")
    }
}
