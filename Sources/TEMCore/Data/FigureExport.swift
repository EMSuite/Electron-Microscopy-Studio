//
//  FigureExport.swift
//  Role: File > Export Figure… as a vector figure (#822, plan row X6): the Image room's image as EMSuiteUI's `FigureScene`, drawn
//        as a PDF with live text or an SVG by ShellExport's `FigureRenderer`. The picture is the display's own mapping (window,
//        gamma, colormap: `DisplayMapping`, the PNG's pixels) at its own pixels; the scale bar, the marks and their labels are
//        vectors over it at the style's type size (Helvetica 7 pt, nothing smaller), so a journal can scale the figure
//        without blurring a line or a letter. The figure is 90, 140 or 190 mm wide (one column, one and a half, two) and as tall
//        as the image's aspect makes it.
//
//        PNG stays `ImageExport`'s own drawing, byte for byte what Export Image… wrote before: the format picker chooses the
//        writer, never a second PNG renderer.
//
//        The scale bar is ImagoKit's plan (`ScaleBarMath`, the PNG's length and label), drawn as a white bar on the PNG's
//        translucent black plate at the bottom left; the marks are the Image room's yellow lines, a profile's band, a spot's
//        ring, each with its value beside it.
//

import Foundation
import ImagoCore
import ShellExport
import TEMSEM

package nonisolated enum FigureExport {
    /// What Export Figure… writes: a vector PDF or SVG, or the PNG Export Image… always wrote.
    package enum Format: String, Sendable, Equatable, CaseIterable {
        case pdf, svg, png

        /// "PDF", "SVG", "PNG": the panel's picker.
        package var title: String { rawValue.uppercased() }
        /// Whether the figure is drawn from a scene (PDF, SVG) rather than as the image's own pixels (PNG).
        package var isVector: Bool { self != .png }
    }

    /// The marks' yellow, as the Image room draws them (`ImageExport.drawMarks`).
    package static let markColor = FigureColor(red: 1, green: 0.8, blue: 0)
    /// The plate under the scale bar, as the PNG's.
    static let plateColor = FigureColor(gray: 0, alpha: 0.45)
    /// The bar's thickness, the plate's padding and its distance from the picture's edges, in points.
    static let barThickness = 1.5, platePadding = 3.0, plateMargin = 4.0
    /// The marks' line width and a spot's ring, in points.
    static let markLineWidth = 0.75, spotRing = 6.0

    /// The display's picture, each value through the display's mapping as the PNG maps it: RGB at the image's own pixels.
    package static func raster(_ display: ImageExport.Display) -> FigureRaster? {
        guard display.width >= 1, display.height >= 1, display.normalized.count == display.width * display.height,
              let mapping = DisplayMapping(low: display.low, high: display.high, gamma: display.gamma, lut: display.lut) else { return nil }
        var pixels = [UInt8]()
        pixels.reserveCapacity(display.normalized.count * 3)
        for value in display.normalized {
            let (r, g, b) = mapping.rgb(value)
            pixels.append(r); pixels.append(g); pixels.append(b)
        }
        return FigureRaster(width: display.width, height: display.height, format: .rgb8, pixels: pixels)
    }

    /// The figure of the image: its picture across the style's width, then the marks (when `options.marks`) and the scale bar
    /// (when `options.scaleBar` and the image is calibrated) as vectors. `barLeftOut` is true when the bar was asked for and the
    /// image has no scale for it. Throws `ExportFile.Failure.tooLarge` above `ImageExport.maximumSide`, as the PNG does.
    package static func scene(source: ExportSource, display: ImageExport.Display, marks: [ImageExport.Mark], options: ImageExport.Options,
                              width: FigureStyle.Width) throws -> (scene: FigureScene, barLeftOut: Bool) {
        guard display.width <= ImageExport.maximumSide, display.height <= ImageExport.maximumSide else {
            throw ExportFile.Failure.tooLarge(width: display.width, height: display.height)
        }
        guard let raster = raster(display) else { throw ExportFile.Failure.encodeFailed }
        let style = FigureStyle(width: width)
        // Points per image pixel: the picture fills the width.
        let k = style.widthPoints / Double(display.width)
        let height = Double(display.height) * k
        var layers: [FigureLayer] = [.raster(raster, frame: FigureRect(x: 0, y: 0, width: style.widthPoints, height: height))]
        if options.marks { layers += markLayers(marks, pointsPerPixel: k) }
        var barLeftOut = false
        if options.scaleBar {
            if let plan = ImageExport.scaleBarPlan(x: source.x, y: source.y, width: display.width, height: display.height) {
                layers += barLayers(plan, pointsPerPixel: k, height: height, typeSize: style.typeSize)
            } else {
                barLeftOut = true
            }
        }
        return (FigureScene(style: style, heightMM: height / FigureScene.pointsPerMillimetre, layers: layers), barLeftOut)
    }

    /// The marks in figure points: an image point (x, y) at ((x + 0.5)·k, (y + 0.5)·k), the centre of its pixel.
    static func markLayers(_ marks: [ImageExport.Mark], pointsPerPixel k: Double) -> [FigureLayer] {
        func point(_ p: ImagePoint) -> FigurePoint { FigurePoint(x: (p.x + 0.5) * k, y: (p.y + 0.5) * k) }
        var layers: [FigureLayer] = []
        for mark in marks where ImageExport.isDrawn(mark) {
            let points = mark.points.map(point)
            switch mark.kind {
            case .spot:
                layers.append(.markers(FigureMarkers(shape: .circle, centers: points, size: spotRing, stroke: markColor,
                                                     lineWidth: markLineWidth)))
            case .simulatedSpot:
                // A smaller cyan ring, as the room and the PNG draw a simulated spot.
                layers.append(.markers(FigureMarkers(shape: .circle, centers: points, size: spotRing * 5 / 7, stroke: simulatedColor,
                                                     lineWidth: markLineWidth)))
            case .profile where mark.width > 1:
                let dx = points[1].x - points[0].x, dy = points[1].y - points[0].y, length = (dx * dx + dy * dy).squareRoot()
                if length > 0 {
                    let half = Double(mark.width) * k / 2, nx = -dy / length * half, ny = dx / length * half
                    let band = [FigurePoint(x: points[0].x + nx, y: points[0].y + ny), FigurePoint(x: points[1].x + nx, y: points[1].y + ny),
                                FigurePoint(x: points[1].x - nx, y: points[1].y - ny), FigurePoint(x: points[0].x - nx, y: points[0].y - ny)]
                    layers.append(.path(FigurePath(points: band, closed: true, stroke: nil,
                                                   fill: FigureColor(red: 1, green: 0.8, blue: 0, alpha: 0.18))))
                }
                layers.append(.path(FigurePath(points: points, stroke: markColor, lineWidth: markLineWidth)))
            case .distance, .angle, .profile:
                layers.append(.path(FigurePath(points: points, stroke: markColor, lineWidth: markLineWidth)))
            case .ring:
                layers.append(.path(FigurePath(points: points, closed: true, stroke: markColor, lineWidth: markLineWidth)))
            case .annulus:
                layers.append(.path(FigurePath(points: points, closed: true, stroke: FigureColor(red: 1, green: 1, blue: 1, alpha: 0.8),
                                               lineWidth: markLineWidth)))
            }
            guard !mark.label.isEmpty else { continue }
            // The value beside the mark: at an angle's vertex, a line's middle, a spot's ring.
            let at: FigurePoint
            switch mark.kind {
            case .angle where points.count >= 3: at = points[1]
            case .spot, .simulatedSpot: at = FigurePoint(x: points[0].x + spotRing / 2, y: points[0].y - spotRing / 2)
            case .ring, .annulus: at = points[0]
            default: at = FigurePoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2)
            }
            layers.append(.text(FigureText(mark.label, at: FigurePoint(x: at.x + 2, y: at.y - 2), color: markColor)))
        }
        return layers
    }

    /// The bar `plan.lengthPixels` long at the bottom left, its label above it, on the PNG's plate.
    static func barLayers(_ plan: ScaleBarPlan, pointsPerPixel k: Double, height: Double, typeSize: Double) -> [FigureLayer] {
        let length = plan.lengthPixels * k
        // An estimate of the label's width (Helvetica's digits are 0.556 em) for the plate; the label itself is live text.
        let labelWidth = Double(plan.label.count) * 0.556 * typeSize
        let plateWidth = max(length, labelWidth) + 2 * platePadding
        let plateHeight = typeSize + 2 + barThickness + 2 * platePadding
        let plate = FigureRect(x: plateMargin, y: height - plateMargin - plateHeight, width: plateWidth, height: plateHeight)
        let barTop = plate.y + plate.height - platePadding - barThickness
        return [
            .path(.rectangle(plate, fill: plateColor)),
            .path(.rectangle(FigureRect(x: plate.x + platePadding, y: barTop, width: length, height: barThickness), fill: .white)),
            .text(FigureText(plan.label, at: FigurePoint(x: plate.x + platePadding, y: barTop - 2), color: .white)),
        ]
    }

    // MARK: - A diffraction pattern

    /// What the Diffraction room draws over its pattern, in image pixels (x the column, y the row, a pixel's centre at integers).
    package struct PatternOverlay: Sendable, Equatable {
        /// One measured ring (its fitted ellipse as a closed polyline) or spot, with the d (and family) the room's readout gives.
        package struct Measured: Sendable, Equatable {
            package var points: [ImagePoint]
            package var label: String

            package init(points: [ImagePoint], label: String) {
                self.points = points
                self.label = label
            }
        }

        package var centre: ImagePoint?
        package var rings: [Measured]
        package var spots: [Measured]
        /// The simulated spots of the typed zone axis or the orientation Index found.
        package var simulated: [ZoneAxisOverlay.Spot]
        /// Which of them carry their hkl: the room's `hkl labels` mode, placed in the figure's points so none overprints (#1053).
        package var labelMode: HKLLabelMode

        package init(centre: ImagePoint?, rings: [Measured], spots: [Measured], simulated: [ZoneAxisOverlay.Spot],
                     labelMode: HKLLabelMode) {
            self.centre = centre
            self.rings = rings
            self.spots = spots
            self.simulated = simulated
            self.labelMode = labelMode
        }
    }

    /// The room's colours: measured rings yellow, measured spots red, the simulated phase cyan, the centre white.
    package static let ringColor = markColor
    package static let spotColor = FigureColor(red: 1, green: 0.23, blue: 0.19)
    package static let simulatedColor = FigureColor(red: 0, green: 0.85, blue: 0.95)

    /// What a pattern's figure carries below its picture (#823, plan row X7): the legend of what is drawn (one row per kind of
    /// mark in the figure) and the readout as a table, one row per measured ring or spot.
    package struct PatternExtras: Sendable, Equatable {
        package var legend: Bool
        /// The table's rows, `tableHeader`'s columns each; empty leaves the table out.
        package var table: [[String]]

        package init(legend: Bool = false, table: [[String]] = []) {
            self.legend = legend
            self.table = table
        }
    }

    /// The spot table's columns: the readout's number, the family or hkl, d measured, d of the crystal's list, the misfit.
    package static let tableHeader = ["#", "hkl", "d (Å)", "d listed (Å)", "Δd/d (%)"]
    package static let tableAnchors: [FigureTextAnchor] = [.start, .start, .end, .end, .end]
    /// Column widths in points at 7 pt: wide enough for "99", "{113}" and "2.3550" at Helvetica's widest digits; they scale with the type.
    /// The number starts its column, so it never runs into the hkl that starts the next ("1{111}", #1148).
    package static func tableColumnWidths(typeSize: Double) -> [Double] { [16.0, 60, 40, 52, 44].map { $0 * typeSize / 7 } }

    /// One table row per readout row: its number, family, d, listed d and misfit, three decimals for d and two for the misfit
    /// (the readout's own), in the POSIX locale; a value the row lacks is left empty.
    package static func tableRows(_ rows: [DiffractionReadoutRow]) -> [[String]] {
        let posix = Locale(identifier: "en_US_POSIX")
        func number(_ value: Double?, _ digits: Int) -> String {
            value.map { String(format: "%.\(digits)f", locale: posix, $0) } ?? ""
        }
        return rows.map { row in
            ["\(row.number)", row.family ?? "", number(row.d, 3), number(row.dListed, 3), number(row.deltaPercent, 2)]
        }
    }

    /// The legend's rows for what `overlay` draws, in the order it is drawn: measured rings, measured spots, simulated spots.
    package static func legendEntries(_ overlay: PatternOverlay) -> [FigureLegend.Entry] {
        var entries: [FigureLegend.Entry] = []
        if overlay.rings.contains(where: { $0.points.count >= 3 }) { entries.append(.init("Measured ring", swatch: .line(ringColor))) }
        if overlay.spots.contains(where: { $0.points.count == 1 }) {
            entries.append(.init("Measured spot", swatch: .marker(.cross, stroke: spotColor, fill: nil)))
        }
        if !overlay.simulated.isEmpty {
            entries.append(.init("Simulated spot", swatch: .marker(.circle, stroke: simulatedColor, fill: nil)))
        }
        return entries
    }

    /// The legend and the table under the picture, each a type size apart; the scene grows to hold them.
    static func addExtras(_ extras: PatternExtras, overlay: PatternOverlay, to scene: inout FigureScene) {
        let typeSize = scene.style.typeSize, rowHeight = FigureTable.rowHeightFactor * typeSize
        var bottom = scene.heightPoints
        let entries = extras.legend ? legendEntries(overlay) : []
        if !entries.isEmpty {
            bottom += typeSize
            scene.layers.append(.legend(FigureLegend(origin: FigurePoint(x: 0, y: bottom), entries: entries)))
            bottom += Double(entries.count) * rowHeight
        }
        if !extras.table.isEmpty {
            bottom += typeSize
            scene.layers.append(.table(FigureTable(origin: FigurePoint(x: 0, y: bottom), columnWidths: tableColumnWidths(typeSize: typeSize),
                                                   anchors: tableAnchors, header: tableHeader, rows: extras.table)))
            bottom += Double(extras.table.count + 1) * rowHeight
        }
        scene.heightMM = bottom / FigureScene.pointsPerMillimetre
    }

    /// The figure of a pattern: the picture across the style's width, then (with `labels`) the measured rings and spots with their
    /// d, the simulated spots as one marker shape per phase (rings for the simulation, crosses for what was measured) with their
    /// hkl, the centre, and the scale bar in the room's reciprocal units (`source`'s axes). `barLeftOut` as for an image. `extras` adds the
    /// legend and the spot table under the picture.
    package static func patternScene(source: ExportSource, display: ImageExport.Display, overlay: PatternOverlay, scaleBar: Bool, labels: Bool,
                                     width: FigureStyle.Width, extras: PatternExtras = PatternExtras()) throws -> (scene: FigureScene, barLeftOut: Bool) {
        var made = try scene(source: source, display: display, marks: [], options: ImageExport.Options(scaleBar: false, marks: false),
                             width: width)
        let k = made.scene.widthPoints / Double(display.width)
        func point(_ p: ImagePoint) -> FigurePoint { FigurePoint(x: (p.x + 0.5) * k, y: (p.y + 0.5) * k) }
        var layers: [FigureLayer] = []
        for ring in overlay.rings where ring.points.count >= 3 {
            layers.append(.path(FigurePath(points: ring.points.map(point), closed: true, stroke: ringColor, lineWidth: markLineWidth)))
            if labels, !ring.label.isEmpty, let first = ring.points.first {
                let at = point(first)
                layers.append(.text(FigureText(ring.label, at: FigurePoint(x: at.x + 3, y: at.y - 3), color: .white)))
            }
        }
        let spots = overlay.spots.filter { $0.points.count == 1 }
        if !spots.isEmpty {
            layers.append(.markers(FigureMarkers(shape: .cross, centers: spots.map { point($0.points[0]) }, size: spotRing, stroke: spotColor,
                                                 lineWidth: markLineWidth)))
        }
        if labels {
            for spot in spots where !spot.label.isEmpty {
                let at = point(spot.points[0])
                layers.append(.text(FigureText(spot.label, at: FigurePoint(x: at.x + spotRing / 2 + 1, y: at.y - 2), color: .white)))
            }
        }
        for spot in overlay.simulated {
            // A ring 3 to 9 points across, by the square root of its intensity as the room draws it; double diffraction the smallest.
            let size = 3 + 6 * spot.relative.squareRoot()
            layers.append(.markers(FigureMarkers(shape: .circle, centers: [point(ImagePoint(x: spot.column, y: spot.row))], size: size,
                                                 stroke: simulatedColor, lineWidth: markLineWidth)))
        }
        if labels {
            // The room's placement (#1053), in the figure's points and type size: the mode's spots, strongest first, each where its
            // box meets no other label and not the centre's mark.
            let typeSize = made.scene.style.typeSize, fontScale = typeSize / HKLLabelPlacement.captionSize
            func vector(_ p: FigurePoint) -> SIMD2<Double> { SIMD2(p.x, p.y) }
            let placed = HKLLabelPlacement.place(
                overlay.simulated, mode: overlay.labelMode,
                point: { vector(point(ImagePoint(x: $0.column, y: $0.row))) },
                radius: { (3 + 6 * $0.relative.squareRoot()) / 2 }, beam: overlay.centre.map { vector(point($0)) },
                labelSize: { HKLLabelPlacement.estimatedLabelSize($0) * fontScale })
            for label in placed {
                layers.append(.text(FigureText(label.spot.label, at: FigurePoint(x: label.low.x, y: label.low.y + typeSize),
                                               color: simulatedColor)))
            }
        }
        if let centre = overlay.centre {
            layers.append(.markers(FigureMarkers(shape: .plus, centers: [point(centre)], size: 8, stroke: .white, lineWidth: markLineWidth)))
        }
        if scaleBar {
            if let plan = ImageExport.scaleBarPlan(x: source.x, y: source.y, width: display.width, height: display.height) {
                layers += barLayers(plan, pointsPerPixel: k, height: made.scene.heightPoints, typeSize: made.scene.style.typeSize)
            } else {
                made.barLeftOut = true
            }
        }
        made.scene.layers += layers
        addExtras(extras, overlay: overlay, to: &made.scene)
        return made
    }

    /// The scene as the file `format` names (PDF or SVG), with its title, software line and methods record.
    package static func data(_ scene: FigureScene, format: Format, metadata: FigureMetadata) throws -> Data {
        switch format {
        case .pdf: return try FigureRenderer.pdf(scene, metadata: metadata)
        case .svg: return Data(FigureRenderer.svg(scene, metadata: metadata).utf8)
        case .png: return try FigureRenderer.png(scene, scale: 300 / 72, metadata: metadata)
        }
    }

    /// A pattern's scene, file and write, off the main actor; PNG is the figure at 300 dpi.
    @concurrent package static func exportPattern(source: ExportSource, display: ImageExport.Display, overlay: PatternOverlay, scaleBar: Bool,
                                                  labels: Bool, width: FigureStyle.Width, extras: PatternExtras = PatternExtras(),
                                                  format: Format, methods: MethodsRecord?,
                                                  to url: URL) async throws -> (scene: FigureScene, barLeftOut: Bool) {
        let made = try patternScene(source: source, display: display, overlay: overlay, scaleBar: scaleBar, labels: labels, width: width,
                                    extras: extras)
        let metadata = FigureMetadata(title: source.fileName, creator: source.software, methodsRecord: try methods?.json())
        try ExportFile.write(try data(made.scene, format: format, metadata: metadata), to: url)
        return made
    }

    /// The pattern's figure as PDF and PNG, for the clipboard (Copy Figure) and a drag: the same scene Export Figure… writes, PDF
    /// first so a vector-aware app takes it, PNG at 300 dpi for the rest. Off the main actor.
    @concurrent package static func patternClipboard(source: ExportSource, display: ImageExport.Display, overlay: PatternOverlay,
                                                     scaleBar: Bool, labels: Bool, width: FigureStyle.Width, extras: PatternExtras,
                                                     methods: MethodsRecord?) async throws -> (pdf: Data, png: Data) {
        let made = try patternScene(source: source, display: display, overlay: overlay, scaleBar: scaleBar, labels: labels, width: width,
                                    extras: extras)
        let metadata = FigureMetadata(title: source.fileName, creator: source.software, methodsRecord: try methods?.json())
        return (try data(made.scene, format: .pdf, metadata: metadata), try data(made.scene, format: .png, metadata: metadata))
    }

    /// Scene, file and write, off the main actor (a 4096² picture is 48 MB of RGB).
    @concurrent package static func export(source: ExportSource, display: ImageExport.Display, marks: [ImageExport.Mark],
                                           options: ImageExport.Options, width: FigureStyle.Width, format: Format,
                                           methods: MethodsRecord?, to url: URL) async throws -> (scene: FigureScene, barLeftOut: Bool) {
        let made = try scene(source: source, display: display, marks: marks, options: options, width: width)
        let metadata = FigureMetadata(title: source.fileName, creator: source.software, methodsRecord: try methods?.json())
        try ExportFile.write(try data(made.scene, format: format, metadata: metadata), to: url)
        return made
    }
}
