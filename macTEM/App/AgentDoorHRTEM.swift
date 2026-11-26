//
//  AgentDoorHRTEM.swift
//  Role: the agent door's tools for a Simulation document's HRTEM image (#899, plan row MA13), beside #846's `new_simulation`
//        (AgentDoorSimulation.swift): `set_simulation` sets what the Specimen, HRTEM, Microscope and Thermal Vibrations sections
//        set (the phase from the library and the zone axis as the Diffraction room takes them); `run_simulation` shows the HRTEM
//        image and runs it (the static lattice's multislice, or Simulate and Continue for frozen phonons); `read_simulation` reads it
//        all back with the app's own verdicts: the specimen's summary or refusal, the potential and transfer, the plan line, the
//        run's progress, the convergence, the method line and every failure sentence. `stop_run` stops a frozen-phonon run as ⌘.
//        does (`RoomPrimaryAction`). #907 extends set_simulation and read_simulation with the 2.3 Microscope and Orientation sections.
//
//        ONE SOURCE PER FACT: every change goes through the intent the section's control calls (`SimulationModel`'s setters,
//        `DiffractionAnalysis.setCrystal` and `setZoneAxis`, `DiffractionPhases.crystal(for:)`), and every sentence read back is the
//        section's own (`SimulationSpecimen.summary`, `Refusal.sentence`, `HRTEMImage.methodLine`, `thermalPlanLine`,
//        `simulateBlocker`, `BusyOperation.simulating`). The picture of the image is get_image's, with the HRTEM image shown.
//        A set_simulation call is checked whole before anything is applied, so a refusal changes nothing.
//

import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellPhaseLibrary
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let hrtemTools: [AgentTool] = [
        said(AgentTool(name: "set_simulation", title: "Simulation settings",
                       summary: "The shown Simulation document's (or its HRTEM image's) settings, only those given, through the "
                           + "sections' own controls. phase (a library phase's name or id) and zone_axis (\"1 1 0\") as the Diffraction "
                           + "room takes them; thickness_nm, build_with_strain true (accept the strain the specimen refusal names); "
                           + "defocus_nm (positive is underfocus) or scherzer true, thickness_index (0 is one period); voltage_kv and "
                           + "camera_length_mm (the Diffraction room's Microscope section: R in mm = λ L |g| in the Spots table), "
                           + "optics (Uncorrected, Cs Corrected), cs_mm, focal_spread_nm, angular_spread_mrad, aperture_mrad (0 for none), "
                           + "field_of_view_nm; frozen_phonons, sigma (\"Si 0.08, O 0.1\" in Å) and configurations; beside (an open "
                           + "image's file name, or none), beside_layout, beside_rotation_deg, beside_inset_across and _down. Refused with the "
                           + "section's words when a value is not kept. A setting that needs a new run reads stale in read_simulation "
                           + "until run_simulation.",
                       input: .window, parameters: simulationParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulation }
            if let refusal = applySimulation(call.arguments, to: simulation, in: appState) { return refusal }
            return .json(simulationState(simulation, in: appState))
        }),
        said(AgentTool(name: "run_simulation", title: "Run simulation",
                       summary: "Shows the HRTEM image of the shown Simulation document (in a tab of its own, in the Image room, as Show "
                           + "HRTEM Image does) and runs it: the static lattice's exit waves, or with frozen phonons on, Simulate (the "
                           + "configurations not yet averaged: Continue after a stop or more configurations). Refused with the room's "
                           + "words when it cannot run (no phase, a specimen refused, a run too large for this Mac) or while one runs. "
                           + "It answers at once; read_simulation says running until it ends, and stop_run stops it, keeping the "
                           + "configurations done.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulation }
            let model = simulation.multislice, analysis = simulation.diffraction
            let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
            if model.isSimulating || model.isComputing {
                return .refusal(status: 409, message: "The simulation is running; wait until read_simulation says it ended, or stop_run.")
            }
            if model.thermal != nil {
                if let blocker = model.simulateBlocker(crystal: crystal, zoneAxis: zoneAxis) { return .refusal(status: 409, message: blocker) }
                let resumes = model.canContinue(crystal: crystal, zoneAxis: zoneAxis)
                appState.showHRTEMImage(of: simulation)
                Task { await appState.simulateHRTEM(of: simulation) }
                return .json(["started": resumes ? "Continue" : "Simulate"])
            }
            if case .failure(let refusal) = model.specimen(crystal: crystal, zoneAxis: zoneAxis) {
                return .refusal(status: 409, message: refusal.sentence)
            }
            appState.showHRTEMImage(of: simulation)
            return .json(["started": "exit waves"])
        }),
        AgentTool(name: "read_simulation", title: "Simulation",
                  summary: "What the shown Simulation document (or its HRTEM image) holds: the phase and zone axis, the zone axis "
                      + "nearest the drawn orientation and the angle off it, the camera length and the Spots table's rows (hkl, R in "
                      + "px and mm, q, d, the dynamical intensity where Dynamical is on), the specimen's summary "
                      + "or why it is refused, the optics and defocus, the stored thicknesses, the image's method line, frozen phonons "
                      + "(σ, configurations, the plan line, the run's progress, the convergence), Place Beside (the measured image, layout, "
                      + "rotation, inset size, and the scale both share or why the pair is not drawn), the potential, the transfer (point "
                      + "resolution, aperture cut-off, Scherzer defocus), whether a run is going or its "
                      + "waves are stale, and every failure sentence the sections show. get_image draws the image with the HRTEM image shown.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulation }
            return .json(simulationState(simulation, in: appState))
        },
    ]

    private static let noSimulation = AgentToolOutput.refusal(
        status: 404, message: "The window shows no Simulation document or HRTEM image: File > New Simulation opens one.")

    /// The Simulation document the window shows: the selected one, or the document of the selected HRTEM image, CBED pattern or
    /// STEM image.
    static func simulationItem(_ appState: AppState) -> OpenItem? {
        guard let item = appState.openItems.selected else { return nil }
        if DemoDocuments.isSimulation(item.url) { return item }
        return appState.simulationDocument(ofHRTEM: item) ?? appState.simulationDocument(ofCBED: item) ?? appState.simulationDocument(ofSTEM: item)
    }

    /// How many of the marked columns `read_simulation` lists (the count is always whole).
    static let columnsListed = 50

    static let simulationParameters: [AgentParameter] = [
        AgentParameter("phase", .text, summary: "A library phase's name or id: the crystal simulated."),
        AgentParameter("zone_axis", .text, summary: "The zone axis, \"u v w\"."),
        AgentParameter("thickness_nm", .number(SimulationSpecimen.thicknessRangeNM), summary: "The specimen thickness, nm."),
        AgentParameter("build_with_strain", .boolean, summary: "Accept the strain the specimen refusal names."),
        AgentParameter("defocus_nm", .number(-1000...1000), summary: "The defocus, nm; positive is underfocus."),
        AgentParameter("scherzer", .boolean, summary: "Back to Scherzer defocus."),
        AgentParameter("thickness_index", .integer(0...10_000), summary: "The stored thickness shown, 0 is one period."),
        AgentParameter("voltage_kv", .number(1...10_000), summary: "The beam energy, kV (the document's, its pattern's too)."),
        AgentParameter("camera_length_mm", .number(DiffractionAnalysis.cameraLengthRangeMM),
                       summary: "The camera length, mm: the Spots table's R in mm = λ L |g|."),
        AgentParameter("optics", .choice([HRTEMPreset.uncorrected.rawValue, HRTEMPreset.csCorrected.rawValue]), summary: "A preset's Cs and focal spread."),
        AgentParameter("cs_mm", .number(-100...100), summary: "Spherical aberration Cs, mm."),
        AgentParameter("focal_spread_nm", .number(0...1000), summary: "Focal spread (1/e half-width), nm."),
        AgentParameter("angular_spread_mrad", .number(0...100), summary: "Beam convergence semiangle, mrad."),
        AgentParameter("aperture_mrad", .number(0...1000), summary: "The objective aperture's semiangle, mrad; 0 for none."),
        AgentParameter("field_of_view_nm", .number(0.01...SimulationModel.largestFieldOfViewNM), summary: "The image's width, nm."),
        AgentParameter("mark_columns", .boolean, summary: "Ring the specimen's atom columns on the HRTEM image."),
        AgentParameter("frozen_phonons", .boolean, summary: "Frozen phonons on (σ per element, Simulate) or the static lattice."),
        AgentParameter("sigma", .text, summary: "σ per element, Å: \"Si 0.08, O 0.1\"."),
        AgentParameter("configurations", .integer(HRTEMThermal.configurationRange), summary: "Frozen-phonon configurations to average."),
        AgentParameter("beside", .text, summary: "Place Beside: an open measured image's file name, or none."),
        AgentParameter("beside_layout", .choice(HRTEMBeside.Layout.allCases.map(\.rawValue)), summary: "Beside or Inset."),
        AgentParameter("beside_rotation_deg", .number(-360...360), summary: "The simulation's rotation on screen, degrees, counter-clockwise."),
        AgentParameter("beside_inset_across", .integer(HRTEMBeside.insetCellRange), summary: "The inset's width in unit cells."),
        AgentParameter("beside_inset_down", .integer(HRTEMBeside.insetCellRange), summary: "The inset's height in unit cells."),
    ]

    /// Checks `arguments` whole, then applies them in the sections' order (crystal, specimen, optics, image, thermal) through the
    /// controls' intents; a refusal changes nothing.
    static func applySimulation(_ arguments: [String: String], to simulation: OpenItem, in appState: AppState) -> AgentToolOutput? {
        let model = simulation.multislice, analysis = simulation.diffraction
        func refused(_ words: String) -> AgentToolOutput { .refusal(status: 409, message: words) }
        func number(_ key: String) -> Double? { arguments[key].flatMap(Double.init) }
        if model.isSimulating, ["frozen_phonons", "sigma", "configurations"].contains(where: { arguments[$0] != nil }) {
            return refused("A frozen-phonon run is going: stop_run first, as the section's controls wait for Stop.")
        }

        // Check every value first.
        var phase: Phase?
        if let name = arguments["phase"] {
            phase = PhaseServices.library.phases.first(where: { $0.id == name || $0.name == name })
            guard phase != nil else {
                let names = PhaseServices.library.phases.map(\.name)
                return refused("No phase \"\(name)\" in the library: " + (names.isEmpty ? "the library is empty" : names.joined(separator: ", ")) + ".")
            }
        }
        var zoneAxis: SIMD3<Int>?
        if let text = arguments["zone_axis"] {
            guard let uvw = ZoneAxisText.parse(text), uvw != .zero else { return refused("A zone axis is three integers, as \"1 1 0\".") }
            zoneAxis = uvw
        }
        let crystal = phase.map(DiffractionPhases.crystal(for:)) ?? analysis.simulatedPhase
        let axis = zoneAxis ?? analysis.simulation.zoneAxis
        // The strain a specimen is refused for is its lateral unit's, the same at any thickness, so a thickness_nm in the same call
        // does not change this check.
        if arguments["build_with_strain"] == "true" {
            guard let crystal, case .failure(let refusal) = model.specimen(crystal: crystal, zoneAxis: axis), refusal.acceptableStrain != nil
            else { return refused("The specimen is not refused for its strain.") }
        }
        var optics = model.optics
        if let kV = number("voltage_kv") { optics.volts = kV * 1000 }
        if let name = arguments["optics"], let preset = HRTEMPreset(rawValue: name) { optics = preset.applied(to: optics) }
        if let v = number("cs_mm") { optics.csMM = v }
        if let v = number("focal_spread_nm") { optics.focalSpreadNM = v }
        if let v = number("angular_spread_mrad") { optics.angularSpreadMrad = v }
        if let v = number("aperture_mrad") { optics.apertureMrad = v > 0 ? v : nil }
        if let v = number("field_of_view_nm") { optics.fieldOfViewNM = v }
        if let mm = number("camera_length_mm"), !(mm.isFinite && DiffractionAnalysis.cameraLengthRangeMM.contains(mm)) {
            return refused("The camera length is \(UnitDisplay.number(DiffractionAnalysis.cameraLengthRangeMM.lowerBound, digits: 3)) to "
                + "\(UnitDisplay.number(DiffractionAnalysis.cameraLengthRangeMM.upperBound, digits: 6)) mm.")
        }
        guard SimulationModel.isValid(optics) else { return refused("Those optics are not valid: a positive voltage, a finite Cs, spreads of at least 0, "
            + "an aperture above 0 or none, and a field of view up to \(UnitDisplay.number(SimulationModel.largestFieldOfViewNM, digits: 3)) nm.") }
        let turnsOn = arguments["frozen_phonons"] == "true" && model.thermal == nil
        if turnsOn, model.sourceIdentity(crystal: crystal) == nil { return refused(SimulationSpecimen.Refusal.noPhase.sentence) }
        var thermal: HRTEMThermal?
        if arguments["sigma"] != nil || arguments["configurations"] != nil {
            guard arguments["frozen_phonons"] != "false" else { return refused("σ and configurations need frozen phonons on.") }
            guard var base = model.thermal ?? (turnsOn ? model.thermalTurnedOn(crystal: crystal) : nil) else {
                return refused("Frozen phonons are off: set frozen_phonons true with them.")
            }
            if let text = arguments["sigma"] {
                guard let sigmas = sigmas(text) else { return refused("σ is \"Si 0.08, O 0.1\": an element and Å, comma separated.") }
                base.sigmas.merge(sigmas) { _, new in new }
            }
            if let count = arguments["configurations"].flatMap(Int.init) { base.configurations = count }
            guard base.sigmas.values.allSatisfy({ $0.isFinite && $0 >= 0 }), HRTEMThermal.configurationRange.contains(base.configurations) else {
                return refused("σ must be finite and at least 0, and configurations within "
                    + "\(HRTEMThermal.configurationRange.lowerBound) to \(HRTEMThermal.configurationRange.upperBound).")
            }
            thermal = base
        }
        var beside = model.beside
        if let name = arguments["beside"] {
            if name.lowercased() == "none" {
                beside = nil
            } else {
                let images = appState.measuredImages()
                guard let item = images.first(where: { $0.url.lastPathComponent == name }) else {
                    let names = images.map(\.url.lastPathComponent)
                    return refused("No open image \"\(name)\": " + (names.isEmpty ? "open a measured image first" : names.joined(separator: ", ")) + ".")
                }
                beside = appState.besideNaming(item, in: beside)
            }
        }
        if ["beside_layout", "beside_rotation_deg", "beside_inset_across", "beside_inset_down"].contains(where: { arguments[$0] != nil }) {
            guard var new = beside else { return refused("Place Beside is off: name the measured image with beside.") }
            if let layout = arguments["beside_layout"].flatMap(HRTEMBeside.Layout.init(rawValue:)) { new.layout = layout }
            if let degrees = number("beside_rotation_deg") { new.rotationDegrees = degrees }
            if let across = arguments["beside_inset_across"].flatMap(Int.init) { new.insetCells.x = across }
            if let down = arguments["beside_inset_down"].flatMap(Int.init) { new.insetCells.y = down }
            beside = new
        }

        // Then apply, as the controls do.
        if let phase { analysis.setCrystal(DiffractionPhases.crystal(for: phase)) }
        if let zoneAxis { analysis.setZoneAxis(zoneAxis) }
        if let nm = number("thickness_nm") { model.setThickness(nm: nm) }
        if arguments["build_with_strain"] == "true", let crystal, case .failure(let refusal) = model.specimen(crystal: crystal, zoneAxis: axis),
           let strain = refusal.acceptableStrain {
            model.acceptStrain(strain, crystal: crystal, zoneAxis: axis)
        }
        if optics != model.optics { model.changeOptics { $0 = optics } }
        // The document's voltage, as the Diffraction room's Microscope section types it, even when the optics already hold it.
        if number("voltage_kv") != nil { analysis.typedBeamKV = optics.volts / 1000 }
        if let mm = number("camera_length_mm") { analysis.setCameraLength(mm: mm) }
        if let nm = number("defocus_nm") { model.setDefocus(nm: nm) }
        if arguments["scherzer"] == "true" { model.useScherzerDefocus() }
        if let index = arguments["thickness_index"].flatMap(Int.init) { model.setThicknessIndex(index) }
        if let on = arguments["mark_columns"] { model.setMarksColumns(on == "true") }
        if let on = arguments["frozen_phonons"] { model.useThermalVibrations(on == "true", crystal: crystal) }
        if let thermal { model.setThermal(thermal) }
        if beside != model.beside { model.setBeside(beside) }
        appState.refreshHRTEMImage(of: simulation)
        return nil
    }

    /// "Si 0.08, O 0.1" as σ by atomic number; nil when a part does not read.
    nonisolated static func sigmas(_ text: String) -> [Int: Double]? {
        var out: [Int: Double] = [:]
        for part in text.split(separator: ",") {
            let words = part.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count == 2, let z = Element.atomicNumber(forSymbol: String(words[0])), let sigma = Double(words[1]) else { return nil }
            out[z] = sigma
        }
        return out.isEmpty ? nil : out
    }

    /// The document as its sections show it, in the door's words.
    static func simulationState(_ simulation: OpenItem, in appState: AppState) -> [String: Any] {
        let model = simulation.multislice, analysis = simulation.diffraction
        let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
        let optics = model.optics
        var state: [String: Any] = [
            "document": simulation.url.lastPathComponent,
            "phase": AgentJSON.orNull(crystal?.name),
            "zone_axis": ZoneAxisText.text(zoneAxis),
            "thickness_nm": model.thicknessNM,
            "voltage_kv": optics.volts / 1000,
            "camera_length_mm": analysis.cameraLengthMM,
            "optics": HRTEMPreset.of(optics).rawValue,
            "cs_mm": optics.csMM,
            "focal_spread_nm": optics.focalSpreadNM,
            "angular_spread_mrad": optics.angularSpreadMrad,
            "aperture_mrad": AgentJSON.orNull(optics.apertureMrad),
            "field_of_view_nm": optics.fieldOfViewNM,
            "potential": "\(HRTEMImage.potentialName), \(UnitDisplay.number(SimulationSpecimen.sliceThickness, digits: 3)) Å slices",
            "defocus_nm": model.effectiveDefocusNM,
            "scherzer": model.defocusNM == nil,
            "image_shown": appState.hrtemItem(of: simulation) != nil,
            "columns_marked": model.marksColumns,
            "running": model.isComputing || model.isSimulating,
            "waves_current": model.exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis),
            "compute_failure": AgentJSON.orNull(model.computeFailure),
            "image_failure": AgentJSON.orNull(model.imageFailure),
        ]
        // The Diffraction room's readouts of the document (#846): the place the pattern is drawn at and its Spots table.
        // With no phase shown the screen draws no pattern and lists no spots (the empty state, #1152): the door says the same, never
        // the calibration standard the room falls back to.
        if !SimulationEmptyState.isShown(for: simulation),
           let near = analysis.drawnOrientation?.nearestZoneAxis(cell: analysis.crystal.structure.cell) {
            state["nearest_zone_axis"] = ["zone_axis": [near.uvw.x, near.uvw.y, near.uvw.z], "degrees_off": near.angle * 180 / .pi,
                                          "place": PatternIndexing.place(phase: analysis.crystal.name, zoneAxis: near.uvw, angle: near.angle)]
                as [String: Any]
        }
        let spots: [[String: Any]] = simulation.session.image.map { SimulationEmptyState.spotRows(of: simulation, image: $0).map(spotRow) } ?? []
        state["spots"] = spots
        if let curve = try? HRTEMTransferCurve.of(optics, defocusNM: model.effectiveDefocusNM) {
            state["transfer"] = ["point_resolution_nm": AgentJSON.orNull(curve.pointResolutionAngstrom.map { $0 / 10 }),
                                 "aperture_cutoff_per_nm": AgentJSON.orNull(curve.apertureFrequency),
                                 "scherzer_defocus_nm": AgentJSON.orNull(try? optics.scherzerDefocusNM())]
        }
        switch model.specimen(crystal: crystal, zoneAxis: zoneAxis) {
        case .success(let built):
            state["specimen"] = model.atomModel.map { $0.summary(built, beam: model.beamAxis) }
                ?? SimulationSpecimen.summary(built, phase: crystal?.name ?? "", zoneAxis: zoneAxis)
        case .failure(.building):
            // Not a refusal: the model's slab is still being built; read again when it lands.
            state["specimen_building"] = true
        case .failure(let refusal):
            state["specimen_refusal"] = refusal.sentence
            state["build_with_strain"] = AgentJSON.orNull(refusal.acceptableStrain)
        }
        // The columns ringed on the image, in its pixels (row, column, elements): what the person sees over the contrast (#897).
        if model.marksColumns {
            if let blocker = model.columnsBlocker(crystal: crystal, zoneAxis: zoneAxis) {
                state["columns_blocked"] = blocker
            } else if let image = appState.hrtemItem(of: simulation)?.session.image,
                      let columns = model.drawnColumns(crystal: crystal, zoneAxis: zoneAxis, on: image) {
                let listed: [[String: Any]] = columns.prefix(Self.columnsListed).map { c -> [String: Any] in
                    ["row": c.row, "column": c.column,
                     "elements": c.atomicNumbers.map { Element.symbol(forAtomicNumber: $0) ?? "Z\($0)" }]
                }
                state["columns"] = ["count": columns.count, "first": listed] as [String: Any]
            }
        }
        if let waves = model.exitWaves, let index = model.shownThicknessIndex {
            state["thicknesses_nm"] = waves.planePeriods.indices.map { waves.thicknessNM(at: $0) }
            state["thickness_index"] = index
            state["method"] = HRTEMImage.methodLine(waves, thicknessIndex: index, defocusNM: model.effectiveDefocusNM, optics: optics)
        }
        if let thermal = model.thermal {
            var phonons: [String: Any] = ["sigma": thermal.sigmaText, "configurations": thermal.configurations,
                                          "averaged": model.exitWaves?.thermal != nil ? model.exitWaves?.configurations.count ?? 0 : 0,
                                          "can_continue": model.canContinue(crystal: crystal, zoneAxis: zoneAxis)]
            switch model.thermalPlanLine(crystal: crystal, zoneAxis: zoneAxis) {
            case .success(let line): phonons["plan"] = line
            case .failure(let error): phonons["plan_refusal"] = ErrorDetail.text(error)
            case nil: break
            }
            if let progress = model.thermalProgress {
                phonons["progress"] = BusyOperation.simulating(progress)
                phonons["fraction"] = BusyOperation.simulationFraction(progress)
            }
            if let convergence = model.convergence {
                phonons["convergence_percent"] = convergence.change * 100
                phonons["convergence_read_at"] = ["defocus_nm": convergence.defocusNM, "thickness_index": convergence.thicknessIndex]
            }
            state["frozen_phonons"] = phonons
        } else {
            state["frozen_phonons"] = false
        }
        if let beside = model.beside {
            state["beside"] = ["measured": beside.measured.lastPathComponent, "layout": beside.layout.rawValue,
                               "rotation_deg": beside.rotationDegrees, "inset_cells": [beside.insetCells.x, beside.insetCells.y],
                               "readout": appState.besideStatus(of: simulation).lines]
        } else {
            state["beside"] = false
        }
        return state
    }
}
