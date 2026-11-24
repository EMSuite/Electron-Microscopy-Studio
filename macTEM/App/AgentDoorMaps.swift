//
//  AgentDoorMaps.swift
//  Role: the agent door's tools for the Maps room (#558). `get_maps` reads the room: the map and its source, the phases, the layer, the
//        picked point's orientation and grain, the Misorientation and Grains settings with the segmentation's summary, Slip and Texture.
//        `get_grains` gives the grain table and a histogram as the room's tables and Histogram tab hold them; `get_maps_picture` draws
//        the map figure (with its key or legend) and the texture figure as the Export section does. `set_maps` sets the inspector's
//        sections and the bottom pane's tab, `select_grains` selects as the grain table does. Segment itself is `run_room`, the toolbar
//        verb, and a point is picked with `select_scan_position`, which follows the room shown.
//
//        ONE SOURCE PER FACT: the pictures are `MapsFigure.png` and `MapsFigure.texturePNG`, the Export section's own figures, from the
//        session's raster, keys, display and boundaries; the histograms are the session's (`OrientationMapSession.histogram`), the bins
//        the Histogram tab draws.
//

import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let mapsTools: [AgentTool] = [
        AgentTool(name: "get_maps", title: "Maps room",
                  summary: "What the Maps room holds: the map (file, format, grid, steps, points not indexed) and its source (a map file, "
                      + "the pattern file's own map, or the Indexing room's run, and whether that run is stale), the phases, the layer "
                      + "and the layers on offer, the picked point's phase, orientation, grain and KAM, the segmentation's settings and "
                      + "summary (grains, mean size, ASTM number), the selected grains, Slip and Texture, and what is running.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return maps(appState)
        },
        AgentTool(name: "get_grains", title: "Maps room grains",
                  summary: "After Segment: the grain table (number, phase, points, area, equivalent circle diameter, mean Bunge angles, "
                      + "GOS, neighbours, centroid, the largest Schmid factor once slip systems are set), first and count picking the "
                      + "rows (100 from the first by default, largest first when sort is size); and with histogram (kam, gos, grain_size) "
                      + "that distribution's bins as the Histogram tab draws them.",
                  input: .window,
                  parameters: [
                      AgentParameter("first", .integer(0...10_000_000), summary: "The first row, from 0."),
                      AgentParameter("count", .integer(1...1_000), summary: "How many rows (100 by default)."),
                      AgentParameter("sort", .choice(["number", "size"]), summary: "Grain order (number) or largest first (size)."),
                      AgentParameter("histogram", .choice(["kam", "gos", "grain_size"]), summary: "A distribution's bins as well."),
                  ]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return grains(appState, call.arguments)
        },
        AgentTool(name: "get_maps_picture", title: "Maps room picture",
                  summary: "which map: the map as Export's Map PNG… draws it, the layer on screen with its colour key, phase legend "
                      + "or colour bar, the scale bar and the boundaries when shown; which texture: the pole figures, the IPF density "
                      + "and the ODF sections of the texture shown, as Texture PNG… draws them.",
                  input: .windowPicture,
                  parameters: [AgentParameter("which", .choice(["map", "texture"]), summary: "The figure to draw.", required: true)]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return mapsPicture(appState, which: call.arguments["which"] ?? "", scale: call.scale)
        },
        said(AgentTool(name: "set_maps", title: "Maps room settings",
                       summary: "The Maps room's inspector and bottom pane; only what is given changes. source: a held result by its index "
                           + "in get_maps' sources. layer: an id from get_maps' layers (ipf-x, ipf-y, ipf-z, phase, property-<name>, and "
                           + "after Segment derived-kam, derived-gos, derived-grains, derived-gnd, derived-schmid). boundary_angle, "
                           + "minimum_size and kam_max are the next Segment's (DefDAP's), so the analysis shown reads stale until "
                           + "run_room. load and slip_systems (with slip_phase) set the Schmid factors' load axis and a phase's DefDAP "
                           + "slip-system file. texture_phase computes that phase's texture (answers at once; get_maps says computing). "
                           + "tab and histogram choose the bottom pane.",
                       input: .window, parameters: mapsParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.maps.hasMap else { return noMap }
            if let refusal = applyMaps(call.arguments, to: appState) { return refusal }
            return maps(appState)
        }),
        said(AgentTool(name: "select_grains", title: "Maps room grain selection",
                       summary: "Selects grains as the grain table does: one grain selects it and moves the picked point to its middle; "
                           + "several select them all (their outlines on the map, their orientations on the pole figures); none clears.",
                       input: .window,
                       parameters: [AgentParameter("grains", .text, summary: "Grain numbers, e.g. \"3\" or \"3, 7, 12\", or none.", required: true)],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let session = appState.maps
            guard session.hasMap else { return noMap }
            guard let analysis = session.analysis else {
                return .refusal(status: 409, message: "No grains yet: Segment the map first (run_room).")
            }
            let words = (call.arguments["grains"] ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            if words == ["none"] {
                session.selectGrains([])
                return maps(appState)
            }
            let numbers = words.compactMap(Int.init)
            guard !numbers.isEmpty, numbers.count == words.count else {
                return .refusal(status: 400, message: "grains takes grain numbers separated by commas, or none.")
            }
            let known = Set(analysis.table.map(\.id))
            if let unknown = numbers.first(where: { !known.contains($0) }) {
                return .refusal(status: 404, message: "There is no grain \(unknown); the map has grains 1 to \(analysis.table.count).")
            }
            session.selectGrains(Set(numbers))
            appState.followMapsPin()
            return maps(appState)
        }),
    ]

    private static let noMap = AgentToolOutput.refusal(
        status: 404, message: "No orientation map is open; open one first (open_demo with demo orientationMap opens orix's duplex steel map).")

    static let mapsParameters: [AgentParameter] = [
        AgentParameter("source", .integer(0...100), summary: "The held result to show, by its index in get_maps' sources."),
        AgentParameter("layer", .text, summary: "The layer's id, as get_maps lists it."),
        AgentParameter("boundary_angle", .number(0.1...90), summary: "Degrees between neighbours on different grains (Segment)."),
        AgentParameter("minimum_size", .integer(1...1_000_000), summary: "Grains of fewer points are left out (Segment)."),
        AgentParameter("kam_max", .number(0.1...90), summary: "KAM drops a neighbour more misoriented than this, degrees (Segment)."),
        AgentParameter("show_boundaries", .boolean, summary: "The grain and phase boundaries over the map."),
        AgentParameter("load", .choice(SampleDirection.allCases.map(\.rawValue)), summary: "The uniaxial load's sample axis."),
        AgentParameter("slip_phase", .integer(-1...1_000), summary: "With slip_systems: the phase id, as get_maps lists it."),
        AgentParameter("slip_systems", .choice(["none"] + SlipSystemFile.allCases.map(\.rawValue)), summary: "DefDAP's slip-system file, or none."),
        AgentParameter("show_slip_traces", .boolean, summary: "The selected grain's slip traces over the map."),
        AgentParameter("texture_phase", .integer(-1...1_000), summary: "Compute this phase's texture (its id)."),
        AgentParameter("tab", .choice(MapsBottomTab.allCases.map { agentWord($0) }), summary: "The bottom pane's tab."),
        AgentParameter("histogram", .choice(MapAnalysis.HistogramKind.allCases.map { agentWord($0) }), summary: "The Histogram tab's distribution."),
    ]

    /// "Pole figures" → "pole_figures", "Grain size" → "grain_size": a tab's or a histogram's title as the door spells it.
    static func agentWord(_ tab: MapsBottomTab) -> String { tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "_") }
    static func agentWord(_ kind: MapAnalysis.HistogramKind) -> String { kind.rawValue.lowercased().replacingOccurrences(of: " ", with: "_") }

    // MARK: Answers

    static func maps(_ appState: AppState) -> AgentToolOutput {
        let session = appState.maps
        guard let document = session.document else { return noMap }
        let map = document.map
        let pinned = session.pinned
        let degrees = { (radians: Double) -> Any in AgentJSON.number(radians * 180 / Double.pi) }
        var answer: [String: Any] = [
            "file_name": document.fileName,
            "format": document.format,
            "source": MapsRoomFormat.sourceWords(document.source),
            "sources": session.sources.enumerated().map { i, held -> [String: Any] in
                ["index": i, "title": MapsRoomFormat.sourceTitle(held), "shown": held.id == document.id]
            },
            "source_stale": AgentJSON.orNull(appState.mapsStaleness),
            "grid": ["rows": document.rows, "columns": document.columns, "step_x": AgentJSON.number(document.dx),
                     "step_y": AgentJSON.number(document.dy), "unit": map.scanUnit] as [String: Any],
            "points": document.size,
            "not_indexed": document.notIndexedCount,
            "phases": MapsRoomFormat.indexedPhases(map).map { entry -> [String: Any] in
                ["id": entry.id, "name": MapsRoomFormat.phaseName(entry.phase, id: entry.id),
                 "point_group": AgentJSON.orNull(entry.phase.pointGroupName), "space_group": AgentJSON.orNull(entry.phase.spaceGroup),
                 "points": document.phaseCounts[entry.id] ?? 0]
            },
            "layer": session.layer.id,
            "layers": session.layers.map(\.id),
            "position": ["x": pinned.column, "y": pinned.row],
            "segment": segmentAnswer(session),
            "show_boundaries": session.showsBoundaries,
            "slip": slipAnswer(session, map: map),
            "texture": textureAnswer(session),
            "tab": agentWord(appState.mapsRoom.bottomTab),
            "histogram": agentWord(appState.mapsRoom.histogramKind),
            "busy": session.isBusy,
            "running": ["opening": session.isOpening, "drawing": session.isDrawing, "segmenting": session.isSegmenting,
                        "texture": session.isTexturing],
        ]
        if let found = session.orientation(at: pinned) {
            var point: [String: Any] = [
                "phase": found.phase.name,
                "euler_degrees": [degrees(found.euler.x), degrees(found.euler.y), degrees(found.euler.z)],
            ]
            if let analysis = session.analysis {
                point["grain"] = AgentJSON.orNull(analysis.grain(atRow: pinned.row, column: pinned.column))
                let i = pinned.row * analysis.columns + pinned.column
                if analysis.grains.kam.indices.contains(i) { point["kam_degrees"] = degrees(analysis.grains.kam[i]) }
            }
            answer["picked_point"] = point
        } else {
            answer["picked_point"] = NSNull()
        }
        return .json(answer)
    }

    private static func segmentAnswer(_ session: OrientationMapSession) -> [String: Any] {
        let s = session.analysisSettings
        var segment: [String: Any] = [
            "boundary_angle": AgentJSON.number(s.boundaryDegrees), "minimum_size": s.minimumSize, "kam_max": AgentJSON.number(s.kamMaxDegrees),
            "can_segment": session.canSegment, "blocker": AgentJSON.orNull(session.segmentBlocker),
            "segmented": session.analysis != nil, "stale": session.analysisIsStale,
            "selected_grains": session.selectedRows.map { grainRow($0) },
        ]
        if let analysis = session.analysis {
            segment["grains"] = analysis.table.count
            segment["scan_unit"] = analysis.scanUnit
            segment["mean_diameter"] = AgentJSON.number(analysis.meanDiameter?.byNumber)
            segment["mean_diameter_by_area"] = AgentJSON.number(analysis.meanDiameter?.byArea)
            segment["mean_lineal_intercept"] = AgentJSON.number(analysis.meanLinealIntercept)
            segment["astm_grain_size_number"] = AgentJSON.number(analysis.astmGrainSizeNumber)
            segment["gnd_refusal"] = AgentJSON.orNull(analysis.gndRefusal)
        }
        return segment
    }

    private static func slipAnswer(_ session: OrientationMapSession, map: CrystalMap) -> [String: Any] {
        var slip: [String: Any] = [
            "load": session.loadDirection.rawValue,
            "show_slip_traces": session.showsSlipTraces,
            "phases": MapsRoomFormat.indexedPhases(map).map { entry -> [String: Any] in
                ["id": entry.id, "slip_systems": session.slipFiles[entry.id]?.rawValue ?? "none",
                 "choices": MapsRoomFormat.slipChoices(entry.phase).map(\.rawValue)]
            },
        ]
        if let row = session.selectedRow, let selected = session.selectedSlip {
            slip["selected_grain"] = row.id
            slip["planes"] = selected.planes.map { plane -> [String: Any] in
                ["plane": plane.label, "schmid": AgentJSON.number(plane.schmid),
                 "trace_degrees": AgentJSON.number(plane.traceAngle * 180 / Double.pi),
                 "inclination_degrees": AgentJSON.number(plane.inclination * 180 / Double.pi), "colour": plane.colour]
            }
        }
        return slip
    }

    private static func textureAnswer(_ session: OrientationMapSession) -> [String: Any] {
        var texture: [String: Any] = [
            "phase": AgentJSON.orNull(session.texturePhaseID),
            "phases": session.texturePhases.map { ["id": $0.id, "name": $0.phase.name] as [String: Any] },
            "computing": session.isTexturing, "stopped": session.textureStopped,
            "failure": AgentJSON.orNull(session.textureFailure),
        ]
        if let made = session.texture {
            let figures = made.poleFigures + (made.inversePoleFigure.map { [$0] } ?? []) + made.odfSections
            texture["landed"] = [
                "phase": made.phaseName, "points": made.points, "odf_points": made.odfPoints,
                "figures": figures.map { ["title": $0.title, "maximum_mrd": AgentJSON.number($0.maximum)] as [String: Any] },
            ] as [String: Any]
        }
        return texture
    }

    private static func grainRow(_ row: GrainRow) -> [String: Any] {
        ["grain": row.id, "phase": row.phaseName, "points": row.points, "area": AgentJSON.number(row.area),
         "diameter": AgentJSON.number(row.diameter),
         "euler_degrees": [AgentJSON.number(row.euler.x), AgentJSON.number(row.euler.y), AgentJSON.number(row.euler.z)],
         "gos_degrees": AgentJSON.number(row.gosDegrees), "neighbours": row.neighbours,
         "centroid": ["x": AgentJSON.number(row.centroid.x), "y": AgentJSON.number(row.centroid.y)]]
    }

    static func grains(_ appState: AppState, _ a: [String: String]) -> AgentToolOutput {
        let session = appState.maps
        guard session.hasMap else { return noMap }
        guard let analysis = session.analysis else {
            return .refusal(status: 409, message: session.isSegmenting ? "Segment is running; ask again when get_maps says not busy."
                : "No grains yet: Segment the map first (run_room).")
        }
        var table = analysis.table
        if a["sort"] == "size" { table.sort { $0.points > $1.points || ($0.points == $1.points && $0.id < $1.id) } }
        let first = min(a["first"].flatMap(Int.init) ?? 0, table.count)
        let count = a["count"].flatMap(Int.init) ?? 100
        let schmid = session.schmidByGrain
        let rows = table[first..<min(table.count, first + count)].map { row -> [String: Any] in
            var out = grainRow(row)
            if let s = schmid[row.id] { out["max_schmid"] = AgentJSON.number(s) }
            return out
        }
        var answer: [String: Any] = ["grains": table.count, "first": first, "rows": rows, "scan_unit": analysis.scanUnit,
                                     "stale": session.analysisIsStale]
        if let word = a["histogram"], let kind = MapAnalysis.HistogramKind.allCases.first(where: { agentWord($0) == word }),
           let histogram = session.histogram(kind) {
            answer["histogram"] = ["kind": word, "unit": kind == .grainSize ? analysis.scanUnit : "degrees",
                                   "edges": histogram.edges.map { AgentJSON.number($0) }, "counts": histogram.counts] as [String: Any]
        }
        return .json(answer)
    }

    // MARK: Setting

    /// `set_maps`: source first (it rebuilds what the room shows), then the layer, the analysis settings, slip, texture and the bottom pane.
    static func applyMaps(_ a: [String: String], to appState: AppState) -> AgentToolOutput? {
        let session = appState.maps
        let flag = { (key: String) -> Bool? in a[key].map { $0 == "true" } }
        if let i = a["source"].flatMap(Int.init) {
            guard session.sources.indices.contains(i) else {
                return .refusal(status: 404, message: "The room holds \(session.sources.count) results: source 0 to \(session.sources.count - 1).")
            }
            if session.sources[i].id != session.document?.id { appState.showMapsSource(session.sources[i].id) }
        }
        if let id = a["layer"] {
            guard let layer = session.layers.first(where: { $0.id == id }) else {
                return .refusal(status: 409, message: "The map has no layer \(id); it has " + session.layers.map(\.id).joined(separator: ", ")
                    + (session.analysis == nil ? ". The derived layers come with Segment." : "."))
            }
            session.setLayer(layer)
        }
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        if a["boundary_angle"] != nil || a["minimum_size"] != nil || a["kam_max"] != nil {
            var s = session.analysisSettings
            if let v = number("boundary_angle") { s.boundaryDegrees = v }
            if let v = a["minimum_size"].flatMap(Int.init) { s.minimumSize = v }
            if let v = number("kam_max") { s.kamMaxDegrees = v }
            session.setAnalysisSettings(s)
        }
        if let v = flag("show_boundaries") { session.showsBoundaries = v }
        if let v = a["load"].flatMap(SampleDirection.init(rawValue:)) { session.setLoadDirection(v) }
        if let word = a["slip_systems"] {
            guard let map = session.map, let id = a["slip_phase"].flatMap(Int.init),
                  let entry = MapsRoomFormat.indexedPhases(map).first(where: { $0.id == id }) else {
                return .refusal(status: 400, message: "slip_systems needs slip_phase, a phase id as get_maps lists it.")
            }
            let file = SlipSystemFile(rawValue: word)
            if let file, !MapsRoomFormat.slipChoices(entry.phase).contains(file) {
                return .refusal(status: 409, message: "\(word) does not fit \(entry.phase.name); it takes "
                    + MapsRoomFormat.slipChoices(entry.phase).map(\.rawValue).joined(separator: ", ") + ".")
            }
            session.setSlipFile(file, phaseID: id)
        }
        if let v = flag("show_slip_traces") { session.showsSlipTraces = v }
        if let id = a["texture_phase"].flatMap(Int.init) {
            guard session.texturePhases.contains(where: { $0.id == id }) else {
                return .refusal(status: 409, message: "Phase \(id) has no texture: the textured phases are "
                    + session.texturePhases.map { "\($0.id) (\($0.phase.name))" }.joined(separator: ", ") + ".")
            }
            session.showTexture(phaseID: id)
        }
        if let word = a["tab"], let tab = MapsBottomTab.allCases.first(where: { agentWord($0) == word }) { appState.mapsRoom.bottomTab = tab }
        if let word = a["histogram"], let kind = MapAnalysis.HistogramKind.allCases.first(where: { agentWord($0) == word }) {
            appState.mapsRoom.histogramKind = kind
        }
        return nil
    }

    // MARK: Pictures

    static func mapsPicture(_ appState: AppState, which: String, scale: Int) -> AgentToolOutput {
        let session = appState.maps
        guard let document = session.document else { return noMap }
        let side = pictureSide * scale
        do {
            let png: Data
            if which == "texture" {
                guard let texture = session.texture else {
                    return .refusal(status: 404, message: session.isTexturing ? "The texture is being computed; ask again when get_maps says so."
                        : (session.textureFailure ?? "No texture yet: set_maps texture_phase computes one."))
                }
                png = try MapsFigure.texturePNG(texture, fileName: document.fileName)
            } else {
                guard let raster = session.raster else {
                    return .refusal(status: 404, message: "The map has not landed yet; wait until get_maps says not busy.")
                }
                png = try MapsFigure.png(raster: raster, layer: session.layer, map: document.map, keys: session.keys,
                                         presentation: session.propertyPresentation, fileName: document.fileName,
                                         boundaries: session.showsBoundaries ? (session.grainBoundaryEdges, session.phaseBoundaryEdges) : ([], []),
                                         grainCount: session.analysis?.table.count)
            }
            return .png(smaller(png, side: side) ?? png)
        } catch {
            return .refusal(status: 500, message: "The picture could not be drawn: \(error.localizedDescription)")
        }
    }
}
