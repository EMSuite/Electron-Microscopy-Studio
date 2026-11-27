//
//  AgentDoorPhases.swift
//  Role: the agent door's tools for the phase library (#781). `list_phases` reads the library: each phase's id, name, source and
//        credit, its lattice and whether it was edited, and an add still running or the last one's outcome. `add_phase` adds a
//        Materials Project entry by its id through the Add Phase sheet's own model (`AddPhaseModel`: the same download, the same
//        conversion to the conventional cell, the same record), and can show it in the Diffraction room. `set_phase_lattice`
//        sets a phase's free lattice parameters through DiffractoKit's `editingLattice` (the parameters the symmetry ties move
//        with them; a change of Laue class is refused in the kit's words) and writes the library; the room's copy follows when
//        the phase is the one it shows, as an edit in the room's inspector would.
//
//        THE KEY NEVER PASSES THE DOOR: no tool takes or answers an API key. A download uses the person's own key from the
//        Keychain when Settings holds one, as the sheet does, and the open service otherwise. Every tool that changes the
//        library acts (Settings > Agents, "Let agents run analyses") and leaves an Output line that starts "An agent".
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellPhaseLibrary
import TEMSession

extension MacTEMAgentDoor {
    /// An add_phase still running, or the last one's outcome, as list_phases reports it.
    @MainActor final class PhaseAdds {
        static let shared = PhaseAdds()
        private(set) var running: String?
        private(set) var last: [String: Any]?
        /// The download in flight, so a test can wait for it.
        private(set) var task: Task<Void, Never>?

        /// Adds `id` through the sheet's model and, when `show`, shows it in `analysis`.
        func add(_ id: String, show analysis: DiffractionAnalysis?) {
            running = id
            let model = AddPhaseModel(library: PhaseServices.library, client: PhaseServices.client, keyStore: PhaseServices.keyStore)
            model.selection = id
            task = Task { @MainActor in
                await model.loadPreview()
                defer { running = nil }
                switch model.preview {
                case .failed(_, let message):
                    last = ["id": id, "added": false, "problem": message]
                case .ready where model.isInLibrary:
                    last = ["id": id, "added": false, "problem": "\(id) is already in the library."]
                case .ready:
                    do {
                        if let phase = try model.add() {
                            if let analysis { DiffractionPhases.set(phase, shown: true, in: analysis) }
                            last = ["id": id, "added": true, "phase": MacTEMAgentDoor.phase(phase, at: PhaseServices.library)]
                        }
                    } catch {
                        last = ["id": id, "added": false, "problem": "The phase could not be saved: \(error.localizedDescription)"]
                    }
                default:
                    last = ["id": id, "added": false, "problem": "The entry could not be read."]
                }
            }
        }
    }

    static let phaseTools: [AgentTool] = [
        AgentTool(name: "list_phases", title: "Phase library",
                  summary: "The phases of the library on this Mac, oldest first as the Diffraction room's Phases section lists them: id "
                      + "(a Materials Project id, or cif- and a hash for a CIF), name, source and credit, the marker, the lattice "
                      + "(a, b, c in Å, angles in degrees) and whether it was edited; records that could not be read; an add_phase "
                      + "still running and the last one's outcome. get_diffraction names the phase the room shows.",
                  input: .noWindow) { _ in
            guard PhaseServices.isLoaded else { return libraryLoading }
            let library = PhaseServices.library
            var out: [String: Any] = [
                "phases": DiffractionPhases.ordered(library.phases).map { phase($0, at: library) },
                "unreadable": library.unreadable,
            ]
            out["adding"] = AgentJSON.orNull(PhaseAdds.shared.running)
            out["last_add"] = AgentJSON.orNull(PhaseAdds.shared.last)
            return .json(out)
        },
        said(AgentTool(name: "add_phase", title: "Add phase",
                       summary: "Adds a Materials Project entry to the library by its id (mp-81), as Add Phase… does: the open "
                           + "service, or the person's own key when Settings holds one (no tool takes or shows a key). show true "
                           + "also shows it in the window's Diffraction room. It answers at once; list_phases says adding until the "
                           + "entry is read, then the outcome.",
                       input: .window,
                       parameters: [
                           AgentParameter("material_id", .text, summary: "The Materials Project id, such as mp-81.", required: true),
                           AgentParameter("show", .boolean, summary: "Show it in the Diffraction room once added."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard PhaseServices.isLoaded else { return libraryLoading }
            let id = (call.arguments["material_id"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard id.range(of: #"^(mp|mvc)-[0-9]+$"#, options: .regularExpression) != nil else {
                return .refusal(status: 400, message: "material_id must be a Materials Project id such as mp-81, not \(id).")
            }
            if PhaseAdds.shared.running != nil {
                return .refusal(status: 409, message: "An add is running; list_phases says when it ends.")
            }
            var analysis: DiffractionAnalysis?
            if call.arguments["show"] == "true" {
                switch diffractionItem(appState) {
                case .refused(let refusal): return refusal
                case .item(let item): analysis = item.diffraction
                }
            }
            if let existing = PhaseServices.library.phase(materialsProjectID: id) {
                if let analysis { DiffractionPhases.set(existing, shown: true, in: analysis) }
                return .json(["adding": false, "already_in_library": true, "phase": phase(existing, at: PhaseServices.library)])
            }
            PhaseAdds.shared.add(id, show: analysis)
            return .json(["adding": id])
        }),
        said(AgentTool(name: "set_phase_lattice", title: "Phase lattice",
                       summary: "Sets a library phase's lattice parameters, only those given and only those its symmetry leaves free "
                           + "(a cubic phase: a); the parameters tied to them follow, the atoms keep their fractional positions, and "
                           + "an edit that changes the Laue class is refused with the reason. When the window's Diffraction room shows "
                           + "the phase, the room takes the edit (Index and the readout start again).",
                       input: .window,
                       parameters: [AgentParameter("id", .text, summary: "The phase's id from list_phases.", required: true)]
                           + LatticeParameter.allCases.map { p in
                               p.rawValue.count == 1
                                   ? AgentParameter(p.rawValue, .number(0.1...1000), summary: "\(p.rawValue), Å.")
                                   : AgentParameter(p.rawValue, .number(1...179), summary: "\(p.description), degrees.")
                           },
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard PhaseServices.isLoaded else { return libraryLoading }
            let library = PhaseServices.library
            guard let id = call.arguments["id"], var target = library.phases.first(where: { $0.id == id }) else {
                return .refusal(status: 404, message: "No phase \(call.arguments["id"] ?? "") in the library; list_phases names them.")
            }
            var values: [LatticeParameter: Double] = [:]
            for p in LatticeParameter.allCases { if let v = call.arguments[p.rawValue].flatMap(Double.init) { values[p] = v } }
            guard !values.isEmpty else { return .refusal(status: 400, message: "Give at least one of a, b, c, alpha, beta, gamma.") }
            let edited: CrystalStructure
            do {
                edited = try target.structure().editingLattice(values)
            } catch {
                return .refusal(status: 422, message: String(describing: error))
            }
            target.replaceStructure(edited)
            do { try library.update(target) } catch {
                return .refusal(status: 500, message: "The phase could not be saved: \(error.localizedDescription)")
            }
            if let item = appState.openItems.selected, item.diffraction.crystal.phaseID == target.id {
                DiffractionPhases.set(target, shown: true, in: item.diffraction)
            }
            return .json(["phase": phase(target, at: library)])
        }),
    ]

    /// Refused until the library has been read at launch, so no answer is made from an empty library.
    static let libraryLoading = AgentToolOutput.refusal(status: 503, message: "The phase library is still being read; ask again in a moment.")

    /// One phase as list_phases gives it.
    static func phase(_ p: Phase, at library: PhaseLibrary) -> [String: Any] {
        let cell = p.structure().cell
        let index = DiffractionPhases.ordered(library.phases).firstIndex { $0.id == p.id } ?? 0
        let style = DiffractionPhases.style(at: index)
        let source: String = switch p.source {
        case .materialsProject: "materials_project"
        case .cif(let fileName): "cif \(fileName)"
        }
        return [
            "id": p.id, "name": p.name, "source": source, "credit": AgentJSON.orNull(p.source.attribution),
            "marker": "\(DiffractionPhases.colours[style.colourIndex].name) \(style.marker.spoken)",
            "lattice": ["a": cell.a, "b": cell.b, "c": cell.c, "alpha": cell.alphaDeg, "beta": cell.betaDeg, "gamma": cell.gammaDeg],
            "lattice_text": DiffractionPhases.latticeText(cell), "edited": p.isEdited,
            "free_parameters": p.structure().freeLatticeParameters.map(\.rawValue),
        ]
    }
}
