//
//  CBEDThickness.swift
//  Role: the specimen thickness from a two-beam CBED pattern (#916, plan row MA15): the transmitted and the diffracted disc found on
//        the pattern, the intensity profile across the diffracted disc along g, and DiffractoKit's two-beam fit of it
//        (`TwoBeamThickness.fit`, Kelly et al. 1975 with Allen's 1981 fringe line). Every number of the fit is the kit's.
//
//        The discs: the transmitted disc is at the room's centre, its radius where the azimuthal mean about it falls to a quarter
//        of its largest value (the fringes run across g, so the mean over every turn keeps the edge). The reflection is proposed
//        from the phase: of its first `proposedFamilies` families, the turn of the ring |g| / Δq about the centre where the mean
//        over a disc of 0.8 the radius is highest is on the diffracted disc; the middle of the turns about it above half height
//        (halfway between the ring's median and that highest mean) is the disc's centre (#978). The profile runs along g through it over
//        0.9 of the radius either side, every half pixel, each sample the mean of a band five pixels wide across g (bilinear).
//

import Foundation
import DiffractoCore
import DiffractoScattering
import DiffractoGeometry

package nonisolated enum CBEDThickness {
    /// The length of a vector on the pattern, pixels.
    static func length(_ v: SIMD2<Double>) -> Double { (v * v).sum().squareRoot() }

    /// The families tried when the reflection is proposed.
    package static let proposedFamilies = 6
    /// A residual above this fraction of the peak is "does not follow a two-beam profile" (the design's 18 % example is poor; the
    /// simulated Si 220 disc fits at a few %).
    package static let poorResidual = 0.1

    /// The discs and the profile read off the pattern.
    package struct Discs: Sendable, Equatable {
        /// The transmitted and the diffracted disc's centres, pixels (row, column).
        package let transmitted: SIMD2<Double>
        package let diffracted: SIMD2<Double>
        /// The disc radius, pixels.
        package let radius: Double
        /// The reflection and its |g|, Å⁻¹.
        package let hkl: MillerIndex
        package let gLength: Double
        /// The profile: offsets from the diffracted disc's centre along g (pixels, positive away from the transmitted disc) and the
        /// intensities.
        package let offsets: [Double]
        package let intensities: [Double]
    }

    /// A measurement: the discs, the kit's fit and the sentence.
    package struct Measurement: Sendable, Equatable {
        package let discs: Discs
        package let fit: TwoBeamThicknessFit
        package let phase: String
        package let volts: Double

        /// The one thickness to report, nm; nil when the kit returned a second candidate (the verdict is "ambiguous").
        package var thicknessNM: Double? { fit.isAmbiguous ? nil : fit.thickness / 10 }
        package var isPoor: Bool { fit.residual > poorResidual }

        /// The design's sentences: found, two candidates, poor.
        package var sentence: String {
            func nm(_ a: Double) -> String { UnitDisplay.number(a / 10, digits: 3) }
            let reflection = "\(phase) \(ZoneAxisText.label(discs.hkl))"
            if let second = fit.secondCandidate {
                return "Two thicknesses fit this disc about equally: \(nm(fit.thickness)) nm and \(nm(second.thickness)) nm. "
                    + "A stray line crosses the disc; a cleaner two-beam tilt would decide."
            }
            let residual = UnitDisplay.number(fit.residual * 100, digits: 2)
            if isPoor {
                return "The profile does not follow a two-beam profile (residual \(residual) % of the peak). Tilt until only one reflection is strong."
            }
            let edge = fit.extinctionDistanceAtWindowEdge
                ? " The extinction distance sits at the edge of its window: other beams are strong, so tilt closer to two beams." : ""
            let line = fit.fringeLine.map { " The fringe line through the minima gives \(nm($0.thickness)) nm." } ?? ""
            return "Thickness \(nm(fit.thickness)) nm along the beam (\(reflection), extinction distance \(nm(fit.extinctionDistance)) nm, "
                + "two-beam value \(nm(fit.twoBeamExtinctionDistance)) nm). Residual \(residual) % of the peak." + line + edge
        }

        /// The verdict in one word for the header and the door: found, ambiguous, poor.
        package var verdict: String { fit.isAmbiguous ? "ambiguous" : (isPoor ? "poor" : "found") }

        /// "Two-beam CBED thickness · Si 2 2 0 · 200 kV · whole-profile fit, extinction distance free within 0.7 to 1.15 of the
        /// two-beam value · Kelly et al. 1975"
        package var methodLine: String {
            let w = TwoBeamThickness.extinctionWindow
            return ["Two-beam CBED thickness", "\(phase) \(ZoneAxisText.label(discs.hkl))", "\(UnitDisplay.number(volts / 1000, digits: 4)) kV",
                    "whole-profile fit, extinction distance free within \(UnitDisplay.number(w.lowerBound, digits: 3)) to "
                        + "\(UnitDisplay.number(w.upperBound, digits: 3)) of the two-beam value", "Kelly et al. 1975"]
                .joined(separator: " · ")
        }

        /// The fitted curve at each profile sample, in the profile's intensity unit, for the plot.
        package var fittedCurve: [Double] {
            let factor = discs.gLength * discs.gLength * ElectronWavelength.angstroms(volts: volts)
                / CBEDThickness.length(discs.diffracted - discs.transmitted)
            return discs.offsets.map {
                fit.scale * TwoBeamThickness.intensity(deviation: $0 * factor - fit.centre, thickness: fit.thickness,
                                                       extinctionDistance: fit.extinctionDistance) + fit.background
            }
        }

        /// The minima the fit predicts inside the profile, as offsets (pixels) with their order, for the plot's numbers.
        package var minima: [(order: Int, offset: Double)] {
            let factor = discs.gLength * discs.gLength * ElectronWavelength.angstroms(volts: volts)
                / CBEDThickness.length(discs.diffracted - discs.transmitted)
            guard factor > 0, let first = discs.offsets.first, let last = discs.offsets.last else { return [] }
            var out: [(order: Int, offset: Double)] = []
            for n in 1 ... 40 {
                guard let s = TwoBeamThickness.minimumDeviation(order: n, thickness: fit.thickness, extinctionDistance: fit.extinctionDistance)
                else { continue }
                for sign in [-1.0, 1.0] {
                    let x = (fit.centre + sign * s) / factor
                    if x >= first, x <= last { out.append((n, x)) }
                }
            }
            return out.sorted { $0.offset < $1.offset }
        }

        package static func == (a: Measurement, b: Measurement) -> Bool {
            a.discs == b.discs && a.fit == b.fit && a.phase == b.phase && a.volts == b.volts
        }
    }

    /// Why no thickness, in the room's words.
    package enum Refusal: Error, Equatable, Sendable {
        case noPhase
        case noScale
        case noVoltage
        case noDisc
        case kit(String)

        package var sentence: String {
            switch self {
            case .noPhase: "Add the phase first: the reflection sets the scale."
            case .noScale: "Calibrate the pattern first: the discs are found at |g| from the centre."
            case .noVoltage: "Type the beam energy first: the extinction distance depends on it."
            case .noDisc: "No diffracted disc stands out on the rings of the phase's first reflections: tilt to a two-beam condition."
            case .kit(let words): words
            }
        }
    }

    /// The discs and the profile on `image` about `centre` at `deltaQ` (Å⁻¹ per pixel) for `structure`; `hkl` forces the
    /// reflection, else it is proposed from the first families of `families` (strongest first is not needed: the brightest ring
    /// wins), each by its first member: the members of a family share |g|, and the turn found on the ring is the disc's.
    package static func discs(image: CalibratedImage, centre: SIMD2<Double>, deltaQ: Double, cell: UnitCell,
                              families: [ReflectionFamily], hkl forced: MillerIndex? = nil) throws(Refusal) -> Discs {
        guard deltaQ.isFinite, deltaQ > 0 else { throw .noScale }
        let candidates: [MillerIndex] = forced.map { [$0] } ?? families.prefix(proposedFamilies).compactMap(\.members.first)
        let rings = candidates.map { (hkl: $0, g: cell.gLength($0)) }.filter { $0.g / deltaQ > 4 }
        guard let nearest = rings.map(\.g).min() else { throw .noDisc }
        let radius = discRadius(image, centre: centre, reach: nearest / deltaQ / 2)
        // The diffracted disc: of every ring, the turn where the mean over a disc of 0.8 the radius is highest. The fringes run
        // across g, so the disc's mean, not its brightest pixel, finds its centre; |g| / Δq sets the distance. A disc of 0.8 the
        // radius slides along the ring inside the reflection's disc with the same mean, so the highest mean is a plateau of turns
        // (the first turn of the plateau sat up to 0.2 of the radius off). On a recorded pattern Poisson noise, Kikuchi lines and a
        // sloping background break the plateau, so the centre is the middle of the turns about the highest one above half height,
        // halfway between the ring's background (its median: the disc covers a small part of the ring) and its top (#978). The
        // overlap of the sliding disc with the reflection's falls steeply at both half-height turns, so noise moves them little;
        // a sloping background moves the middle by its change across the disc over that fall, about a pixel on the test's ramp.
        var best: (hkl: MillerIndex, g: Double, r: Double, steps: Int, values: [Double?], value: Double)?
        let pattern = discPattern(radius: 0.8 * radius)
        for ring in rings {
            let r = ring.g / deltaQ
            let steps = max(360, Int(4 * Double.pi * r))
            let values = (0 ..< steps).map { k -> Double? in
                let a = 2 * Double.pi * Double(k) / Double(steps)
                return mean(image, at: centre + r * SIMD2(cos(a), sin(a)), pattern: pattern)
            }
            if let top = values.compactMap({ $0 }).max(), best == nil || top > best!.value {
                best = (ring.hkl, ring.g, r, steps, values, top)
            }
        }
        guard let found = best, let peak = found.values.firstIndex(where: { $0 == found.value }) else { throw .noDisc }
        let ring = found.values.compactMap { $0 }.sorted()
        let background = ring.count % 2 == 1 ? ring[ring.count / 2] : (ring[ring.count / 2 - 1] + ring[ring.count / 2]) / 2
        let half = (background + found.value) / 2
        func aboveHalf(_ k: Int) -> Bool { (found.values[(k % found.steps + found.steps) % found.steps] ?? -.infinity) >= half }
        var low = peak, high = peak
        while high - low < found.steps, aboveHalf(low - 1) { low -= 1 }
        while high - low < found.steps, aboveHalf(high + 1) { high += 1 }
        let a = 2 * Double.pi * (Double(low + high) / 2) / Double(found.steps)
        let c = centre + found.r * SIMD2(cos(a), sin(a))
        let g = (c - centre) / length(c - centre), n = SIMD2(-g.y, g.x)
        var offsets: [Double] = [], intensities: [Double] = []
        var x = -0.9 * radius
        while x <= 0.9 * radius {
            var sum = 0.0, count = 0
            for w in -2 ... 2 {
                if let v = sample(image, c + x * g + Double(w) * n) { sum += v; count += 1 }
            }
            if count > 0 { offsets.append(x); intensities.append(sum / Double(count)) }
            x += 0.5
        }
        guard offsets.count >= TwoBeamThickness.minimumSamples else { throw .noDisc }
        return Discs(transmitted: centre, diffracted: c, radius: radius, hkl: found.hkl, gLength: found.g, offsets: offsets,
                     intensities: intensities)
    }

    /// The transmitted disc's radius, pixels: the azimuthal mean about the centre falls below a quarter of its largest value and
    /// stays there for two pixels (the fringes run across g, so the mean over every turn keeps the disc's edge); at most `reach`.
    static func discRadius(_ image: CalibratedImage, centre: SIMD2<Double>, reach: Double) -> Double {
        var means: [Double] = []
        var rho = 0.0
        while rho <= reach {
            let steps = max(16, Int(2 * Double.pi * rho))
            var sum = 0.0, count = 0
            for k in 0 ..< steps {
                let a = 2 * Double.pi * Double(k) / Double(steps)
                if let v = sample(image, centre + rho * SIMD2(cos(a), sin(a))) { sum += v; count += 1 }
            }
            means.append(count > 0 ? sum / Double(count) : 0)
            rho += 0.5
        }
        let top = means.max() ?? 0
        for i in means.indices where means[i] < top / 4 {
            if means[i ..< min(means.count, i + 4)].allSatisfy({ $0 < top / 4 }) { return max(2, Double(i) * 0.5) }
        }
        return max(2, reach)
    }

    /// The offsets of a disc of `radius` on a one-pixel lattice, for `mean`.
    static func discPattern(radius: Double) -> [SIMD2<Double>] {
        let r = Int(radius.rounded(.down))
        var out: [SIMD2<Double>] = []
        for dr in -r ... r { for dc in -r ... r where Double(dr * dr + dc * dc) <= radius * radius { out.append(SIMD2(Double(dr), Double(dc))) } }
        return out.isEmpty ? [SIMD2(0, 0)] : out
    }

    /// The mean of the pattern over `pattern` about `p`; nil when any sample is off the image.
    static func mean(_ image: CalibratedImage, at p: SIMD2<Double>, pattern: [SIMD2<Double>]) -> Double? {
        var sum = 0.0
        for d in pattern {
            guard let v = sample(image, p + d) else { return nil }
            sum += v
        }
        return sum / Double(pattern.count)
    }

    /// Measure Thickness: the discs, then the kit's fit with the phase's two-beam extinction distance at `volts`.
    package static func measure(image: CalibratedImage, centre: SIMD2<Double>, deltaQ: Double, structure: CrystalStructure,
                                families: [ReflectionFamily], phase: String, volts: Double,
                                hkl: MillerIndex? = nil) throws(Refusal) -> Measurement {
        let discs = try Self.discs(image: image, centre: centre, deltaQ: deltaQ, cell: structure.cell, families: families, hkl: hkl)
        let profile = TwoBeamProfile(offsets: discs.offsets, discSeparation: length(discs.diffracted - discs.transmitted),
                                     gLength: discs.gLength, wavelength: ElectronWavelength.angstroms(volts: volts),
                                     intensities: discs.intensities)
        do throws(TwoBeamThicknessError) {
            let fit = try TwoBeamThickness.fit(profile, reflection: discs.hkl, in: structure, volts: volts)
            return Measurement(discs: discs, fit: fit, phase: phase, volts: volts)
        } catch .tooFewMinima(_, _) {
            throw .kit("Fewer than two fringes on each side of the disc. This method needs a thicker area or a reflection with a shorter extinction distance.")
        } catch {
            throw .kit(error.description)
        }
    }

    /// The pixel at (row, column), bilinear; nil off the image or on a missing pixel.
    static func sample(_ image: CalibratedImage, _ p: SIMD2<Double>) -> Double? {
        let r0 = Int(p.x.rounded(.down)), c0 = Int(p.y.rounded(.down))
        guard r0 >= 0, c0 >= 0, r0 + 1 < image.height, c0 + 1 < image.width else { return nil }
        let fr = p.x - Double(r0), fc = p.y - Double(c0)
        func v(_ r: Int, _ c: Int) -> Double { Double(image.value(at: r * image.width + c)) }
        let value = (1 - fr) * ((1 - fc) * v(r0, c0) + fc * v(r0, c0 + 1)) + fr * ((1 - fc) * v(r0 + 1, c0) + fc * v(r0 + 1, c0 + 1))
        return value.isFinite ? value : nil
    }
}
