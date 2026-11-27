//
//  TiltPlanning.swift
//  Role: the tilt planner as the Diffraction room's Map tab, Holder section and the agent door read it (plan rows R15 and R16,
//        #814, #815): the zone-axis map of the indexed crystal around the beam (`ZoneAxisMap.poles` to index 3, the three
//        lowest plane families' traces, kit S12, orix's stereographic projection), the double-tilt holder (`DoubleTiltHolder`:
//        tilts to a zone axis, the reach, the tilt axis calibrated from a second indexed pattern), the sentences the room says
//        and the tilt list CSV. Every number is the kit's; this file names them. Nothing about a microscope is assumed: α and β
//        are said only once the tilt axis is calibrated on the user's own two patterns.
//        Pure and nonisolated: the room and the door call the same functions. The CSV's numbers are exact, `%.17g`
//        (`CSVText.number`), as FFTExport's are.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import ImagoCore
import TEMBase

/// The holder as the document keeps it: the tilts now, where they came from, the limits and the calibrated axis.
package nonisolated struct HolderSettings: Sendable, Codable, Equatable {
    /// Where the tilts now came from.
    package enum TiltSource: String, Sendable, Codable, Equatable {
        /// The file's stage tilts.
        case file
        /// Typed in the Holder section.
        case typed
    }

    /// How the tilt axis was calibrated.
    package struct Calibration: Sendable, Codable, Equatable {
        /// The other pattern's name.
        package var otherPattern: String
        /// The stage's rotation between the two patterns (degrees).
        package var tiltChangeDeg: Double
        /// How far the measured rotation is from the stage's at the found axis (degrees).
        package var misfitDeg: Double
        /// The β sense the axis was fitted with: found from the pair, or the one set by hand (#932). nil in a document saved
        /// before the sense was kept, which read β the positive way.
        package var betaSense: DoubleTiltHolder.BetaSense?
        package init(otherPattern: String, tiltChangeDeg: Double, misfitDeg: Double, betaSense: DoubleTiltHolder.BetaSense? = nil) {
            self.otherPattern = otherPattern; self.tiltChangeDeg = tiltChangeDeg; self.misfitDeg = misfitDeg
            self.betaSense = betaSense
        }
    }

    /// Where the β sense in use came from.
    package enum BetaSenseSource: String, Sendable, Equatable {
        /// Set by hand in the Holder section.
        case hand
        /// Found by the calibration from the pair.
        case calibration
        /// Neither: β is read the positive way.
        case assumed
    }

    package var alphaDeg: Double = 0
    package var betaDeg: Double = 0
    package var source: TiltSource = .typed
    package var alphaLimitDeg: Double = 30
    package var betaLimitDeg: Double = 30
    /// The α axis in the pattern (degrees from lab x toward lab y); nil until calibrated.
    package var axisAngleDeg: Double?
    package var calibration: Calibration?
    /// The β sense set by hand (#932); nil lets the calibration find it from the pair.
    package var betaSenseSetting: DoubleTiltHolder.BetaSense?

    package init() {}

    /// The β sense in use: set by hand, else the calibration's, else positive.
    package var betaSense: DoubleTiltHolder.BetaSense { betaSenseSetting ?? calibration?.betaSense ?? .positive }
    package var betaSenseSource: BetaSenseSource {
        if betaSenseSetting != nil { return .hand }
        return calibration?.betaSense != nil ? .calibration : .assumed
    }

    /// The kit's holder.
    package var holder: DoubleTiltHolder {
        DoubleTiltHolder(alphaLimitDeg: alphaLimitDeg, betaLimitDeg: betaLimitDeg, axisAngleDeg: axisAngleDeg, betaSense: betaSense)
    }
    package var tilts: DoubleTiltHolder.Tilts { DoubleTiltHolder.Tilts(alpha: alphaDeg, beta: betaDeg) }

    /// The tilts from the file's stage readout when it has both (degrees), else unchanged.
    package mutating func readStage(alphaDeg: Double?, betaDeg: Double?) {
        guard let a = alphaDeg, let b = betaDeg, a.isFinite, b.isFinite else { return }
        self.alphaDeg = a; self.betaDeg = b; source = .file
    }
}

/// One row of the tilt list: a zone axis near the beam, its angle, and the tilts that bring it on (with a calibrated axis).
package nonisolated struct TiltListRow: Sendable, Equatable, Identifiable {
    package var id: String { TiltPlanning.zoneText(uvw) }
    package let uvw: SIMD3<Int>
    package let angleFromBeamDeg: Double
    /// Its stereographic position on the map: (along the pattern's rows, along its columns), the beam at the origin.
    package let position: SIMD2<Double>
    /// The tilts that bring it on the beam; nil while the axis is not calibrated.
    package let target: DoubleTiltHolder.Tilts?
    /// Inside the holder's limits; nil while the axis is not calibrated.
    package let reachable: Bool?
}

/// The map and the tilt list of one indexed crystal.
package nonisolated struct TiltPlan: Sendable, Equatable {
    package let phase: String
    package let holder: HolderSettings
    /// Zone axes to index 3 within 60° of the beam, nearest first.
    package let rows: [TiltListRow]
    /// The three lowest plane families' traces.
    package let traces: [ZoneAxisMap.Trace]
    /// The holder's reach on the map: the directions it can bring onto the beam, as one closed loop; empty while uncalibrated.
    package let reach: [SIMD2<Double>]

    /// The row of a zone axis, by [u v w].
    package func row(_ uvw: SIMD3<Int>) -> TiltListRow? { rows.first { $0.uvw == uvw } }

    /// The sentence under the map for a selected pole: "[1 1 2] is 35.3° from the beam. Set α +24.1°, β −26.6°: inside the
    /// holder's range." / "… Set α +41.0°, β −12.0°: outside the holder's range of ±30°." / uncalibrated: the angle and
    /// `uncalibratedSentence`.
    package func sentence(for row: TiltListRow) -> String {
        let head = "\(TiltPlanning.zoneText(row.uvw)) is \(String(format: "%.1f°", row.angleFromBeamDeg)) from the beam."
        guard let target = row.target, let reachable = row.reachable else {
            return head + " " + TiltPlanning.uncalibratedSentence
        }
        let set = "Set α \(TiltPlanning.signed(target.alpha)), β \(TiltPlanning.signed(target.beta))"
        if reachable { return head + " " + set + ": inside the holder's range." }
        return head + " " + set + ": outside the holder's range of " + TiltPlanning.limitsText(holder) + "."
    }

    /// The Holder section's calibration sentence: "Calibrated from two patterns 14° apart: tilt axis at 23° in the pattern, good to
    /// about 1°. β turns the positive way, found from the pair." or the uncalibrated sentence.
    package var calibrationSentence: String {
        guard let axis = holder.axisAngleDeg, let c = holder.calibration else { return TiltPlanning.uncalibratedSentence }
        return String(format: "Calibrated from two patterns %.0f° apart: tilt axis at %.0f° in the pattern, good to about ",
                      c.tiltChangeDeg, axis) + TiltPlanning.axisAccuracy(tiltChangeDeg: c.tiltChangeDeg) + ". "
            + TiltPlanning.betaSenseSentence(holder)
    }

    /// The tilt list as CSV: zone axis, angle from the beam, α, β, reachable (α, β and reachable empty while uncalibrated).
    package func csv() -> String {
        func g(_ v: Double) -> String { CSVText.number(v) }
        var lines = ["# \(AppName.writer) tilt list",
                     "# phase: \(CSVText.headerValue(phase))",
                     "# holder: now alpha \(g(holder.alphaDeg)) deg, beta \(g(holder.betaDeg)) deg (\(holder.source.rawValue)); "
                        + "limits alpha +-\(g(holder.alphaLimitDeg)) deg, beta +-\(g(holder.betaLimitDeg)) deg",
                     "# tilt axis: " + (holder.axisAngleDeg.map { "\(g($0)) deg in the pattern" } ?? "not calibrated"),
                     "# beta sense: \(TiltPlanning.betaSenseWord(holder.betaSense)) (\(holder.betaSenseSource.rawValue))"]
        lines.append("zone_axis,angle_from_beam_deg,alpha_deg,beta_deg,reachable")
        for r in rows {
            lines.append([CSVText.quoted(TiltPlanning.zoneText(r.uvw)), g(r.angleFromBeamDeg), r.target.map { g($0.alpha) } ?? "",
                          r.target.map { g($0.beta) } ?? "", r.reachable.map { $0 ? "yes" : "no" } ?? ""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

package nonisolated enum TiltPlanning {

    /// What the room says while the tilt axis is not calibrated.
    package static let uncalibratedSentence =
        "The tilt axis is not calibrated. Angles between zone axes are exact; α and β need a second indexed pattern at another tilt."

    /// The map of `structure` at `orientation` (measured with the holder at `holder`'s tilts): poles to index 3 within 60° of the
    /// beam, the three lowest plane families (Bragg angles at `wavelengthAngstroms`), and with a calibrated axis the tilts to each
    /// pole and the holder's reach.
    package static func plan(phase: String, structure: CrystalStructure, orientation: CrystalOrientation, holder: HolderSettings,
                             wavelengthAngstroms: Double?) -> TiltPlan {
        let kit = holder.holder, now = holder.tilts
        let poles = ZoneAxisMap.poles(structure: structure, orientation: orientation, maxIndex: 3, withinDeg: 60)
        let rows = poles.map { p -> TiltListRow in
            let target = kit.tilts(toZoneAxis: p.uvw, cell: structure.cell, orientation: orientation, at: now)
            return TiltListRow(uvw: p.uvw, angleFromBeamDeg: p.angleFromBeamDeg, position: p.position, target: target?.tilts,
                               reachable: target?.reachable)
        }
        let traces = ZoneAxisMap.planeTraces(structure: structure, orientation: orientation, families: 3,
                                             wavelengthAngstroms: wavelengthAngstroms)
        return TiltPlan(phase: phase, holder: holder, rows: rows, traces: traces,
                        reach: reach(holder: holder, orientation: orientation))
    }

    /// The outline of what the holder reaches: for each tilt on the edge of the limits (α and β swept along the rectangle's four
    /// sides), the crystal direction that tilt puts on the beam, in today's pattern frame, projected. Empty while uncalibrated.
    package static func reach(holder: HolderSettings, orientation: CrystalOrientation, perSide: Int = 45) -> [SIMD2<Double>] {
        let kit = holder.holder
        guard kit.axisAngleDeg != nil, perSide >= 1 else { return [] }
        let a = holder.alphaLimitDeg, b = holder.betaLimitDeg
        var edge: [DoubleTiltHolder.Tilts] = []
        for k in 0..<perSide { let t = Double(k) / Double(perSide); edge.append(.init(alpha: -a + 2 * a * t, beta: -b)) }
        for k in 0..<perSide { let t = Double(k) / Double(perSide); edge.append(.init(alpha: a, beta: -b + 2 * b * t)) }
        for k in 0..<perSide { let t = Double(k) / Double(perSide); edge.append(.init(alpha: a - 2 * a * t, beta: b)) }
        for k in 0..<perSide { let t = Double(k) / Double(perSide); edge.append(.init(alpha: -a, beta: b - 2 * b * t)) }
        var out: [SIMD2<Double>] = []
        for tilts in edge {
            guard let moved = kit.orientation(orientation, at: holder.tilts, movedTo: tilts) else { continue }
            // the crystal direction on the beam after the move, seen in today's lab frame
            if let p = DiffractoGeometry.StereographicProjection.project(orientation.labCoordinates(of: moved.beamDirection)) { out.append(p) }
        }
        return out
    }

    /// Calibrates the tilt axis from the room's pattern (`orientation` at `tilts`) and another indexed pattern of the same phase
    /// (`other` at `otherTilts`, named `otherName`), with the phase's symmetry. On success the settings carry the axis and how
    /// it was found; a refusal is the kit's sentence.
    package static func calibrate(_ settings: HolderSettings, structure: CrystalStructure, orientation: CrystalOrientation,
                                  other: CrystalOrientation, otherTilts: DoubleTiltHolder.Tilts, otherName: String)
        -> Result<HolderSettings, DoubleTiltHolder.CalibrationError> {
        do throws(DoubleTiltHolder.CalibrationError) {
            let c = try DoubleTiltHolder.calibrateAxis(orientation, at: settings.tilts, other, at: otherTilts,
                                                       symmetry: DoubleTiltHolder.properRotations(of: structure),
                                                       // A sense set by hand fits that sense alone; none fits both and refuses
                                                       // a pair that fits both (`ambiguousSense`, #932).
                                                       betaSense: settings.betaSenseSetting)
            var out = settings
            out.axisAngleDeg = c.axisAngleDeg
            out.calibration = .init(otherPattern: otherName, tiltChangeDeg: c.tiltChangeDeg, misfitDeg: c.misfitDeg,
                                    betaSense: c.betaSense)
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    /// How well a calibration fixes the axis, from the kit's planted cases (0.2° orientation error per pattern, p95): under 10°
    /// of tilt about 2.5°, 10 to 20° about 1.5°, above 20° about 1°.
    package static func axisAccuracy(tiltChangeDeg: Double) -> String {
        if tiltChangeDeg < 10 { return "2.5°" }
        if tiltChangeDeg < 20 { return "1.5°" }
        return "1°"
    }

    /// "positive" or "reversed".
    package static func betaSenseWord(_ sense: DoubleTiltHolder.BetaSense) -> String { sense == .positive ? "positive" : "reversed" }

    /// "β turns the positive way, found from the pair." / "β turns the reversed way, set by hand." / "β is taken to turn the
    /// positive way." (no calibration and none set).
    package static func betaSenseSentence(_ h: HolderSettings) -> String {
        switch h.betaSenseSource {
        case .hand: return "β turns the \(betaSenseWord(h.betaSense)) way, set by hand."
        case .calibration: return "β turns the \(betaSenseWord(h.betaSense)) way, found from the pair."
        case .assumed: return "β is taken to turn the positive way."
        }
    }

    /// "[1 1 2]".
    package static func zoneText(_ uvw: SIMD3<Int>) -> String { "[\(uvw.x) \(uvw.y) \(uvw.z)]" }

    /// "+24.1°", "−26.6°" (a true minus sign).
    package static func signed(_ v: Double) -> String {
        let t = String(format: "%.1f°", abs(v))
        return (v < 0 && t != "0.0°" ? "−" : "+") + t
    }

    /// "±30°", or "α ±30°, β ±20°" when the limits differ.
    package static func limitsText(_ h: HolderSettings) -> String {
        if h.alphaLimitDeg == h.betaLimitDeg { return String(format: "±%g°", h.alphaLimitDeg) }
        return String(format: "α ±%g°, β ±%g°", h.alphaLimitDeg, h.betaLimitDeg)
    }
}
