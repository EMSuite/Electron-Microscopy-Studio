//
//  AgentDoorIndexing.swift
//  Role: the agent door's tools for the Indexing room (#558). `get_indexing` reads the room: the phases, the method and its settings,
//        the run on screen with its counts and means, the picked point's solution and detected bands, Refine and Compare.
//        `get_indexing_picture` draws the map, the pattern and the best match as the panes show them; `set_indexing` and
//        `set_indexing_phase` set the Display, Method, Hough, Dictionary and Refine sections and the Phases list through the session calls
//        their controls make (`IndexingSession`); `open_in_maps` is the Export section's Open in Maps. Index itself is `run_room`, the
//        toolbar verb, and a position is picked with `select_scan_position`, which follows the room shown.
//
//        ONE SOURCE PER FACT: the map picture is the Export section's Map PNG (`IndexingRoomState.input`'s two cases: a scalar layer
//        through `PatternsRoomState.mapPNG`, a pointwise one through `.mixPNG`); the pattern and best match go through
//        `PatternsRoomState.patternPNG` from the panes' own canvases. The run's state is Info's sentence (`IndexingInfoFormat.state`).
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let indexingTools: [AgentTool] = [
        AgentTool(name: "get_indexing", title: "Indexing room",
                  summary: "What the Indexing room holds: where its patterns come from, the phases (on or off, space group, reflectors, "
                      + "where each came from), the method and every setting of Hough, Dictionary and Refine (in set_indexing's names), the "
                      + "master patterns open, why Index is refused, the run on screen (its state, points indexed per phase, the mean "
                      + "confidence or score and fit), the picked point's solution and its detected bands, the map layer, Compare's "
                      + "summary, and what is running.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return indexing(appState)
        },
        AgentTool(name: "get_indexing_picture", title: "Indexing room picture",
                  summary: "One of the Indexing room's panes: which map (the layer on screen as Export's Map PNG draws it, one pixel per "
                      + "scan point: an IPF, Euler or phase colour, or a scalar layer in its colormap), pattern (the pattern at the picked "
                      + "position as it is indexed, without the band overlay: get_indexing lists the bands) or best_match (a Dictionary "
                      + "run's simulated best match at the picked position). A small picture is enlarged by a whole factor without "
                      + "smoothing.",
                  input: .windowPicture,
                  parameters: [AgentParameter("which", .choice(["map", "pattern", "best_match"]), summary: "The pane to draw.", required: true)]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return indexingPicture(appState, which: call.arguments["which"] ?? "", scale: call.scale)
        },
        said(AgentTool(name: "set_indexing", title: "Indexing room settings",
                       summary: "The Display, Method, Hough, Dictionary and Refine sections; only what is given changes, and a change to an "
                           + "input of a run makes that run stale (get_indexing says so) until Index runs again. reset (hough, dictionary or "
                           + "refine) goes back to the room's defaults first. The Hough settings are pyEBSDindex's EBSDIndexer's "
                           + "(kikuchipy's tutorial values by default), Dictionary kikuchipy's dictionary_indexing with orix's sampling, "
                           + "Refine kikuchipy's refine_orientation, refine_projection_center or both after a Dictionary run.",
                       input: .window, parameters: indexingParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.indexing.hasDataset else { return noIndexing }
            if let refusal = applyIndexing(call.arguments, to: appState.indexing) { return refusal }
            return indexing(appState)
        }),
        said(AgentTool(name: "set_indexing_phase", title: "Indexing phase",
                       summary: "The Phases section, and the master pattern a phase's dictionary is projected from. add puts a built-in "
                           + "phase in the list (" + IndexingPhase.presets.map(\.name).joined(separator: ", ") + "); then phase names the "
                           + "phase to change: on, reflectors (fcc, bcc, or hcp for a hexagonal space group), master (the file name of an "
                           + "open master pattern of its space group), remove. A CIF or a master pattern from disk is opened by the person.",
                       input: .window,
                       parameters: [
                           AgentParameter("add", .choice(IndexingPhase.presets.map(\.name)), summary: "A built-in phase to add."),
                           AgentParameter("phase", .text, summary: "The phase to change, by name as get_indexing lists it."),
                           AgentParameter("on", .boolean, summary: "Index against it."),
                           AgentParameter("reflectors", .choice(IndexingPhase.Reflectors.allCases.map(\.rawValue)),
                                          summary: "pyEBSDindex's reflector list for the Hough method."),
                           AgentParameter("master", .text, summary: "The master pattern for its dictionary, by file name."),
                           AgentParameter("remove", .boolean, summary: "true takes it out of the list; the file is unchanged."),
                       ],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.indexing.hasDataset else { return noIndexing }
            if let refusal = applyPhase(call.arguments, to: appState.indexing) { return refusal }
            return indexing(appState)
        }),
        AgentTool(name: "open_in_maps", title: "Open in Maps",
                  summary: "The Indexing room's Open in Maps: the run on screen goes to the Maps room as its crystal map (the rows "
                      + "reached, the phase colours, the scan's steps), at the picked position, and the window moves there. Refused while "
                      + "a run goes or before one reached a point.",
                  input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let session = appState.indexing
            guard session.hasDataset else { return noIndexing }
            if let why = session.openInMapsRefusal { return .refusal(status: 409, message: why + ".") }
            guard appState.openIndexingInMaps() != nil else {
                return .refusal(status: 500, message: "The run could not be handed to the Maps room: " + appState.statusText)
            }
            appState.statusText = "An agent opened the Indexing room's run in the Maps room."
            return .json(["room": WorkspaceArea.maps.rawValue, "file_name": session.patterns.document?.fileName ?? ""])
        },
    ]

    private static let noIndexing = AgentToolOutput.refusal(
        status: 404, message: "No EBSD pattern dataset is open; open one first (open_demo with demo ebsd opens kikuchipy's nickel scan).")

    /// `set_indexing`'s inputs, named as `get_indexing` names the settings.
    static let indexingParameters: [AgentParameter] = [
        AgentParameter("reset", .choice(["hough", "dictionary", "refine"]), summary: "Back to that section's defaults, before the rest."),
        AgentParameter("method", .choice(IndexingMethod.allCases.map(\.rawValue)), summary: "hough or dictionary (needs a master pattern)."),
        AgentParameter("layer", .choice(IndexingLayer.allCases.map(\.rawValue)),
                       summary: "The map's layer; get_indexing lists those of the method shown (available_layers)."),
        AgentParameter("show_bands", .boolean, summary: "The detected bands over the pattern."),
        AgentParameter("show_simulation", .boolean, summary: "The simulated Kikuchi bands of the picked point's orientation over the pattern."),
        AgentParameter("compare", .boolean, summary: "Compare two results in place of the Results and Bands tables."),
        AgentParameter("compare_a", .choice(IndexingCompareSource.allCases.map(\.rawValue)), summary: "Compare's left result."),
        AgentParameter("compare_b", .choice(IndexingCompareSource.allCases.map(\.rawValue)), summary: "Compare's right result."),
        AgentParameter("hough_bands", .integer(3...50), summary: "Bands detected per pattern (nBands)."),
        AgentParameter("rho_mask_percent", .number(0...49), summary: "The ρ range left out at each edge, in % (rhoMaskFrac × 100)."),
        AgentParameter("rho_bins", .integer(1...10_000), summary: "Radon bins across ρ (nRho)."),
        AgentParameter("theta_bins", .integer(1...10_000), summary: "Radon bins over 180° (nTheta)."),
        AgentParameter("rho_sigma", .number(0...100), summary: "The kernel's width across ρ, in bins (rSigma)."),
        AgentParameter("theta_sigma", .number(0...100), summary: "The kernel's width along θ, in bins (tSigma)."),
        AgentParameter("angle_tolerance", .number(0...90), summary: "The vote's angle tolerance in degrees (angTol)."),
        AgentParameter("early_exit_bands", .integer(1...50), summary: "Bands agreeing that end a pattern's vote (nband_earlyexit)."),
        AgentParameter("resolution", .number(DictionaryIndexingSettings.resolutionRange),
                       summary: "Dictionary: orix's sampling resolution in degrees."),
        AgentParameter("metric", .choice(DictionaryIndexing.Metric.allCases.map(\.rawValue)), summary: "Dictionary: ncc or ndp."),
        AgentParameter("keep", .integer(DictionaryIndexingSettings.keepRange), summary: "Dictionary: matches kept per pattern (keep_n)."),
        AgentParameter("signal_mask", .choice(DictionaryIndexingSettings.SignalMask.allCases.map(\.rawValue)),
                       summary: "Dictionary: none, or circular (the pattern's inscribed circle)."),
        AgentParameter("refine", .boolean, summary: "Index refines a Dictionary run after it, and the room shows the refinement."),
        AgentParameter("refine_target", .choice(IndexingRefineSettings.Target.allCases.map(\.rawValue)),
                       summary: "What Refine moves: orientation, projectionCenter or both."),
        AgentParameter("trust_angle", .number(0...90), summary: "Refine: ± degrees around each indexed Euler angle (trust_region)."),
        AgentParameter("trust_pc", .number(0...1), summary: "Refine: ± around each of PCx, PCy, PCz (Bruker fractions)."),
    ]

    // MARK: Answers

    /// Numbers in the answers are written with a point, whatever the Mac's Region.
    private static let indexingPoint = Locale(identifier: "en_US_POSIX")

    static func indexing(_ appState: AppState) -> AgentToolOutput {
        let session = appState.indexing
        guard let document = session.patterns.document else { return noIndexing }
        let dataset = document.dataset
        let pinned = session.patterns.pinned
        var sourceWords: Any = ""
        switch session.source() {
        case .success(let source): sourceWords = source.kind.title
        case .failure(let refusal): sourceWords = ["refused": refusal.sentence]
        }
        let h = session.settings, d = session.dictionarySettings, r = session.refineSettings
        var answer: [String: Any] = [
            "file_name": document.fileName,
            "scan": ["columns": dataset.scanColumns, "rows": dataset.scanRows],
            "patterns_source": sourceWords,
            "projection_centre": AgentJSON.orNull(IndexingPlan.meanProjectionCenter(dataset.detector).map { [$0.x, $0.y, $0.z] }),
            "phases": session.phases.map { phase -> [String: Any] in
                ["name": phase.name, "on": phase.isOn, "space_group": phase.spaceGroup,
                 "point_group": AgentJSON.orNull(phase.pointGroupName), "reflectors": phase.reflectors.rawValue,
                 "source": phase.source.rawValue, "lattice": phase.lattice, "refusal": AgentJSON.orNull(phase.refusal),
                 "hough_caveat": AgentJSON.orNull(phase.houghCaveat),
                 "master": AgentJSON.orNull(session.master(for: phase)?.fileName)]
            },
            "phases_skipped": session.skippedPhases,
            "method": session.method.rawValue,
            "hough": ["hough_bands": h.bands, "rho_mask_percent": AgentJSON.number(h.rhoMaskFraction * 100), "rho_bins": h.rhoBins,
                      "theta_bins": h.thetaBins, "rho_sigma": AgentJSON.number(h.rhoSigma), "theta_sigma": AgentJSON.number(h.thetaSigma),
                      "angle_tolerance": AgentJSON.number(h.angleTolerance), "early_exit_bands": h.earlyExitBands,
                      "refusal": AgentJSON.orNull(h.refusal)] as [String: Any],
            "dictionary": ["resolution": AgentJSON.number(d.resolution), "metric": d.metric.rawValue, "keep": d.keep,
                           "signal_mask": d.signalMask.rawValue, "size": AgentJSON.orNull(session.dictionarySize),
                           "master_patterns": session.masterPatterns.map { ["file_name": $0.fileName, "summary": $0.summary(locale: indexingPoint)] },
                           "reading_master": session.isLoadingMaster,
                           "refusal": AgentJSON.orNull(session.dictionaryRefusal),
                           "master_warnings": session.masterWarnings] as [String: Any],
            "refine": refineAnswer(session, r),
            "layer": session.layer.rawValue,
            "available_layers": session.availableLayers.map(\.rawValue),
            "show_bands": session.showsDetectedBands,
            "show_simulation": session.showsSimulation,
            "compare": compareAnswer(session),
            "position": ["x": pinned.column, "y": pinned.row],
            "pattern_shown_at": AgentJSON.orNull(session.patternPosition.map { ["x": $0.column, "y": $0.row] }),
            "pattern_failure": AgentJSON.orNull(session.patternFailure),
            "detected_bands": session.detectedBands.map { band -> [String: Any] in
                ["rank": band.id, "rho": AgentJSON.number(band.rho), "theta": AgentJSON.number(band.thetaDegrees),
                 "peak": AgentJSON.number(band.peak), "width": AgentJSON.number(band.width), "valid": band.isValid,
                 "family": AgentJSON.orNull(band.family), "fit": AgentJSON.number(band.fitDegrees)]
            },
            "index_refusal": AgentJSON.orNull(session.refusal),
            "can_index": session.canIndex,
            "index_help": session.verbHelp,
            "open_in_maps_refusal": AgentJSON.orNull(session.openInMapsRefusal),
            "busy": session.isIndexing || session.patterns.isBusy,
            "running": ["indexing": session.isIndexing && !session.isRefining, "refining": session.isRefining,
                        "patterns_room": session.patterns.isBusy],
            "progress": AgentJSON.number(RoomProgress.fraction(room: .indexing, appState: appState)),
        ]
        answer["run"] = AgentJSON.orNull(session.result.map { runAnswer($0, session: session, at: pinned) })
        answer["other_run"] = AgentJSON.orNull(session.otherRun.map { other -> [String: Any] in
            ["method": other.method.rawValue, "indexed": other.result.indexedCount, "state": IndexingInfoFormat.state(of: other, session: session)]
        })
        return .json(answer)
    }

    /// The run on screen: Info's state, the counts, the means over the indexed points, and the picked point's solution.
    private static func runAnswer(_ result: IndexingResult, session: IndexingSession, at position: EBSDPosition) -> [String: Any] {
        var confidence = 0.0, fit = 0.0, fits = 0
        for case let s? in result.solutions where result.phase(of: s) != nil {
            confidence += s.confidence
            if s.fit.isFinite { fit += s.fit; fits += 1 }
        }
        let indexed = result.indexedCount
        var run: [String: Any] = [
            "method": result.method.rawValue,
            "refined": result.isRefined,
            "state": IndexingInfoFormat.state(result, session: session),
            "stale": session.isStale,
            "stopped": session.wasStopped,
            "complete": result.isComplete,
            "rows_done": result.rowsDone,
            "points": result.pointCount,
            "reached": result.reachedCount,
            "indexed": indexed,
            "indexed_by_phase": result.phases.indices.map { i -> [String: Any] in
                ["phase": result.phases[i].name, "points": result.countsByPhase.indices.contains(i) ? result.countsByPhase[i] : 0]
            },
            "score_name": result.scoreTitle,
            "mean_score": AgentJSON.number(indexed > 0 ? confidence / Double(indexed) : nil),
            "seconds": AgentJSON.number(session.lastRunSeconds),
            "readout": AgentJSON.orNull(result.readout(at: position, locale: indexingPoint)),
        ]
        if result.method == .hough { run["mean_fit_degrees"] = AgentJSON.number(fits > 0 ? fit / Double(fits) : nil) }
        if let s = result.solution(at: position) {
            let phase = result.phase(of: s)
            let euler = phase == nil ? nil : IndexingResult.eulerDegrees(s)
            var point: [String: Any] = [
                "phase": AgentJSON.orNull(phase?.name),
                "euler_degrees": AgentJSON.orNull(euler.map { [AgentJSON.number($0.x), AgentJSON.number($0.y), AgentJSON.number($0.z)] }),
            ]
            point[result.method == .hough ? "confidence" : "score"] = AgentJSON.number(s.confidence)
            if result.method == .hough {
                point["fit_degrees"] = AgentJSON.number(phase == nil ? nil : s.fit)
                point["matched_bands"] = s.matchedBands
                point["detected_bands"] = s.bandMatch.count
                point["pattern_quality"] = AgentJSON.number(s.patternQuality)
            } else {
                point["osm"] = AgentJSON.number(result.value(.osm, at: position.index(columns: result.scanColumns)))
            }
            run["picked_point"] = point
        } else {
            run["picked_point"] = NSNull()
        }
        return run
    }

    private static func refineAnswer(_ session: IndexingSession, _ r: IndexingRefineSettings) -> [String: Any] {
        var refine: [String: Any] = [
            "refine": session.refinesAfterIndexing, "refine_target": r.target.rawValue,
            "trust_angle": AgentJSON.number(r.trustAngle), "trust_pc": AgentJSON.number(r.trustPC),
            "solver": "Nelder-Mead", "stale": session.refinesAfterIndexing && session.isRefinementStale,
            "refusal": AgentJSON.orNull(session.refineRefusal),
        ]
        if let scores = session.refinementScores {
            refine["mean_score"] = ["metric": scores.metric, "as_indexed": AgentJSON.number(scores.before),
                                    "refined": AgentJSON.number(scores.after)]
        }
        if let pc = session.refinedProjectionCentre {
            refine["pc_mean"] = [pc.mean.x, pc.mean.y, pc.mean.z].map { AgentJSON.number($0) }
            refine["pc_std"] = [pc.deviation.x, pc.deviation.y, pc.deviation.z].map { AgentJSON.number($0) }
        }
        return refine
    }

    private static func compareAnswer(_ session: IndexingSession) -> [String: Any] {
        var compare: [String: Any] = [
            "compare": session.showsCompare, "compare_a": session.compareA.rawValue, "compare_b": session.compareB.rawValue,
            "sources": session.compareSources.map(\.rawValue),
            "a_absent": AgentJSON.orNull(session.compareAbsence(session.compareA)),
            "b_absent": AgentJSON.orNull(session.compareAbsence(session.compareB)),
        ]
        if session.showsCompare, let c = session.comparison {
            compare["summary"] = [
                "compared": c.comparedCount,
                "median_disorientation_degrees": AgentJSON.number(c.medianDegrees),
                "fraction_over_2_degrees": AgentJSON.number(c.fractionOverThreshold),
                "none_in_a": c.count(.noneInA), "none_in_b": c.count(.noneInB), "unpaired_phases": c.count(.unpairedPhases),
            ] as [String: Any]
        }
        return compare
    }

    // MARK: Setting

    /// `set_indexing`: reset first, then Display, Method, Hough, Dictionary and Refine, through the session calls their controls make.
    static func applyIndexing(_ a: [String: String], to session: IndexingSession) -> AgentToolOutput? {
        let flag = { (key: String) -> Bool? in a[key].map { $0 == "true" } }
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        let whole = { (key: String) -> Int? in a[key].flatMap(Int.init) }
        if let method = a["method"].flatMap(IndexingMethod.init(rawValue:)) {
            if method != session.method, session.isIndexing {
                return .refusal(status: 409, message: "A run is going; stop it (stop_run) or wait before changing the method.")
            }
        }
        for key in ["compare_a", "compare_b"] {
            if let source = a[key].flatMap(IndexingCompareSource.init(rawValue:)), !session.compareSources.contains(source) {
                return .refusal(status: 409, message: "\(key): \(source.rawValue) has no result to compare; the room offers "
                    + session.compareSources.map(\.rawValue).joined(separator: ", ") + ".")
            }
        }
        switch a["reset"] {
        case "hough": session.resetSettings()
        case "dictionary": session.resetDictionarySettings()
        case "refine": session.resetRefineSettings()
        default: break
        }
        if let method = a["method"].flatMap(IndexingMethod.init(rawValue:)), method != session.method { session.setMethod(method) }
        if let layer = a["layer"].flatMap(IndexingLayer.init(rawValue:)) {
            guard session.availableLayers.contains(layer) else {
                return .refusal(status: 409, message: "The \(session.method.title) run has no \(layer.title) layer; it has "
                    + session.availableLayers.map(\.rawValue).joined(separator: ", ") + ".")
            }
            session.setLayer(layer)
        }
        if let v = flag("show_bands") { session.showsDetectedBands = v }
        if let v = flag("show_simulation") { session.showsSimulation = v }
        if let v = flag("compare") { session.setShowsCompare(v) }
        if let v = a["compare_a"].flatMap(IndexingCompareSource.init(rawValue:)) { session.setCompareA(v) }
        if let v = a["compare_b"].flatMap(IndexingCompareSource.init(rawValue:)) { session.setCompareB(v) }
        let hough = ["hough_bands", "rho_mask_percent", "rho_bins", "theta_bins", "rho_sigma", "theta_sigma", "angle_tolerance", "early_exit_bands"]
        if hough.contains(where: { a[$0] != nil }) {
            session.editSettings { s in
                if let v = whole("hough_bands") { s.bands = v }
                if let v = number("rho_mask_percent") { s.rhoMaskFraction = v / 100 }
                if let v = whole("rho_bins") { s.rhoBins = v }
                if let v = whole("theta_bins") { s.thetaBins = v }
                if let v = number("rho_sigma") { s.rhoSigma = v }
                if let v = number("theta_sigma") { s.thetaSigma = v }
                if let v = number("angle_tolerance") { s.angleTolerance = v }
                if let v = whole("early_exit_bands") { s.earlyExitBands = v }
            }
        }
        if ["resolution", "metric", "keep", "signal_mask"].contains(where: { a[$0] != nil }) {
            session.editDictionarySettings { s in
                if let v = number("resolution") { s.resolution = v }
                if let v = a["metric"].flatMap(DictionaryIndexing.Metric.init(rawValue:)) { s.metric = v }
                if let v = whole("keep") { s.keep = v }
                if let v = a["signal_mask"].flatMap(DictionaryIndexingSettings.SignalMask.init(rawValue:)) { s.signalMask = v }
            }
        }
        if let v = flag("refine") { session.setRefinesAfterIndexing(v) }
        if ["refine_target", "trust_angle", "trust_pc"].contains(where: { a[$0] != nil }) {
            session.editRefineSettings { s in
                if let v = a["refine_target"].flatMap(IndexingRefineSettings.Target.init(rawValue:)) { s.target = v }
                if let v = number("trust_angle") { s.trustAngle = v }
                if let v = number("trust_pc") { s.trustPC = v }
            }
        }
        return nil
    }

    /// `set_indexing_phase`: add a preset, then change the named phase (the added one when no name is given), as the Phases rows do.
    static func applyPhase(_ a: [String: String], to session: IndexingSession) -> AgentToolOutput? {
        let names = { session.phases.map(\.name).joined(separator: ", ") }
        var name = a["phase"]
        if let preset = a["add"] {
            guard let phase = IndexingPhase.presets.first(where: { $0.name == preset }) else {
                return .refusal(status: 400, message: "\(preset) is not a built-in phase.")
            }
            session.addPhase(phase)
            if name == nil { name = session.phases.last?.name }
        }
        let changes = ["on", "reflectors", "master", "remove"].contains { a[$0] != nil }
        guard changes else {
            return a["add"] == nil ? .refusal(status: 400, message: "Give add, or phase with on, reflectors, master or remove.") : nil
        }
        guard let name, let phase = session.phases.first(where: { $0.name == name }) else {
            return .refusal(status: 404, message: "No phase is named \(a["phase"] ?? "so"); the list holds "
                + (session.phases.isEmpty ? "none" : names()) + ".")
        }
        if let word = a["reflectors"], let reflectors = IndexingPhase.Reflectors(rawValue: word) {
            guard reflectors.fits(spaceGroup: phase.spaceGroup) else {
                return .refusal(status: 409, message: "The HCP list takes a hexagonal space group (168 to 194); \(name) is \(phase.spaceGroup).")
            }
        }
        if let file = a["master"] {
            guard let master = session.masterPatterns.first(where: { $0.fileName == file }) else {
                return .refusal(status: 404, message: "No master pattern named \(file) is open; open ones: "
                    + (session.masterPatterns.isEmpty ? "none (the person opens one with Open Master Pattern…)"
                        : session.masterPatterns.map(\.fileName).joined(separator: ", ")) + ".")
            }
            session.selectMasterPattern(master.id, forPhase: name)
        }
        if let word = a["reflectors"], let reflectors = IndexingPhase.Reflectors(rawValue: word) { session.setReflectors(reflectors, named: name) }
        if let on = a["on"] { session.setPhase(named: name, isOn: on == "true") }
        if a["remove"] == "true" { session.removePhase(named: name) }
        return nil
    }

    // MARK: Pictures

    static func indexingPicture(_ appState: AppState, which: String, scale: Int) -> AgentToolOutput {
        let session = appState.indexing
        guard let document = session.patterns.document else { return noIndexing }
        let dataset = document.dataset
        let side = pictureSide * scale
        do {
            let png: Data?
            switch which {
            case "pattern":
                guard let canvas = session.patternPresentation.canvas, let position = session.patternPosition else {
                    return .refusal(status: 404, message: session.patternFailure ?? "No pattern is on screen yet; wait until get_indexing says pattern_shown_at.")
                }
                png = try PatternsRoomState.patternPNG(canvas: canvas, presentation: session.patternPresentation, dataset: dataset,
                                                       fileName: document.fileName, position: position)
            case "best_match":
                guard session.result?.method == .dictionary else {
                    return .refusal(status: 404, message: "The best match is a Dictionary run's; the run on screen is not one.")
                }
                guard let canvas = session.bestMatchPresentation.canvas, let position = session.bestMatchPosition else {
                    return .refusal(status: 404, message: session.bestMatchFailure ?? "No best match is on screen yet: pick an indexed point.")
                }
                png = try PatternsRoomState.patternPNG(canvas: canvas, presentation: session.bestMatchPresentation, dataset: dataset,
                                                       fileName: document.fileName, position: position)
            default:
                if session.showsScalarMap {
                    guard let canvas = session.mapPresentation.canvas else {
                        return .refusal(status: 404, message: "The map has not landed yet; ask again in a moment.")
                    }
                    png = try PatternsRoomState.mapPNG(canvas: canvas, presentation: session.mapPresentation, dataset: dataset,
                                                       fileName: document.fileName, map: "indexed \(session.layer.title)")
                } else {
                    let points = dataset.scanRows * dataset.scanColumns
                    guard let rgba = session.mapRGBA, rgba.count == points * 4 else {
                        return .refusal(status: 404, message: "The map has not landed yet; ask again in a moment.")
                    }
                    png = PatternsRoomState.mixPNG(rgba: rgba, width: dataset.scanColumns, height: dataset.scanRows, fileName: document.fileName)
                }
            }
            guard let png else { return .refusal(status: 500, message: "The picture could not be encoded.") }
            return .png(enlarged(png, toAbout: min(side, 512 * scale)) ?? smaller(png, side: side) ?? png)
        } catch {
            return .refusal(status: 500, message: "The picture could not be drawn: \(error.localizedDescription)")
        }
    }
}
