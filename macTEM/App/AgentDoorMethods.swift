//
//  AgentDoorMethods.swift
//  Role: the agent door's methods record (#818): `get_methods_record` returns what File > Export Methods Record… writes and Edit >
//        Copy Methods Paragraph copies for the room on screen, the record's JSON and its paragraph, with the save panel's "Leave out
//        file names" as `leave_out_file_names`. ONE SOURCE PER FACT: both come from `MethodsRecordExport.record(of:)`, the menu's own.
//

import Foundation
import ShellAgentDoor
import ShellExport
import TEMCore

extension MacTEMAgentDoor {
    static let methodsTools: [AgentTool] = [
        AgentTool(name: "get_methods_record", title: "Methods record",
                  summary: "The methods record of the room on screen's result, as Export Methods Record… writes it (the app and kits, the "
                      + "source by name, size and fingerprint, each step with its method and settings, the results) and the paragraph "
                      + "Copy Methods Paragraph copies. With leave_out_file_names true, each source is named source 1, source 2, ... as the "
                      + "save panel's checkbox does. Refused while the room holds no result, and while an SEM room's file or the EDS spectrum "
                      + "image is read for its fingerprint the first time (ask again).",
                  input: .window,
                  parameters: [AgentParameter("leave_out_file_names", .boolean,
                                              summary: "Name each source source 1, source 2, ... instead of its file name.")]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard MethodsRecordExport.isAvailable(in: appState) else {
                return .refusal(status: 404, message: "The \(appState.navigation.workspaceArea.title) room holds no result to record yet.")
            }
            guard let record = MethodsRecordExport.record(of: appState) else {
                // One read runs per file: this joins it, or reads again after a failure (access may have come back).
                let failed = MethodsRecordExport.lastReadFailed(appState)
                Task { await MethodsRecordExport.prepare(appState) }
                if failed { return .refusal(status: 409, message: MethodsRecordExport.unreadableLine) }
                return .refusal(status: 409, message: "The source is being read for its fingerprint (an SEM file can be gigabytes); ask again "
                                    + "in a moment.")
            }
            let leaveOut = call.arguments["leave_out_file_names"] == "true"
            do {
                let written = leaveOut ? record.withoutFileNames() : record
                return .json(["room": record.room, "record": try MethodsRecordExport.json(record, leaveOutFileNames: leaveOut),
                              "paragraph": written.paragraph])
            } catch {
                return .refusal(status: 500, message: "The record could not be written: \(error.localizedDescription)")
            }
        },
    ]
}
