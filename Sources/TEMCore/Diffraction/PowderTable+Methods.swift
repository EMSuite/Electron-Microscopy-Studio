//
//  PowderTable+Methods.swift
//  Role: the methods record the powder CSV carries (#817's rule, plan row R12, #811): how the peaks were computed (pymatgen's
//        XRDCalculator for X-rays, kit pin P49; the kinematic ring list for rings, pin P4), the line or beam energy, the range, the
//        overlap resolution, and the counts the table holds. The .xy profile stays two columns of numbers and carries none.
//

import Foundation
import DiffractoScattering
import FormatoCore
import ShellExport
import TEMBase
import TEMSEM

extension ExportMethods {

    package static func powderRecord(app: MethodsRecord.Software, source: MethodsRecord.Source, table: PowderTable) -> MethodsRecord {
        let s = table.settings
        let method: String, reference: MethodsRecord.Software?
        var settings: [MethodsRecord.Quantity]
        switch s.kind {
        case .xray:
            method = "X-ray powder pattern: atomic scattering factors, structure factor and Lorentz-polarisation, no Debye-Waller factor"
            reference = MethodsRecord.Software(name: "pymatgen", version: "2026.9.24")
            settings = [MethodsRecord.Quantity(name: "radiation", value: .text(s.radiation.name ?? "typed")),
                        MethodsRecord.Quantity(name: "wavelength (A)", value: .number(s.radiation.wavelengthAngstroms)),
                        MethodsRecord.Quantity(name: "two theta from (deg)", value: .number(s.range.lowerBound)),
                        MethodsRecord.Quantity(name: "two theta to (deg)", value: .number(s.range.upperBound))]
        case .rings:
            method = "electron rings: the kinematic ring list, the sum of |F|^2 over each ring's reflections"
            reference = nil
            settings = [MethodsRecord.Quantity(name: "beam (V)", value: .number(s.volts)),
                        MethodsRecord.Quantity(name: "reach (1/A)", value: .number(s.ringReach))]
        }
        settings.append(MethodsRecord.Quantity(name: "overlaps marked", value: .flag(s.markOverlaps)))
        let step = MethodsRecord.Step(name: "Powder pattern", method: method, reference: reference, settings: settings)
        return MethodsRecord(app: app, room: "diffraction", exportKind: "powder-csv", kits: kits, references: [],
                             sources: [source], steps: [step],
                             results: [MethodsRecord.Quantity(name: "phases", value: .number(Double(table.phases.count))),
                                       MethodsRecord.Quantity(name: "peaks", value: .number(Double(table.rows.count)))],
                             drawn: [])
    }
}
