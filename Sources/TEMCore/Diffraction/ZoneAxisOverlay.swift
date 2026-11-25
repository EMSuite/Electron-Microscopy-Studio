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
import DiffractoScattering

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
        // A range test, not abs: abs(Int.min) traps, and Int reads "-9223372036854775808" (#933).
        guard values.count == 3, values.contains(where: { $0 != 0 }), values.allSatisfy({ (-99...99).contains($0) }) else { return nil }
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
    /// The spots that carry their hkl when Labels is on: the 60 strongest of at least 2 % of the strongest (`spots` comes strongest
    /// first), then the spots of double diffraction, so a dense pattern stays readable. The room's overlay and Export Figure… (#822).
    package static let labelledCount = 60
    package static let labelledFraction = 0.02

    package static func labelled(_ spots: [Spot]) -> [Spot] {
        Array(spots.filter { $0.relative >= labelledFraction }.prefix(labelledCount)) + spots.filter(\.isDoubleDiffraction).prefix(labelledCount)
    }

    /// One simulated spot on the image.
    package struct Spot: Sendable, Equatable {
        package let hkl: MillerIndex
        package let row: Double
        package let column: Double
        /// The kit's intensity (|F|² with the excitation envelope), Å⁻⁴; for a dynamical pattern the beam's, a fraction of the
        /// incident beam (#911).
        package let intensity: Double
        /// The intensity over the strongest drawn spot's, 0...1 (0 for a spot of double diffraction).
        package let relative: Double
        /// A spot double diffraction adds (#786): g₁ + g₂ where the kinematical pattern has none (a forbidden reflection). It has
        /// no intensity (kinematical theory gives none) and is drawn as an open ring. In a dynamical pattern (#911) it is a beam the
        /// multislice gives where the kinematical pattern has none, with its intensity, drawn the same way.
        package let isDoubleDiffraction: Bool
        package var label: String { ZoneAxisText.label(hkl) }
        package init(hkl: MillerIndex, row: Double, column: Double, intensity: Double, relative: Double, isDoubleDiffraction: Bool = false) {
            self.hkl = hkl; self.row = row; self.column = column; self.intensity = intensity; self.relative = relative
            self.isDoubleDiffraction = isDoubleDiffraction
        }
    }

    /// What the room asks for: the zone axis, its turn in the plane, and which hkl labels are drawn.
    package struct Settings: Sendable, Equatable {
        package var isShown = false
        package var zoneAxis = SIMD3(0, 0, 1)
        /// Degrees, counter-clockwise from the kit's lab x (down the rows) toward lab y (along the columns).
        package var inPlaneDegrees = 0.0
        /// Which simulated spots carry their hkl (#1045): the strongest that fit, all that fit, or none.
        package var labelMode = HKLLabelMode.strongest
        /// Whether any hkl is drawn: the session file's and the door's `labels`. Switching it on keeps a mode already chosen.
        package var showsLabels: Bool {
            get { labelMode != .off }
            set { labelMode = newValue ? (labelMode == .off ? .strongest : labelMode) : .off }
        }
        /// The full orientation Index found, drawn in place of the typed zone axis and turn until either is typed again.
        package var indexed: CrystalOrientation?
        /// Index's measured |q| over |g|: the simulated spots are drawn at |g| times this, onto the measured ones (1 when typed).
        package var scale = 1.0
        /// Draw the spots double diffraction adds (#786).
        package var doubleDiffraction = false
        /// σ of the excitation envelope exp(−s²/2σ²), Å⁻¹; spots with |s| up to three times this are kept (the kit's default,
        /// 0.02, and py4DSTEM's multiple).
        package var excitationError = defaultExcitationError
        package static let defaultExcitationError = 0.02
        package init() {}

        /// The kit's settings for the drawn pattern.
        package var patternSettings: SpotPatternSimulator.Settings { SpotPatternSimulator.Settings(sigmaExcitationError: excitationError) }

        /// The orientation drawn: Index's, else the typed zone axis turned in the plane.
        package func orientation(cell: UnitCell) throws -> CrystalOrientation {
            if let indexed { return indexed }
            return try CrystalOrientation(zoneAxis: zoneAxis, inPlaneAngle: inPlaneDegrees * .pi / 180, cell: cell)
        }
    }

    /// Whether `orientation`'s beam runs along `zoneAxis` (within 1e−9 of the cosine, about 0.003°): a turn about the beam and Flip
    /// keep it along; a tilt or the antiparallel axis does not. What Dynamical's beams need, as they are those of the exact axis (#911).
    package static func isAlong(_ orientation: CrystalOrientation, zoneAxis: SIMD3<Int>, cell: UnitCell) -> Bool {
        let a = cell.realLattice, u = SIMD3<Double>(zoneAxis)
        let direction = u.x * a[0] + u.y * a[1] + u.z * a[2]
        let beam = orientation.beamDirection
        let lengths = (direction * direction).sum().squareRoot() * (beam * beam).sum().squareRoot()
        guard lengths > 0 else { return false }
        return (direction * beam).sum() / lengths >= 1 - 1e-9
    }

    // MARK: Turning by hand (#787)

    /// The Tilt tool's rate: degrees of tilt per screen point dragged (a 100-point drag tilts 5°).
    package static let degreesPerPoint = 0.05

    /// The orientation after a Tilt-tool drag of `drag` screen points, (down the rows, along the columns) = (lab x, lab y): the beam
    /// tilts toward the drag, a drag down the rows about lab y and one along the columns about lab x (`CrystalOrientation.tilted`).
    package static func tilted(_ base: CrystalOrientation, drag: SIMD2<Double>) -> CrystalOrientation {
        let k = degreesPerPoint * .pi / 180
        return base.tilted(by: SIMD2(-drag.y * k, drag.x * k))
    }

    /// The orientation after an ⌥ drag from `start` to `now`, each the pointer's (row, column) offset from the pattern's centre in
    /// screen points: turned about the beam by the angle the pointer swept, so the spot under the pointer follows it. nil within
    /// 2 points of the centre, where the angle means nothing.
    package static func turned(_ base: CrystalOrientation, start: SIMD2<Double>, now: SIMD2<Double>) -> CrystalOrientation? {
        guard hypot(start.x, start.y) > 2, hypot(now.x, now.y) > 2 else { return nil }
        return base.rotatedInPlane(by: atan2(now.y, now.x) - atan2(start.y, start.x))
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
    ///
    /// With `dynamical` (#911) the spots are the multislice's zone-axis beams at its thickness instead, each at the place the
    /// orientation puts its g: a beam the kinematical pattern also has is a spot, one it has not (a forbidden reflection made by
    /// double diffraction) an open ring, and a beam below `DynamicalBeams.drawnFraction` of the strongest is left out.
    package static func spots(simulator: SpotPatternSimulator, settings: Settings, volts: Double, calibration: DiffractionCalibration,
                              centre: DiffractionCentre, width: Int, height: Int, dynamical: DynamicalBeams? = nil) throws -> [Spot] {
        let orientation = try settings.orientation(cell: simulator.structure.cell)
        let scale = settings.scale.isFinite && settings.scale > 0 ? settings.scale : 1
        let pattern = try simulator.pattern(orientation: orientation, volts: volts, settings: settings.patternSettings)
        /// The pixel of (qx, qy) Å⁻¹ at the scale, nil off the image.
        func pixel(_ position: SIMD2<Double>) -> (row: Double, column: Double)? {
            let q = scale * (position.x * position.x + position.y * position.y).squareRoot()
            guard q > 0 else { return nil }
            let r = radius(q: q, calibration: calibration)
            let row = centre.row + r * scale * position.x / q, column = centre.column + r * scale * position.y / q
            guard row.isFinite, column.isFinite, row >= -0.5, row <= Double(height) - 0.5, column >= -0.5, column <= Double(width) - 0.5
            else { return nil }
            return (row, column)
        }
        if let dynamical {
            let cell = simulator.structure.cell
            // Forbidden is "|F| under the kit's cut within its k_max", not "outside the drawn pattern": the excitation envelope and
            // the tilt also leave allowed beams out of `pattern.spots`, and those are no double diffraction.
            let allowed = Set(simulator.reflections.map(\.structureFactor.hkl))
            func forbidden(_ hkl: MillerIndex) -> Bool { !allowed.contains(hkl) && cell.gLength(hkl) <= simulator.kMax }
            let floor = (dynamical.intensities.values.max() ?? 0) * DynamicalBeams.drawnFraction
            var placed: [(hkl: MillerIndex, row: Double, column: Double, intensity: Double)] = []
            for (hkl, intensity) in dynamical.intensities where intensity > floor {
                let lab = orientation.labCoordinates(of: cell.gVector(hkl))
                guard let p = pixel(SIMD2(lab.x, lab.y)) else { continue }
                placed.append((hkl, p.row, p.column, intensity))
            }
            let strongest = placed.map(\.intensity).max() ?? 1
            return placed.sorted { $0.intensity != $1.intensity ? $0.intensity > $1.intensity : $0.hkl < $1.hkl }.map {
                Spot(hkl: $0.hkl, row: $0.row, column: $0.column, intensity: $0.intensity,
                     relative: strongest > 0 ? $0.intensity / strongest : 0, isDoubleDiffraction: forbidden($0.hkl))
            }
        }
        var placed: [(MillerIndex, Double, Double, Double)] = []
        for s in pattern.spots {
            guard let p = pixel(s.position) else { continue }
            placed.append((s.hkl, p.row, p.column, s.intensity))
        }
        let strongest = placed.map(\.3).max() ?? 1
        var out = placed.sorted { $0.3 != $1.3 ? $0.3 > $1.3 : $0.0 < $1.0 }
            .map { Spot(hkl: $0.0, row: $0.1, column: $0.2, intensity: $0.3, relative: strongest > 0 ? $0.3 / strongest : 0) }
        if settings.doubleDiffraction {
            // The kit's added spots of this one crystal (every route within it, so each has its hkl), after the kinematical ones.
            let added = try DoubleDiffraction.spots(simulator: simulator, orientation: orientation, volts: volts, settings: settings.patternSettings).added
            out += added.compactMap { s in
                guard let hkl = s.hkl, let p = pixel(s.position) else { return nil }
                return Spot(hkl: hkl, row: p.row, column: p.column, intensity: 0, relative: 0, isDoubleDiffraction: true)
            }.sorted { $0.hkl < $1.hkl }
        }
        return out
    }
}
