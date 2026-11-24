//
//  FFTStrain.swift
//  Role: strain maps of a lattice image (geometric phase analysis, Hÿtch, Snoeck and Kilaas, Ultramicroscopy 74 (1998) 131),
//        the FFT room's thin slice of MA16 (#917): two measured spots are the reflections g₁ and g₂, a reference window of the
//        transformed pixels has zero mean distortion, and ImagoKit's `GeometricPhaseAnalysis` answers the strain components and
//        the rotation as maps the source pane draws. The numbers are the kit's; this file only keys, runs and packs them.
//
//        Checked on planted fields only: ImagoKit pins GPA against planted displacement fields and no public lattice image
//        with a stated strain (ImagoKit#109), so the room says so beside the maps.
//

import Foundation
import ImagoCore
import ImagoFFT
import ImagoFilters
import TEMCore

/// The sentence the room and every export of a strain map carry (ImagoKit#109).
package nonisolated let strainValidationNote = "Checked on planted fields only: no public lattice image with a stated strain has been compared yet."

/// One reflection for GPA: (g_row, g_col) in cycles per pixel of the transformed pixels, and the spot it came from.
package nonisolated struct FFTStrainReflection: Sendable, Equatable {
    package let row: Double
    package let column: Double
    /// The spot's number, as the Spots list shows it.
    package let spot: Int

    package init(row: Double, column: Double, spot: Int) {
        self.row = row
        self.column = column
        self.spot = spot
    }

    /// A measured spot's centroid as a reflection: the centred spectrum's zero frequency sits at index ⌊n / 2⌋ on each axis
    /// (`fftshift`), so g = (centroid − ⌊n / 2⌋) / n cycles per pixel.
    package init(_ measurement: SpotMeasurement, spot: Int) {
        let h = measurement.height, w = measurement.width
        self.init(row: (measurement.centroidRow - Double(h / 2)) / Double(h),
                  column: (measurement.centroidCol - Double(w / 2)) / Double(w), spot: spot)
    }

    /// g₁ is the first measured spot of the list on the spectrum `key`; g₂ the next measured one at an angle to it, so a Friedel
    /// partner or a higher order of g₁ (Find Spots lists them side by side) is passed over. At an angle is the kit's own bound,
    /// |sin| ≥ 0.02. A spot at the centre (no frequency) is no reflection and is passed over too. Nil when there are not two such.
    package static func firstTwo(of spots: [FFTSpot], on key: FFTSpectrumKey) -> (FFTStrainReflection, FFTStrainReflection)? {
        let measured = spots.filter { $0.spectrumKey == key }.compactMap { spot in
            spot.measured.map { FFTStrainReflection($0, spot: spot.number) }
        }.filter { $0.row != 0 || $0.column != 0 }
        guard let g1 = measured.first else { return nil }
        let n1 = (g1.row * g1.row + g1.column * g1.column).squareRoot()
        let g2 = measured.dropFirst().first { g in
            let n = (g.row * g.row + g.column * g.column).squareRoot()
            return abs(g1.row * g.column - g1.column * g.row) >= 0.02 * n1 * n
        }
        return g2.map { (g1, $0) }
    }
}

/// The part of the transformed pixels taken as undistorted: GPA subtracts its mean distortion, so its mean strain and rotation are
/// zero. All of them, or their centred quarter (half the side each way).
package nonisolated enum FFTStrainReference: String, CaseIterable, Sendable {
    case whole, centredQuarter

    package var title: String {
        switch self {
        case .whole: "Whole Region"
        case .centredQuarter: "Centred Quarter"
        }
    }

    /// The window in the transformed pixels' own rows and columns.
    package func window(rows: Int, columns: Int) -> GeometricPhaseAnalysis.ReferenceWindow {
        switch self {
        case .whole:
            GeometricPhaseAnalysis.ReferenceWindow(rows: 0..<rows, columns: 0..<columns)
        case .centredQuarter:
            GeometricPhaseAnalysis.ReferenceWindow(rows: rows / 4..<(rows / 4 + max(rows / 2, 1)),
                                                   columns: columns / 4..<(columns / 4 + max(columns / 2, 1)))
        }
    }
}

/// What a strain map is of: the spectrum's pixels, the two reflections and the reference.
package nonisolated struct FFTStrainKey: Sendable, Equatable {
    package let spectrum: FFTSpectrumKey
    package let g1: FFTStrainReflection
    package let g2: FFTStrainReflection
    package let reference: FFTStrainReference

    package init(spectrum: FFTSpectrumKey, g1: FFTStrainReflection, g2: FFTStrainReflection, reference: FFTStrainReference) {
        self.spectrum = spectrum
        self.g1 = g1
        self.g2 = g2
        self.reference = reference
    }
}

/// The maps of one run, each drawn linear and symmetric about zero over the 99th percentile of its finite magnitudes
/// (`FFTStrainWork.drawn`), so one frame-edge or low-amplitude pixel does not wash the map out.
package nonisolated final class FFTStrainProduct: Sendable {
    /// x is along the columns, y along the rows (down the image); rotation is in radians, positive clockwise on screen (the kit's
    /// ½(∂u_row/∂col − ∂u_col/∂row) with rows running down).
    package enum Component: String, CaseIterable, Sendable {
        case exx, eyy, exy, rotation
    }

    package let key: FFTStrainKey
    package let exx: CanvasPixels
    package let eyy: CanvasPixels
    package let exy: CanvasPixels
    package let rotation: CanvasPixels
    /// The pixels with no phase (the filtered amplitude below the kit's floor): drawn masked, counted here.
    package let unmeasured: Int

    package init(key: FFTStrainKey, exx: CanvasPixels, eyy: CanvasPixels, exy: CanvasPixels, rotation: CanvasPixels,
                 unmeasured: Int) {
        self.key = key
        self.exx = exx
        self.eyy = eyy
        self.exy = exy
        self.rotation = rotation
        self.unmeasured = unmeasured
    }

    package func canvas(_ component: Component) -> CanvasPixels {
        switch component {
        case .exx: exx
        case .eyy: eyy
        case .exy: exy
        case .rotation: rotation
        }
    }
}

/// The run, off the main actor.
package nonisolated enum FFTStrainWork {
    /// The most pixels a run takes: 2048 × 2048. The kit peaks near 200 bytes a pixel (about 0.8 GB here); a larger region is
    /// refused with words that say to draw one, never cropped behind the person's back.
    package static let largestPixelCount = 2048 * 2048

    /// A map ready to draw: linear and symmetric about zero over the 99th percentile of its finite magnitudes (the largest when
    /// that is 0), values past it clipped to the colormap's ends, non-finite pixels masked. The range is the one drawn.
    package static func drawn(_ values: [Double], width: Int, height: Int) -> CanvasPixels {
        let pixels = values.map(Float.init)
        let magnitudes = pixels.filter(\.isFinite).map(abs).sorted()
        var extent = magnitudes.isEmpty ? 0 : magnitudes[Int((0.99 * Double(magnitudes.count - 1)).rounded(.down))]
        if extent == 0 { extent = magnitudes.last ?? 0 }
        let normalized = pixels.map { v -> Float in
            guard v.isFinite else { return FloatImage.invalidDisplayValue }
            return extent > 0 ? min(max(0.5 + 0.5 * v / extent, 0), 1) : 0.5
        }
        return CanvasPixels(width: width, height: height, normalized: normalized, contentVersion: FFTProductVersion.next(),
                            rawRange: magnitudes.isEmpty ? nil : -extent...extent)
    }

    package typealias Compute = @Sendable (_ image: CalibratedImage, _ key: FFTStrainKey) async throws -> FFTStrainProduct

    package static let live: Compute = { image, key in try await strain(image, key) }

    @concurrent static func strain(_ image: CalibratedImage, _ key: FFTStrainKey) async throws -> FFTStrainProduct {
        let interval = Signposts.begin("fft.strain"); defer { Signposts.end(interval) }
        // The region as it is: GPA filters its own reflections, so the spectrum's smoothing, band-pass and window stay out.
        let source = try FFTWork.transformed(image, key.spectrum.crop)
        let rows = source.height, columns = source.width
        try Task.checkCancellation()
        let result = try GeometricPhaseAnalysis.analyze(source.pixels.map(Double.init), rows: rows, columns: columns,
                                                        g1: (key.g1.row, key.g1.column), g2: (key.g2.row, key.g2.column),
                                                        reference: key.reference.window(rows: rows, columns: columns))
        try Task.checkCancellation()
        func map(_ values: [Double]) -> CanvasPixels { drawn(values, width: columns, height: rows) }
        return FFTStrainProduct(key: key, exx: map(result.strainCC), eyy: map(result.strainRR), exy: map(result.strainRC),
                                rotation: map(result.rotation), unmeasured: result.strainRR.reduce(0) { $1.isFinite ? $0 : $0 + 1 })
    }
}
