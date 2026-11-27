//
//  MapAnalysis.swift
//  The Maps room's side of the map analysis: the derived layers it draws (`DerivedMapLayer`), their rasters and display colours,
//  the boundary and grain outlines, the histograms, and the texture of one phase (`MapTexture`). The numbers are DiffractoKit's
//  (`MapAnalysis`, `GrainAnalysis`, `NyeTensor`, `SlipTraceAnalysis`, `PoleFigures`, `OrientationDensity`, moved there by
//  DiffractoKit#180); this file lays them out as the room draws them: per grid cell, row-major, NaN where no value is.
//
//  Parity: the moved functions keep theirs in DiffractoKit (its docs/parity.md, "The map code (#180)").
//

import DiffractoGeometry
import DiffractoOrientation
import Foundation

/// A map the Maps room draws from the analysis, beside the file's own columns.
package nonisolated enum DerivedMapLayer: String, CaseIterable, Sendable, Hashable {
    /// Kernel average misorientation, degrees (first neighbours of the same phase, above the KAM maximum dropped).
    case kam
    /// Grain orientation spread, degrees: each point carries its grain's.
    case gos
    /// Geometrically necessary dislocation density, log10 of m⁻².
    case gnd
    /// Each grain in its own colour.
    case grains
    /// Each grain's largest Schmid factor for the load direction.
    case schmid

    package var title: String {
        switch self {
        case .kam: "KAM"
        case .gos: "GOS"
        case .gnd: "GND"
        case .grains: "Grains"
        case .schmid: "Schmid factor"
        }
    }

    /// The colour bar's unit.
    package var unit: String {
        switch self {
        case .kam, .gos: "°"
        case .gnd: "log₁₀ m⁻²"
        case .grains, .schmid: ""
        }
    }
}

nonisolated extension MapAnalysis {
    // MARK: Pictures

    /// The values of a scalar derived layer per grid cell (NaN where none); nil for the grain colours or a layer with no numbers
    /// (GND without a crystal structure, Schmid without slip systems).
    package func values(_ layer: DerivedMapLayer, slip: [GrainSlip] = []) -> [Double]? {
        switch layer {
        case .kam:
            return grains.kam.map { $0 * 180 / Double.pi }
        case .gos:
            return grains.statistics.gosMap(grains.segmentation).map { $0 * 180 / Double.pi }
        case .gnd:
            return gnd?.map { $0 > 0 ? log10($0) : .nan }
        case .schmid:
            guard !slip.isEmpty else { return nil }
            var byGrain: [Int: Double] = [:]
            for s in slip { byGrain[s.grain] = s.maximumSchmid }
            return grains.segmentation.grainMap.map { byGrain[$0] ?? .nan }
        case .grains:
            return nil
        }
    }

    /// The grain colours per grid cell: each grain a hue from the golden ratio by its number (neighbours read apart), points of
    /// grains below the minimum size grey, points of no grain black.
    package var grainColours: [SIMD3<Double>] {
        grains.segmentation.grainMap.map { g in
            if g == -2 { return SIMD3(0.5, 0.5, 0.5) }
            guard g > 0 else { return .zero }
            return Self.grainColour(g)
        }
    }

    /// The colour of grain `number`.
    package static func grainColour(_ number: Int) -> SIMD3<Double> {
        let hue = (Double(number) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1)
        let value = number % 2 == 0 ? 0.95 : 0.78
        return DirectionColorKeyTSL.hsvToRGB(hue, 0.55, value)
    }

    /// The raster of a derived layer.
    package func raster(_ layer: DerivedMapLayer, slip: [GrainSlip] = []) -> OrientationMapRaster {
        let inData = grainMap.phase.map { $0 != 0 }
        if layer == .grains {
            return OrientationMapRaster(rows: rows, columns: columns, rgb: grainColours, values: nil, inData: inData)
        }
        let values = self.values(layer, slip: slip) ?? [Double](repeating: .nan, count: rows * columns)
        return OrientationMapRaster(rows: rows, columns: columns, rgb: nil, values: values, inData: inData)
    }

    // MARK: Boundaries

    /// The boundary edges to draw, in image coordinates (a pixel's centre at integers): the edge right of a point is the segment
    /// x = c + ½ from y = r − ½ to r + ½, the edge below it y = r + ½. Grain boundaries that are not phase boundaries, and phase
    /// boundaries, apart.
    package func boundaryEdges() -> (grain: [(SIMD2<Double>, SIMD2<Double>)], phase: [(SIMD2<Double>, SIMD2<Double>)]) {
        let b = grains.boundaries
        var grain: [(SIMD2<Double>, SIMD2<Double>)] = [], phase: [(SIMD2<Double>, SIMD2<Double>)] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let i = r * columns + c
                if c + 1 < columns, b.grainX[i] || b.phaseX[i] {
                    let edge = (SIMD2(Double(c) + 0.5, Double(r) - 0.5), SIMD2(Double(c) + 0.5, Double(r) + 0.5))
                    if b.phaseX[i] { phase.append(edge) } else { grain.append(edge) }
                }
                if r + 1 < rows, b.grainY[i] || b.phaseY[i] {
                    let edge = (SIMD2(Double(c) - 0.5, Double(r) + 0.5), SIMD2(Double(c) + 0.5, Double(r) + 0.5))
                    if b.phaseY[i] { phase.append(edge) } else { grain.append(edge) }
                }
            }
        }
        return (grain, phase)
    }

    /// The outline of grain `number`: every edge between one of its points and a point that is not (the map's border included).
    package func outline(of number: Int) -> [(SIMD2<Double>, SIMD2<Double>)] { outline(of: [number]) }

    /// The outlines of several grains in one pass over the map: every edge between a point of one of them and a point of another grain
    /// or of none (two selected neighbours keep the edge between them).
    package func outline(of numbers: Set<Int>) -> [(SIMD2<Double>, SIMD2<Double>)] {
        guard !numbers.isEmpty else { return [] }
        let g = grains.segmentation.grainMap
        var out: [(SIMD2<Double>, SIMD2<Double>)] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let number = g[r * columns + c]
                guard numbers.contains(number) else { continue }
                let x = Double(c), y = Double(r)
                if c + 1 >= columns || g[r * columns + c + 1] != number { out.append((SIMD2(x + 0.5, y - 0.5), SIMD2(x + 0.5, y + 0.5))) }
                if c == 0 || g[r * columns + c - 1] != number { out.append((SIMD2(x - 0.5, y - 0.5), SIMD2(x - 0.5, y + 0.5))) }
                if r + 1 >= rows || g[(r + 1) * columns + c] != number { out.append((SIMD2(x - 0.5, y + 0.5), SIMD2(x + 0.5, y + 0.5))) }
                if r == 0 || g[(r - 1) * columns + c] != number { out.append((SIMD2(x - 0.5, y - 0.5), SIMD2(x + 0.5, y - 0.5))) }
            }
        }
        return out
    }

    // MARK: Histograms (macTEM#239)

    /// The Histogram tab's distributions: KAM per point (°), GOS per grain (°), equivalent circle diameter per grain (scan unit).
    package enum HistogramKind: String, CaseIterable, Sendable, Hashable {
        case kam = "KAM"
        case gos = "GOS"
        case grainSize = "Grain size"
    }

    /// The values a histogram counts: every finite KAM of the map, or one value per grain of the table.
    package func histogramValues(_ kind: HistogramKind) -> [Double] {
        switch kind {
        case .kam: grains.kam.filter(\.isFinite).map { $0 * 180 / Double.pi }
        case .gos: table.map(\.gosDegrees).filter(\.isFinite)
        case .grainSize: table.map(\.diameter).filter(\.isFinite)
        }
    }

    /// The value one grain contributes to a per-grain histogram (nil for KAM, which is per point).
    package func histogramValue(_ kind: HistogramKind, of row: GrainRow) -> Double? {
        switch kind {
        case .kam: nil
        case .gos: row.gosDegrees
        case .grainSize: row.diameter
        }
    }

    /// `numpy.histogram` of the values over `bins` equal bins: KAM from 0 to the KAM maximum (the values it can take), GOS and grain
    /// size from 0 to their largest value (1 when every value is 0).
    package func histogram(_ kind: HistogramKind, bins: Int = 40) -> AngleHistogram {
        let values = histogramValues(kind)
        let top: Double
        switch kind {
        case .kam: top = settings.kamMaxDegrees
        case .gos, .grainSize: top = values.max().map { $0 > 0 ? $0 : 1 } ?? 1
        }
        let n = max(bins, 1)
        let edges = (0...n).map { top * Double($0) / Double(n) }
        return AngleHistogram(values: values, edges: edges)
    }
}

// MARK: - Texture

/// The texture of one phase of a map, as the Maps room's bottom pane draws it.
package nonisolated struct MapTexture: Sendable {
    package struct Figure: Sendable {
        /// "{111}", "IPF-Z", "φ₂ = 45°".
        package let title: String
        package let raster: TextureRaster
        /// The figure's largest density (multiples of a random distribution).
        package let maximum: Double
        /// A pole figure's crystal directions (the family's symmetry-equivalent poles); empty for the IPF density and an ODF section.
        package var poles: [SIMD3<Double>] = []
    }

    /// Where `orientations` (lab to crystal) put a pole figure's poles, in the figure's unit square (0, 0 the top-left corner, as its
    /// raster is drawn): each pole turned into the sample frame, folded onto the upper hemisphere (a pole is an axis) and projected as
    /// `TextureRaster.stereographic` projects the unit disk. Empty for a figure without poles.
    package static func poleMarkers(_ figure: Figure, orientations: [SIMD4<Double>]) -> [SIMD2<Double>] {
        guard !figure.poles.isEmpty else { return [] }
        var out: [SIMD2<Double>] = []
        for q in orientations {
            let inverse = Rotation(q).inverse
            for p in figure.poles {
                var v = inverse * p
                if v.z < 0 { v = -v }
                let xy = StereographicProjection.project(v, pole: -1)
                out.append(SIMD2((xy.x + 1) / 2, (1 - xy.y) / 2))
            }
        }
        return out
    }

    package let phaseID: Int
    package let phaseName: String
    package let points: Int
    /// The points the ODF sections used (all of the phase's, or a seeded sample of `odfPointLimit`).
    package let odfPoints: Int
    package let poleFigures: [Figure]
    package let inversePoleFigure: Figure?
    package let odfSections: [Figure]

    /// The ODF sums its kernel over every orientation at every node: past this many points the sections take a sample of this many.
    package static let odfPointLimit = 5000

    /// The points the ODF sections take: all up to `limit`, else `limit` of them drawn without replacement by a seeded shuffle, in map
    /// order. Every k-th point of a row-major map aliased with its columns (macEM#615: a map whose texture alternates by column, with
    /// a column count that k divides, showed only one of its components). Seeded, so the same map gives the same sections.
    package static func odfSampleIndices(count: Int, limit: Int = odfPointLimit) -> [Int] {
        guard count > limit, limit > 0 else { return Array(0..<max(count, 0)) }
        var indices = Array(0..<count)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {   // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        for i in 0..<limit {
            let j = i + Int(next() % UInt64(count - i))
            indices.swapAt(i, j)
        }
        return indices[0..<limit].sorted()
    }

    /// The pole families shown for a point group: {100} {110} {111} for cubic, {0001} {10-10} {11-20} for hexagonal, {100} {010}
    /// {001} otherwise.
    package static func families(for group: PointGroup) -> [(title: String, indices: [Double])] {
        switch group.system ?? "" {
        case "cubic": [("{100}", [1, 0, 0]), ("{110}", [1, 1, 0]), ("{111}", [1, 1, 1])]
        case "hexagonal": [("{0001}", [0, 0, 0, 1]), ("{10-10}", [1, 0, -1, 0]), ("{11-20}", [1, 1, -2, 0])]
        default: [("{100}", [1, 0, 0]), ("{010}", [0, 1, 0]), ("{001}", [0, 0, 1])]
        }
    }

    /// The φ₂ sections shown: 0°, 45° and 65° for cubic (the rolling-texture sections), else 0° and half the φ₂ range.
    package static func sections(for group: PointGroup) -> [Double] {
        if group.system == "cubic" { return [0, 45, 65] }
        let range = OrientationDensity.bungeRanges(for: group).phi2
        return [0, range / 2]
    }

    /// The pole figures (stereographic, upper hemisphere, 1° bins smoothed at `sigma`°), the IPF-Z density in the colour key's
    /// sector and the ODF sections of phase `phaseID`, each as a `size`-pixel raster (the ODF at its 5° nodes). A sigma of +∞, or
    /// one whose kernel passes `PoleDensityFunction.maximumKernelRadius` on either grid, is refused before any figure is made; 0,
    /// a negative sigma (−∞ too) and NaN smooth nothing, as scipy's filter skips them. Throws `CancellationError` between figures
    /// once its task is cancelled.
    package static func compute(_ map: CrystalMap, phaseID: Int, size: Int = 181, sigma: Double = 5,
                                odfHalfWidth: Double = OrientationDensity.defaultHalfWidthDegrees) throws -> MapTexture {
        guard let phase = map.phases[id: phaseID], let group = phase.pointGroup else {
            throw MapAnalysis.Refusal.grains("The phase has no point group: no texture.")
        }
        guard PoleDensityFunction.smoothingFits(sigma: sigma), PoleDensityFunction.smoothingFits(sigma: sigma, symmetry: group.laue) else {
            throw MapAnalysis.Refusal.grains("The texture's smoothing sigma must be a finite number of degrees, at most 512°.")
        }
        let orientations = try map.points(ofPhases: [phase.name]).orientations()
        // Each figure is seconds of work on a large map: a cancelled texture (a close, a new map, ⌘.) stops between figures instead of
        // holding the map and its buffers until the last one is made (#713).
        try Task.checkCancellation()
        let lattice: CrystalLattice
        if let l = phase.lattice, l.count == 6, l.allSatisfy({ $0.isFinite && $0 > 0 }) {
            lattice = CrystalLattice(a: l[0], b: l[1], c: l[2], alpha: l[3], beta: l[4], gamma: l[5])
        } else {
            lattice = CrystalLattice.defaultLattice(system: group.system)
        }
        var poles: [Figure] = []
        for family in families(for: group) {
            try Task.checkCancellation()
            let vectors = try PoleFigures.poles(family: family.indices, lattice: lattice, group: group)
            let density = PoleFigures.poleFigure(orientations, poles: vectors, sigma: sigma)
            poles.append(Figure(title: family.title, raster: TextureRaster.stereographic(density, size: size), maximum: density.maximum,
                                poles: vectors))
        }
        try Task.checkCancellation()
        let key = DirectionColorKeyTSL(group)
        let ipf = PoleFigures.inversePoleFigure(orientations, laue: group.laue, sigma: sigma)
        let extent = key.sector.stereographicExtent ?? (-1...1, -1...1)
        let inverse = Figure(title: "IPF-Z", raster: TextureRaster.stereographic(ipf, size: size, extent: extent), maximum: ipf.maximum)

        let picked = odfSampleIndices(count: orientations.count)
        let sample = picked.count == orientations.count ? orientations
            : Orientations(quaternions: picked.map { orientations.quaternions[$0] }, symmetry: orientations.symmetry)
        let odf = try sections(for: group).map { phi2 -> Figure in
            try Task.checkCancellation()
            let s = OrientationDensity.section(sample, phi2Degrees: phi2, halfWidthDegrees: odfHalfWidth)
            return Figure(title: "φ₂ = \(Int(phi2.rounded()))°", raster: TextureRaster.section(s), maximum: s.maximum)
        }
        return MapTexture(phaseID: phaseID, phaseName: phase.name, points: orientations.count, odfPoints: sample.count,
                          poleFigures: poles, inversePoleFigure: inverse, odfSections: odf)
    }

    /// The same off the caller's actor.
    @concurrent package static func computeAsync(_ map: CrystalMap, phaseID: Int) async throws -> MapTexture {
        try compute(map, phaseID: phaseID)
    }
}
