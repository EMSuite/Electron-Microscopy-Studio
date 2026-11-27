//
//  FFTExport.swift
//  Role: the writers of the FFT room's export: the radial profile
//        as a CSV, the measured spots as a CSV, and what the transform's PNG adds to `ImageExport` (its source with the
//        frequency steps as "axes", and its Description's "fft" block). Values in, text or bytes out; the app's snapshot
//        (EMStudio/App/ExportSnapshot.swift) gathers the values from the room's owners when the panel opens.
//
//        EXACT: every number the products hold is written `%.17g` (`CSVText.number`), so a reader's `float()` is the
//        in-memory Double bit for bit; a "shown" column is that Double times the factor the app shows it with
//        (`FFTUnits`), one multiplication, restated by a reader. (No angle column: deferred, a derived number to be registered as tier 1.)
//
//        WHAT THE NUMBERS ARE: the transform and the radial profile are of the region's pixels as read, with NO window and
//        the mean NOT removed (`PowerSpectrum`); only the spot estimator works on a Hann-windowed, mean-removed copy
//        (`SpotMeasurement`). Each header says which.
//

import Foundation
import ImagoCore
import ImagoFFT
import ShellExport
import TEMBase
import TEMSEM

package nonisolated enum FFTExport {

    // MARK: The sentences

    package static let displayNote = "picture: v = log10(|F|^2 / (W*H)^2) per bin, the DC bin masked, normalised over the finite range, "
        + "then the window shown, grey, gamma 1"
    package static let transformValidation = "the transform compared with numpy 2.5.4 (ImagoKit's parity tests); display "
        + "rendering: log scaling, window, 8-bit grey, not intensities; the scale bar's length checked against its label (export-parity)"
    package static let profileValidation = "the radial profile compared with numpy 2.5.4 (ImagoKit's parity tests); "
        + "the calibration as the file states it"
    package static let spotsValidation = "the spot centroid compared with planted spots (ImagoKit's parity tests); the "
        + "calibration as the file states it"
    package static let lineage = "none \u{2014} the FFT room's state carries no lineage id; the region, spots and parameters "
        + "above stand in"

    // MARK: The transform's PNG

    /// The source `ImageExport.render` takes for the transform: the spectrum's own size, and the frequency steps in the
    /// shown unit as its "axes", so the scale bar is the screen's rule applied to |q|.
    package static func transformSource(_ h: FFTExportHeader) -> ExportSource {
        let ux = FFTUnits.spectrumUnit(h.unitsX), uy = FFTUnits.spectrumUnit(h.unitsY)
        return ExportSource(software: h.software, fileName: h.fileName, object: h.object, width: h.spectrumWidth,
                            height: h.spectrumHeight,
                            x: AxisCalibration(scale: h.spacingX * ux.factor, unit: ux.label, origin: 0),
                            y: AxisCalibration(scale: h.spacingY * uy.factor, unit: uy.label, origin: 0),
                            notes: h.notes)
    }

    /// The Description's "fft" block and the two sentences that replace the image export's.
    /// `resampledFrom`: the bins' own size when the PNG is the "As shown" picture (`asShown`), so the Description says so.
    package static func transformProvenance(_ h: FFTExportHeader, spotsDrawn: Int,
                                            resampledFrom bins: (width: Int, height: Int)? = nil) -> ImageExport.Provenance {
        var provenance = binsProvenance(h, spotsDrawn: spotsDrawn)
        if let bins {
            provenance.fields["aspect_note"] = "As shown: the \(bins.width) x \(bins.height) bins resampled bilinearly to \(h.spectrumWidth) x "
                + "\(h.spectrumHeight) square pixels, the shape the pane draws; dq_x and dq_y are per pixel of this PNG"
            provenance.fields["resampled_from"] = "\(bins.width) x \(bins.height) bins"
        }
        return provenance
    }

    private static func binsProvenance(_ h: FFTExportHeader, spotsDrawn: Int) -> ImageExport.Provenance {
        let aspect = (Double(h.spectrumWidth) * h.spacingX) / (Double(h.spectrumHeight) * h.spacingY)
        return ImageExport.Provenance(
            fields: [
                "subject": FFTExportText.subject(crop: h.crop, imageWidth: h.imageWidth, imageHeight: h.imageHeight),
                "space": "reciprocal",
                "image": "\(h.imageWidth) x \(h.imageHeight) px",
                "file_x_scale": h.x.map { $0.isCalibrated ? "\($0.scale) \($0.unit) per px" : "none" } ?? "none",
                "file_y_scale": h.y.map { $0.isCalibrated ? "\($0.scale) \($0.unit) per px" : "none" } ?? "none",
                "dq_x": "\(CSVText.number(h.spacingX)) \(h.unitsX) per bin",
                "dq_y": "\(CSVText.number(h.spacingY)) \(h.unitsY) per bin",
                "transform": FFTExportText.transformNote,
                "display": displayNote,
                "pane_aspect": CSVText.number(aspect),
                "aspect_note": "the PNG is the bins, one square pixel each; the pane draws width*dq_x : height*dq_y (pane_aspect = "
                    + "the ratio); anisotropic compares dq_x with dq_y, which differ with the size alone",
                "spots_drawn": String(spotsDrawn),
            ],
            validation: transformValidation, lineage: lineage)
    }
}

extension FFTExport {
    /// The transform as the pane draws it (#636, Paul 16 Nov: "As shown"): the bins resampled to square pixels in q, the finer of
    /// Δq_x and Δq_y kept as the pixel's size, so one axis is stretched and none is thinned. Bilinear between bin centres; the spots
    /// move with their bins; the header's size and steps become the picture's, so the scale bar is the pane's. Bins already square
    /// come back unchanged. The analysis is untouched: this is the picture only.
    package static func asShown(display: ImageExport.Display, marks: [ImageExport.Mark], header h: FFTExportHeader)
        -> (display: ImageExport.Display, marks: [ImageExport.Mark], header: FFTExportHeader) {
        let w = display.width, ht = display.height
        let step = min(h.spacingX, h.spacingY)
        guard w > 0, ht > 0, step > 0, h.spacingX.isFinite, h.spacingY.isFinite else { return (display, marks, h) }
        let newW = max(1, Int((Double(w) * h.spacingX / step).rounded()))
        let newH = max(1, Int((Double(ht) * h.spacingY / step).rounded()))
        guard newW != w || newH != ht else { return (display, marks, h) }
        let fx = Double(w) / Double(newW), fy = Double(ht) / Double(newH)
        var out = [Float](repeating: 0, count: newW * newH)
        display.normalized.withUnsafeBufferPointer { src in
            for row in 0..<newH {
                let y = min(max((Double(row) + 0.5) * fy - 0.5, 0), Double(ht - 1))
                let y0 = Int(y), y1 = min(y0 + 1, ht - 1), ty = Float(y - Double(y0))
                for col in 0..<newW {
                    let x = min(max((Double(col) + 0.5) * fx - 0.5, 0), Double(w - 1))
                    let x0 = Int(x), x1 = min(x0 + 1, w - 1), tx = Float(x - Double(x0))
                    let top = src[y0 * w + x0] * (1 - tx) + src[y0 * w + x1] * tx
                    let bottom = src[y1 * w + x0] * (1 - tx) + src[y1 * w + x1] * tx
                    out[row * newW + col] = top * (1 - ty) + bottom * ty
                }
            }
        }
        var resampled = display
        resampled.normalized = out
        resampled.width = newW
        resampled.height = newH
        let moved = marks.map { mark in
            var m = mark
            m.points = mark.points.map { ImagePoint(x: ($0.x + 0.5) / fx - 0.5, y: ($0.y + 0.5) / fy - 0.5) }
            return m
        }
        var header = h
        header.spectrumWidth = newW
        header.spectrumHeight = newH
        header.spacingX = h.spacingX * fx
        header.spacingY = h.spacingY * fy
        return (resampled, moved, header)
    }
}

// MARK: - The CSV writers (ImagoFFT's `RadialProfileCSV` and `SpotsCSV`)

extension RadialProfileCSV {
    /// The whole file (UTF-8, LF), or nil when no bin outside the DC holds a pixel (the chart draws none either).
    package nonisolated static func text(_ profile: RadialProfile, header h: FFTExportHeader) -> String? {
        text(profile, header: h, title: "\(AppName.writer) radial profile", validation: FFTExport.profileValidation, lineage: FFTExport.lineage)
    }

    /// `methods`, when given, is one more header line (`ExportMethods`, #817).
    @concurrent package static func export(_ profile: RadialProfile, header: FFTExportHeader, methods: MethodsRecord? = nil,
                                           to url: URL) async throws {
        guard var text = text(profile, header: header) else { throw ExportFile.Failure.noSamples }
        if let methods { text = try ExportMethods.embedding(methods, inText: text) }
        try ExportFile.write(Data(text.utf8), to: url)
    }
}

extension SpotsCSV {
    /// The whole file (UTF-8, LF), or nil without a row. `omitted`: spots in the list that have no numbers (measuring,
    /// refused, no peak, or of another region). `notes`: further sentences (the accuracy by size) written verbatim.
    package nonisolated static func text(rows: [Row], omitted: Int, maskRadius: Double, maskEdge: Double, notes: [String],
                                         header h: FFTExportHeader) -> String? {
        text(rows: rows, omitted: omitted, maskRadius: maskRadius, maskEdge: maskEdge, notes: notes, header: h,
             title: "\(AppName.writer) spots", validation: FFTExport.spotsValidation, lineage: FFTExport.lineage)
    }

    /// `methods`, when given, is one more header line (`ExportMethods`, #817).
    @concurrent package static func export(rows: [Row], omitted: Int, maskRadius: Double, maskEdge: Double, notes: [String],
                                           header: FFTExportHeader, methods: MethodsRecord? = nil, to url: URL) async throws {
        guard var text = text(rows: rows, omitted: omitted, maskRadius: maskRadius, maskEdge: maskEdge, notes: notes,
                              header: header) else { throw ExportFile.Failure.noSpots }
        if let methods { text = try ExportMethods.embedding(methods, inText: text) }
        try ExportFile.write(Data(text.utf8), to: url)
    }
}
