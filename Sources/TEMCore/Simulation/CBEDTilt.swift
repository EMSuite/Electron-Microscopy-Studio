//
//  CBEDTilt.swift
//  Role: the beam tilt of a CBED run (#1013): the orientation drawn by hand (the Tilt tool, the door's tilt_down and tilt_across)
//        read as SimulatoKit's small-angle beam tilt of the probe (`Probe(…, tilt:)`, abTEM 1.0.10's `Probe(tilt=…)`), and back:
//        the orientation the CBED pattern's overlay draws for a run's tilt, so the disc the overlay's Laue circle excites is the
//        one the run makes bright. Every number of the run is the kit's; this file is the frame.
//
//  The frame and the sign. DiffractoKit's `CrystalOrientation` writes the lab axes in the crystal's frame; lab z (the third
//  column, the beam direction) points at the source, so the beam travels along −z, and a reflection g is excited where its
//  excitation error (py4DSTEM's, k₀ = (0, 0, −1/λ)) vanishes: g_z = λ|g|²/2 in the lab frame. The slab's box is the orientation
//  at the specimen's in-plane angle (`SimulationSpecimen.Built.inPlaneAngle`), box z the zone axis pointing at the source; the
//  kit mirrors every period z → period − z and transmits along +z, which mirrors crystal and beam together, so a run sees the
//  crystal from the source with the box's x and y unchanged (SimulatoKit's `SlabBuilder`, #126). abTEM's tilt t (mrad) puts
//  e^{−2πi (kx tan tx + ky tan ty) Δz} on the propagator: the wave's transverse wave vector is tan(t) / λ, so in the unmirrored
//  slab the beam travels along (tan tx, tan ty, −1) of the box. With b the beam direction (toward the source) written in the
//  box, tan tx = −b_x / b_z and tan ty = −b_y / b_z. A zero-order g (g_z = 0 in the box) is then excited at t · g = −λ|g|²/2 in
//  both pictures, and the overlay draws it at (box x, box y) = (row, column), the pattern's frame (row = lab x, #931).
//

import DiffractoCore
import Foundation

package nonisolated enum CBEDTilt {
    /// The largest tilt a CBED run simulates, mrad (2.9°). abTEM's tilt is a phase ramp on the Fresnel propagator of slices
    /// projected along the zone axis; within a 1 Å slice the beam then walks at most 0.05 Å sideways, under a tenth of an atom's
    /// projected width, while a clean two-beam condition off a low-index zone needs 2 to 3° (Si 2 2̄ 0 off [1 1 0]: 45 mrad
    /// at right angles to g).
    package static let largestMrad = 50.0
    /// The tilt is kept to this step, mrad: a tilt under half of it is the zone axis (0).
    package static let stepMrad = 0.01

    /// The kit's beam tilt (x, y), mrad, for the beam of `orientation` in the slab whose box is `slab` (the zone axis at the
    /// specimen's in-plane angle), each component to `stepMrad`; nil when the beam points away from the source's side of the
    /// zone axis (90° or more off it).
    package static func tilt(of orientation: CrystalOrientation, slab: CrystalOrientation) -> SIMD2<Double>? {
        let b = slab.labCoordinates(of: orientation.beamDirection)
        guard b.z > 1e-12 else { return nil }
        return SIMD2(kept(atan2(-b.x, b.z) * 1000), kept(atan2(-b.y, b.z) * 1000))
    }

    /// The orientation whose beam is a run's `tiltMrad` in the slab `slab`, tilted about the box's x and y (`CrystalOrientation
    /// .tilted`) the least way from it: the overlay's orientation on the run's pattern. `tilt(of:slab:)` reads the tilt back.
    package static func orientation(slab: CrystalOrientation, tiltMrad: SIMD2<Double>) -> CrystalOrientation {
        var b = SIMD3(-tan(tiltMrad.x / 1000), -tan(tiltMrad.y / 1000), 1.0)
        b /= (b * b).sum().squareRoot()
        // R = R_y(θ) R_x(φ) moves the beam to Rᵀ ẑ = (−sin θ, cos θ sin φ, cos θ cos φ) in the box.
        return slab.tilted(by: SIMD2(atan2(b.y, b.z), -asin(min(1, max(-1, b.x)))))
    }

    /// The angle between the beam of a tilt and the zone axis, degrees.
    package static func degrees(_ tiltMrad: SIMD2<Double>) -> Double {
        let t = SIMD2(tan(tiltMrad.x / 1000), tan(tiltMrad.y / 1000))
        return atan((t * t).sum().squareRoot()) * 180 / .pi
    }

    /// The tilt's size, mrad (the angle off the zone axis).
    package static func magnitudeMrad(_ tiltMrad: SIMD2<Double>) -> Double { degrees(tiltMrad) * .pi / 180 * 1000 }

    /// Why a run at `tiltMrad` off `zoneAxis` is not simulated: past `largestMrad`; nil within it.
    package static func refusal(_ tiltMrad: SIMD2<Double>, zoneAxis: SIMD3<Int>) -> String? {
        let size = magnitudeMrad(tiltMrad)
        guard size > largestMrad + 1e-9 else { return nil }
        func n(_ v: Double) -> String { UnitDisplay.number(v, digits: 3) }
        return "The beam is tilted \(n(degrees(tiltMrad)))° (\(n(size)) mrad) off \(PatternIndexing.zoneText(zoneAxis)); CBED simulates a "
            + "beam tilt of at most \(n(largestMrad * 180 / .pi / 1000))° (\(n(largestMrad)) mrad), the small-angle tilt of the "
            + "propagator. Tilt back toward the zone axis."
    }

    /// "The beam is tilted 2.03° off [1 1 0] by hand: 35, 6.53 mrad along the rows and columns." for the section; nil for the zone
    /// axis.
    package static func note(_ tiltMrad: SIMD2<Double>, zoneAxis: SIMD3<Int>) -> String? {
        guard tiltMrad != .zero else { return nil }
        func n(_ v: Double) -> String { UnitDisplay.number(v, digits: 3) }
        return "The beam is tilted \(n(degrees(tiltMrad)))° off \(PatternIndexing.zoneText(zoneAxis)) by hand: \(n(tiltMrad.x)), "
            + "\(n(tiltMrad.y)) mrad along the rows and columns."
    }

    /// "beam tilt 10, 6.53 mrad (x, y)", the method line's part; nil for the zone axis.
    package static func methodPart(_ tiltMrad: SIMD2<Double>) -> String? {
        guard tiltMrad != .zero else { return nil }
        return "beam tilt \(UnitDisplay.number(tiltMrad.x, digits: 3)), \(UnitDisplay.number(tiltMrad.y, digits: 3)) mrad (x, y)"
    }

    /// A value to `stepMrad`, with −0 read as 0.
    static func kept(_ v: Double) -> Double {
        let r = (v / stepMrad).rounded() * stepMrad
        return r == 0 ? 0 : r
    }
}

/// A CBED run refused for its tilt (`CBEDTilt.refusal`).
package struct CBEDTiltRefusal: Error, LocalizedError, Equatable {
    package let sentence: String
    package var errorDescription: String? { sentence }
}
