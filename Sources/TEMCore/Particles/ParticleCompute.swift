// The Particles view's compute, on ImagoKit: Gaussian smoothing (`SeparableFilters.gaussianFilter`), a threshold on the raw range,
// connected-component labelling (`Segmentation.label`) and the objects' moments (`Segmentation.objectMoments`). Nothing here is a
// number of macTEM's own: the threshold is `Thresholding.level` (a fraction of the raw range) or `Thresholding.otsu`, the compare is
// `.mask`, objects below the minimum area are removed from the mask by `BinaryMorphology.removeSmallObjects`, the summary (counts, a median
// and a mean of the kit's lengths and widths, the Miles–Lantuéjoul areal density) is `ObjectStatistics.arealDensity`, and the labels and
// every length, width, angle and centroid are ImagoKit's.
import Foundation
import ImagoCore
import ImagoFilters

package nonisolated struct ParticleSettings: Equatable, Sendable {
    package enum Polarity: String, Sendable, CaseIterable, Identifiable {
        case bright, dark
        package var id: String { rawValue }
        package var title: String { self == .bright ? "Bright" : "Dark" }
    }

    /// How the threshold is chosen: the slider's fraction of the range, or Otsu's level of the pixels the objects are cut from.
    package enum Method: String, Sendable, CaseIterable, Identifiable {
        case manual, otsu
        package var id: String { rawValue }
        package var title: String { self == .manual ? "Manual" : "Otsu" }
    }

    package var polarity: Polarity = .bright
    package var method: Method = .manual
    /// The threshold as a fraction of the raw finite range: 0 is the minimum, 1 the maximum (`.manual` only).
    package var thresholdFraction = 0.5
    /// Gaussian smoothing before the threshold, in pixels; 0 is none.
    package var sigma = 0.0
    package var connectivity: Segmentation.Connectivity = .eight
    /// An object of fewer pixels is removed from the mask before the objects are labelled.
    package var minimumArea = 4
    /// The region to analyse (#110, ImageJ's rectangle selection): only its pixels are labelled, an object cut by its border is an edge
    /// object, Otsu's level is of its pixels and the areal density is per its area. nil is the whole image. The manual level stays a
    /// fraction of the WHOLE image's raw range, the range the Level slider shows.
    package var region: PixelCrop?
    package init() {}
}

package nonisolated struct ParticleObject: Equatable, Sendable, Identifiable {
    /// ImagoKit's moments, measured in the region analysed (its top-left pixel is 0, 0).
    package let moments: Segmentation.ObjectMoments
    /// The region's top-left pixel in the image (0, 0 for the whole image): what `centroidCol` and `centroidRow` add.
    package let originCol: Int
    package let originRow: Int
    package init(moments: Segmentation.ObjectMoments, originCol: Int = 0, originRow: Int = 0) {
        self.moments = moments; self.originCol = originCol; self.originRow = originRow
    }
    package var id: Int32 { moments.label }
    /// The centroid in IMAGE pixels.
    package var centroidCol: Double { moments.centroidCol + Double(originCol) }
    package var centroidRow: Double { moments.centroidRow + Double(originRow) }
    package var touchesEdge: Bool { moments.touchesEdge }
    /// Counted in the statistics: not on the image edge (cut by it). Objects below the minimum area are not objects.
    package var isCounted: Bool { !touchesEdge }
}

package nonisolated struct ParticleSummary: Equatable, Sendable {
    /// The objects found, and the small ones removed: `counted + edge + small`.
    package var total = 0
    package var counted = 0
    /// Touching the image edge, or the region's border (whatever their size).
    package var edge = 0
    /// Below the minimum area, removed from the mask (not listed).
    package var small = 0
    /// Over the counted objects, in pixels; nil with none.
    package var medianLengthPx: Double?
    package var meanWidthPx: Double?
    /// Counted objects per unit area of the scale's unit, edge-corrected (Miles–Lantuéjoul); nil when the image is not calibrated.
    package var arealDensity: Double?
    package init() {}
}

package nonisolated struct ParticleReport: Equatable, Sendable {
    package let settings: ParticleSettings
    package let width: Int
    package let height: Int
    /// The raw value the threshold fraction stood for.
    package let thresholdValue: Float
    package let objects: [ParticleObject]
    package let summary: ParticleSummary
    /// The image's size, zero outside the region analysed.
    package let labels: Segmentation.LabelImage
}

/// The region to analyse as pixels (pure): the rectangle a drag covers, and the region held to an image.
package nonisolated enum ParticleRegion {
    /// The pixels a drag from `a` to `b` covers (image coordinates, a pixel's centre at whole numbers), held to the image; nil when
    /// it is under 2 pixels either way (a click is not a region).
    package static func drawn(from a: ImagePoint, to b: ImagePoint, width: Int, height: Int) -> PixelCrop? {
        guard width > 0, height > 0 else { return nil }
        func index(_ v: Double, _ n: Int) -> Int { min(max(Int(v.rounded()), 0), n - 1) }
        let c0 = index(min(a.x, b.x), width), c1 = index(max(a.x, b.x), width)
        let r0 = index(min(a.y, b.y), height), r1 = index(max(a.y, b.y), height)
        guard c1 - c0 + 1 >= 2, r1 - r0 + 1 >= 2 else { return nil }
        return PixelCrop(row: r0, col: c0, height: r1 - r0 + 1, width: c1 - c0 + 1)
    }

    /// `region` held to a `width` × `height` image; nil (the whole image) when there is none, or nothing of it is on the image,
    /// or it covers the whole image.
    package static func clamped(_ region: PixelCrop?, width: Int, height: Int) -> PixelCrop? {
        guard let region else { return nil }
        let c0 = max(region.col, 0), r0 = max(region.row, 0)
        let c1 = min(region.col + region.width, width), r1 = min(region.row + region.height, height)
        guard c1 > c0, r1 > r0 else { return nil }
        if c0 == 0, r0 == 0, c1 == width, r1 == height { return nil }
        return PixelCrop(row: r0, col: c0, height: r1 - r0, width: c1 - c0)
    }

    /// "x 10, y 20 · 500 × 400 px", or "Whole image".
    package static func text(_ region: PixelCrop?) -> String {
        guard let r = region else { return "Whole image" }
        return "x \(r.col), y \(r.row) · \(r.width) × \(r.height) px"
    }

    /// The values of `values` (row-major, `width` wide) inside `region`.
    package static func crop<T>(_ values: [T], width: Int, to region: PixelCrop) -> [T] {
        var out: [T] = []
        out.reserveCapacity(region.width * region.height)
        for row in region.row..<(region.row + region.height) {
            let start = row * width + region.col
            out.append(contentsOf: values[start..<(start + region.width)])
        }
        return out
    }
}

/// A pixel size for lengths: units per pixel, and the unit ("px" when the image is not calibrated or its pixels are not square).
package nonisolated struct ParticleScale: Equatable, Sendable {
    package let perPixel: Double
    package let unit: String
    package init(perPixel: Double, unit: String) { self.perPixel = perPixel; self.unit = unit }
    package var isCalibrated: Bool { unit != "px" }
}

package nonisolated enum ParticleError: Error, Equatable, LocalizedError {
    case noFiniteValues
    package var errorDescription: String? { "The image holds no finite value to threshold." }
}

package nonisolated enum ParticleCompute {
    /// The raw finite range of `pixels`; nil when none is finite.
    package static func range(_ pixels: [Float]) -> ClosedRange<Float>? {
        var lo = Float.infinity, hi = -Float.infinity
        for v in pixels where v.isFinite { lo = min(lo, v); hi = max(hi, v) }
        return lo <= hi ? lo...hi : nil
    }

    /// The pixels the objects are cut from: smoothed when sigma > 0 (a non-finite pixel is read as the range's low end first).
    package static func smoothed(_ pixels: [Float], width: Int, height: Int, sigma: Double, low: Float) throws -> [Float] {
        guard sigma > 0 else { return pixels }
        let clean = pixels.map { $0.isFinite ? $0 : low }
        return try SeparableFilters.gaussianFilter(clean, rows: height, columns: width, sigma: (row: sigma, column: sigma))
    }

    /// `true` where the (smoothed) pixel is on the object side of the threshold. The manual level is a fraction of the raw range;
    /// Otsu's is ImagoKit's `threshold_otsu` of the finite pixels the mask is cut from (the smoothed ones when sigma > 0).
    /// With a region (`settings.region`), Otsu's level is of the region's pixels and the mask is false outside it; the image is smoothed
    /// whole first, so the region's border is not an edge of the filter.
    package static func mask(pixels: [Float], width: Int, height: Int, range: ClosedRange<Float>, settings: ParticleSettings) throws -> (mask: [Bool], threshold: Float) {
        let region = ParticleRegion.clamped(settings.region, width: width, height: height)
        let data = try smoothed(pixels, width: width, height: height, sigma: settings.sigma, low: range.lowerBound)
        let t: Float
        switch settings.method {
        case .manual:
            guard let level = Thresholding.level(pixels, atFraction: settings.thresholdFraction) else { throw ParticleError.noFiniteValues }
            t = level
        case .otsu:
            let finite = (region.map { ParticleRegion.crop(data, width: width, to: $0) } ?? data).filter(\.isFinite)
            guard !finite.isEmpty else { throw ParticleError.noFiniteValues }
            t = Float(try Thresholding.otsu(.float32(finite)))
        }
        var mask = Thresholding.mask(data, threshold: t, polarity: settings.polarity == .bright ? .bright : .dark)
        if let region {
            for row in 0..<height {
                let inRows = row >= region.row && row < region.row + region.height
                for col in 0..<width where mask[row * width + col]
                    && !(inRows && col >= region.col && col < region.col + region.width) { mask[row * width + col] = false }
            }
        }
        return (mask, t)
    }

    /// The objects of `pixels` under `settings`. `pixelSize` (units per pixel, nil when not calibrated) gives the areal density.
    package static func analyse(pixels: [Float], width: Int, height: Int, settings: ParticleSettings,
                                pixelSize: Double? = nil) throws -> ParticleReport {
        guard let range = range(pixels) else { throw ParticleError.noFiniteValues }
        let full = try mask(pixels: pixels, width: width, height: height, range: range, settings: settings)
        // With a region, the objects are found in its pixels alone: its border is the frame (edge objects, the density's area).
        let region = ParticleRegion.clamped(settings.region, width: width, height: height)
        let cut = (mask: region.map { ParticleRegion.crop(full.mask, width: width, to: $0) } ?? full.mask, threshold: full.threshold)
        let w = region?.width ?? width, h = region?.height ?? height
        // A cancelled run (its file closed, #618) stops between stages and lets go of the image it took.
        try Task.checkCancellation()
        let found = try Segmentation.label(cut.mask, width: w, height: h, connectivity: settings.connectivity)
        try Task.checkCancellation()
        // scikit-image's `remove_small_objects(max_size=)` clears objects of at most max_size pixels: below the minimum is minimum − 1.
        let kept = try BinaryMorphology.removeSmallObjects(cut.mask, width: w, height: h, maxSize: settings.minimumArea - 1,
                                                           connectivity: settings.connectivity)
        try Task.checkCancellation()
        let labels = try Segmentation.label(kept, width: w, height: h, connectivity: settings.connectivity)
        try Task.checkCancellation()
        let objects = try Segmentation.objectMoments(labels).map {
            ParticleObject(moments: $0, originCol: region?.col ?? 0, originRow: region?.row ?? 0)
        }
        let density = try ObjectStatistics.arealDensity(labels: labels, pixelSize: pixelSize)
        var s = ParticleSummary()
        s.counted = density.counted
        s.edge = density.edgeExcluded
        s.small = found.count - labels.count
        s.total = s.counted + s.edge + s.small
        s.medianLengthPx = density.medianLength
        s.meanWidthPx = density.meanWidth
        s.arealDensity = density.arealDensity
        // The labels on the image's own grid (zero outside the region), so the pointer readout and the overlay need no offset.
        var placed = labels
        if let region {
            var grid = [Int32](repeating: 0, count: width * height)
            for row in 0..<region.height {
                let to = (region.row + row) * width + region.col
                grid.replaceSubrange(to..<(to + region.width), with: labels.labels[(row * region.width)..<((row + 1) * region.width)])
            }
            placed = Segmentation.LabelImage(width: width, height: height, labels: grid, count: labels.count)
        }
        return ParticleReport(settings: settings, width: width, height: height, thresholdValue: cut.threshold, objects: objects,
                              summary: s, labels: placed)
    }

    /// The scale lengths are shown in: the x axis (ImagoKit's `ScaleBarMath.sampling`), or pixels when the image is not calibrated
    /// or its two axes differ.
    package static func scale(of image: CalibratedImage) -> ParticleScale {
        guard image.hasSquarePixels == true else { return ParticleScale(perPixel: 1, unit: "px") }
        let s = ScaleBarMath.sampling(x: image.x, y: image.y, width: image.width, height: image.height, unitLabel: UnitDisplay.label)
        return ParticleScale(perPixel: s.perPixel, unit: s.unit)
    }
}

package nonisolated enum ParticleFormat {
    /// A number a person reads (the object table, the inspector, the pointer readout): three significant digits in the locale's decimal
    /// mark, never grouped, as `UnitDisplay.number` writes every other number in the Image room ("0,873" in de_DE).
    package static func number(_ v: Double, locale: Locale = .autoupdatingCurrent) -> String { UnitDisplay.number(v, digits: 3, locale: locale) }

    /// The same number for the CSV a script reads: printf's `%.3g`, always a point.
    package static func csvNumber(_ v: Double) -> String { String(format: "%.3g", v) }

    /// "128 objects · 97 counted · 19 edge · 12 small".
    package static func counts(_ s: ParticleSummary) -> String {
        "\(s.total) object\(s.total == 1 ? "" : "s") · \(s.counted) counted · \(s.edge) edge · \(s.small) small"
    }

    /// "median length 18.2 nm · mean width 5.9 nm", or why there is none.
    package static func sizes(_ s: ParticleSummary, scale: ParticleScale, locale: Locale = .autoupdatingCurrent) -> String {
        guard let l = s.medianLengthPx, let w = s.meanWidthPx else { return s.total == 0 ? "No objects above the threshold." : "No object is counted." }
        return "median length \(number(l * scale.perPixel, locale: locale)) \(scale.unit) · mean width \(number(w * scale.perPixel, locale: locale)) \(scale.unit)"
    }

    /// The note for an image that is a render (a TIFF of the screen, #110): its burnt-in labels and scale bar are pixels and are found as
    /// objects. nil for any other image.
    package static func renderNote(notes: [String]) -> String? {
        guard notes.contains(where: { $0.hasPrefix(TIFFImageReader.Note.render) || $0.hasPrefix(TIFFImageReader.Note.colourRender) })
        else { return nil }
        return "This image is a render: burnt-in labels and scale bars are pixels and are found as objects. Draw a region that leaves them out."
    }

    /// "areal density 0.00123 /nm² (edge-corrected)", or why there is none.
    package static func density(_ s: ParticleSummary, scale: ParticleScale) -> String {
        guard scale.isCalibrated, let d = s.arealDensity else { return "No areal density: the image is not calibrated." }
        return "areal density \(number(d)) /\(scale.unit)² (edge-corrected)"
    }

    /// How the threshold was chosen, for the CSV's provenance line (point decimals: `csvNumber`).
    package static func threshold(_ r: ParticleReport) -> String {
        switch r.settings.method {
        case .manual: "fraction \(csvNumber(r.settings.thresholdFraction)) of the raw range = \(csvNumber(Double(r.thresholdValue)))"
        case .otsu: "Otsu (ImagoKit Thresholding.otsu, 256 bins) = \(csvNumber(Double(r.thresholdValue)))"
        }
    }

    /// " region x 10 y 20 500 x 400 px (its border is the edge, the density per its area)," with a region; empty for the whole image, so
    /// that file is as before.
    package static func regionNote(_ r: ParticleReport) -> String {
        guard let g = ParticleRegion.clamped(r.settings.region, width: r.width, height: r.height) else { return "" }
        return " region analysed x \(g.col) y \(g.row) \(g.width) x \(g.height) px (its border is the edge; the density is per its area),"
    }

    /// The objects as CSV with provenance comment lines; lengths in the scale's unit beside the pixels.
    package static func csv(_ r: ParticleReport, scale: ParticleScale, fileName: String) -> String {
        let u = scale.isCalibrated ? scale.unit : "px"
        let density = scale.isCalibrated ? r.summary.arealDensity : nil
        let densityLine = density != nil
            ? "# areal density: \(String(format: "%.6g", density ?? 0)) per \(scale.unit)^2, counted objects weighted by Miles-Lantuejoul's edge correction (ImagoKit ObjectStatistics.arealDensity)"
            : "# areal density: none (the image is not calibrated)"
        var out = ["# \(AppName.writer) particles, file: \(CSVText.headerValue(fileName))",
                   "# threshold: \(r.settings.polarity.rawValue) objects, \(threshold(r)),\(regionNote(r)) smoothing sigma \(csvNumber(r.settings.sigma)) px, connectivity \(r.settings.connectivity.rawValue), minimum area \(r.settings.minimumArea) px (smaller objects removed: ImagoKit BinaryMorphology.removeSmallObjects)",
                   "# \(ParticleFormat.counts(r.summary)); labels, centroids, lengths, widths and angles: ImagoKit Segmentation.objectMoments; counted = not touching the image edge",
                   densityLine,
                   "# length_ and width_ in \(u) (pixel size \(csvNumber(scale.perPixel)) \(scale.unit)/px); angle: long axis from +x toward +y, degrees",
                   // `small` stays so a script reading the columns by position keeps working: objects below the minimum area are now removed before
                   // labelling, so a listed object is never small (always 0); the count removed is in the summary line above.
                   "label,counted,touches_edge,small,area_px,centroid_x_px,centroid_y_px,length_px,width_px,angle_deg,length_\(u),width_\(u),area_\(u)2"]
        for o in r.objects {
            let m = o.moments
            let cells: [String] = ["\(m.label)", o.isCounted ? "1" : "0", m.touchesEdge ? "1" : "0", "0", "\(m.area)",
                                   String(format: "%.4f", o.centroidCol), String(format: "%.4f", o.centroidRow),
                                   String(format: "%.4f", m.lengthPx), String(format: "%.4f", m.widthPx), String(format: "%.3f", m.orientationDegrees),
                                   String(format: "%.5g", m.lengthPx * scale.perPixel), String(format: "%.5g", m.widthPx * scale.perPixel),
                                   String(format: "%.5g", Double(m.area) * scale.perPixel * scale.perPixel)]
            out.append(cells.joined(separator: ","))
        }
        return out.joined(separator: "\n") + "\n"
    }
}
