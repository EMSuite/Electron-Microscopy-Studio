//
//  FigureExportTests.swift
//  Export Figure… as a vector figure (#822, plan row X6; `FigureExport`): the Image room's image drawn as EMSuiteUI's figure scene
//  at a journal width, its picture the display's own mapping at the image's pixels, the marks and the scale bar as lines and
//  live text over it. PDFKit finds every label as text in the PDF, the SVG holds them as <text>, and a figure of an image
//  without a scale says the bar was left out. The PNG is untouched: Export Figure…'s PNG is `ImageExport`'s, the file Export
//  Image… wrote (`ImageExportRenderTests` pins it).
//  Red before: `FigureExport` did not exist; Export Image… wrote PNG only.
//

import Foundation
import ImagoCore
import PDFKit
import ShellExport
import TEMCore
import XCTest

nonisolated final class FigureExportTests: XCTestCase {
    /// Entry i is (i, i, i, 255): black at 0.
    private static let grayLUT: [UInt8] = (0..<1024).map { (i: Int) -> UInt8 in i % 4 == 3 ? 255 : UInt8(i / 4) }
    private static let w = 512, h = 256

    private func source(calibrated: Bool = true) -> ExportSource {
        let axis = calibrated ? AxisCalibration(scale: 0.5, unit: "nm") : nil
        let image = CalibratedImage(width: Self.w, height: Self.h, pixels: [Float](repeating: 0, count: Self.w * Self.h), x: axis, y: axis,
                                    fileName: "lattice.dm4", source: "ImageList.1", voltage: nil)
        return ExportSource(image: image, software: "Electron Microscopy Studio 2.4.0 (1)")
    }

    /// A left-to-right ramp, so the picture's pixels are not all one value.
    private func display() -> ImageExport.Display {
        let values = (0..<(Self.w * Self.h)).map { Float($0 % Self.w) / Float(Self.w - 1) }
        return ImageExport.Display(normalized: values, width: Self.w, height: Self.h, low: 0, high: 1, gamma: 1, lut: Self.grayLUT,
                                   colormap: "gray")
    }

    private let distance = ImageExport.Mark(kind: .distance, points: [ImagePoint(x: 10, y: 20), ImagePoint(x: 110, y: 20)], width: 1,
                                            label: "50.0 nm")

    /// The picture fills 90 mm and keeps the image's aspect; the mark is a yellow line from pixel centre to pixel centre with its
    /// value beside it; the bar is ImagoKit's plan with its label as text. Mutation: the picture's pixels not the display's
    /// mapping, a mark off its pixel centre, the label left out, or the figure's height not the image's aspect - red.
    func testTheSceneHoldsThePictureTheMarksAndTheBar() throws {
        let made = try FigureExport.scene(source: source(), display: display(), marks: [distance],
                                          options: ImageExport.Options(scaleBar: true, marks: true), width: .mm90)
        let scene = made.scene
        XCTAssertFalse(made.barLeftOut)
        XCTAssertEqual(scene.widthMM, 90)
        XCTAssertEqual(scene.heightMM, 45, accuracy: 1e-9)
        let k = scene.widthPoints / Double(Self.w)
        guard case .raster(let raster, let frame) = scene.layers.first else { return XCTFail("the picture is not the first layer") }
        XCTAssertEqual(raster.width, Self.w)
        XCTAssertEqual(raster.height, Self.h)
        XCTAssertEqual(Array(raster.pixels[(3 * (Self.w - 1))..<(3 * Self.w)]), [255, 255, 255], "the row's last pixel is white")
        XCTAssertEqual(Array(raster.pixels[0..<3]), [0, 0, 0])
        XCTAssertEqual(frame, FigureRect(x: 0, y: 0, width: scene.widthPoints, height: scene.heightPoints))

        let paths = scene.layers.compactMap { layer -> FigurePath? in if case .path(let path) = layer { path } else { nil } }
        let line = try XCTUnwrap(paths.first { $0.stroke == FigureExport.markColor })
        XCTAssertEqual(line.points, [FigurePoint(x: 10.5 * k, y: 20.5 * k), FigurePoint(x: 110.5 * k, y: 20.5 * k)])
        let texts = scene.layers.compactMap { layer -> FigureText? in if case .text(let text) = layer { text } else { nil } }
        XCTAssertTrue(texts.contains { $0.string == "50.0 nm" && $0.color == FigureExport.markColor })
        let plan = try XCTUnwrap(ImageExport.scaleBarPlan(x: source().x, y: source().y, width: Self.w, height: Self.h))
        XCTAssertTrue(texts.contains { $0.string == plan.label && $0.color == .white })
        XCTAssertTrue(paths.contains { $0.fill == .white && abs(($0.points[1].x - $0.points[0].x) - plan.lengthPixels * k) < 1e-9 },
                      "the bar is the plan's length")
        XCTAssertTrue(texts.allSatisfy { ($0.size ?? scene.style.typeSize) >= 7 }, "no text under 7 pt")
    }

    /// The options leave out what they say, and an image without a scale has no bar and says so.
    /// Mutation: the marks drawn with Marks off, or a bar invented for an uncalibrated image - red.
    func testTheOptionsAndAnUncalibratedImage() throws {
        let bare = try FigureExport.scene(source: source(calibrated: false), display: display(), marks: [distance],
                                          options: ImageExport.Options(scaleBar: true, marks: false), width: .mm140)
        XCTAssertTrue(bare.barLeftOut)
        XCTAssertEqual(bare.scene.widthMM, 140)
        XCTAssertEqual(bare.scene.layers.count, 1, "the picture alone")
    }

    /// The PDF and the SVG carry the labels as text and the methods record as their metadata. Mutation: the labels drawn as
    /// outlines, or the record not handed to the renderer - red.
    func testThePDFAndTheSVGHoldTheLabelsAsText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("figure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = MethodsRecord(app: MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.4.0 (1)"), room: "image",
                                   exportKind: "image-figure-pdf", kits: [], sources: [], steps: [], drawn: ["scale bar", "marks"])
        let options = ImageExport.Options(scaleBar: true, marks: true)
        let plan = try XCTUnwrap(ImageExport.scaleBarPlan(x: source().x, y: source().y, width: Self.w, height: Self.h))

        let pdfURL = folder.appendingPathComponent("lattice.pdf")
        _ = try await FigureExport.export(source: source(), display: display(), marks: [distance], options: options, width: .mm90,
                                          format: .pdf, methods: record, to: pdfURL)
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("50.0 nm"), text)
        XCTAssertTrue(text.contains(plan.label), text)
        let subject = pdf.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String
        XCTAssertEqual(try subject.map { try MethodsRecord.decode($0) }, record)

        let svgURL = folder.appendingPathComponent("lattice.svg")
        _ = try await FigureExport.export(source: source(), display: display(), marks: [distance], options: options, width: .mm90,
                                          format: .svg, methods: record, to: svgURL)
        let svg = try String(contentsOf: svgURL, encoding: .utf8)
        XCTAssertTrue(svg.hasPrefix("<?xml") || svg.hasPrefix("<svg"), String(svg.prefix(80)))
        XCTAssertTrue(svg.contains(">50.0 nm<"))
        XCTAssertTrue(svg.contains(">\(plan.label)<"))
    }
}
