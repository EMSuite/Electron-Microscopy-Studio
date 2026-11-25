//
//  AgentDoorRooms.swift
//  Role: the agent door's first tools that act in macEM (#558): move a window to a room, as the room bar does; open a demo document, as
//        Help > Open Demo Data does; the shared EDS room's tools (MacEMUI's `EDXAgentTools`, written once for both apps, as mac4DSTEM
//        registers them); and the EDS maps as the room's "Maps as PNG…" draws them. Every acting tool runs only while Settings > Agents lets agents run analyses (`acts: true`), goes
//        through what the window's own control calls, and leaves an Output line that starts "An agent", as mac4DSTEM's do.
//
//        ONE SOURCE PER FACT: the room's refusal is `roomUnavailableReason`'s; the maps picture is `EDXMapsFigure.png` of the session's
//        `figureContent`, the export's own renderer.
//

import Foundation
import TEMCore
import ShellAgentDoor
import ShellEDXAgent
import ShellEDXModel
import ShellSpectroscopy

extension MacTEMAgentDoor {
    /// Every tool the door offers: the read-only ones and the guide, then the ones that act.
    static var allTools: [AgentTool] { tools + guideTools + folderTools + roomTools + verbTools + edsTools + patternsTools + indexingTools + mapsTools + eelsTools + imageTools + fftTools + diffractionTools + phaseTools + diffractionScienceTools + simulationTools + sessionTools }

    /// The EDS room's tools on the window's `EDXSession`, each acting one leaving its Output line.
    static let edsTools: [AgentTool] = EDXAgentTools.tools { ($0 as? AppState)?.edx }.map { said($0) } + [edsMapsTool]

    static let roomTools: [AgentTool] = [
        AgentTool(name: "select_room", title: "Select room",
                  summary: "Moves the window to a room, as the room bar does: "
                      + WorkspaceArea.allCases.map { "\($0.rawValue) (\($0.title))" }.joined(separator: ", ")
                      + ". A room the window's files do not fill is refused with the reason the room bar gives. Nothing runs.",
                  input: .window,
                  parameters: [AgentParameter("room", .choice(WorkspaceArea.allCases.map(\.rawValue)), summary: "The room to show.",
                                              required: true)],
                  acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let room = call.arguments["room"].flatMap(WorkspaceArea.init(rawValue:)) else {
                return .refusal(status: 400, message: "Name a room: " + WorkspaceArea.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            if let reason = appState.roomUnavailableReason(room) { return .refusal(status: 409, message: reason) }
            appState.selectWorkspace(room)
            appState.statusText = "An agent selected the \(room.title) room."
            return .json(window(appState))
        },
        AgentTool(name: "open_demo", title: "Open demo data",
                  summary: "Opens one of the demo documents in its room, as Help > Open Demo Data does: "
                      + DemoDocument.allCases.map { "\($0.rawValue) (\($0.title), \($0.room.title) room)" }.joined(separator: ", ")
                      + ". A file opens beside the window's other files; a generated spectrum image takes the EDS or EELS room's place. "
                      + "It answers at once; get_window says the file is reading until it is read.",
                  input: .window,
                  parameters: [AgentParameter("demo", .choice(DemoDocument.allCases.map(\.rawValue)), summary: "The demo document.",
                                              required: true)],
                  acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let demo = call.arguments["demo"].flatMap(DemoDocument.init(rawValue:)) else {
                return .refusal(status: 400, message: "Name a demo: " + DemoDocument.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            appState.openDemo(demo)
            appState.statusText = "An agent opened the demo \(demo.title)."
            return .json(window(appState))
        },
    ]

    static let edsMapsTool = AgentTool(
        name: "get_eds_maps", title: "EDS maps picture",
        summary: "The EDS room's maps as its Maps as PNG… export draws them: the shown element tiles in a grid with their titles, the kept "
            + "regions and the selected one, and the scale bar. Run quantify first for composition tiles.",
        input: .windowPicture) { call in
        guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
        let session = appState.edx
        guard session.hasImage else { return .refusal(status: 404, message: "No spectrum image is open in the EDS room; open one first.") }
        guard let content = session.figureContent(), let png = EDXMapsFigure.png(content) else {
            return .refusal(status: 404, message: "The EDS room shows no map yet; wait until get_eds says not busy.")
        }
        return .png(smaller(png, side: pictureSide * call.scale) ?? png)
    }

    /// `tool` with an Output line after each call that acted and was not refused, naming the tool and what it was given.
    static func said(_ tool: AgentTool) -> AgentTool {
        guard tool.acts else { return tool }
        let run = tool.run
        return AgentTool(name: tool.name, title: tool.title, summary: tool.summary, input: tool.input, parameters: tool.parameters,
                         acts: true) { call in
            let output = run(call)
            if case .refusal = output { return output }
            if let appState = call.window?.state as? AppState { appState.statusText = agentLine(tool.title, call.arguments) }
            return output
        }
    }

    /// "An agent used EDS room settings (add Fe, Ni; region whole)." The arguments in name order, so a line reads the same each time.
    nonisolated static func agentLine(_ title: String, _ arguments: [String: String]) -> String {
        let given = arguments.keys.sorted().compactMap { key in arguments[key].map { "\(key) \($0)" } }
        return "An agent used \(title)" + (given.isEmpty ? "." : " (\(given.joined(separator: "; "))).")
    }

    static let notAWindowRefusal = AgentToolOutput.refusal(status: 500, message: "That window is not a \(AppName.display) window.")
}
