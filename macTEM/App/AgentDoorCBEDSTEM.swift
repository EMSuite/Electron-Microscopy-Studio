//
//  AgentDoorCBEDSTEM.swift
//  Role: the agent door's tools for release 2.6's simulations and the thickness they feed (#918, plan row MA17), beside MA13's
//        HRTEM tools (AgentDoorHRTEM.swift), on the Simulation document the window shows (or its HRTEM image, CBED pattern or STEM
//        image): dynamical spot intensities (MA8: `set_dynamical`, `read_dynamical`), the CBED pattern with its thickness series
//        (MA9: `set_cbed`, `run_cbed`, `stop_cbed`, `read_cbed`), two-beam CBED thickness on the pattern shown (MA15:
//        `measure_thickness`, `read_thickness`, `use_measured_thickness`) and the STEM image with its detector bands (MA10:
//        `set_stem`, `run_stem`, `stop_stem`, `read_stem`). The atom model as the specimen (MA14) and the abTEM script are
//        AgentDoorAtomModel.swift's (`set_atom_model`, `read_atom_model`, `get_abtem_script`).
//
//        ONE SOURCE PER FACT: every change goes through the intent the section's control calls (`SimulationModel.setDynamical` and
//        `setThicknessIndex`, `AppState.computeHRTEMImage` as the Simulation section's task, `CBEDModel`'s setters and
//        `AppState.showCBEDPattern`, `CBEDThicknessModel.measure` with `OpenItem.thicknessInputs`, `STEMModel`'s setters and
//        `AppState.simulateSTEM`), and every sentence read back is the section's own (`dynamicalAbsence`, `dynamicalOffAxis`,
//        `DynamicalBeams.methodLine`, `cbedBlocker`, `cbedPlan`, `CBEDRun.overlapSentence`, `CBEDThickness.Measurement.sentence`,
//        `stemRun`'s refusal, `STEMImage.planLine`, `STEMScan.notQuantitative` and `methodLine`). A set call is checked whole before
//        anything is applied, so a refusal changes nothing. The pictures are get_image's, with the pattern or image shown.
//

import DiffractoCore
import DiffractoGeometry
import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static var cbedSTEMTools: [AgentTool] { dynamicalTools + cbedTools + thicknessTools + stemTools + atomModelTools }

    private static func refused(_ words: String) -> AgentToolOutput { .refusal(status: 409, message: words) }

    // MARK: Dynamical spot intensities (MA8)

    static let dynamicalTools: [AgentTool] = [
        said(AgentTool(name: "set_dynamical", title: "Dynamical intensities",
                       summary: "The Simulation section's Intensities of the shown Simulation document, through its own controls: "
                           + "dynamical true draws the multislice's zone-axis beams at a thickness in place of the kinematical |F|² "
                           + "(and runs the multislice, as the section does), false the kinematical spots; thickness_index steps "
                           + "through the stored exit waves (0 is one period; read_dynamical lists them). Refused with the section's "
                           + "words when a value is not kept.",
                       input: .window,
                       parameters: [AgentParameter("dynamical", .boolean, summary: "Dynamical (true) or Kinematic (false) intensities."),
                                    AgentParameter("thickness_index", .integer(0...10_000), summary: "The stored thickness shown, 0 is one period.")],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            let model = simulation.multislice, analysis = simulation.diffraction
            let on = call.arguments["dynamical"].map { $0 == "true" }
            if on == true, model.atomModel != nil { return refused(SimulationModel.modelDynamicalSentence) }
            let index = call.arguments["thickness_index"].flatMap(Int.init)
            if let index {
                guard on ?? model.isDynamical else { return refused("The thickness steps through the dynamical beams: set dynamical true with it.") }
                guard let waves = model.exitWaves, model.exitWavesAreCurrent(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis)
                else { return refused("No stored thicknesses yet: read_dynamical says when the exit waves are computed.") }
                guard index < waves.waves.count else { return refused("The stored thicknesses are 0 to \(waves.waves.count - 1).") }
            }
            if let on {
                model.setDynamical(on)
                if on { Task { await appState.computeHRTEMImage(of: simulation) } }
            }
            if let index {
                model.setThicknessIndex(index)
                appState.refreshHRTEMImage(of: simulation)
            }
            return .json(dynamicalState(simulation))
        }),
        AgentTool(name: "read_dynamical", title: "Dynamical intensities",
                  summary: "The shown Simulation document's Intensities: Kinematic or Dynamical, whether the exit waves are computing, the "
                      + "stored thicknesses and the one shown, the method line, why the kinematical spots are drawn instead (thermal "
                      + "vibrations on, a refused specimen, a failed run, a pattern tilted off the axis), the beams drawn with their "
                      + "intensity in percent of the incident beam, and Index's spot rows with their dynamical intensity.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            return .json(dynamicalState(simulation))
        },
    ]

    /// The Intensities rows and the spots they draw, in the door's words.
    static func dynamicalState(_ simulation: OpenItem) -> [String: Any] {
        let model = simulation.multislice, analysis = simulation.diffraction
        let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
        var state: [String: Any] = [
            "document": simulation.url.lastPathComponent,
            "dynamical": model.isDynamical,
            "computing": model.isComputing,
            "absence": AgentJSON.orNull(model.dynamicalAbsence(crystal: crystal, zoneAxis: zoneAxis)),
            "model_refusal": AgentJSON.orNull(model.atomModel != nil ? SimulationModel.modelDynamicalSentence : nil),
            "off_axis": AgentJSON.orNull(analysis.simulation.isShown ? simulation.dynamicalOffAxis : nil),
        ]
        if model.isDynamical, let waves = model.exitWaves, let index = model.shownThicknessIndex,
           model.exitWavesAreCurrent(crystal: crystal, zoneAxis: zoneAxis) {
            state["thicknesses_nm"] = waves.planePeriods.indices.map { waves.thicknessNM(at: $0) }
            state["thickness_index"] = index
        }
        if let beams = simulation.dynamicalBeams {
            state["thickness_nm"] = beams.thicknessNM
            state["method"] = beams.methodLine
            let strongest = beams.intensities.filter { $0.key != MillerIndex(0, 0, 0) }.values.max() ?? 0
            state["beams"] = beams.intensities
                .filter { $0.key == MillerIndex(0, 0, 0) || $0.value >= strongest * DynamicalBeams.drawnFraction }
                .sorted { $0.value > $1.value }
                .map { ["hkl": ZoneAxisText.label($0.key), "percent": $0.value * 100] as [String: Any] }
        }
        state["spots"] = simulation.indexSpotRows.map {
            ["number": $0.number, "hkl": AgentJSON.orNull($0.hkl.map(ZoneAxisText.label)), "dynamical_percent": AgentJSON.number($0.dynamicalPercent)]
                as [String: Any]
        }
        return state
    }

    // MARK: CBED (MA9)

    static let cbedTools: [AgentTool] = [
        said(AgentTool(name: "set_cbed", title: "CBED settings",
                       summary: "The Simulation section's Beam and CBED settings of the shown Simulation document, only those given, "
                           + "through its own controls: beam (Parallel or Convergent), semiangle_mrad or fit_discs true (the largest "
                           + "semiangle that keeps the discs apart), largest_thickness_nm, angular_step_mrad (it sets the box), "
                           + "edge_mrad (the largest angle the pattern shows), and thickness_index (which stored pattern the CBED pattern "
                           + "shows). Refused with the section's ranges when a value is not kept; new settings need run_cbed.",
                       input: .window,
                       parameters: [
                           AgentParameter("beam", .choice(["Parallel", "Convergent"]), summary: "A plane wave (the spots) or a probe (CBED)."),
                           AgentParameter("semiangle_mrad", .number(CBEDSettings.semiangleRangeMrad), summary: "The probe's convergence semiangle, mrad."),
                           AgentParameter("fit_discs", .boolean, summary: "The largest semiangle that keeps the discs apart."),
                           AgentParameter("largest_thickness_nm", .number(CBEDSettings.largestThicknessRangeNM), summary: "The thickest stored pattern, nm."),
                           AgentParameter("angular_step_mrad", .number(CBEDSettings.angularStepRangeMrad), summary: "The pattern's mrad per pixel."),
                           AgentParameter("edge_mrad", .number(CBEDSettings.edgeRangeMrad), summary: "The largest angle the pattern shows, mrad."),
                           AgentParameter("thickness_index", .integer(0...10_000), summary: "The stored pattern shown, 0 the thinnest."),
                       ],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            let model = simulation.cbed, arguments = call.arguments
            func number(_ key: String) -> Double? { arguments[key].flatMap(Double.init) }
            if number("semiangle_mrad") != nil, arguments["fit_discs"] == "true" {
                return refused("Give semiangle_mrad or fit_discs, not both: Fit Discs replaces the typed semiangle.")
            }
            if arguments["fit_discs"] == "true", simulation.multislice.atomModel != nil { return refused(SimulationModel.modelFitDiscsSentence) }
            let index = arguments["thickness_index"].flatMap(Int.init)
            if let index {
                guard let pattern = model.pattern else { return refused("No stored patterns yet: run_cbed computes them.") }
                guard index < pattern.patterns.count else { return refused("The stored patterns are 0 to \(pattern.patterns.count - 1).") }
            }
            let kept = model.changeSettings { s in
                if let v = number("semiangle_mrad") { s.semiangleMrad = v }
                if let v = number("largest_thickness_nm") { s.largestThicknessNM = v }
                if let v = number("angular_step_mrad") { s.angularStepMrad = v }
                if let v = number("edge_mrad") { s.edgeMrad = v }
            }
            guard kept else {
                return refused("Those settings are not kept: a semiangle of \(range(CBEDSettings.semiangleRangeMrad)) mrad, a largest thickness of "
                    + "\(range(CBEDSettings.largestThicknessRangeNM)) nm and at least the step, an angular step of "
                    + "\(range(CBEDSettings.angularStepRangeMrad)) mrad and an edge of \(range(CBEDSettings.edgeRangeMrad)) mrad.")
            }
            if let beam = arguments["beam"] { model.setConvergent(beam == "Convergent") }
            if arguments["fit_discs"] == "true" { model.fitDiscs() }
            if let index {
                model.setThicknessIndex(index)
                appState.refreshCBEDPattern(of: simulation)
            }
            return .json(cbedState(simulation, in: appState))
        }),
        said(AgentTool(name: "run_cbed", title: "Show CBED pattern",
                       summary: "Show CBED Pattern for the shown Simulation document: opens the pattern in the Diffraction room (in a "
                           + "tab of its own) and runs the probe through the slab, storing a pattern at every thickness step. Refused "
                           + "with the section's words when it cannot run (Parallel beam, no phase, a refused specimen, no beam energy, an "
                           + "edge that cuts the discs off, a hand tilt past the small-angle range, another document's run) or while it "
                           + "runs. A tilt set by hand (set_zone_axis tilt_down, tilt_across) is the run's beam tilt, so a pattern tilted "
                           + "to one strong reflection is two-beam. It answers at once; read_cbed says computing until it ends, and "
                           + "stop_cbed stops it.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            guard simulation.cbed.isConvergent else { return refused("The beam is Parallel: set_cbed beam Convergent first, as the section shows CBED only then.") }
            if simulation.cbed.isComputing { return refused("The CBED run is going; wait until read_cbed says it ended, or stop_cbed.") }
            if let blocker = appState.cbedBlocker(of: simulation) { return refused(blocker) }
            appState.showCBEDPattern(of: simulation)
            return .json(["started": "Show CBED Pattern"])
        }),
        said(AgentTool(name: "stop_cbed", title: "Stop CBED",
                       summary: "The CBED section's Stop: ends the shown Simulation document's CBED run; the patterns already stored stay.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            guard simulation.cbed.isComputing else { return refused("No CBED run is going.") }
            simulation.cbed.stop()
            return .json(["stopped": "CBED"])
        }),
        AgentTool(name: "read_cbed", title: "CBED",
                  summary: "The shown Simulation document's Beam and CBED rows: the settings, the semiangle used (typed or Fit Discs') and "
                      + "the largest that keeps the discs apart, the overlap sentence, the plan (box, grid, patterns) and the small-box "
                      + "warning, the beam tilt the run takes from the orientation drawn by hand (tilt_mrad along the pattern's rows "
                      + "and columns, tilt_degrees off the zone axis), why Show CBED Pattern cannot run, the run's progress and "
                      + "failure, and the stored patterns: their "
                      + "thicknesses, the one shown, the beyond-the-validated-depth chip and the method line. get_image draws the "
                      + "pattern with the CBED pattern shown.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            return .json(cbedState(simulation, in: appState))
        },
    ]

    /// The Beam and CBED rows as the section shows them, in the door's words.
    static func cbedState(_ simulation: OpenItem, in appState: AppState) -> [String: Any] {
        let model = simulation.cbed, analysis = simulation.diffraction, settings = model.settings
        let volts = analysis.typedBeamKV.map { $0 * 1000 }
        let shortestG = appState.cbedShortestG(of: simulation)
        let separated = volts.flatMap { v in shortestG.flatMap { try? CBEDRun.separatedSemiangle(shortestG: $0, volts: v) } }
        let semiangle = volts.flatMap { model.semiangle(shortestG: shortestG, volts: $0) }
        var state: [String: Any] = [
            "document": simulation.url.lastPathComponent,
            "beam": model.isConvergent ? "Convergent" : "Parallel",
            "semiangle_mrad": AgentJSON.number(semiangle),
            "fit_discs": settings.semiangleMrad == nil,
            "separated_semiangle_mrad": AgentJSON.number(separated),
            "largest_thickness_nm": settings.largestThicknessNM,
            "thickness_step_nm": settings.thicknessStepNM,
            "angular_step_mrad": settings.angularStepMrad,
            "edge_mrad": settings.edgeMrad,
            "blocker": AgentJSON.orNull(appState.cbedBlocker(of: simulation)),
            // An atom model's pattern: Fit Discs and the overlay's spots and labels refuse with the section's sentences (#953).
            "fit_discs_refusal": AgentJSON.orNull(simulation.multislice.atomModel != nil ? SimulationModel.modelFitDiscsSentence : nil),
            "labels_refusal": AgentJSON.orNull(simulation.multislice.atomModel != nil ? SimulationModel.modelLabelsSentence : nil),
            "computing": model.isComputing,
            "progress": AgentJSON.number(model.progress),
            "failure": AgentJSON.orNull(model.failure),
            "pattern_shown": appState.pairedItem(at: DemoDocuments.cbedURL(of: simulation.url)) != nil,
        ]
        if let tilt = appState.cbedTilt(of: simulation) {
            state["tilt_mrad"] = [tilt.x, tilt.y]
            state["tilt_degrees"] = CBEDTilt.degrees(tilt)
        }
        if let semiangle, let separated, let sentence = CBEDRun.overlapSentence(semiangleMrad: semiangle, separatedMrad: separated) {
            state["overlap"] = sentence
        }
        if let plan = appState.cbedPlan(of: simulation) {
            state["plan"] = plan.sentence
            state["small_box"] = AgentJSON.orNull(plan.smallBoxSentence)
        }
        if let pattern = model.pattern, let index = model.shownIndex {
            state["thicknesses_nm"] = pattern.thicknessesNM
            state["thickness_index"] = index
            state["thickness_nm"] = pattern.thicknessesNM[index]
            state["method"] = pattern.methodLine(at: index)
            state["depth_chip"] = AgentJSON.orNull(pattern.depthChip)
        }
        return state
    }

    // MARK: Two-beam CBED thickness (MA15)

    static let thicknessTools: [AgentTool] = [
        said(AgentTool(name: "measure_thickness", title: "Measure thickness",
                       summary: "The Diffraction room's Measure Thickness on the pattern shown (a measured two-beam CBED pattern, or a "
                           + "Simulation document's CBED pattern run at a hand tilt to one strong reflection): finds the transmitted and diffracted discs on the phase's first "
                           + "reflections and fits the two-beam intensity across the diffracted disc (Kelly et al. 1975). Needs the "
                           + "phase, the calibration and the beam energy (set_diffraction). It answers at once; read_thickness gives the "
                           + "verdict, the sentence and the numbers when it ends.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected else { return refused("The window shows no pattern.") }
            guard !item.thickness.isMeasuring else { return refused("A measurement is going; read_thickness says when it ends.") }
            let inputs = item.thicknessInputs
            Task { await item.thickness.measure(inputs) }
            if case .failure(let refusal) = inputs { return refused(refusal.sentence) }
            return .json(["started": "Measure Thickness"])
        }),
        AgentTool(name: "read_thickness", title: "Thickness",
                  summary: "The Diffraction room's Thickness section for the pattern shown: whether a measurement is going, its verdict "
                      + "(found, ambiguous, poor) and sentence, the thickness, extinction distances and residual, the fringe line's "
                      + "thickness, the method line, the profile across the diffracted disc with the fitted curve and the minima by "
                      + "order, and whether Use in Simulation is offered. stale true when the pattern or its calibration changed since.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected else { return refused("The window shows no pattern.") }
            return .json(thicknessState(item, in: appState))
        },
        said(AgentTool(name: "use_measured_thickness", title: "Use thickness in simulation",
                       summary: "The Thickness section's Use in Simulation: sets the specimen thickness of the Simulation document the "
                           + "measured pattern belongs to (the document itself or its CBED pattern) to the thickness found. Refused when "
                           + "there is no current measurement that found one, the pattern is a measured file with no Simulation document, "
                           + "or the document simulates an atom model (its thickness is the model's own).",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected else { return refused("The window shows no pattern.") }
            if let refusal = appState.useInSimulationRefusal(of: item) { return refused(refusal) }
            guard let measurement = currentMeasurement(item), let nm = measurement.thicknessNM, !measurement.isPoor else {
                return refused("No thickness was found on this pattern now: measure_thickness first, and read_thickness for its verdict.")
            }
            guard let simulation = appState.thicknessSimulation(of: item) else {
                return refused("This pattern belongs to no Simulation document: File > New Simulation opens one, and set_simulation takes thickness_nm.")
            }
            simulation.multislice.setThickness(nm: nm)
            return .json(["document": simulation.url.lastPathComponent, "thickness_nm": simulation.multislice.thicknessNM])
        }),
    ]

    /// The measurement the section shows now: one of the pattern, calibration and phase as they are.
    private static func currentMeasurement(_ item: OpenItem) -> CBEDThickness.Measurement? {
        guard !item.thickness.isMeasuring, case .success(let m)? = item.thickness.outcome,
              item.thickness.isCurrent(try? item.thicknessInputs.get()) else { return nil }
        return m
    }

    static func thicknessState(_ item: OpenItem, in appState: AppState) -> [String: Any] {
        let model = item.thickness
        var state: [String: Any] = ["measuring": model.isMeasuring]
        switch model.outcome {
        case nil:
            state["verdict"] = NSNull()
        case .failure(let refusal)?:
            state["verdict"] = "refused"
            state["sentence"] = refusal.sentence
        case .success(let m)?:
            state["verdict"] = m.verdict
            state["sentence"] = m.sentence
            state["stale"] = !model.isCurrent(try? item.thicknessInputs.get())
            state["thickness_nm"] = AgentJSON.number(m.thicknessNM)
            state["candidates_nm"] = [m.fit.thickness / 10] + (m.fit.secondCandidate.map { [$0.thickness / 10] } ?? [])
            state["extinction_distance_nm"] = m.fit.extinctionDistance / 10
            state["two_beam_extinction_distance_nm"] = m.fit.twoBeamExtinctionDistance / 10
            state["residual_percent"] = m.fit.residual * 100
            state["fringe_line_thickness_nm"] = AgentJSON.number(m.fit.fringeLine.map { $0.thickness / 10 })
            state["reflection"] = "\(m.phase) \(ZoneAxisText.label(m.discs.hkl))"
            state["method"] = m.methodLine
            state["profile"] = ["offsets_px": m.discs.offsets, "intensities": m.discs.intensities, "fitted": m.fittedCurve,
                                "minima": m.minima.map { ["order": $0.order, "offset_px": $0.offset] as [String: Any] }] as [String: Any]
        }
        state["use_in_simulation"] = currentMeasurement(item).map { $0.thicknessNM != nil && !$0.isPoor } == true
            && appState.thicknessSimulation(of: item) != nil
        return state
    }

    // MARK: STEM (MA10)

    static let stemTools: [AgentTool] = [
        said(AgentTool(name: "set_stem", title: "STEM settings",
                       summary: "The STEM section of the shown Simulation document (or its STEM image), only the values given, through "
                           + "its own controls: semiangle_mrad, defocus_nm (positive is underfocus) or scherzer true, scan_step_angstrom "
                           + "or nyquist true (λ over 4α), collect_mrad (the largest angle collected), detector (BF, ABF, ADF, HAADF, or "
                           + "Custom with inner_mrad and outer_mrad; edges snap to whole 1 mrad rings, as the kit sums them). A preset "
                           + "that runs past the angles collected is refused. The detector band moves after a run with no new run; the other "
                           + "settings need run_stem. Refused with the section's ranges when a value is not kept.",
                       input: .window,
                       parameters: [
                           AgentParameter("semiangle_mrad", .number(STEMSettings.semiangleRangeMrad), summary: "The probe's convergence semiangle, mrad."),
                           AgentParameter("defocus_nm", .number(-10_000...10_000), summary: "The probe's defocus, nm; positive is underfocus."),
                           AgentParameter("scherzer", .boolean, summary: "Back to Scherzer defocus for the optics' Cs."),
                           AgentParameter("scan_step_angstrom", .number(STEMSettings.scanStepRangeAngstrom), summary: "The distance between probe positions, Å."),
                           AgentParameter("nyquist", .boolean, summary: "Back to the Nyquist step for the probe."),
                           AgentParameter("collect_mrad", .number(STEMSettings.collectRangeMrad), summary: "The largest angle the detector collects, mrad."),
                           AgentParameter("detector", .choice(STEMDetector.allCases.map(\.title) + ["Custom"]), summary: "A preset band, or Custom."),
                           AgentParameter("inner_mrad", .number(0...400), summary: "Custom: the band's inner angle, mrad."),
                           AgentParameter("outer_mrad", .number(0...400), summary: "Custom: the band's outer angle, mrad."),
                       ],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            let model = simulation.stem, arguments = call.arguments
            func number(_ key: String) -> Double? { arguments[key].flatMap(Double.init) }
            if number("defocus_nm") != nil, arguments["scherzer"] == "true" { return refused("Give defocus_nm or scherzer, not both.") }
            if number("scan_step_angstrom") != nil, arguments["nyquist"] == "true" { return refused("Give scan_step_angstrom or nyquist, not both.") }
            var preset: STEMDetector?? = nil
            if let name = arguments["detector"] { preset = .some(STEMDetector.allCases.first { $0.title == name }) }
            let bandGiven = number("inner_mrad") != nil || number("outer_mrad") != nil
            if bandGiven, case .some(.some) = preset {
                return refused("A preset sets its own band: give detector Custom with inner_mrad and outer_mrad.")
            }
            var settings = model.settings
            if let v = number("semiangle_mrad") { settings.semiangleMrad = v }
            if let v = number("defocus_nm") { settings.defocusNM = v }
            if arguments["scherzer"] == "true" { settings.defocusNM = nil }
            if let v = number("scan_step_angstrom") { settings.scanStepAngstrom = v }
            if arguments["nyquist"] == "true" { settings.scanStepAngstrom = nil }
            if let v = number("collect_mrad") { settings.collectMrad = v }
            let shown = model.band
            let typed = STEMBand(inner: number("inner_mrad") ?? shown.inner, outer: number("outer_mrad") ?? shown.outer)
            let band = typed.snapped()
            if bandGiven, !(typed.outer > typed.inner && band.inner >= 0 && band.outer <= settings.collectMrad.rounded()) {
                return refused("A band runs from an inner angle of at least 0 to a larger outer angle, at most the "
                    + "\(UnitDisplay.number(settings.collectMrad, digits: 3)) mrad collected.")
            }
            if case .some(.some(let p)) = preset, !model.fits(p, settings: settings) {
                return refused("\(p.title) runs past the angles collected: choose a band inside them, or raise collect_mrad and run_stem again.")
            }
            guard model.changeSettings({ $0 = settings }) else {
                return refused("Those settings are not kept: a semiangle of \(range(STEMSettings.semiangleRangeMrad)) mrad, a finite defocus, a scan "
                    + "step of \(range(STEMSettings.scanStepRangeAngstrom)) Å and a collection angle of \(range(STEMSettings.collectRangeMrad)) mrad.")
            }
            if let preset { model.setDetector(preset) }
            if bandGiven { model.setBand(band) }
            appState.refreshSTEMImage(of: simulation)
            return .json(stemState(simulation, in: appState))
        }),
        said(AgentTool(name: "run_stem", title: "Simulate STEM",
                       summary: "Show STEM Image and the STEM section's Simulate (Continue after a stop, with the settings unchanged) for "
                           + "the shown Simulation document: opens the image in the Image room (in a tab of its own) and scans the probe "
                           + "over one projected unit, the image filling as it is computed. Refused with the section's words when it "
                           + "cannot run (no phase, no beam energy, a refused specimen, another document's run), while it runs, or when "
                           + "the image is complete for these settings. It answers at once; read_stem says running until it ends, and "
                           + "stop_stem stops it, keeping the positions done.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            let model = simulation.stem
            if model.isRunning { return refused("The STEM run is going; wait until read_stem says it ended, or stop_stem.") }
            let run: (key: STEMModel.RunKey, built: SimulationSpecimen.Built, specimen: String)
            switch appState.stemRun(of: simulation) {
            case .failure(let refusal): return refused(refusal.sentence)
            case .success(let r): run = r
            }
            if let blocker = model.blocker { return refused(blocker) }
            if model.holds(run.key), model.scan?.isComplete == true {
                return refused("The STEM image is complete for these settings: change one with set_stem to run again.")
            }
            let resumes = model.holds(run.key)
            appState.showSTEMImage(of: simulation)
            Task { await appState.simulateSTEM(of: simulation) }
            return .json(["started": resumes ? "Continue" : "Simulate"])
        }),
        said(AgentTool(name: "stop_stem", title: "Stop STEM",
                       summary: "The STEM section's Stop: ends the shown Simulation document's STEM run after its current positions; what "
                           + "is finished stays, and run_stem continues from there.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            guard simulation.stem.isRunning else { return refused("No STEM run is going.") }
            simulation.stem.stop()
            return .json(["stopped": "STEM"])
        }),
        AgentTool(name: "read_stem", title: "STEM",
                  summary: "The shown Simulation document's STEM section: the settings with the defocus and scan step used (Scherzer and "
                      + "Nyquist until typed), the plan line, whether the lattice is static, why Simulate cannot run, the run's "
                      + "progress, positions and failure, whether the settings changed since the image, the detector and its band, the "
                      + "scattered intensity against angle, the \"not quantitative\" chip and the method line. get_image draws the image "
                      + "with the STEM image shown.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let simulation = simulationItem(appState) else { return noSimulationDocument }
            return .json(stemState(simulation, in: appState))
        },
    ]

    /// The STEM section as it shows, in the door's words.
    static func stemState(_ simulation: OpenItem, in appState: AppState) -> [String: Any] {
        let model = simulation.stem, settings = model.settings
        let volts = simulation.diffraction.typedBeamKV.map { $0 * 1000 }
        let csMM = simulation.multislice.optics.csMM
        let band = model.band
        var state: [String: Any] = [
            "document": simulation.url.lastPathComponent,
            "semiangle_mrad": settings.semiangleMrad,
            "defocus_nm": AgentJSON.number(volts.flatMap { try? STEMImage.defocusNM(settings, csMM: csMM, volts: $0) }),
            "scherzer": settings.defocusNM == nil,
            "scan_step_angstrom": AgentJSON.number(settings.scanStepAngstrom
                ?? volts.flatMap { try? STEMImage.nyquistStep(semiangleMrad: settings.semiangleMrad, volts: $0) }),
            "nyquist": settings.scanStepAngstrom == nil,
            "collect_mrad": settings.collectMrad,
            "detector": model.detector?.title ?? "Custom",
            "band_mrad": [band.inner, band.outer],
            "band_refusal": AgentJSON.orNull(model.bandRefusal),
            "wrap": AgentJSON.orNull(appState.stemWrapSentence(of: simulation)),
            "static_lattice": simulation.multislice.thermal == nil,
            "running": model.isRunning,
            "progress": AgentJSON.number(model.progress),
            "failure": AgentJSON.orNull(model.failure),
            "blocker": AgentJSON.orNull(model.blocker),
            "image_shown": appState.pairedItem(at: DemoDocuments.stemURL(of: simulation.url)) != nil,
        ]
        switch appState.stemRun(of: simulation) {
        case .failure(let refusal):
            state["refusal"] = refusal.sentence
        case .success(let run):
            let configurations = simulation.multislice.thermal?.configurations ?? 1
            switch Result(catching: { try STEMImage.planLine(run.built, settings: settings, volts: run.key.volts, configurations: configurations) }) {
            case .success(let line): state["plan"] = line
            case .failure(let error): state["plan_refusal"] = ErrorDetail.text(error)
            }
            state["stale"] = model.scan != nil && !model.holds(run.key)
        }
        if let scan = model.scan {
            state["complete"] = scan.isComplete
            state["completed_configurations"] = scan.completedConfigurations
            state["completed_positions"] = scan.completedPositions
            if !scan.isEmpty {
                let profile = scan.radialProfile()
                state["radial_profile"] = ["angles_mrad": profile.angles, "intensities": profile.intensities] as [String: Any]
                state["not_quantitative"] = AgentJSON.orNull(scan.notQuantitative(band: band))
                state["method"] = scan.methodLine(band: band)
            }
        }
        return state
    }

    private static func range(_ r: ClosedRange<Double>) -> String {
        "\(UnitDisplay.number(r.lowerBound, digits: 3)) to \(UnitDisplay.number(r.upperBound, digits: 3))"
    }

    static let noSimulationDocument = AgentToolOutput.refusal(
        status: 404, message: "The window shows no Simulation document or its image or pattern: File > New Simulation opens one.")
}
