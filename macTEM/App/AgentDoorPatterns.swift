//
//  AgentDoorPatterns.swift
//  Role: the agent door's tools for the toolbar verb and the Patterns room (#558). `run_room` and `stop_run` press what ⌘R and ⌘. press
//        (`RoomPrimaryAction`): Quantify, Run, Process, Index or Segment, and Stop. The Patterns room's tools read the room
//        (`get_patterns`), draw its two panes as its Export section does (`get_patterns_picture`), pick a scan position as a click on the
//        map does, and set the Virtual images and Processing sections through the session calls their controls make (`EBSDSession`).
//        Every acting tool leaves an Output line that starts "An agent", and says so when a change moved a setting it was not given.
//
//        ONE SOURCE PER FACT: the pictures are `PatternsRoomState.mapPNG`, `.patternPNG` and `.mixPNG`, the export's own encoders, from the
//        panes' own canvases and display; a small one is enlarged by a whole factor with no smoothing, so each scan point or detector pixel
//        stays a square. The verb's refusal is the toolbar button's own help.
//

import CoreGraphics
import Foundation
import ImageIO
import ShellAgentDoor
import ShellLayout
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    // MARK: The toolbar verb

    static let verbTools: [AgentTool] = [
        AgentTool(name: "run_room", title: "Run the room's verb",
                  summary: "Presses the shown room's toolbar verb, as ⌘R does: Quantify (EDS), Run (EELS), Process (Patterns), Index "
                      + "(Indexing, and Diffraction's Index part), Calibrate and Measure (Diffraction's Calibrate and Thickness parts), "
                      + "Segment (Maps), Simulate (a STEM or frozen-phonon HRTEM image, a CBED pattern of a Simulation document in the "
                      + "Simulate part; a Simulation document itself, Tilt Plan and Powder have none). Refused with the button's own words while it is disabled, and while a run is going. "
                      + "It answers at once; the room's get tool says busy until the run ends.",
                  input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let room = appState.navigation.workspaceArea
            guard let action = RoomPrimaryAction.current(appState), let title = action.title else {
                return .refusal(status: 409, message: "The \(room.title) room has nothing to run now: it has no verb, or no file is open in it.")
            }
            if action.isRunning {
                return .refusal(status: 409, message: "\(action.operationName ?? title) is running; wait until it ends, or stop it with stop_run.")
            }
            guard action.isEnabled else { return .refusal(status: 409, message: action.help) }
            action.run()
            appState.statusText = "An agent pressed \(title) in the \(room.title) room."
            return .json(["started": title, "room": room.rawValue])
        },
        AgentTool(name: "stop_run", title: "Stop",
                  summary: "Stops what runs, as ⌘. does: the shown room's run or open, or else a run left going in another room that the "
                      + "toolbar shows. A stopped run keeps what it finished (rows indexed, the last complete processing).",
                  input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard RoomPrimaryAction.canStop(appState) else { return .refusal(status: 409, message: "Nothing is running that Stop ends.") }
            let target = RoomPrimaryAction.stopTarget(appState)
            RoomPrimaryAction.stopActive(appState)
            appState.statusText = "An agent stopped the \(target.title) room's run."
            return .json(["stopped": target.rawValue])
        },
    ]

    // MARK: The Patterns room

    static let patternsTools: [AgentTool] = [
        AgentTool(name: "get_patterns", title: "Patterns room",
                  summary: "What the Patterns room holds: the scan and pattern size, the file's calibration, the picked position and the "
                      + "pattern shown, the map and the virtual-image grid, the colour mix, every processing setting (in set_pattern_processing's "
                      + "names) with each stage's state (not_run, current, stale), why Process is refused, NLPAR's λ, and what is running.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return patterns(appState)
        },
        AgentTool(name: "get_patterns_picture", title: "Patterns room picture",
                  summary: "One of the Patterns room's panes as its Export section draws it: which map (the scan map on screen: mean, BSE, "
                      + "a tile, the colour mix or a quality map, one pixel per scan point) or pattern (the pattern on screen, raw or "
                      + "processed, one pixel per detector pixel), in the pane's colormap and contrast. A small picture is enlarged by a "
                      + "whole factor without smoothing.",
                  input: .windowPicture,
                  parameters: [AgentParameter("which", .choice(["map", "pattern"]), summary: "The pane to draw.", required: true)]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return patternsPicture(appState, which: call.arguments["which"] ?? "", scale: call.scale)
        },
        said(AgentTool(name: "select_scan_position", title: "Scan position",
                       summary: "Picks a scan position, as a click on the map of the Patterns, Indexing or Maps room does: the marker "
                           + "moves there (the rooms share it while the map is of the pattern scan) and the pattern pane shows its pattern, "
                           + "in the Indexing room as it is indexed, with its bands and best match; in the Maps room the grain under it is "
                           + "selected. The room's get tool answers. x is the column, y the row, from 0 at the top left.",
                       input: .window,
                       parameters: [AgentParameter("x", .integer(0...1_000_000), summary: "The column, from 0.", required: true),
                                    AgentParameter("y", .integer(0...1_000_000), summary: "The row, from 0.", required: true)],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let x = call.arguments["x"].flatMap(Int.init) ?? -1, y = call.arguments["y"].flatMap(Int.init) ?? -1
            let isMaps = appState.navigation.workspaceArea == .maps
            let shape: (rows: Int, columns: Int)
            if isMaps {
                guard appState.maps.hasMap else { return .refusal(status: 404, message: "No orientation map is open.") }
                shape = appState.maps.gridShape
            } else {
                guard let dataset = appState.ebsd.dataset else { return noPatterns }
                shape = (rows: dataset.scanRows, columns: dataset.scanColumns)
            }
            let rows = shape.rows, columns = shape.columns
            guard (0..<columns).contains(x), (0..<rows).contains(y) else {
                return .refusal(status: 400, message: "The \(isMaps ? "map" : "scan") is \(columns) columns by \(rows) rows: x from 0 to "
                    + "\(columns - 1), y from 0 to \(rows - 1).")
            }
            let position = EBSDPosition(row: y, column: x)
            switch appState.navigation.workspaceArea {
            case .maps:
                appState.maps.pin(position)
                appState.followMapsPin()
                return maps(appState)
            case .indexing:
                appState.indexing.pin(position)
                return indexing(appState)
            default:
                appState.ebsd.pin(position)
                return patterns(appState)
            }
        }),
        AgentTool(name: "set_patterns", title: "Patterns room view",
                  summary: "The Virtual images section and the pattern's Raw/Processed switch; only what is given changes. grid cuts the "
                      + "detector into 1, 3, 5 or 7 tiles a side (the pass runs again, and the tiles, the colour mix and a tile map are the "
                      + "new grid's). map: mean, bse, image_quality, dot_product (their pass runs the first time), tile (with tile, e.g. "
                      + "\"r2 c1\") or mix. mix_red, mix_green, mix_blue: a tile label or none; with all three the map shows the colour mix. "
                      + "display raw or processed (the pattern through the processing settings; NLPAR and averaging show after Process). "
                      + "simulation and its settings: the Simulation section's Kikuchi overlay (the settings are the Indexing room's too).",
                  input: .window,
                  parameters: [
                      AgentParameter("grid", .choice(["1", "3", "5", "7"]), summary: "Tiles per side of the detector grid."),
                      AgentParameter("map", .choice(["mean", "bse", "image_quality", "dot_product", "tile", "mix"]), summary: "What the scan map shows."),
                      AgentParameter("tile", .text, summary: "With map tile: the tile, e.g. \"r2 c1\" (row, column from 0)."),
                      AgentParameter("mix_red", .text, summary: "The colour mix's red tile, or none."),
                      AgentParameter("mix_green", .text, summary: "The colour mix's green tile, or none."),
                      AgentParameter("mix_blue", .text, summary: "The colour mix's blue tile, or none."),
                      AgentParameter("show_tiles", .boolean, summary: "The pane with every tile's image under the map."),
                      AgentParameter("display", .choice(["raw", "processed"]), summary: "The pattern as stored or through the processing."),
                      AgentParameter("simulation", .choice(["off", "geometrical", "kinematical"]),
                                     summary: "The Simulation section's overlay of the orientation the file stores at the shown point."),
                      AgentParameter("simulation_min_d", .number(0.3...10), summary: "The smallest interplanar spacing drawn, Å."),
                      AgentParameter("simulation_band_width", .boolean, summary: "Draw the band edges (needs the file's beam energy)."),
                      AgentParameter("simulation_zone_axes", .boolean, summary: "Draw the zone axes."),
                      AgentParameter("simulation_labels", .boolean, summary: "Label the bands and zone axes."),
                      AgentParameter("simulation_blend", .number(0...1), summary: "The kinematical simulation's opacity over the pattern."),
                  ],
                  acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return setPatterns(appState, call.arguments)
        },
        said(AgentTool(name: "set_pattern_processing", title: "Pattern processing",
                       summary: "The Processing sections' settings, kikuchipy's methods; only what is given changes, and the pattern pane follows "
                           + "when it shows the processed pattern. run_room then processes the whole scan (Process). Stages in order: static "
                           + "background, dynamic background, intensity, FFT filter, size (binning), average neighbours, NLPAR. A stage set "
                           + "out of reach (a dynamic width larger than the pattern, a scan too small for NLPAR) is refused by the room: "
                           + "get_patterns says why in processing_refusal.",
                       input: .window, parameters: processingParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.ebsd.dataset != nil else { return noPatterns }
            if let refusal = applyProcessing(call.arguments, to: appState.ebsd) { return refusal }
            return patterns(appState)
        }),
    ]

    private static let noPatterns = AgentToolOutput.refusal(
        status: 404, message: "No EBSD pattern dataset is open; open one first (open_demo with demo ebsd opens kikuchipy's nickel scan).")

    /// The Processing sections' inputs, named as `get_patterns` names the settings.
    static let processingParameters: [AgentParameter] = [
        AgentParameter("static_on", .boolean, summary: "Remove the static background."),
        AgentParameter("static_source", .choice(PatternPipeline.BackgroundSource.allCases.map(\.rawValue)),
                       summary: "file: the file's background; mean: the scan's mean pattern."),
        AgentParameter("static_operation", .choice(PatternProcessing.Operation.allCases.map(\.rawValue)), summary: "Subtract or divide."),
        AgentParameter("static_scale", .boolean, summary: "Scale the background to each pattern's range first (scale_bg)."),
        AgentParameter("dynamic_on", .boolean, summary: "Remove the dynamic background."),
        AgentParameter("dynamic_filter", .choice(PatternProcessing.FilterDomain.allCases.map(\.rawValue)), summary: "The Gaussian blur's domain."),
        AgentParameter("dynamic_operation", .choice(PatternProcessing.Operation.allCases.map(\.rawValue)), summary: "Subtract or divide."),
        AgentParameter("dynamic_std", .number(0.01...10_000), summary: "The blur's standard deviation in pixels (default: width / 8)."),
        AgentParameter("dynamic_truncate", .number(0.1...100), summary: "Where the blur is cut, in standard deviations (default 4)."),
        AgentParameter("intensity_mode", .choice(PatternPipeline.IntensityMode.allCases.map(\.rawValue)),
                       summary: "none, rescale (rescale_intensity) or normalize (normalize_intensity)."),
        AgentParameter("intensity_percentiles", .boolean, summary: "Rescale: clip to the percentiles first."),
        AgentParameter("intensity_low", .number(0...100), summary: "Rescale: the low percentile."),
        AgentParameter("intensity_high", .number(0...100), summary: "Rescale: the high percentile."),
        AgentParameter("intensity_num_std", .number(0.01...100), summary: "Normalize: num_std."),
        AgentParameter("intensity_sqrt", .boolean, summary: "Normalize: divide_by_square_root."),
        AgentParameter("equalize", .boolean, summary: "Adaptive histogram equalization."),
        AgentParameter("equalize_kernel", .integer(1...10_000), summary: "Its kernel size in pixels (default: kikuchipy's)."),
        AgentParameter("clip_limit", .number(0...1), summary: "Its clip limit (0: none)."),
        AgentParameter("fft_on", .boolean, summary: "The FFT filter."),
        AgentParameter("fft_pass", .choice(PatternPipeline.FFTPass.allCases.map(\.rawValue)), summary: "low, high or band pass."),
        AgentParameter("fft_low_cutoff", .number(0...10_000), summary: "The lowpass cutoff."),
        AgentParameter("fft_low_width", .number(0...10_000), summary: "The lowpass cutoff width."),
        AgentParameter("fft_high_cutoff", .number(0...10_000), summary: "The highpass cutoff."),
        AgentParameter("fft_high_width", .number(0...10_000), summary: "The highpass cutoff width."),
        AgentParameter("binning", .choice(PatternPipeline.binnings.map(String.init)), summary: "Bin the patterns by 1, 2, 4 or 8."),
        AgentParameter("average_on", .boolean, summary: "Average neighbour patterns."),
        AgentParameter("average_window", .choice(PatternPipeline.AveragingWindow.allCases.map(\.rawValue)), summary: "The averaging window."),
        AgentParameter("nlpar_on", .boolean, summary: "Non-local pattern averaging (λ chosen from the scan's noise)."),
        AgentParameter("nlpar_radius", .integer(1...100), summary: "NLPAR's search radius."),
    ]

    // MARK: Answers

    /// Numbers in the answers are written with a point, whatever the Mac's Region.
    private static let point = Locale(identifier: "en_US_POSIX")

    static func patterns(_ appState: AppState) -> AgentToolOutput {
        let session = appState.ebsd
        guard let document = session.document else { return noPatterns }
        let dataset = document.dataset
        let position = { (p: EBSDPosition) -> [String: Any] in ["x": p.column, "y": p.row] }
        return .json([
            "file_name": document.fileName,
            "scan": ["columns": dataset.scanColumns, "rows": dataset.scanRows, "step_x": AgentJSON.number(dataset.stepX),
                     "step_y": AgentJSON.number(dataset.stepY), "unit": dataset.scanUnit] as [String: Any],
            "pattern_size": ["columns": dataset.patternColumns, "rows": dataset.patternRows],
            "calibration": EBSDBrowsing.calibrationRows(dataset, locale: point).map { ["label": $0.label, "value": $0.value] },
            "position": position(session.pinned),
            "pattern_shown_at": AgentJSON.orNull(session.patternPosition.map(position)),
            "display": session.patternDisplay.rawValue,
            "grid": session.virtualGrid.rows,
            "map": mapWord(session.mapChoice),
            "maps_landed": session.virtualImages != nil,
            "mix": session.mixTiles.map { AgentJSON.orNull($0?.label) },
            "show_tiles": session.showsTiles,
            "processing": processingSettings(session.pipeline),
            "stages": PatternPipeline.Stage.allCases.map { stage -> [String: Any] in
                ["stage": stage.title, "on": session.pipeline.isActive(stage), "state": stateWord(session.stageState(stage))]
            },
            "first_stale_stage": AgentJSON.orNull(session.firstStaleStage?.title),
            "processing_refusal": AgentJSON.orNull(session.processingRefusal?.sentence),
            "preview_failure": AgentJSON.orNull(session.previewFailure),
            "scan_processed": session.processed != nil,
            "nlpar_lambda": AgentJSON.number(session.nlparLambda),
            "busy": session.isBusy,
            "running": ["opening": session.isOpening, "map_pass": session.isMapping, "quality_pass": session.isQualityMapping,
                        "processing": session.isProcessing, "mean_pattern": session.isComputingMean],
            "progress": AgentJSON.number(RoomProgress.fraction(room: .patterns, appState: appState)),
            "map_failure": AgentJSON.orNull(session.mapFailure),
            "simulation": simulation(session),
        ])
    }

    /// The Simulation section: the overlay's mode and settings, and what it draws on the pattern shown or why it draws nothing.
    static func simulation(_ session: EBSDSession) -> [String: Any] {
        let s = session.overlaySettings
        var drawn: Any = NSNull(), absence: Any = NSNull()
        switch session.overlay {
        case .success(let p)?: drawn = "\(p.phase): \(p.drawnWords)"
        case .failure(let a)?: absence = a.sentence
        case nil: break
        }
        return [
            "mode": session.overlayOn ? (s.kinematical ? "kinematical" : "geometrical") : "off",
            "min_d_angstroms": AgentJSON.number(s.minDSpacing), "band_width": s.bandWidth, "zone_axes": s.zoneAxes, "labels": s.labels,
            "blend": AgentJSON.number(s.blend), "can_overlay": session.canOverlay, "can_draw_band_width": session.canDrawBandWidth,
            "drawn": drawn, "absence": absence,
        ]
    }

    /// The Simulation section's settings in `set_patterns`; nil when none was given. Checked before anything changes.
    static func simulationSettings(_ session: EBSDSession, _ a: [String: String]) -> SimulationAsk {
        let keys = ["simulation", "simulation_min_d", "simulation_band_width", "simulation_zone_axes", "simulation_labels", "simulation_blend"]
        guard keys.contains(where: { a[$0] != nil }) else { return .none }
        var s = session.overlaySettings
        var on = session.overlayOn
        if let mode = a["simulation"] {
            guard mode == "off" || session.canOverlay else {
                return .refused("This dataset carries no orientations; the overlay draws the solution the file stores at each point.")
            }
            on = mode != "off"
            s.kinematical = mode == "kinematical"
        }
        if let v = a["simulation_min_d"].flatMap(Double.init) { s.minDSpacing = min(max(v, 0.3), 10) }
        if let v = a["simulation_band_width"] {
            guard v != "true" || session.canDrawBandWidth else {
                return .refused("The file states no beam energy, so the band edges' Bragg angles are unknown.")
            }
            s.bandWidth = v == "true"
        }
        if let v = a["simulation_zone_axes"] { s.zoneAxes = v == "true" }
        if let v = a["simulation_labels"] { s.labels = v == "true" }
        if let v = a["simulation_blend"].flatMap(Double.init) { s.blend = min(max(v, 0), 1) }
        return .set(on: on, settings: s)
    }

    /// What `set_patterns` asked of the Simulation section.
    enum SimulationAsk {
        case none
        case set(on: Bool, settings: KikuchiOverlay.Settings)
        case refused(String)
    }

    /// The map's word in `set_patterns`' terms: "mean", "tile r2 c1", ...
    static func mapWord(_ choice: EBSDSession.MapChoice) -> String {
        switch choice {
        case .mean: "mean"
        case .bse: "bse"
        case .tile(let tile): "tile \(tile.label)"
        case .mix: "mix"
        case .imageQuality: "image_quality"
        case .dotProduct: "dot_product"
        }
    }

    static func stateWord(_ state: EELSStageState) -> String {
        switch state {
        case .notRun: "not_run"
        case .current: "current"
        case .stale: "stale"
        }
    }

    /// Every processing setting under `set_pattern_processing`'s name for it.
    static func processingSettings(_ p: PatternPipeline) -> [String: Any] {
        [
            "static_on": p.staticStage.isOn, "static_source": p.staticStage.source.rawValue,
            "static_operation": p.staticStage.operation.rawValue, "static_scale": p.staticStage.scaleBackground,
            "dynamic_on": p.dynamicStage.isOn, "dynamic_filter": p.dynamicStage.domain.rawValue,
            "dynamic_operation": p.dynamicStage.operation.rawValue, "dynamic_std": AgentJSON.number(p.dynamicStage.std),
            "dynamic_truncate": AgentJSON.number(p.dynamicStage.truncate),
            "intensity_mode": p.intensity.mode.rawValue, "intensity_percentiles": p.intensity.usesPercentiles,
            "intensity_low": AgentJSON.number(p.intensity.lowPercentile), "intensity_high": AgentJSON.number(p.intensity.highPercentile),
            "intensity_num_std": AgentJSON.number(p.intensity.numStd), "intensity_sqrt": p.intensity.divideBySquareRoot,
            "equalize": p.intensity.equalize, "equalize_kernel": AgentJSON.orNull(p.intensity.equalizeKernel),
            "clip_limit": AgentJSON.number(p.intensity.clipLimit),
            "fft_on": p.fftFilter.isOn, "fft_pass": p.fftFilter.pass.rawValue,
            "fft_low_cutoff": AgentJSON.number(p.fftFilter.lowCutoff), "fft_low_width": AgentJSON.number(p.fftFilter.lowWidth),
            "fft_high_cutoff": AgentJSON.number(p.fftFilter.highCutoff), "fft_high_width": AgentJSON.number(p.fftFilter.highWidth),
            "binning": p.binning,
            "average_on": p.averaging.isOn, "average_window": p.averaging.window.rawValue,
            "nlpar_on": p.nlpar.isOn, "nlpar_radius": p.nlpar.searchRadius,
        ]
    }

    /// Sets the given processing settings in one edit, as the rows of the Processing sections do; nil when done.
    static func applyProcessing(_ a: [String: String], to session: EBSDSession) -> AgentToolOutput? {
        let flag = { (key: String) -> Bool? in a[key].map { $0 == "true" } }
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        let whole = { (key: String) -> Int? in a[key].flatMap(Int.init) }
        if let low = number("intensity_low") ?? (a["intensity_high"] != nil ? session.pipeline.intensity.lowPercentile : nil),
           let high = number("intensity_high") ?? (a["intensity_low"] != nil ? session.pipeline.intensity.highPercentile : nil), low >= high {
            return .refusal(status: 400, message: "The low percentile must be below the high one (\(low) and \(high)).")
        }
        session.editPipeline { p in
            if let v = flag("static_on") { p.staticStage.isOn = v }
            if let v = a["static_source"].flatMap(PatternPipeline.BackgroundSource.init(rawValue:)) { p.staticStage.source = v }
            if let v = a["static_operation"].flatMap(PatternProcessing.Operation.init(rawValue:)) { p.staticStage.operation = v }
            if let v = flag("static_scale") { p.staticStage.scaleBackground = v }
            if let v = flag("dynamic_on") { p.dynamicStage.isOn = v }
            if let v = a["dynamic_filter"].flatMap(PatternProcessing.FilterDomain.init(rawValue:)) { p.dynamicStage.domain = v }
            if let v = a["dynamic_operation"].flatMap(PatternProcessing.Operation.init(rawValue:)) { p.dynamicStage.operation = v }
            if let v = number("dynamic_std") { p.dynamicStage.std = v }
            if let v = number("dynamic_truncate") { p.dynamicStage.truncate = v }
            if let v = a["intensity_mode"].flatMap(PatternPipeline.IntensityMode.init(rawValue:)) { p.intensity.mode = v }
            if let v = flag("intensity_percentiles") { p.intensity.usesPercentiles = v }
            if let v = number("intensity_low") { p.intensity.lowPercentile = v }
            if let v = number("intensity_high") { p.intensity.highPercentile = v }
            if let v = number("intensity_num_std") { p.intensity.numStd = v }
            if let v = flag("intensity_sqrt") { p.intensity.divideBySquareRoot = v }
            if let v = flag("equalize") { p.intensity.equalize = v }
            if let v = whole("equalize_kernel") { p.intensity.equalizeKernel = v }
            if let v = number("clip_limit") { p.intensity.clipLimit = v }
            if let v = flag("fft_on") { p.fftFilter.isOn = v }
            if let v = a["fft_pass"].flatMap(PatternPipeline.FFTPass.init(rawValue:)) { p.fftFilter.pass = v }
            if let v = number("fft_low_cutoff") { p.fftFilter.lowCutoff = v }
            if let v = number("fft_low_width") { p.fftFilter.lowWidth = v }
            if let v = number("fft_high_cutoff") { p.fftFilter.highCutoff = v }
            if let v = number("fft_high_width") { p.fftFilter.highWidth = v }
            if let v = whole("binning") { p.binning = v }
            if let v = flag("average_on") { p.averaging.isOn = v }
            if let v = a["average_window"].flatMap(PatternPipeline.AveragingWindow.init(rawValue:)) { p.averaging.window = v }
            if let v = flag("nlpar_on") { p.nlpar.isOn = v }
            if let v = whole("nlpar_radius") { p.nlpar.searchRadius = v }
        }
        return nil
    }

    /// `set_patterns`: the Virtual images section and the Raw/Processed switch, in that order, through the session calls their controls make.
    static func setPatterns(_ appState: AppState, _ a: [String: String]) -> AgentToolOutput {
        let session = appState.ebsd
        guard let dataset = session.dataset else { return noPatterns }
        let mapBefore = session.mapChoice, mixBefore = session.mixTiles
        let overlay = simulationSettings(session, a)
        if case .refused(let message) = overlay { return .refusal(status: 409, message: message) }
        // Every check first, against the grid the call asks for, so a refused call changes nothing (#927).
        var grid = session.virtualGrid
        if let n = a["grid"].flatMap(Int.init) {
            guard n <= min(dataset.patternRows, dataset.patternColumns) else {
                return .refusal(status: 409, message: "A \(n) × \(n) grid does not fit \(dataset.patternColumns) × \(dataset.patternRows) px patterns.")
            }
            grid = VirtualBSEGrid(n)
        }
        // A new grid starts a new pass over the scan and drops the colour mix, as `setVirtualGrid` does.
        let newGrid = grid != session.virtualGrid
        let landed = !newGrid && session.virtualImages != nil
        let waiting = newGrid
            ? "A new grid starts a new pass over the scan: set grid alone, then ask again when get_patterns says maps_landed."
            : "Waiting for the pass over the scan; ask again when get_patterns says maps_landed."
        let tile = { (label: String) -> VirtualBSETile? in grid.tiles.first { $0.label == label } }
        let tiles = grid.tiles.map(\.label).joined(separator: ", ")
        var picks: [(tile: VirtualBSETile?, channel: Int)] = []
        var mixTiles: [VirtualBSETile?] = newGrid ? [nil, nil, nil] : session.mixTiles
        var hasMix = !newGrid && session.hasMix
        for (channel, key) in ["mix_red", "mix_green", "mix_blue"].enumerated() {
            guard let label = a[key] else { continue }
            if label != "none" {
                guard grid.tileCount > 1, let picked = tile(label) else {
                    return .refusal(status: 400, message: "\(key): \(label) is not a tile of the \(grid.rows) × \(grid.rows) grid"
                        + (grid.tileCount > 1 ? " (\(tiles))." : "; pick a grid of 3 or more first."))
                }
                guard landed else { return .refusal(status: 409, message: waiting) }
                mixTiles[channel] = picked
            } else {
                mixTiles[channel] = nil
            }
            picks.append((mixTiles[channel], channel))
            // As `setMixTile` leaves it: no mix while a channel has no tile; a full pick keeps the mix shown until the new one lands.
            if mixTiles.contains(where: { $0 == nil }) || !landed { hasMix = false }
        }
        var choice: EBSDSession.MapChoice?
        if let word = a["map"] {
            switch word {
            case "mean": choice = .mean
            case "bse": choice = .bse
            case "image_quality": choice = .imageQuality
            case "dot_product": choice = .dotProduct
            case "mix":
                guard hasMix else { return .refusal(status: 409, message: "No colour mix yet: pick mix_red, mix_green and mix_blue first.") }
                choice = .mix
            default:
                guard let label = a["tile"], grid.tileCount > 1, let picked = tile(label) else {
                    return .refusal(status: 400, message: "map tile needs tile, one of the grid's tiles"
                        + (grid.tileCount > 1 ? ": \(tiles)." : "; pick a grid of 3 or more first."))
                }
                choice = .tile(picked)
            }
            guard landed || choice == .mean else { return .refusal(status: 409, message: waiting) }
        }

        if newGrid { session.setVirtualGrid(grid) }
        for pick in picks { session.setMixTile(pick.tile, channel: pick.channel) }
        if let choice { session.showMap(choice) }
        if let show = a["show_tiles"] { session.showsTiles = show == "true" }
        if let display = a["display"].flatMap(EBSDSession.PatternDisplay.init(rawValue:)) { session.setPatternDisplay(display) }
        if case .set(let on, let settings) = overlay {
            session.setOverlaySettings(settings)
            session.setOverlayOn(on)
        }

        // What moved without being asked: a new grid drops the colour mix and a tile map.
        var moved: [String] = []
        if a["map"] == nil, session.mapChoice != mapBefore { moved.append("map \(mapWord(mapBefore)) → \(mapWord(session.mapChoice))") }
        if a["mix_red"] == nil, a["mix_green"] == nil, a["mix_blue"] == nil, session.mixTiles != mixBefore { moved.append("colour mix cleared") }
        var line = agentLine("Patterns room view", a), short = agentLine("Patterns room view", [:])
        if !moved.isEmpty { line += " It also changed: " + moved.joined(separator: "; ") + "."; short += " It also changed: " + moved.joined(separator: "; ") + "." }
        appState.setAgentStatus(short, record: line)
        guard case .json(var answer) = patterns(appState) else { return patterns(appState) }
        answer["also_changed"] = moved
        return .json(answer)
    }

    static func patternsPicture(_ appState: AppState, which: String, scale: Int) -> AgentToolOutput {
        let session = appState.ebsd
        guard let document = session.document else { return noPatterns }
        let side = pictureSide * scale
        do {
            let png: Data?
            if which == "pattern" {
                guard let canvas = session.patternPresentation.canvas, let position = session.patternPosition else {
                    return .refusal(status: 404, message: "No pattern is on screen yet; wait until get_patterns says pattern_shown_at.")
                }
                png = try PatternsRoomState.patternPNG(canvas: canvas, presentation: session.patternPresentation, dataset: document.dataset,
                                                       fileName: document.fileName, position: position)
            } else {
                guard let canvas = session.mapPresentation.canvas else {
                    return .refusal(status: 404, message: "The map has not landed yet; wait until get_patterns says not busy.")
                }
                if session.mapChoice == .imageQuality || session.mapChoice == .dotProduct, session.chosenImage == nil {
                    return .refusal(status: 404, message: "The quality maps have not landed yet; wait until get_patterns says not busy.")
                }
                if session.mapChoice == .mix, let rgba = session.mixRGBA {
                    png = PatternsRoomState.mixPNG(rgba: rgba, width: canvas.width, height: canvas.height, fileName: document.fileName)
                } else {
                    png = try PatternsRoomState.mapPNG(canvas: canvas, presentation: session.mapPresentation, dataset: document.dataset,
                                                       fileName: document.fileName, map: PatternsRoomState.mapName(session.mapChoice))
                }
            }
            guard let png else { return .refusal(status: 500, message: "The picture could not be encoded.") }
            return .png(enlarged(png, toAbout: min(side, 512 * scale)) ?? smaller(png, side: side) ?? png)
        } catch {
            return .refusal(status: 500, message: "The picture could not be drawn: \(error.localizedDescription)")
        }
    }

    /// The PNG enlarged by the largest whole factor that keeps its longest side at most `side`, each pixel a square of pixels (no
    /// smoothing); nil when it is already that large or ImageIO cannot read it. A 75 × 55 scan map reads as a picture, not a stamp.
    nonisolated static func enlarged(_ png: Data, toAbout side: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let factor = side / longest
        guard factor >= 2 else { return nil }
        let width = image.width * factor, height = image.height * factor
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let big = context.makeImage() else { return nil }
        return AgentJSON.png(big)
    }
}
