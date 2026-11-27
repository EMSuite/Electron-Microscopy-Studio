//
//  AgentDoorAtomModel.swift
//  Role: the agent door's tools for a Simulation document's atom model (#918, plan row MA17 for MA14's Specimen section) and the
//        HRTEM section's Export abTEM Script… (MA13): `set_atom_model` is the Source picker, Atom Model… and Open Another Model…
//        (a CIF, XYZ or POSCAR file of the Agent folder, found as `open_file` finds its files) and the Beam along switch;
//        `read_atom_model` reads the section back: the source, the model, the beam axis, the model's own thickness, the box, the
//        summary and notes, or why the file was not opened; `get_abtem_script` answers the script Export abTEM Script… writes.
//
//        ONE SOURCE PER FACT: the file is read as the section reads it (`AtomModelSpecimen(contentsOf:)`, off the main actor) and
//        kept through `SimulationModel.useAtomModel`; the axis is `setBeamAxis`; every sentence read back is the section's own
//        (`AtomModelSpecimen.Refusal.sentence`, `summary`, `notes`, `SimulationSpecimen.boxText`), the script `abTEMScript`.
//        A call is checked whole before anything changes; a beam axis given with a file is set only once the file is in, so a
//        file that is refused changes nothing.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let atomModelTools: [AgentTool] = [
        said(AgentTool(name: "set_atom_model", title: "Atom model",
                       summary: "The Specimen section's Source of the shown Simulation document, through its own controls: path (a "
                           + "CIF, XYZ or POSCAR file of the Agent folder, as list_agent_folder names it) reads the file as Atom Model… "
                           + "and Open Another Model… do and simulates it in the phase's place; source Phase simulates the phase again; "
                           + "beam_axis (c, a or b) turns the model so the beam runs along that cell axis, its thickness then the "
                           + "model's own. The file is read off the main actor: the call answers at once with reading true, and "
                           + "read_atom_model says when the model is in, or why it was not opened in the section's words.",
                       input: .window,
                       parameters: [
                           AgentParameter("path", .text, summary: "An atom model file (CIF, XYZ or POSCAR), relative to the Agent folder."),
                           AgentParameter("source", .choice(["Phase", "Atom Model"]),
                                          summary: "Phase drops the model; Atom Model keeps the one open or reads path."),
                           AgentParameter("beam_axis", .choice(AtomModelSpecimen.BeamAxis.allCases.map(\.rawValue)),
                                          summary: "The model's cell axis the beam runs along."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            return applyAtomModel(call.arguments, to: simulation, in: appState)
        }),
        AgentTool(name: "read_atom_model", title: "Atom model",
                  summary: "The shown Simulation document's Specimen source: Phase or Atom Model, whether a file is being read, why the "
                      + "last file was not opened, and with a model its file, atoms by element, the beam axis, the model's own "
                      + "thickness along the beam (nm, the section's Thickness), the box, the summary and the notes (no cell, atoms "
                      + "wrapped, atoms too close), or why the specimen is refused.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            return .json(atomModelState(simulation))
        },
        AgentTool(name: "get_abtem_script", title: "abTEM script",
                  summary: "The Python script Export abTEM Script… writes for the shown Simulation document's HRTEM image: its name "
                      + "and text, which runs the image again in abTEM \(AbTEMScript.abTEMVersion) (the same specimen, grid, slices, "
                      + "lens and defocus). Refused, as the button is off, until the exit waves are computed and current "
                      + "(run_simulation, read_simulation).",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            let model = simulation.multislice, analysis = simulation.diffraction
            let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
            guard model.exitWaves != nil, !model.isComputing, model.exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) else {
                return .refusal(status: 409, message: "No current exit waves to write a script for: run_simulation, and ask "
                    + "read_simulation until running is false and waves_current true.")
            }
            guard let script = model.abTEMScript(crystal: crystal, zoneAxis: zoneAxis, appVersion: version()) else {
                return .refusal(status: 409, message: "This specimen has no abTEM script.")
            }
            return .json(["name": script.name, "text": script.text])
        },
    ]

    /// `set_atom_model`: every check first, so a refused call changes nothing; then the section's intents.
    static func applyAtomModel(_ a: [String: String], to simulation: OpenItem, in appState: AppState) -> AgentToolOutput {
        let model = simulation.multislice
        func refused(_ words: String, status: Int = 409) -> AgentToolOutput { .refusal(status: status, message: words) }
        let axis = a["beam_axis"].flatMap(AtomModelSpecimen.BeamAxis.init(rawValue:))
        if AtomModelReads.isReading(simulation) {
            return refused("A model is being read; read_atom_model says when it is in.")
        }
        if a["source"] == "Phase", a["path"] != nil || axis != nil {
            return refused("source Phase drops the model: give path or beam_axis without it.")
        }
        if a["path"] == nil, model.atomModel == nil, a["source"] == "Atom Model" || axis != nil {
            return refused("No atom model is open: give path, a CIF, XYZ or POSCAR file of the Agent folder.")
        }
        var file: URL?
        if let path = a["path"] {
            switch folder.resolve(path) {
            case .success(let url): file = url
            case .failure(let refusal): return refused(refusal.message, status: 404)
            }
            var isFolder: ObjCBool = false
            guard let url = file, FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
                return refused(noFileMessage(file ?? URL(fileURLWithPath: path)), status: 404)
            }
        }

        if a["source"] == "Phase" {
            model.useAtomModel(nil)
            AtomModelReads.forget(simulation)
        }
        if let file {
            AtomModelReads.read(file, into: simulation, beamAxis: axis, appState: appState)
        } else if let axis {
            model.setBeamAxis(axis)
        }
        return .json(atomModelState(simulation))
    }

    /// The Specimen section's source and model, in the door's words.
    static func atomModelState(_ simulation: OpenItem) -> [String: Any] {
        let model = simulation.multislice, analysis = simulation.diffraction
        var state: [String: Any] = [
            "document": simulation.url.lastPathComponent,
            "source": model.atomModel == nil ? "Phase" : "Atom Model",
            "reading": AtomModelReads.isReading(simulation),
            "refusal": AgentJSON.orNull(AtomModelReads.refusal(of: simulation)),
        ]
        guard let atomModel = model.atomModel else { return state }
        state["model"] = atomModel.name
        state["file"] = atomModel.fileName
        state["atoms"] = atomModel.atomicNumbers.count
        state["elements"] = atomModel.countsText
        state["beam_axis"] = model.beamAxis.rawValue
        switch model.specimen(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis) {
        case .success(let built):
            state["thickness_nm"] = built.box.z / 10
            state["box"] = SimulationSpecimen.boxText(built.box)
            state["summary"] = atomModel.summary(built, beam: model.beamAxis)
            state["notes"] = atomModel.notes(built)
        case .failure(.building):
            // Not a refusal: the model's slab is still being built off the main actor; read again when it lands.
            state["building"] = true
        case .failure(let refusal):
            state["specimen_refusal"] = refusal.sentence
            state["notes"] = atomModel.notes(nil)
        }
        return state
    }
}

/// The atom model files the door is reading, by Simulation document, and why the last one was not opened: the section's own
/// "Reading the model…" and its warning, which are the view's state and not the document's.
@MainActor enum AtomModelReads {
    private static var reading: Set<URL> = []
    private static var refusals: [URL: String] = [:]

    static func isReading(_ simulation: OpenItem) -> Bool { reading.contains(simulation.url) }
    static func refusal(of simulation: OpenItem) -> String? { refusals[simulation.url] }
    static func forget(_ simulation: OpenItem) { refusals[simulation.url] = nil }

    /// Reads `file` off the main actor as the section does, then simulates it (and turns it to `beamAxis`), or keeps the refusal
    /// and says it in Output.
    static func read(_ file: URL, into simulation: OpenItem, beamAxis: AtomModelSpecimen.BeamAxis?, appState: AppState) {
        let key = simulation.url, model = simulation.multislice
        reading.insert(key)
        refusals[key] = nil
        Task {
            let read: Result<AtomModelSpecimen, AtomModelSpecimen.Refusal> = await offMainActor {
                do {
                    return .success(try AtomModelSpecimen(contentsOf: file))
                } catch let refusal as AtomModelSpecimen.Refusal {
                    return .failure(refusal)
                } catch {
                    return .failure(.unreadable(file: file.lastPathComponent, reason: error.localizedDescription))
                }
            }
            reading.remove(key)
            switch read {
            case .success(let atomModel):
                model.useAtomModel(atomModel)
                if let beamAxis { model.setBeamAxis(beamAxis) }
            case .failure(let refusal):
                refusals[key] = refusal.sentence
                appState.statusText = refusal.sentence
            }
        }
    }
}
