//
//  DiffractionSpotCropTests.swift
//  A Spot-tool click refines from a crop about the click (`DiffractionCompute.refineSpot`), not from the whole image widened to
//  Float32 on the main actor (#928). The answer is the kit's on the whole image (`PatternSpot.refine`): the same centre to 1e-9 px
//  (only the summation's rounding differs) inside the image, at its edges and corners, and the same refusal off it. Red before
//  #928: `refineSpot` did not exist and a click copied the whole image.
//

import XCTest
import DiffractoGeometry
import TEMCore

nonisolated final class DiffractionSpotCropTests: XCTestCase {

    /// A uint16 pattern, 160 × 120, with Gaussian spots (sigma 2) at fractional centres, a corner spot and a sloped background.
    private static func image() -> CalibratedImage {
        let w = 160, h = 120
        let spots: [(Double, Double)] = [(60.3, 80.7), (2.4, 3.1), (117.6, 157.2), (30.5, 30.5), (60.9, 84.2)]
        var levels = [UInt16](repeating: 0, count: w * h)
        for y in 0 ..< h {
            for x in 0 ..< w {
                var v = 40 + 0.2 * Double(x) + 0.1 * Double(y)
                for (r, c) in spots { v += 3000 * exp(-((Double(y) - r) * (Double(y) - r) + (Double(x) - c) * (Double(x) - c)) / 8) }
                levels[y * w + x] = UInt16(v.rounded())
            }
        }
        return CalibratedImage(width: w, height: h, stored: .uint16(levels), x: nil, y: nil, fileName: "spots.tif", source: "test",
                               voltage: nil)
    }

    func testCropGivesTheWholeImagesCentre() {
        let image = Self.image()
        let whole = DiffractionPattern(width: image.width, height: image.height, pixels: image.pixels)
        let clicks: [(Double, Double)] = [(61, 79), (59.6, 82.9), (2, 2), (0, 0), (-3, 4), (119, 159), (122.5, 161), (117, 155),
                                          (30.5, 30.5), (60, 140), (10, 150), (-5, -5)]
        for (row, column) in clicks {
            for half in [3, 5, 8] {
                let expected = PatternSpot.refine(pattern: whole, row: row, column: column, half: half)
                let cropped = DiffractionCompute.refineSpot(in: image, row: row, column: column, half: half)
                XCTAssertEqual(expected == nil, cropped == nil, "click (\(row), \(column)) half \(half)")
                guard let expected, let cropped else { continue }
                XCTAssertEqual(cropped.row, expected.row, accuracy: 1e-9, "click (\(row), \(column)) half \(half)")
                XCTAssertEqual(cropped.column, expected.column, accuracy: 1e-9, "click (\(row), \(column)) half \(half)")
            }
        }
    }

    func testAClickOffTheImageIsRefused() {
        let image = Self.image()
        let whole = DiffractionPattern(width: image.width, height: image.height, pixels: image.pixels)
        for (row, column) in [(-6.0, 10.0), (10.0, 166.0), (126.0, 10.0), (-1e12, 0.0), (Double.nan, 4.0), (4.0, .infinity)] {
            XCTAssertNil(PatternSpot.refine(pattern: whole, row: row, column: column))
            XCTAssertNil(DiffractionCompute.refineSpot(in: image, row: row, column: column), "click (\(row), \(column))")
        }
    }
}
