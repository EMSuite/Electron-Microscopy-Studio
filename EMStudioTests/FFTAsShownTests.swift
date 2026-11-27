//
//  FFTAsShownTests.swift
//  The FFT transform's "As shown" export (#636, Paul 16 Nov): bins that are not square in q are resampled to square pixels of the
//  finer step, bilinear between bin centres, the spots moved with their bins and the header's size and steps made the picture's;
//  square bins come back unchanged, and the panel offers the choice only when the bins are not square. Red before: none of it existed.
//

import ImagoFFT
import TEMCore
import XCTest
@testable import EMStudio

nonisolated final class FFTAsShownTests: XCTestCase {
    private func header(width: Int, height: Int, dx: Double, dy: Double) -> FFTExportHeader {
        FFTExportHeader(software: "macEM", fileName: "a.dm4", object: "o", imageWidth: width, imageHeight: height, x: nil, y: nil,
                        notes: [], crop: nil, spectrumWidth: width, spectrumHeight: height, spacingX: dx, spacingY: dy,
                        unitsX: "1/nm", unitsY: "1/nm")
    }

    private func display(_ values: [Float], _ w: Int, _ h: Int) -> ImageExport.Display {
        ImageExport.Display(normalized: values, width: w, height: h, low: 0, high: 1, gamma: 1,
                            lut: [UInt8](repeating: 255, count: 1024), colormap: "gray", windowLow: nil, windowHigh: nil, rawRange: nil)
    }

    func testRectangularBinsBecomeSquarePixelsOfTheFinerStep() {
        // 2 × 2 bins, Δq_y twice Δq_x: the pane draws it 1 : 2, so the picture is 2 wide and 4 tall.
        let h = header(width: 2, height: 2, dx: 0.5, dy: 1.0)
        let spot = ImageExport.Mark(kind: .spot, points: [ImagePoint(x: 1, y: 1)], width: 1, label: "1")
        let shown = FFTExport.asShown(display: display([0, 0, 1, 1], 2, 2), marks: [spot], header: h)
        XCTAssertEqual(shown.display.width, 2)
        XCTAssertEqual(shown.display.height, 4)
        XCTAssertEqual(shown.header.spectrumWidth, 2)
        XCTAssertEqual(shown.header.spectrumHeight, 4)
        XCTAssertEqual(shown.header.spacingX, 0.5, accuracy: 1e-12)
        XCTAssertEqual(shown.header.spacingY, 0.5, accuracy: 1e-12, "square pixels in q")
        // Rows 0 and 1 of bins (0 and 1) resampled to 4 rows: the edges hold, the middle two blend.
        let column = (0..<4).map { shown.display.normalized[$0 * 2] }
        XCTAssertEqual(column, [0, 0.25, 0.75, 1])
        // The spot at bin row 1 (centre) sits at picture row 2.5: the same place in q.
        XCTAssertEqual(shown.marks[0].points[0].x, 1, accuracy: 1e-12)
        XCTAssertEqual(shown.marks[0].points[0].y, 2.5, accuracy: 1e-12)
    }

    func testSquareBinsComeBackUnchanged() {
        let h = header(width: 2, height: 2, dx: 0.5, dy: 0.5)
        let shown = FFTExport.asShown(display: display([0, 1, 2, 3], 2, 2), marks: [], header: h)
        XCTAssertEqual(shown.display.normalized, [0, 1, 2, 3])
        XCTAssertEqual(shown.header, h)
    }

    func testTheDescriptionSaysWhenThePictureIsResampled() {
        let h = header(width: 2, height: 4, dx: 0.5, dy: 0.5)
        let plain = FFTExport.transformProvenance(h, spotsDrawn: 0)
        XCTAssertNil(plain.fields["resampled_from"])
        let resampled = FFTExport.transformProvenance(h, spotsDrawn: 0, resampledFrom: (width: 2, height: 2))
        XCTAssertEqual(resampled.fields["resampled_from"], "2 x 2 bins")
        XCTAssertTrue(resampled.fields["aspect_note"]?.hasPrefix("As shown:") == true)
    }

    func testTheDoneLineSaysPixelsWhenAsShown() {
        XCTAssertEqual(ExportSnapshot.transformDoneLine(name: "a.png", width: 64, height: 128, spots: 0, barLeftOut: false, asShown: true),
                       "Exported a.png — 64 × 128 px as shown")
    }

    @MainActor func testTheChoiceIsOfferedOffByDefault() {
        let choices = ExportImageChoices(ExportImageDefaults(scaleBar: true, marks: true, offersMarks: true), kind: .spots, offersAsShown: true)
        XCTAssertTrue(choices.offersAsShown)
        XCTAssertFalse(choices.asShown, "one pixel per bin stays the default")
        XCTAssertFalse(ExportImageChoices(ExportImageDefaults(scaleBar: true, marks: true, offersMarks: true)).offersAsShown)
    }
}
