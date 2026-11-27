//
//  MapsFigure+Vector.swift
//  Role: the Maps room's map as a vector figure (#902, plan row X10): the map's picture at one pixel per point, the boundaries the
//        pane shows as lines over it, a vector scale bar on a plate at its bottom left and the key below (EMSuiteUI's
//        `FigurePlot.map`): a box per phase with its count, a colour ramp with the layer's range for a property or derived layer, and
//        for an IPF layer each phase's colour key as a picture with its corner labels as text. Written as PDF or SVG through
//        ShellExport's `FigureRenderer`, with the room's methods record. The PNG stays `MapsFigure.png`.
//

import Foundation
import ShellExport
import TEMCore
import TEMSession

nonisolated extension MapsFigure {
    /// The map as a figure `width` wide; throws when the layer has no picture.
    static func scene(_ input: MapInput, width: FigureStyle.Width) throws -> FigureScene {
        let raster = input.raster, layer = input.layer, map = input.map
        let picture: FigureRaster?
        if layer.isColour {
            picture = raster.rgba8.flatMap { onWhite(premultipliedRGBA: $0, width: raster.columns, height: raster.rows) }
        } else {
            picture = input.display.flatMap(FigureExport.raster)
        }
        guard let picture else { throw Failure(text: "The map has no picture to export.") }
        let style = FigureStyle(width: width)
        var bar: FigurePlot.ScaleBar?
        if map.dx > 0, picture.width > 0 {
            let length = niceLength(Double(picture.width) * map.dx)
            bar = FigurePlot.ScaleBar(lengthFraction: length / map.dx / Double(picture.width),
                                      label: scaleBarLabel(length: length, unit: map.scanUnit))
        }
        var scene = FigurePlot.map(picture, scaleBar: bar, key: key(input), style: style)
        // The boundaries over the picture, under the bar's plate: grain boundaries white, phase boundaries black, at the points' centres.
        let k = style.widthPoints / Double(picture.width)
        let lines = boundaryLayers(input.boundaries.grain, color: .white, pointsPerPoint: k)
            + boundaryLayers(input.boundaries.phase, color: .black, pointsPerPoint: k)
        scene.layers.insert(contentsOf: lines, at: 1)
        if case .ipf(let direction) = layer { appendIPFKeys(input.keys, direction: direction, to: &scene) }
        return scene
    }

    /// The figure's bytes, off the main actor: PDF or SVG with the software line and the methods record as its metadata.
    @concurrent nonisolated static func vector(_ input: MapInput, width: FigureStyle.Width, format: FigureExport.Format,
                                               software: String, methodsRecord: String? = nil) async throws -> Data {
        let made = try scene(input, width: width)
        return try FigureExport.data(made, format: format,
                                     metadata: FigureMetadata(title: input.fileName, creator: software, methodsRecord: methodsRecord))
    }

    /// The key below the map: phases by colour with their counts, a property's ramp, the grains' sentence; nil for an IPF layer,
    /// whose keys are pictures (`appendIPFKeys`).
    static func key(_ input: MapInput) -> FigurePlot.MapKey? {
        switch input.layer {
        case .ipf:
            return nil
        case .phase:
            let ids = input.map.phaseIDs
            return .entries(input.map.phasesInData.entries.map { id, phase in
                let rgb = phase.colorRGB ?? .zero
                let count = ids.reduce(0) { $0 + ($1 == id ? 1 : 0) }
                return FigureLegend.Entry("\(MapsRoomFormat.phaseName(phase, id: id)) · \(count)",
                                          swatch: .box(FigureColor(red: rgb.x, green: rgb.y, blue: rgb.z)))
            })
        case .derived(.grains):
            return .entries([FigureLegend.Entry("\(UnitDisplay.count(input.grainCount ?? 0, "grain", "grains")), each its own colour",
                                                swatch: .box(FigureColor(gray: 0.6))),
                             FigureLegend.Entry("below the smallest grain", swatch: .box(FigureColor(gray: 0.8)))])
        case .property(let name):
            return ramp(input, title: name)
        case .derived(let derived):
            return ramp(input, title: derived.unit.isEmpty ? derived.title : "\(derived.title) (\(derived.unit))")
        }
    }

    /// A property layer's colour ramp as the picture is drawn: sixteen steps across the display's window through its gamma and
    /// colormap (`ImageExport.rgb`, the shader's arithmetic), the window's raw values at its ends.
    static func ramp(_ input: MapInput, title: String) -> FigurePlot.MapKey? {
        guard let display = input.display, display.lut.count == 1024, display.high > display.low else { return nil }
        let raw = display.rawRange.map { (Double($0.lowerBound), Double($0.upperBound)) }
            ?? input.raster.valueRange.map { ($0.lowerBound, $0.upperBound) }
        guard let low = display.windowLow.map(Double.init) ?? raw?.0, let high = display.windowHigh.map(Double.init) ?? raw?.1 else { return nil }
        let colors = (0..<16).map { step -> FigureColor in
            let n = display.low + (display.high - display.low) * Float(step) / 15
            let (r, g, b) = ImageExport.rgb(n, low: display.low, high: display.high, gamma: display.gamma, lut: display.lut)
            return FigureColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
        let locale = ExportSnapshot.labelLocale
        return .ramp(colors: colors, low: UnitDisplay.number(low, digits: 4, locale: locale),
                     high: UnitDisplay.number(high, digits: 4, locale: locale), title: title)
    }

    /// The boundary edges at the points' centres (a point (x, y) at ((x + 0.5)·k, (y + 0.5)·k)), one line each.
    static func boundaryLayers(_ edges: [(SIMD2<Double>, SIMD2<Double>)], color: FigureColor, pointsPerPoint k: Double) -> [FigureLayer] {
        edges.map { a, b in
            .path(FigurePath(points: [FigurePoint(x: (a.x + 0.5) * k, y: (a.y + 0.5) * k), FigurePoint(x: (b.x + 0.5) * k, y: (b.y + 0.5) * k)],
                             stroke: color, lineWidth: 0.4))
        }
    }

    /// Each phase's IPF colour key below the figure, a third of its width, with its title and corner labels as text; inset by two
    /// type sizes, so a corner label centred on the key's edge ("[001]") stays on the page.
    static func appendIPFKeys(_ keys: [OrientationMapSession.PhaseKey], direction: SampleDirection, to scene: inout FigureScene) {
        let t = scene.style.typeSize, keyWidth = scene.widthPoints / 3, inset = 2 * t
        var top = scene.heightPoints + 1.8 * t
        for key in keys {
            guard let picture = onWhite(premultipliedRGBA: key.image.premultipliedRGBA8, width: key.image.width, height: key.image.height)
            else { continue }
            let keyHeight = keyWidth * Double(key.image.height) / Double(max(key.image.width, 1))
            scene.layers.append(.text(FigureText("\(key.name) · IPF-\(direction.rawValue.uppercased())", at: FigurePoint(x: 0, y: top - 0.5 * t))))
            scene.layers.append(.raster(picture, frame: FigureRect(x: inset, y: top, width: keyWidth, height: keyHeight)))
            for label in key.labels {
                let x = inset + label.column * keyWidth / Double(key.image.width), y = top + label.row * keyHeight / Double(key.image.height)
                scene.layers.append(.text(FigureText(label.text, at: FigurePoint(x: x, y: y + 1.2 * t), anchor: .middle)))
            }
            top += keyHeight + 3 * t
        }
        scene.heightMM = top / FigureScene.pointsPerMillimetre
    }

    /// Premultiplied RGBA over white, as RGB: what the PNG shows on its white page.
    static func onWhite(premultipliedRGBA rgba: [UInt8], width: Int, height: Int) -> FigureRaster? {
        guard width >= 1, height >= 1, rgba.count == width * height * 4 else { return nil }
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let clear = 255 - Int(rgba[i + 3])
            for c in 0..<3 { rgb.append(UInt8(min(255, Int(rgba[i + c]) + clear))) }
        }
        return FigureRaster(width: width, height: height, format: .rgb8, pixels: rgb)
    }
}
