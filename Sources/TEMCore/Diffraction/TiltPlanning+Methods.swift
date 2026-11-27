//
//  TiltPlanning+Methods.swift
//  Role: the methods record the tilt list CSV carries (#817's rule, plan row R16, #815): the zone-axis map (orix's stereographic
//        projection, DiffractoKit S12), the holder model and how its axis was found, and the counts the list holds.
//

import Foundation
import FormatoCore
import ShellExport
import TEMBase
import TEMSEM

extension ExportMethods {

    package static func tiltListRecord(app: MethodsRecord.Software, source: MethodsRecord.Source, plan: TiltPlan) -> MethodsRecord {
        let h = plan.holder
        var steps = [
            MethodsRecord.Step(name: "Zone-axis map",
                               method: "zone axes to index 3 within 60° of the beam from Index's orientation; stereographic projection X = x/(1+z), Y = y/(1+z)",
                               reference: MethodsRecord.Software(name: "orix", version: "0.15.0")),
            MethodsRecord.Step(name: "Holder",
                               method: "double tilt: α about the holder axis, β about the axis α carries; tilts to bring a zone axis onto the beam in closed form",
                               settings: [MethodsRecord.Quantity(name: "alpha now (deg)", value: .number(h.alphaDeg)),
                                          MethodsRecord.Quantity(name: "beta now (deg)", value: .number(h.betaDeg)),
                                          MethodsRecord.Quantity(name: "alpha limit (deg)", value: .number(h.alphaLimitDeg)),
                                          MethodsRecord.Quantity(name: "beta limit (deg)", value: .number(h.betaLimitDeg))]),
        ]
        if let axis = h.axisAngleDeg {
            var settings = [MethodsRecord.Quantity(name: "tilt axis (deg)", value: .number(axis))]
            if let c = h.calibration {
                settings.append(MethodsRecord.Quantity(name: "tilt change (deg)", value: .number(c.tiltChangeDeg)))
                settings.append(MethodsRecord.Quantity(name: "misfit (deg)", value: .number(c.misfitDeg)))
            }
            steps.append(MethodsRecord.Step(name: "Tilt axis",
                                            method: h.calibration == nil ? "typed"
                                                : "calibrated from a second indexed pattern at other stage tilts",
                                            settings: settings))
        }
        return MethodsRecord(app: app, room: "diffraction", exportKind: "tilt-list-csv", kits: kits, references: [],
                             sources: [source], steps: steps,
                             results: [MethodsRecord.Quantity(name: "zone axes", value: .number(Double(plan.rows.count))),
                                       MethodsRecord.Quantity(name: "reachable",
                                                              value: .number(Double(plan.rows.filter { $0.reachable == true }.count)))],
                             drawn: [])
    }
}
