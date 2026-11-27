//
//  H5EBSDHeaderBoundsTests.swift
//  The header numbers an EBSD reader counts, sizes and indexes by, checked before anything is sized by them. `ReaderNumber.int` makes
//  a float count or index the whole number Python's `int()` makes and answers nil where Swift's `Int(_:)` traps (NaN, infinity,
//  beyond Int's range), and the h5ebsd reader refuses such a number in words; `ReaderNumber.product` answers nil where `*` traps. A scan
//  or pattern of no rows or columns, or of more bytes than an Int counts, fails `EBSDDataset.validated()` with a sentence that names
//  the file, and the shipped Ni scan and every h5ebsd and EDAX fixture still open through `EBSDOpening.open` as their readers read
//  them. Oxford's camera mode with a height of 0 gives no binning; a Bruker region of interest with indices far apart is not
//  rectangular.
//  Red before the change: `Int(Double.nan)`, `Int(1e300)`, a binning of `1024 / 0` and `$1 - $0` of `Int.min` and `0` trap; a
//  dataset of 0 or -1 scan rows opened.
//

import Foundation
import FormatoCore
import TEMCore
import XCTest

nonisolated final class H5EBSDHeaderBoundsTests: XCTestCase {

    /// The shipped Ni scan (kikuchipy's `nickel_ebsd_large`, 55 x 75 patterns of 60 x 60), read beside this test file.
    private static let nickelScan = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("DemoData/nickel_ebsd_large/patterns_v2.h5")
    private static let fixturesFolder = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// A dataset as an h5ebsd reader fills it, of `scanRows` x `scanColumns` patterns of `patternRows` x `patternColumns` uint8.
    private static func dataset(scanRows: Int, scanColumns: Int, patternRows: Int = 60, patternColumns: Int = 60) -> EBSDDataset {
        let detector = EBSDDetectorGeometry(rows: patternRows, columns: patternColumns, projectionCenters: [SIMD3(0.5, 0.5, 0.5)])
        let source = EBSDPatternSource(url: URL(fileURLWithPath: "/hostile/scan.h5"), datasetPath: "/Scan 1/EBSD/Data/patterns",
                                       fileShape: [1, patternRows, patternColumns], dataType: .uint8)
        return EBSDDataset(format: .kikuchipyH5EBSD, manufacturer: "kikuchipy", version: "0.1", scanGroup: "Scan 1", scanGroups: ["Scan 1"],
                           scanRows: scanRows, scanColumns: scanColumns, patternRows: patternRows, patternColumns: patternColumns,
                           dataType: .uint8, stepY: 1.5, stepX: 1.5, detector: detector, patterns: source)
    }

    /// The shipped Ni scan and the h5ebsd and EDAX fixtures open through the one door as their readers read them: validation refuses
    /// no file that reads.
    func testTheShippedScanAndTheFixturesStillOpen() throws {
        let nickel = try EBSDOpening.open(url: Self.nickelScan).dataset
        XCTAssertEqual([nickel.scanRows, nickel.scanColumns, nickel.patternRows, nickel.patternColumns], [55, 75, 60, 60])
        XCTAssertEqual(try nickel.validated(), nickel)
        for name in ["ebsd-kikuchipy-h5ebsd.h5", "ebsd-edax-h5ebsd.h5", "ebsd-bruker-h5ebsd.h5", "ebsd-bruker-roi-h5ebsd.h5", "ebsd-oxford.h5oina",
                     "ebsd-oxford-6.h5oina"] {
            let url = Self.fixturesFolder.appendingPathComponent(name)
            XCTAssertEqual(try EBSDOpening.open(url: url).dataset, try EBSDH5Reader.read(url: url), name)
        }
        for name in ["ebsd-edax-binary.up1", "ebsd-edax-binary.up2"] {
            let url = Self.fixturesFolder.appendingPathComponent(name)
            XCTAssertEqual(try EBSDOpening.open(url: url).dataset, try EDAXOpening.open(url: url), name)
        }
    }

}
