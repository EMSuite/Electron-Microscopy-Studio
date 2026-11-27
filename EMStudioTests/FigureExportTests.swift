//
//  FigureExportTests.swift
//  Export Figure… as a vector figure (#822, plan row X6; `FigureExport`): the Image room's image drawn as EMSuiteUI's figure scene
//  at a journal width, its picture the display's own mapping at the image's pixels, the marks and the scale bar as lines and
//  live text over it. PDFKit finds every label as text in the PDF, the SVG holds them as <text>, and a figure of an image
//  without a scale says the bar was left out. The PNG is untouched: Export Figure…'s PNG is `ImageExport`'s, the file Export
//  Image… wrote (`ImageExportRenderTests` pins it).
//  In the Diffraction room the figure is the pattern on screen: the measured rings and spots, the simulated spots with their hkl,
//  the centre and a bar in Å⁻¹ (`FigureExport.patternScene`, `DiffractionFigureSnapshot`).
//  Red before: `FigureExport` did not exist; Export Image… wrote PNG only, and the Diffraction room had no figure.
//  A figure carries its key and spot table (#823, plan row X7): the legend's rows for the marks drawn, the readout as a table under
//  the picture, the scene grown to hold them, and Copy Figure's PDF and PNG of the same scene.
//  Red before: the pattern's scene had no legend or table, and nothing drew a figure for the clipboard.
//

import DiffractoCore
import Foundation
import ImageIO
import ImagoCore
import PDFKit
import ShellExport
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

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

    /// The options leave out what they say, and an image without a scale gets the PNG's bar in pixels.
    /// Mutation: the marks or the bar drawn with their option off, or the figure's bar not the PNG's for an uncalibrated image - red.
    func testTheOptionsAndAnUncalibratedImage() throws {
        let bare = try FigureExport.scene(source: source(calibrated: false), display: display(), marks: [distance],
                                          options: ImageExport.Options(scaleBar: false, marks: false), width: .mm140)
        XCTAssertFalse(bare.barLeftOut)
        XCTAssertEqual(bare.scene.widthMM, 140)
        XCTAssertEqual(bare.scene.layers.count, 1, "the picture alone")

        let pixels = try FigureExport.scene(source: source(calibrated: false), display: display(), marks: [],
                                            options: ImageExport.Options(scaleBar: true, marks: false), width: .mm140)
        let plan = try XCTUnwrap(ImageExport.scaleBarPlan(x: nil, y: nil, width: Self.w, height: Self.h))
        XCTAssertEqual(plan.unit, "px")
        XCTAssertFalse(pixels.barLeftOut)
        let texts = pixels.scene.layers.compactMap { layer -> FigureText? in if case .text(let text) = layer { text } else { nil } }
        XCTAssertEqual(texts.map(\.string), [plan.label], "the PNG's bar, in pixels")
    }

    /// A pattern's figure: the rings closed yellow paths, the measured spots red crosses, the simulated spots cyan rings with
    /// their hkl, the centre a plus, the bar in Å⁻¹, and without Labels no text but the bar's. Mutation: a ring left open, the
    /// phases drawn in one shape, an hkl drawn with Labels off, or the bar not in the room's units - red.
    func testAPatternFigureDrawsEachPhaseInItsShapeWithItsLabels() throws {
        let ring = FigureExport.PatternOverlay.Measured(points: (0..<12).map { i in
            let a = Double(i) / 12 * 2 * .pi
            return ImagePoint(x: 256 + 80 * cos(a), y: 128 + 80 * sin(a))
        }, label: "d 2.355 Å · {111}")
        let spot = FigureExport.PatternOverlay.Measured(points: [ImagePoint(x: 300, y: 100)], label: "d 2.039 Å")
        let simulated = [ZoneAxisOverlay.Spot(hkl: MillerIndex(2, 0, 0), row: 128, column: 340, intensity: 1, relative: 1),
                         ZoneAxisOverlay.Spot(hkl: MillerIndex(0, 2, 0), row: 44, column: 256, intensity: 0.5, relative: 0.5)]
        let overlay = FigureExport.PatternOverlay(centre: ImagePoint(x: 256, y: 128), rings: [ring], spots: [spot], simulated: simulated,
                                                  labelMode: .all)
        var pattern = source()
        pattern.x = AxisCalibration(scale: 0.0125, unit: "Å⁻¹", origin: 256)
        pattern.y = AxisCalibration(scale: 0.0125, unit: "Å⁻¹", origin: 128)

        let made = try FigureExport.patternScene(source: pattern, display: display(), overlay: overlay, scaleBar: true, labels: true, width: .mm90)
        let layers = made.scene.layers
        let paths = layers.compactMap { layer -> FigurePath? in if case .path(let path) = layer { path } else { nil } }
        XCTAssertTrue(paths.contains { $0.closed && $0.stroke == FigureExport.ringColor && $0.points.count == 12 }, "the ring")
        let markers = layers.compactMap { layer -> FigureMarkers? in if case .markers(let m) = layer { m } else { nil } }
        XCTAssertEqual(markers.filter { $0.shape == .cross }.map(\.stroke), [FigureExport.spotColor], "the measured spot")
        XCTAssertEqual(markers.filter { $0.shape == .circle }.count, 2, "the simulated phase, one ring a spot")
        XCTAssertTrue(markers.allSatisfy { $0.shape != .circle || $0.stroke == FigureExport.simulatedColor })
        XCTAssertEqual(markers.filter { $0.shape == .plus }.count, 1, "the centre")
        let texts = layers.compactMap { layer -> String? in if case .text(let text) = layer { text.string } else { nil } }
        XCTAssertTrue(texts.contains("d 2.355 Å · {111}"))
        XCTAssertTrue(texts.contains("d 2.039 Å"))
        XCTAssertTrue(texts.contains(simulated[0].label))
        XCTAssertTrue(texts.contains(simulated[1].label))
        let plan = try XCTUnwrap(ImageExport.scaleBarPlan(x: pattern.x, y: pattern.y, width: Self.w, height: Self.h))
        XCTAssertTrue(plan.label.contains("Å"), plan.label)
        XCTAssertTrue(texts.contains(plan.label))

        let bare = try FigureExport.patternScene(source: pattern, display: display(), overlay: overlay, scaleBar: true, labels: false, width: .mm90)
        let bareTexts = bare.scene.layers.compactMap { layer -> String? in if case .text(let text) = layer { text.string } else { nil } }
        XCTAssertEqual(bareTexts, [plan.label], "Labels off: the bar's label alone")
    }

    /// #1053: the figure's hkl labels follow the room's mode and never overprint. A row of 40 spots 6 px apart: None draws no hkl,
    /// Strongest at most `strongestCap`, All more, and no two of the label boxes meet. Mutation: the 60-strongest rule back, the
    /// mode ignored, or the labels drawn at a fixed offset with no placement - red.
    func testAPatternFiguresHKLLabelsFollowTheModeAndNeverMeet() throws {
        var simulated: [ZoneAxisOverlay.Spot] = []
        for i in 0..<40 {
            let strength = Double(40 - i)
            let column = 20.0 + 6.0 * Double(i)
            simulated.append(ZoneAxisOverlay.Spot(hkl: MillerIndex(i + 1, 0, 0), row: 128, column: column, intensity: strength,
                                                  relative: strength / 40))
        }
        let labels = Set(simulated.map { (spot: ZoneAxisOverlay.Spot) -> String in spot.label })
        func hklTexts(_ mode: HKLLabelMode) throws -> [FigureText] {
            let overlay = FigureExport.PatternOverlay(centre: nil, rings: [], spots: [], simulated: simulated, labelMode: mode)
            let made = try FigureExport.patternScene(source: source(), display: display(), overlay: overlay, scaleBar: false, labels: true,
                                                     width: .mm90)
            return made.scene.layers.compactMap { layer -> FigureText? in
                if case .text(let text) = layer, labels.contains(text.string) { text } else { nil }
            }
        }
        XCTAssertTrue(try hklTexts(.off).isEmpty)
        let strongest = try hklTexts(.strongest), all = try hklTexts(.all)
        XCTAssertFalse(strongest.isEmpty)
        XCTAssertLessThanOrEqual(strongest.count, HKLLabelPlacement.strongestCap)
        XCTAssertEqual(strongest.first?.string, simulated[0].label, "the strongest is always named")
        XCTAssertGreaterThanOrEqual(all.count, strongest.count)
        XCTAssertLessThan(all.count, simulated.count, "6 px apart, not every label has room")
        for texts in [strongest, all] {
            let typeSize: Double = FigureStyle(width: .mm90).typeSize
            let scale: Double = typeSize / HKLLabelPlacement.captionSize
            let boxes = texts.map { (t: FigureText) -> (low: SIMD2<Double>, high: SIMD2<Double>) in
                let low = SIMD2<Double>(Double(t.origin.x), Double(t.origin.y) - typeSize)
                let size: SIMD2<Double> = HKLLabelPlacement.estimatedLabelSize(t.string) * scale
                return (low: low, high: low + size)
            }
            for i in boxes.indices { for j in boxes.indices where j > i { XCTAssertFalse(HKLLabelPlacement.meet(boxes[i], boxes[j])) } }
        }
    }

    /// The legend keys what is drawn and only that, the table is the readout's rows in the POSIX locale, and both sit under the
    /// picture in a scene grown to hold them. Mutation: an entry for a kind not drawn, the table's d in the person's locale, or the
    /// scene's height left the picture's - red.
    func testAPatternFigureCarriesItsLegendAndSpotTable() throws {
        let spot = FigureExport.PatternOverlay.Measured(points: [ImagePoint(x: 300, y: 100)], label: "d 2.039 Å")
        let simulated = [ZoneAxisOverlay.Spot(hkl: MillerIndex(2, 0, 0), row: 128, column: 340, intensity: 1, relative: 1)]
        let overlay = FigureExport.PatternOverlay(centre: nil, rings: [], spots: [spot], simulated: simulated, labelMode: .off)
        XCTAssertEqual(FigureExport.legendEntries(overlay).map(\.label), ["Measured spot", "Simulated spot"], "no ring drawn, none keyed")

        let readout = [DiffractionReadoutRow(id: UUID(), kind: .spot, number: 1, radiusPx: 82.1, q: 1.0262, d: 0.97448, family: "{200}",
                                             dListed: 0.97, deltaPercent: 0.4618, oddsText: nil, verdict: "accepted", validation: ""),
                       DiffractionReadoutRow(id: UUID(), kind: .ring, number: 2, radiusPx: nil, q: nil, d: nil, family: nil, dListed: nil,
                                             deltaPercent: nil, oddsText: nil, verdict: "no ring", validation: "")]
        let rows = FigureExport.tableRows(readout)
        XCTAssertEqual(rows, [["1", "{200}", "0.974", "0.970", "0.46"], ["2", "", "", "", ""]])

        let plain = try FigureExport.patternScene(source: source(), display: display(), overlay: overlay, scaleBar: false, labels: false,
                                                  width: .mm90)
        let full = try FigureExport.patternScene(source: source(), display: display(), overlay: overlay, scaleBar: false, labels: false,
                                                 width: .mm90, extras: FigureExport.PatternExtras(legend: true, table: rows))
        let legends = full.scene.layers.compactMap { layer -> FigureLegend? in if case .legend(let l) = layer { l } else { nil } }
        let tables = full.scene.layers.compactMap { layer -> FigureTable? in if case .table(let t) = layer { t } else { nil } }
        XCTAssertEqual(legends.map { $0.entries.count }, [2])
        XCTAssertEqual(tables.map(\.header), [FigureExport.tableHeader])
        XCTAssertEqual(tables.first?.rows, rows)
        let picture = plain.scene.heightPoints, type = full.scene.style.typeSize, row = FigureTable.rowHeightFactor * type
        XCTAssertEqual(legends.first?.origin.y ?? 0, picture + type, accuracy: 1e-9, "under the picture")
        XCTAssertEqual(full.scene.heightPoints, picture + type + 2 * row + type + 3 * row, accuracy: 1e-9, "grown to hold both")
        XCTAssertFalse(plain.scene.layers.contains { if case .legend = $0 { true } else if case .table = $0 { true } else { false } })
    }

    /// An indexed pattern's figure tabulates and labels Index's answer, not the ring readout's nearest family (#1148, nanowire demo:
    /// 7 of 29 spots disagreed): an explained spot takes Index's hkl, d, expected d and misfit; an unexplained one is blank though
    /// the readout named a family; a ring keeps the readout's. The number starts its column so "1" and "{111}" never run together.
    /// Red before: the figure took `readout` alone. Mutation: unexplained spots keep the readout's family; Index's d left out.
    func testAnIndexedFigureTakesIndexsRows() {
        let explained = UUID(), unexplained = UUID(), ring = UUID()
        let readout = [
            DiffractionReadoutRow(id: ring, kind: .ring, number: 1, radiusPx: 40, q: 0.3, d: 3.3, family: "{111}", dListed: 3.26,
                                  deltaPercent: 1.2, oddsText: nil, verdict: "accepted", validation: ""),
            DiffractionReadoutRow(id: explained, kind: .spot, number: 1, radiusPx: 50, q: 0.36, d: 2.78, family: "{200}", dListed: 2.83,
                                  deltaPercent: -1.8, oddsText: "odds", verdict: "accepted", validation: ""),
            DiffractionReadoutRow(id: unexplained, kind: .spot, number: 2, radiusPx: 60, q: 0.45, d: 2.2, family: "{220}", dListed: 2.0,
                                  deltaPercent: -1.37, oddsText: nil, verdict: "accepted", validation: "")]
        let index = [
            PatternIndexing.SpotRow(id: explained, number: 1, hkl: MillerIndex(-1, -1, 1), radiusPx: 50, q: 0.3, d: 3.42, dExpected: 3.26,
                                    deltaPercent: 4.86, phase: "GaAs"),
            PatternIndexing.SpotRow(id: unexplained, number: 2, hkl: nil, radiusPx: 60, q: 0.45, d: 2.21, dExpected: nil,
                                    deltaPercent: nil, phase: "")]
        let rows = DiffractionReadoutRow.takingIndex(readout, spots: index)
        XCTAssertEqual(rows[0], readout[0], "a ring keeps the readout")
        XCTAssertEqual(rows[1].family, ZoneAxisText.label(MillerIndex(-1, -1, 1)))
        XCTAssertEqual(rows[1].d, 3.42)
        XCTAssertEqual(rows[1].dListed, 3.26)
        XCTAssertEqual(rows[1].deltaPercent, 4.86)
        XCTAssertNil(rows[2].family, "Index left it unexplained")
        XCTAssertNil(rows[2].dListed)
        XCTAssertNil(rows[2].deltaPercent)
        XCTAssertEqual(FigureExport.tableRows(rows)[2], ["2", "", "2.210", "", ""])
        XCTAssertEqual(Array(FigureExport.tableAnchors.prefix(2)), [FigureTextAnchor.start, .start], "the number and the hkl both start their columns")
    }

    /// The Diffraction room's snapshot is the pattern on screen as the room displays it, with the room's scale on its axes.
    /// Mutation: the snapshot taken outside the room, or the axes left the file's - red.
    @MainActor func testTheDiffractionRoomsSnapshotIsThePatternOnScreen() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.diffraction)?.value
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        await item.diffractionView.show(image: image, generation: item.session.generation, analysis: item.diffraction)
        state.navigation.workspaceArea = .image
        XCTAssertNil(ExportSnapshot.diffractionFigureSnapshot(of: state), "the Image room has its own figure")
        state.navigation.workspaceArea = .diffraction
        XCTAssertTrue(ExportSnapshot.diffractionFigureAvailable(in: state))
        let snapshot = try XCTUnwrap(ExportSnapshot.diffractionFigureSnapshot(of: state))
        XCTAssertEqual(snapshot.display.width, image.width)
        XCTAssertEqual(snapshot.display.height, image.height)
        if let deltaQ = item.diffraction.exportHeader(image: image).deltaQ {
            XCTAssertEqual(snapshot.source.x?.unit, "Å⁻¹")
            XCTAssertEqual(snapshot.source.x?.scale, deltaQ)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pattern-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await snapshot.write(to: url, format: .pdf, width: .mm90, scaleBar: true, labels: true)
        XCTAssertNotNil(PDFDocument(url: url))

        // Copy Figure's two types and the door's PNG: the same figure, its table with the readout's rows (#823).
        XCTAssertEqual(snapshot.table, FigureExport.tableRows(item.diffraction.figureReadout(image: image)))
        let pictures = try await snapshot.pictures()
        let copied = try XCTUnwrap(PDFDocument(data: pictures.pdf))
        if !snapshot.table.isEmpty { XCTAssertTrue(copied.string?.contains("d listed (Å)") == true, copied.string ?? "") }
        let png = try XCTUnwrap(CGImageSourceCreateWithData(pictures.png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        XCTAssertEqual(Double(png.width), FigureStyle.Width.mm90.rawValue / 25.4 * 300, accuracy: 2, "90 mm at 300 dpi")
        XCTAssertEqual(try snapshot.png().count > 0, true)
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
