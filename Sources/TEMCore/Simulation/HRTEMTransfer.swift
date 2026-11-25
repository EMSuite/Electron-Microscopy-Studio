//
//  HRTEMTransfer.swift
//  Role: the HRTEM controls' numbers (#895, plan row MA3): the optics presets of the mockup brief, the transfer function strip
//        (SimulatoKit's `profiles`, abTEM's `CTF.profiles`, with the point resolution and the aperture edge), and the defocus and
//        thickness table (five defocus columns centred on the current one, five thickness rows from the first step). Every number
//        is the kit's.
//

import Foundation
import SimulatoCore
import SimulatoProbe

/// The Optics popup of the mockup brief: Uncorrected is the default (Paul, 23 Nov).
package nonisolated enum HRTEMPreset: String, CaseIterable, Sendable {
    case uncorrected = "Uncorrected"
    case csCorrected = "Cs Corrected"
    case custom = "Custom"

    /// The preset's Cs (mm) and focal spread (nm); nil for Custom.
    package var values: (csMM: Double, focalSpreadNM: Double)? {
        switch self {
        case .uncorrected: (1.0, 5.0)
        case .csCorrected: (-0.010, 3.0)
        case .custom: nil
        }
    }

    /// `optics` with this preset's Cs and focal spread; Custom leaves them.
    package func applied(to optics: HRTEMOptics) -> HRTEMOptics {
        guard let values else { return optics }
        var o = optics
        o.csMM = values.csMM
        o.focalSpreadNM = values.focalSpreadNM
        return o
    }

    /// The preset whose Cs and focal spread `optics` has, else Custom.
    package static func of(_ optics: HRTEMOptics) -> HRTEMPreset {
        allCases.first { $0.values.map { $0.csMM == optics.csMM && $0.focalSpreadNM == optics.focalSpreadNM } ?? false } ?? .custom
    }
}

/// The transfer function strip: the transfer function and its envelope against spatial frequency, the point resolution and the
/// aperture edge. abTEM 1.0.10's `CTF.profiles` range: to 50 mrad without an aperture, 1.6 times the aperture with one.
package nonisolated struct HRTEMTransferCurve: Sendable, Equatable {
    /// Spatial frequency, 1/nm.
    package let frequencies: [Double]
    /// The phase transfer with every envelope and the aperture (abTEM's `ctf` row).
    package let transfer: [Double]
    /// The product of the focal-spread and angular-spread envelopes; nil when neither is set.
    package let envelope: [Double]?
    /// Scherzer's point resolution, Å (abTEM's `point_resolution`); nil without Cs.
    package let pointResolutionAngstrom: Double?
    /// The aperture's edge, 1/nm; nil without one.
    package let apertureFrequency: Double?

    package static func of(_ optics: HRTEMOptics, defocusNM: Double, points: Int = 400) throws -> HRTEMTransferCurve {
        let ctf = try optics.transferFunction(defocusNM: defocusNM)
        let profiles = try ctf.profiles(energy: optics.volts, points: points)
        let envelope: [Double]? = switch (profiles.temporalEnvelope, profiles.spatialEnvelope) {
        case (nil, nil): nil
        case (let t?, nil): t
        case (nil, let s?): s
        case (let t?, let s?): zip(t, s).map { $0 * $1 }
        }
        let resolution: Double? = try optics.csMM == 0 ? nil : ctf.pointResolution(energy: optics.volts)
        return HRTEMTransferCurve(frequencies: profiles.spatialFrequencies.map { $0 * 10 }, transfer: profiles.transfer,
                                  envelope: envelope, pointResolutionAngstrom: resolution,
                                  apertureFrequency: optics.apertureMrad.map { $0 * 1e-3 / profiles.wavelength * 10 })
    }
}

extension HRTEMImage {
    /// The defocus and thickness table: `cells[row][column]` is the image at `thicknessIndices[row]` and `defocusNM[column]`.
    package struct Table: Sendable, Equatable {
        package let defocusNM: [Double]
        package let thicknessIndices: [Int]
        package let thicknessNM: [Double]
        package let cells: [[CalibratedImage]]
    }

    /// The field of view a table cell is made at, nm: cells are drawn at 88 points, so the document's field of view (up to 20 nm)
    /// would cost time and memory for detail no one sees.
    package static let tableCellFieldNM = 2.0

    /// The table's description for its exported PNG: the method line at the first cell's settings, then the defocus columns and
    /// the thickness rows, so a reader of the figure has every setting.
    package static func tableDescription(_ table: Table, exit: HRTEMExitWaves, optics: HRTEMOptics) -> String {
        func list(_ v: [Double]) -> String { v.map { UnitDisplay.number($0, digits: 4) }.joined(separator: ", ") }
        let line = methodLine(exit, thicknessIndex: table.thicknessIndices.first ?? 0, defocusNM: table.defocusNM.first ?? 0, optics: optics)
        return "HRTEM defocus by thickness table · columns: defocus \(list(table.defocusNM)) nm · rows: thickness "
            + "\(list(table.thicknessNM)) nm · each cell \(UnitDisplay.number(tableCellFieldNM, digits: 3)) nm wide · \(line)"
    }

    /// The table's columns and rows allowed by the brief: 3 to 9.
    package static let tableCounts = 3 ... 9

    /// `count` defocus values `stepNM` apart, centred on `centreNM` (the brief's five columns, 10 nm apart).
    package static func defocusColumns(centreNM: Double, stepNM: Double, count: Int) -> [Double] {
        let n = min(max(count, tableCounts.lowerBound), tableCounts.upperBound)
        return (0 ..< n).map { centreNM + (Double($0) - Double(n - 1) / 2) * stepNM }
    }

    /// The stored exit waves nearest `stepNM`, 2 `stepNM`, … (`count` rows, the brief's five from 2 nm): each the stored wave whose
    /// thickness is nearest, each used once, in the stored range.
    package static func thicknessRows(_ exit: HRTEMExitWaves, stepNM: Double, count: Int) -> [Int] {
        let n = min(max(count, tableCounts.lowerBound), tableCounts.upperBound)
        guard stepNM.isFinite, stepNM > 0, !exit.waves.isEmpty else { return [] }
        var rows: [Int] = []
        for k in 1 ... n {
            let want = Double(k) * stepNM
            let index = exit.planePeriods.indices.min { abs(exit.thicknessNM(at: $0) - want) < abs(exit.thicknessNM(at: $1) - want) } ?? 0
            if rows.last != index { rows.append(index) }
        }
        return rows
    }

    /// Every cell of the table, each the image `image(_:thicknessIndex:defocusNM:optics:name:)` gives.
    package static func table(_ exit: HRTEMExitWaves, defocusNM: [Double], thicknessIndices: [Int], optics: HRTEMOptics,
                              name: String) throws -> Table {
        let cells = try thicknessIndices.map { t in
            try defocusNM.map { d in try image(exit, thicknessIndex: t, defocusNM: d, optics: optics, name: name) }
        }
        return Table(defocusNM: defocusNM, thicknessIndices: thicknessIndices,
                     thicknessNM: thicknessIndices.map { exit.thicknessNM(at: $0) }, cells: cells)
    }
}
