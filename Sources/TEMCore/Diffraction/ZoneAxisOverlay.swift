//
//  ZoneAxisOverlay.swift
//  Role: the simulated spot pattern of a typed zone axis over a measured pattern (plan row R1, #782): the zone axis as typed
//        ("[1 1 0]", "1 1 0", "110", "1̄10", "-1 1 0"), the hkl as a label ("1̄11"), and the spots of DiffractoKit's
//        `SpotPatternSimulator` at `CrystalOrientation(zoneAxis:inPlaneAngle:cell:)` placed in the image's pixels. Every number is
//        the kit's; this file only maps q to pixels and keeps the spots that land on the image.
//
//  The map (py4DSTEM's): the kit's qx runs down the rows and qy along the columns, row = centre.row + qx / Δq and
//  column = centre.column + qy / Δq, so a pattern the kit indexes from found spots (R2) is drawn back where they were found. The
//  radius is the inverse of the readout's q (`RingScale.radius`: exact with a ring's L and λ, else |q| / Δq), so a drawn spot
//  reads back its own q under the pointer.
//

import Foundation
import DiffractoCore
import DiffractoGeometry

package nonisolated enum ZoneAxisText {
    /// [u v w] from what a person types: three integers separated by spaces or commas, inside [ ] or not, or three digits run
    /// together ("110"), each with a leading minus or a combining overbar after it ("1̄10"). nil for anything else and for [0 0 0].
    package static func parse(_ text: String) -> SIMD3<Int>? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("[") || s.hasPrefix("<") { s.removeFirst() }
        if s.hasSuffix("]") || s.hasSuffix(">") { s.removeLast() }
        s = s.replacingOccurrences(of: "−", with: "-")
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let values: [Int]
        if parts.count == 3 {
            let v = parts.compactMap(integer)
            guard v.count == 3 else { return nil }
            values = v
        } else if parts.count == 1 {
            guard let v = runTogether(parts[0]) else { return nil }
            values = v
        } else {
            return nil
        }
        guard values.count == 3, values.contains(where: { $0 != 0 }), values.allSatisfy({ abs($0) <= 99 }) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    /// One integer: "-2", "2", or "2̄" (the combining overbar U+0304 after its digits).
    private static func integer(_ s: String) -> Int? {
        let bar: Unicode.Scalar = "\u{0304}"
        if s.unicodeScalars.contains(bar) {
            var scalars = s.unicodeScalars
            guard scalars.last == bar else { return nil }
            scalars.removeLast()
            guard !scalars.contains(bar), let v = Int(String(scalars)), v > 0 else { return nil }
            return -v
        }
        return Int(s)
    }

    /// Three single digits run together, each with an optional leading minus or trailing overbar.
    private static func runTogether(_ s: String) -> [Int]? {
        var out: [Int] = []
        var negative = false
        for scalar in s.unicodeScalars {
            if scalar == "-" {
                guard !negative else { return nil }
                negative = true
            } else if scalar == "\u{0304}" {
                guard !negative, let last = out.popLast(), last > 0 else { return nil }
                out.append(-last)
            } else if let d = Int(String(scalar)), (0...9).contains(d) {
                out.append(negative ? -d : d)
                negative = false
            } else {
                return nil
            }
        }
        return negative ? nil : out
    }

    /// "[1 1 0]", the form the field shows back.
    package static func text(_ uvw: SIMD3<Int>) -> String { "[\(uvw.x) \(uvw.y) \(uvw.z)]" }

    /// "1̄11": each index's digits, a negative one with the overbar over its last digit; spaces between them when an index has two
    /// digits ("10 0 1̄").
    package static func label(_ hkl: MillerIndex) -> String {
        let parts = [hkl.h, hkl.k, hkl.l].map { $0 < 0 ? "\(-$0)\u{0304}" : "\($0)" }
        return [hkl.h, hkl.k, hkl.l].allSatisfy { abs($0) < 10 } ? parts.joined() : parts.joined(separator: " ")
    }
}

package nonisolated enum ZoneAxisOverlay {

    /// One simulated spot on the image.
    package struct Spot: Sendable, Equatable {
        package let hkl: MillerIndex
        package let row: Double
        package let column: Double
        /// The kit's intensity (|F|² with the excitation envelope), Å⁻⁴.
        package let intensity: Double
        /// The intensity over the strongest drawn spot's, 0...1.
        package let relative: Double
        package var label: String { ZoneAxisText.label(hkl) }
    }

    /// What the room asks for: the zone axis, its turn in the plane, and whether hkl labels are drawn.
    package struct Settings: Sendable, Equatable {
        package var isShown = false
        package var zoneAxis = SIMD3(0, 0, 1)
        /// Degrees, counter-clockwise from the kit's lab x (down the rows) toward lab y (along the columns).
        package var inPlaneDegrees = 0.0
        package var showsLabels = true
        package init() {}
    }

    /// The pixel radius of a spot of |q| (Å⁻¹): the inverse of the readout's q (`DiffractionCalibration.q(radius:)`), so a drawn
    /// spot reads back its own q. With a ring calibration that is the kit's `RingScale.radius` (exact with L and λ), else |q| / Δq.
    /// NaN past the detector's Bragg limit.
    package static func radius(q: Double, calibration: DiffractionCalibration) -> Double {
        if let ring = calibration.ring { return RingScale.radius(q: q, calibration: ring) }
        return q / calibration.deltaQ
    }

    /// The pixel q reaches farthest on this image: from the centre to its farthest corner, in Å⁻¹ (the simulator's k_max).
    package static func reach(width: Int, height: Int, centre: DiffractionCentre, deltaQ: Double) -> Double {
        let corners = [(0.0, 0.0), (0.0, Double(width - 1)), (Double(height - 1), 0.0), (Double(height - 1), Double(width - 1))]
        let r = corners.map { hypot($0.0 - centre.row, $0.1 - centre.column) }.max() ?? 0
        return r * deltaQ
    }

    /// The spots of `simulator` at `settings`' zone axis and turn, at `volts`, that land on a `width` × `height` image about
    /// `centre`, strongest first. Throws the kit's refusal (a zone axis with no length in the cell, a voltage).
    package static func spots(simulator: SpotPatternSimulator, settings: Settings, volts: Double, calibration: DiffractionCalibration,
                              centre: DiffractionCentre, width: Int, height: Int) throws -> [Spot] {
        let orientation = try CrystalOrientation(zoneAxis: settings.zoneAxis, inPlaneAngle: settings.inPlaneDegrees * .pi / 180,
                                                 cell: simulator.structure.cell)
        let pattern = try simulator.pattern(orientation: orientation, volts: volts)
        var placed: [(MillerIndex, Double, Double, Double)] = []
        for s in pattern.spots {
            let q = (s.position.x * s.position.x + s.position.y * s.position.y).squareRoot()
            guard q > 0 else { continue }
            let r = radius(q: q, calibration: calibration)
            let row = centre.row + r * s.position.x / q, column = centre.column + r * s.position.y / q
            guard row.isFinite, column.isFinite, row >= -0.5, row <= Double(height) - 0.5, column >= -0.5, column <= Double(width) - 0.5
            else { continue }
            placed.append((s.hkl, row, column, s.intensity))
        }
        let strongest = placed.map(\.3).max() ?? 1
        return placed.sorted { $0.3 != $1.3 ? $0.3 > $1.3 : $0.0 < $1.0 }
            .map { Spot(hkl: $0.0, row: $0.1, column: $0.2, intensity: $0.3, relative: strongest > 0 ? $0.3 / strongest : 0) }
    }
}
