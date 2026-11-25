//
//  HRTEMBeside.swift
//  Role: a simulated HRTEM image placed beside a measured one at the same scale (#898, plan row MA6; the design's "Simulated beside
//        measured"): the settings a person makes (the measured image, Beside or Inset, the rotation of the simulation, the inset's
//        size in unit cells), the measured image's nanometres per pixel or the sentence when it has none, and the one picture of the
//        pair that the HRTEM item shows and exports with one scale bar.
//
//        The simulation is resampled onto the measured image's pixels: the simulated image is first averaged over a measured pixel's
//        footprint (so fringes finer than the measured pixels average out rather than alias), then each output pixel takes one bilinear
//        sample of it, wrapped at its edges (the image is whole periods of the crystal, so it is periodic), turned by the rotation;
//        then its mean and standard deviation are set to the measured image's, so both read on one grey scale. In Float32, the
//        pixels' own type, with the sums in Double. Nothing is fitted:
//        there is no automatic match in 2.5 and no score is shown that the app cannot pin (the design).
//

import Foundation
import ImagoCore
import Synchronization

/// What Place Beside shows: the measured image (by its file), the layout, the rotation and the inset's size.
package nonisolated struct HRTEMBeside: Sendable, Equatable {
    package enum Layout: String, CaseIterable, Sendable {
        /// The measured image on the left, the simulation on the right, as large.
        case beside = "Beside"
        /// The simulation in a box in the measured image's top right corner.
        case inset = "Inset"
    }

    /// The measured image's file.
    package var measured: URL
    package var layout = Layout.beside
    /// The simulation's rotation on screen, degrees, counter-clockwise.
    package var rotationDegrees = 0.0
    /// The inset's size in unit cells, across and down (Inset only).
    package var insetCells = SIMD2(4, 4)

    package init(measured: URL) { self.measured = measured }

    package static let insetCellRange = 1 ... 50
    /// The design's sentences. The design's "Calibrate it in Imaging first." is left out: the Image room sets no calibration
    /// today, so the sentence says what is true instead.
    package static let uncalibrated = "This image has no calibration: its file records no length per pixel, so it cannot be shown at the simulation's scale."
    package static let coarser = "The measured image is coarser than the simulation; the simulation is averaged over each measured pixel and resampled to it."
    /// The pair is the HRTEM image while Place Beside is on, so the tools that read the image read the pair.
    package static let pairNote = "FFT and Profile read the pair; turn Place Beside off to measure the simulation alone."

    /// Nanometres per pixel of `image` along its columns (x) and rows (y); nil when either axis is not a calibrated length.
    package static func nanometresPerPixel(_ image: CalibratedImage) -> (x: Double, y: Double)? {
        guard let x = image.x, let y = image.y, x.isCalibrated, y.isCalibrated,
              let perX = LengthUnit.nanometres(per: x.unit), let perY = LengthUnit.nanometres(per: y.unit) else { return nil }
        let scale = (x: x.scale * perX, y: y.scale * perY)
        guard scale.x.isFinite, scale.x > 0, scale.y.isFinite, scale.y > 0 else { return nil }
        return scale
    }

    /// The readout: "Both at 0.0182 nm per pixel." (two numbers when the measured pixels are not square); nil when uncalibrated.
    package static func sameScaleLine(_ measured: CalibratedImage) -> String? {
        guard let scale = nanometresPerPixel(measured) else { return nil }
        let x = UnitDisplay.number(scale.x, digits: 3), y = UnitDisplay.number(scale.y, digits: 3)
        return x == y ? "Both at \(x) nm per pixel." : "Both at \(x) × \(y) nm per pixel."
    }

    /// Whether a measured pixel is larger than a simulated one (`simulated`, nm per pixel) along either axis.
    package static func isCoarser(_ measured: CalibratedImage, than simulated: (x: Double, y: Double)) -> Bool {
        guard let m = nanometresPerPixel(measured) else { return false }
        return m.x > simulated.x * (1 + 1e-9) || m.y > simulated.y * (1 + 1e-9)
    }

    /// The pair as one image at the measured image's nanometres per pixel, named as `simulated` (the HRTEM item shows it in place
    /// of the simulation alone). `cellNM` is one unit cell of the simulated image, across its columns and down its rows. `measuredKey`
    /// names the measured image's pixels (their hash), so its mean and deviation are computed once per image, not on every redraw.
    /// Throws `Refusal.uncalibrated` when either image has no length calibration. In Float, as the pixels are: the measured half is
    /// copied as it is and only the simulated panel is computed.
    package func composite(simulated: CalibratedImage, measured: CalibratedImage, cellNM: SIMD2<Double>,
                           measuredKey: String? = nil) throws -> CalibratedImage {
        guard let scale = Self.nanometresPerPixel(measured), let simScale = Self.nanometresPerPixel(simulated) else {
            throw Refusal.uncalibrated
        }
        let width = measured.width, height = measured.height
        let values = measured.pixels
        let stats = Self.measuredStatistics(values, key: measuredKey)
        let filtered = Self.footprintAveraged(simulated, simScale: simScale, scale: scale)

        func panel(width: Int, height: Int) -> [Float] {
            Self.matched(Self.resampled(filtered, simulated: (simulated.width, simulated.height), simScale: simScale, scale: scale, width: width, height: height, degrees: rotationDegrees),
                         to: stats)
        }

        var out: [Float]
        let outWidth: Int
        switch layout {
        case .beside:
            let gap = max(2, width / 64)
            outWidth = 2 * width + gap
            let simulatedPanel = panel(width: width, height: height)
            out = [Float](repeating: Float(stats.mean), count: outWidth * height)
            for row in 0 ..< height {
                out.replaceSubrange(row * outWidth ..< row * outWidth + width, with: values[row * width ..< (row + 1) * width])
                out.replaceSubrange(row * outWidth + width + gap ..< (row + 1) * outWidth,
                                    with: simulatedPanel[row * width ..< (row + 1) * width])
            }
        case .inset:
            outWidth = width
            out = values
            let margin = max(2, width / 64)
            let insetWidth = min(width - 2 * margin, max(2, Int((Double(insetCells.x) * cellNM.x / scale.x).rounded())))
            let insetHeight = min(height - 2 * margin, max(2, Int((Double(insetCells.y) * cellNM.y / scale.y).rounded())))
            guard insetWidth >= 2, insetHeight >= 2 else { break }
            let inset = panel(width: insetWidth, height: insetHeight)
            let left = width - margin - insetWidth, top = margin
            // The frame takes the measured extreme farthest from its mean, so it shows on a dark image and on a bright one.
            let frame = Float(stats.maximum - stats.mean >= stats.mean - stats.minimum ? stats.maximum : stats.minimum)
            for row in -1 ... insetHeight {
                for column in -1 ... insetWidth {
                    let x = left + column, y = top + row
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let edge = row < 0 || row == insetHeight || column < 0 || column == insetWidth
                    out[y * width + x] = edge ? frame : inset[row * insetWidth + column]
                }
            }
        }
        var notes = simulated.notes + ["\(layout == .beside ? "beside" : "inset in") \(measured.fileName), "
                                       + "rotated \(UnitDisplay.number(rotationDegrees, digits: 4))°"]
        if let line = Self.sameScaleLine(measured) { notes.append(line) }
        if let volts = measured.voltage { notes.append("measured at \(UnitDisplay.number(volts / 1000, digits: 4)) kV") }
        return CalibratedImage(width: outWidth, height: height, pixels: out,
                               x: AxisCalibration(scale: scale.x, unit: "nm"), y: AxisCalibration(scale: scale.y, unit: "nm"),
                               fileName: simulated.fileName, source: simulated.source, voltage: simulated.voltage, notes: notes)
    }

    package enum Refusal: LocalizedError, Equatable {
        case uncalibrated
        package var errorDescription: String? { HRTEMBeside.uncalibrated }
    }

    /// The mean, standard deviation and extremes of an image's finite pixels.
    struct Statistics: Equatable {
        var mean = 0.0, deviation = 0.0, minimum = 0.0, maximum = 0.0
    }

    static func statistics(_ values: some Collection<Float>) -> Statistics {
        var n = 0.0, sum = 0.0, squares = 0.0, low = Double.infinity, high = -Double.infinity
        for value in values where value.isFinite {
            let v = Double(value)
            n += 1; sum += v; squares += v * v
            low = min(low, v); high = max(high, v)
        }
        guard n > 0 else { return Statistics() }
        let mean = sum / n
        return Statistics(mean: mean, deviation: max(0, squares / n - mean * mean).squareRoot(), minimum: low, maximum: high)
    }

    /// The last measured image's statistics, by its pixels' hash: a redraw of the simulation does not read the measured image again.
    private static let lastMeasured = Mutex<(key: String, statistics: Statistics)?>(nil)

    static func measuredStatistics(_ values: [Float], key: String?) -> Statistics {
        if let key, let held = lastMeasured.withLock({ $0 }), held.key == key { return held.statistics }
        let made = statistics(values)
        if let key { lastMeasured.withLock { $0 = (key, made) } }
        return made
    }

    /// The simulated image averaged over a measured pixel's footprint (a box per axis as wide as that axis's scale ratio, made odd so
    /// it is centred on the pixel, wrapped at the edges, as the image is periodic), so a fringe finer than the measured pixels averages
    /// out instead of aliasing; the image itself when a measured pixel is no larger than a simulated one.
    static func footprintAveraged(_ simulated: CalibratedImage, simScale: (x: Double, y: Double),
                                  scale: (x: Double, y: Double)) -> [Float] {
        let source = simulated.pixels
        func odd(_ ratio: Double) -> Int { Int(ratio.rounded()) | 1 }
        let boxX = odd(scale.x / simScale.x), boxY = odd(scale.y / simScale.y)
        guard boxX > 1 || boxY > 1 else { return source }
        let w = simulated.width, h = simulated.height
        func smoothed(_ line: (Int) -> Float, count: Int, box: Int) -> [Float] {
            guard box > 1 else { return (0 ..< count).map(line) }
            // A running sum over `box` neighbours, centred, wrapped.
            let half = box / 2
            var sum = 0.0
            for k in -half ..< box - half { sum += Double(line(((k % count) + count) % count)) }
            var out = [Float](repeating: 0, count: count)
            for i in 0 ..< count {
                out[i] = Float(sum / Double(box))
                sum += Double(line(((i + box - half) % count + count) % count)) - Double(line(((i - half) % count + count) % count))
            }
            return out
        }
        var rows = [Float](repeating: 0, count: w * h)
        for r in 0 ..< h {
            let line = smoothed({ source[r * w + $0] }, count: w, box: boxX)
            rows.replaceSubrange(r * w ..< (r + 1) * w, with: line)
        }
        var out = [Float](repeating: 0, count: w * h)
        for c in 0 ..< w {
            let line = smoothed({ rows[$0 * w + c] }, count: h, box: boxY)
            for r in 0 ..< h { out[r * w + c] = line[r] }
        }
        return out
    }

    /// The simulated image (its pixels `source`, already averaged over the measured footprint) on a `width` × `height` grid at `scale`
    /// nm per pixel, turned `degrees` counter-clockwise on screen about the panel's centre: one bilinear sample at each pixel's
    /// centre, wrapped at the simulated image's edges.
    static func resampled(_ source: [Float], simulated: (width: Int, height: Int), simScale: (x: Double, y: Double),
                          scale: (x: Double, y: Double), width: Int, height: Int, degrees: Double) -> [Float] {
        let sw = simulated.width, sh = simulated.height
        let angle = degrees * .pi / 180
        let c = cos(angle), s = sin(angle)
        func at(_ x: Int, _ y: Int) -> Double { Double(source[(((y % sh) + sh) % sh) * sw + ((x % sw) + sw) % sw]) }
        var out = [Float](repeating: 0, count: width * height)
        for row in 0 ..< height {
            // nm from the panel's centre, x right and y down.
            let dy = (Double(row) + 0.5 - Double(height) / 2) * scale.y
            for column in 0 ..< width {
                let dx = (Double(column) + 0.5 - Double(width) / 2) * scale.x
                // Turning the picture counter-clockwise on screen samples the source turned the other way (rows point down).
                let xs = c * dx - s * dy, ys = s * dx + c * dy
                let u = Double(sw) / 2 + xs / simScale.x - 0.5, v = Double(sh) / 2 + ys / simScale.y - 0.5
                let x0 = Int(u.rounded(.down)), y0 = Int(v.rounded(.down))
                let fx = u - Double(x0), fy = v - Double(y0)
                let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
                let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
                out[row * width + column] = Float(top * (1 - fy) + bottom * fy)
            }
        }
        return out
    }

    /// `values` with the measured image's mean and standard deviation (the measured mean everywhere when `values` is flat).
    static func matched(_ values: [Float], to measured: Statistics) -> [Float] {
        let own = statistics(values)
        guard own.deviation > 0, own.deviation.isFinite else { return [Float](repeating: Float(measured.mean), count: values.count) }
        let gain = measured.deviation / own.deviation
        return values.map { Float((Double($0) - own.mean) * gain + measured.mean) }
    }
}
