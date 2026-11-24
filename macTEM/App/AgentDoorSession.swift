//
//  AgentDoorSession.swift
//  Role: the agent door's look at the Results room's SEM session (#558): `get_session` gives the rows the session table shows
//        (`SEMSessionLedger.rows`: the EBSD dataset, the processing run, the scan maps, the indexing run, the orientation map, grains,
//        texture, the SEM-EDS lines and every file the SEM rooms wrote), each with the fields its Info shows, its methods and the
//        Output lines it logged; and an SEM spectrum's conditions as the EDS room's SEM Conditions section words them (the take-off
//        angle exspy computes among them).
//
//        ONE SOURCE PER FACT: the rows are the ledger's, the same the table, the session report and ⌘C read; the conditions are
//        `SEMEDSFormat.conditionRows`, the inspector's rows. Numbers keep the point, as every door answer does.
//

import Foundation
import ShellAgentDoor
import TEMCore

extension MacTEMAgentDoor {
    static let sessionTools: [AgentTool] = [
        AgentTool(name: "get_session", title: "SEM session",
                  summary: "The Results room's SEM session table: every SEM result of the window (the EBSD dataset, the processing run, the scan "
                      + "maps, the indexing run, the orientation map, grains, texture, the SEM-EDS line intensities, every file the SEM rooms "
                      + "wrote), each with its group, value, source, time, the fields its Info shows, the methods that made it and the Output "
                      + "lines it logged; and an SEM spectrum's conditions as the EDS room's SEM Conditions section lists them (with the "
                      + "take-off angle).",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return .json(session(appState))
        },
    ]

    /// Numbers with a point, whatever the Mac's Region.
    private static let sessionLocale = Locale(identifier: "en_US_POSIX")

    static func session(_ appState: AppState) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = SEMSessionLedger.rows(of: appState, locale: sessionLocale).map { row in
            let fields: [[String: Any]] = row.fields.map { ["name": $0.name, "value": $0.value] }
            let log: [[String: Any]] = row.log.map { ["time": iso.string(from: $0.time), "text": $0.text] }
            return [
                "id": row.id, "group": row.kind.title, "result": row.label, "value": row.value, "source": row.source,
                "time": AgentJSON.orNull(row.time.map { iso.string(from: $0) }), "method": row.methodTitle,
                "methods": row.methods.map(\.title), "fields": fields, "file": AgentJSON.orNull(row.file?.lastPathComponent),
                "log": log,
            ]
        }
        let eds = appState.semEDS
        var conditions: Any = NSNull()
        if eds.isSEMSpectrum, let spectrum = eds.spectrum {
            conditions = SEMEDSFormat.conditionRows(spectrum.conditions, microscope: spectrum.microscope, locale: sessionLocale)
                .map { ["label": $0.label, "value": $0.value] as [String: Any] }
        }
        return ["rows": rows, "sem_conditions": conditions, "sem_eds_failure": AgentJSON.orNull(eds.failure)]
    }
}
