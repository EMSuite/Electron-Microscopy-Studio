//
//  ParticleRegionTests.swift
//  The Particles region to analyse (#110, Paul 16 Nov: "Region to analyse + a note"), ImageJ's rectangle selection: only the region's
//  pixels are labelled, an object cut by its border is an edge object, Otsu's level is of its pixels, the manual level stays a fraction
//  of the whole image's range, and the objects and labels come back in image pixels. With no region every number is as before (the
//  existing ParticleTests hold that). The note on a TIFF render says its burnt-in labels are found as objects. Red before: no region.
//

import XCTest
import ImagoCore
import TEMCore
import TEMSession

nonisolated final class ParticleRegionTests: XCTestCase {
    private func settings(_ region: PixelCrop?) -> ParticleSettings {
        var s = ParticleSettings()
        s.region = region
        return s
    }

    func testADragCoversThePixelsUnderItHeldToTheImage() {
        XCTAssertEqual(ParticleRegion.drawn(from: ImagePoint(x: 10.2, y: 1.0), to: ImagePoint(x: 2.4, y: 3.6), width: 20, height: 20),
                       PixelCrop(row: 1, col: 2, height: 4, width: 9))
        XCTAssertEqual(ParticleRegion.drawn(from: ImagePoint(x: -5, y: -5), to: ImagePoint(x: 40, y: 3), width: 20, height: 20),
                       PixelCrop(row: 0, col: 0, height: 4, width: 20))
        XCTAssertNil(ParticleRegion.drawn(from: ImagePoint(x: 3, y: 3), to: ImagePoint(x: 3.2, y: 9), width: 20, height: 20), "one column is not a region")
    }

    func testARegionIsHeldToTheImageAndTheWholeImageIsNone() {
        XCTAssertNil(ParticleRegion.clamped(nil, width: 10, height: 10))
        XCTAssertNil(ParticleRegion.clamped(PixelCrop(row: 0, col: 0, height: 10, width: 10), width: 10, height: 10))
        XCTAssertNil(ParticleRegion.clamped(PixelCrop(row: 20, col: 20, height: 5, width: 5), width: 10, height: 10))
        XCTAssertEqual(ParticleRegion.clamped(PixelCrop(row: 6, col: -2, height: 8, width: 5), width: 10, height: 10),
                       PixelCrop(row: 6, col: 0, height: 4, width: 3))
        XCTAssertEqual(ParticleRegion.text(nil), "Whole image")
        XCTAssertEqual(ParticleRegion.text(PixelCrop(row: 20, col: 10, height: 400, width: 500)), "x 10, y 20 · 500 × 400 px")
    }

    /// A region round the three ellipses leaves out the 1-px object and the block on the right edge: three counted, none edge, none
    /// small; the level is still half the whole range; the centroids, lengths and labels are the whole image's own.
    func testARegionCountsOnlyItsObjectsInImagePixels() throws {
        let pixels = ParticleTests.planted(), w = ParticleTests.width, h = ParticleTests.height
        let whole = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: ParticleSettings())
        let region = PixelCrop(row: 8, col: 8, height: 70, width: 82)
        let report = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: settings(region))
        XCTAssertEqual(report.summary.counted, 3)
        XCTAssertEqual(report.summary.edge, 0)
        XCTAssertEqual(report.summary.small, 0)
        XCTAssertEqual(report.thresholdValue, 55, accuracy: 1e-4, "the manual level is of the whole image's range, as the slider shows")
        for o in report.objects {
            let twin = try XCTUnwrap(whole.objects.first { abs($0.centroidCol - o.centroidCol) < 1e-6 && abs($0.centroidRow - o.centroidRow) < 1e-6 },
                                     "object \(o.id) at \(o.centroidCol), \(o.centroidRow) is the whole image's")
            XCTAssertEqual(o.moments.area, twin.moments.area)
            XCTAssertEqual(o.moments.lengthPx, twin.moments.lengthPx, accuracy: 1e-9)
        }
        XCTAssertEqual(report.labels.width, w)
        XCTAssertEqual(report.labels.height, h)
        XCTAssertGreaterThan(report.labels.labels[30 * w + 30], 0, "the first ellipse's centre is labelled in image pixels")
        XCTAssertEqual(report.labels.labels[5 * w + 5], 0, "nothing outside the region is labelled")
        XCTAssertEqual(report.labels.labels[42 * w + 98], 0)
    }

    /// An object cut by the region's border is an edge object, as one cut by the image's edge is.
    func testAnObjectCutByTheBorderIsAnEdgeObject() throws {
        let report = try ParticleCompute.analyse(pixels: ParticleTests.planted(), width: ParticleTests.width, height: ParticleTests.height,
                                                 settings: settings(PixelCrop(row: 0, col: 0, height: 80, width: 40)))
        XCTAssertEqual(report.summary.counted, 0)
        XCTAssertEqual(report.summary.edge, 1, "the first ellipse runs past column 39")
        XCTAssertEqual(report.summary.small, 1, "the 1-px object at 5, 5 is inside")
    }

    /// Otsu's level is of the region's pixels: a burnt-in white block outside it no longer sets the level.
    func testOtsuIsOfTheRegionsPixels() throws {
        let w = 20, h = 10
        var pixels = [Float](repeating: 0, count: w * h)
        for r in 0..<h { for c in 0..<w { pixels[r * w + c] = c >= 10 ? 1000 : (r.isMultiple(of: 2) ? 0 : 10) } }
        var s = ParticleSettings()
        s.method = .otsu
        let whole = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: s)
        // The whole image's level parts {0, 10} from 1000 (the bin of 10, 9.77); the region's parts 0 from 10 (the bin of 0).
        XCTAssertGreaterThan(whole.thresholdValue, 9)
        s.region = PixelCrop(row: 0, col: 0, height: h, width: 10)
        let inside = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: s)
        XCTAssertLessThan(inside.thresholdValue, 1)
        let cut = try ParticleCompute.mask(pixels: pixels, width: w, height: h, range: 0...1000, settings: s)
        XCTAssertFalse((0..<h).contains { r in (10..<w).contains { cut.mask[r * w + $0] } }, "the preview's mask is empty outside the region")
    }

    func testTheCSVNamesTheRegionAndIsUnchangedWithout() throws {
        let pixels = ParticleTests.planted(), w = ParticleTests.width, h = ParticleTests.height
        let scale = ParticleScale(perPixel: 0.5, unit: "nm")
        let whole = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: ParticleSettings())
        XCTAssertFalse(ParticleFormat.csv(whole, scale: scale, fileName: "p.dm4").contains("region"))
        let region = try ParticleCompute.analyse(pixels: pixels, width: w, height: h, settings: settings(PixelCrop(row: 8, col: 8, height: 70, width: 82)))
        XCTAssertTrue(ParticleFormat.csv(region, scale: scale, fileName: "p.dm4").contains("region analysed x 8 y 8 82 x 70 px"))
    }

    func testARenderSaysItsLabelsAreFoundAsObjects() {
        XCTAssertNotNil(ParticleFormat.renderNote(notes: [TIFFImageReader.Note.render]))
        XCTAssertNotNil(ParticleFormat.renderNote(notes: ["x", TIFFImageReader.Note.colourRender]))
        XCTAssertNil(ParticleFormat.renderNote(notes: []))
    }

    @MainActor func testTheRegionIsASettingAndDrawingEndsWithIt() {
        let analysis = ParticleAnalysis()
        let crop = PixelCrop(row: 1, col: 2, height: 3, width: 4)
        analysis.setDrawingRegion(true)
        XCTAssertTrue(analysis.isDrawingRegion)
        analysis.setRegion(crop)
        XCTAssertEqual(analysis.settings.region, crop)
        analysis.setDrawingRegion(false)
        analysis.setRegion(nil)
        XCTAssertNil(analysis.settings.region)
    }
}
