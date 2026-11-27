//
//  TextureRaster.swift
//  The rasters the Maps room's Texture tab draws of DiffractoKit's pole densities and ODF sections (`PoleFigures`,
//  `PoleDensityFunction`, `OrientationDensity`, moved there by DiffractoKit#180): values on a square stereographic canvas, NaN
//  outside the hemisphere or the sector, coloured by the shared colormap in the view (D-SEM-68 in docs/decisions.md).
//

import DiffractoGeometry
import DiffractoOrientation
import Foundation

/// A density drawn on a square canvas: `values` row-major from the top row, Float, NaN where nothing is drawn; `low` and
/// `high` the range of the finite values (the colour bar).
package nonisolated struct TextureRaster: Sendable, Equatable {
    package let width: Int
    package let height: Int
    package let values: [Float]
    package let low: Float
    package let high: Float

    package init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height, "one value per pixel")
        self.width = width
        self.height = height
        self.values = values
        let finite = values.filter(\.isFinite)
        low = finite.min() ?? 0
        high = finite.max() ?? 0
    }

    /// The stereographic projection of a pole density map: pixel (column c, row r) of a size x size canvas centred at
    /// x = x0 + (c + 0.5) w / size, y = y1 − (r + 0.5) h / size over `extent` (the unit disk by default; an inverse pole
    /// figure passes its sector's stereographic extent), the vector of that point in the map's hemisphere, the value of the
    /// bin it falls in; NaN outside the disk, the hemisphere, or a masked bin.
    package static func stereographic(_ map: PoleDensityMap, size: Int,
                                      extent: (x: ClosedRange<Double>, y: ClosedRange<Double>) = (-1...1, -1...1)) -> TextureRaster {
        precondition(size > 0, "a raster has at least one pixel")
        let projection = StereographicProjection(pole: map.grid.hemisphere.pole)
        let w = extent.x.upperBound - extent.x.lowerBound, h = extent.y.upperBound - extent.y.lowerBound
        let side = max(w, h)
        var out = [Float](repeating: .nan, count: size * size)
        for r in 0..<size {
            let y = extent.y.upperBound - (Double(r) + 0.5) * side / Double(size)
            for c in 0..<size {
                let x = extent.x.lowerBound + (Double(c) + 0.5) * side / Double(size)
                guard x * x + y * y <= 1 else { continue }
                if let v = map.value(at: projection.xyToVector(SIMD2(x, y))) { out[r * size + c] = Float(v) }
            }
        }
        return TextureRaster(width: size, height: size, values: out)
    }

    /// An ODF section as an image: φ1 across (columns), Φ down (rows), one pixel per node.
    package static func section(_ s: ODFSection) -> TextureRaster {
        var out = [Float](repeating: .nan, count: s.phi1Degrees.count * s.PhiDegrees.count)
        for (i, _) in s.phi1Degrees.enumerated() {
            for (j, _) in s.PhiDegrees.enumerated() { out[j * s.phi1Degrees.count + i] = Float(s.values[i * s.PhiDegrees.count + j]) }
        }
        return TextureRaster(width: s.phi1Degrees.count, height: s.PhiDegrees.count, values: out)
    }
}
