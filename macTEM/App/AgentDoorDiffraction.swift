//
//  AgentDoorDiffraction.swift
//  Role: the agent door's tools for the Diffraction room (#558). `get_diffraction` reads the room for the pattern shown: the
//        centre and where it came from, the scale in use (a ring fit on a standard, the file's axis, or a typed Δq) with the camera
//        length a fit gives, the standard and its rings, the crystal, k_max and the tolerance, the annulus and the tool, the rings and
//        spots measured and the readout (radius, q, d, the family indexed, the listed d and the deviation), or Export Readout CSV…'s
//        text. `set_diffraction` sets the inspector's Centre, Calibration, Crystal, Rings and Tools sections and presses Calibrate on
//        Ring or Fit Ring; `set_diffraction_marks` adds a spot as a click on the pattern does, and removes rings and spots.
//        `get_diffraction_figure` draws the figure Edit > Copy Figure copies (#823): the pattern at 90 mm with its bar, labels,
//        legend and spot table, as PNG at 300 dpi.
//
//        ONE SOURCE PER FACT: the readout is `DiffractionAnalysis.readout`, the rows the room and the Results room show; the CSV is
//        `exportText`, what the export writes. Every change goes through the analysis' intents as the controls' do, removals through
//        `DiffractionUndo`. The room binds the pattern when its inspector appears (`DiffractionRoomSettings`); a tool does the same.
//

import DiffractoCore
import DiffractoGeometry
import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let diffractionTools: [AgentTool] = [
        AgentTool(name: "get_diffraction", title: "Diffraction room",
                  summary: "What the Diffraction room holds for the pattern shown: the centre and its source, the scale in use (a ring "
                      + "fit on a standard, the file's reciprocal axis or a typed Δq) with Δq, the wavelength and the camera length, the "
                      + "beam energy and the camera, the standard and its rings, the crystal, k_max and the indexing tolerance, the "
                      + "annulus and the tool, every ring and spot, and the readout: radius, q, d, the family indexed, the listed d, the "
                      + "deviation and the verdict. With csv true, the readout as Export Readout CSV… writes it.",
                  input: .window,
                  parameters: [AgentParameter("csv", .boolean, summary: "The readout CSV instead.")]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noPattern }
                if call.arguments["csv"] == "true" { return .json(["csv": item.diffraction.exportText(image: image)]) }
                return .json(diffraction(item, image: image))
            }
        },
        AgentTool(name: "get_diffraction_figure", title: "Diffraction figure",
                  summary: "The pattern on screen as Export Figure… draws it at its defaults (Edit > Copy Figure copies the same): 90 mm "
                      + "wide with the scale bar in Å⁻¹, the d of each ring and spot, the hkl of the simulated spots, the legend and the "
                      + "spot table, as PNG at 300 dpi.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item:
                guard let snapshot = ExportSnapshot.diffractionFigureSnapshot(of: appState) else {
                    return .refusal(status: 404, message: "The pattern's display is still being built; ask again in a moment.")
                }
                do { return .png(try snapshot.png()) } catch {
                    return .refusal(status: 500, message: "The figure could not be drawn: \(error.localizedDescription)")
                }
            }
        },
        said(AgentTool(name: "set_diffraction", title: "Diffraction room settings",
                       summary: "The Diffraction room's inspector, only those given. centre_row and centre_column (px); use_ring_centre "
                           + "takes a fitted ring's centre (its number). standard and family (the ring's index in get_diffraction's "
                           + "families) pick the calibration ring; calibrate true fits the ring in the annulus and sets Δq from it, "
                           + "clear_calibration drops it; delta_q (Å⁻¹/px, only for a file with no reciprocal axis), beam_kv (only "
                           + "for a file with no voltage), camera (a name, or none) and pixel_pitch (mm). crystal (a standard's "
                           + "name), k_max (Å⁻¹) and tolerance (% of q) set the indexing. inner and outer set the annulus (px from the "
                           + "centre), fit_ring true fits the ring in it (answers at once; get_diffraction says fitting). tool ring or "
                           + "spot, log the display's log switch, unit_cell the Crystal View section's Unit cell switch (the unit cell's "
                           + "edges in the crystal pane; off limits, as the switch is, while the pane is hidden).",
                       input: .window, parameters: diffractionParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noPattern }
                if let refusal = applyDiffraction(call.arguments, to: item, image: image) { return refusal }
                return .json(diffraction(item, image: image))
            }
        }),
        said(AgentTool(name: "set_diffraction_marks", title: "Diffraction rings and spots",
                       summary: "add_spot \"row column\" adds a spot as a click on the pattern does (its centre refined on the pattern); "
                           + "select and remove take \"ring 2\" or \"spot 1\" as get_diffraction numbers them, remove also all.",
                       input: .window,
                       parameters: [
                           AgentParameter("add_spot", .text, summary: "\"row column\" in pattern pixels."),
                           AgentParameter("select", .text, summary: "\"ring N\" or \"spot N\": the row the readout highlights."),
                           AgentParameter("remove", .text, summary: "\"ring N\", \"spot N\", or all."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noPattern }
                if let refusal = applyDiffractionMarks(call.arguments, to: item, image: image) { return refusal }
                return .json(diffraction(item, image: image))
            }
        }),
    ]

    /// The pattern the Diffraction room shows, or why a tool cannot work on it.
    enum DiffractionFound {
        case item(OpenItem)
        case refused(AgentToolOutput)
    }

    private static let noPattern = AgentToolOutput.refusal(
        status: 404, message: "No pattern is shown; open one first (open_demo with demo diffraction opens the demo Au pattern).")

    /// The file the Diffraction room shows, bound to the analysis as the room's inspector binds it; refused outside the room.
    static func diffractionItem(_ appState: AppState) -> DiffractionFound {
        guard let item = appState.openItems.selected, let image = item.session.image else { return .refused(noPattern) }
        guard appState.navigation.workspaceArea == .diffraction else {
            return .refused(.refusal(status: 409, message: "The window shows the \(appState.navigation.workspaceArea.title) room; "
                + "select_room diffraction first."))
        }
        item.diffraction.bind(image)
        return .item(item)
    }

    static let diffractionParameters: [AgentParameter] = [
        AgentParameter("centre_row", .number(-1e6...1e6), summary: "The pattern centre's row, px."),
        AgentParameter("centre_column", .number(-1e6...1e6), summary: "The pattern centre's column, px."),
        AgentParameter("use_ring_centre", .integer(1...10_000), summary: "Take this fitted ring's centre."),
        AgentParameter("standard", .choice(StandardCrystals.all.map(\.name)), summary: "The calibration standard."),
        AgentParameter("family", .integer(0...5), summary: "The standard's ring to calibrate on: its index in families."),
        AgentParameter("calibrate", .boolean, summary: "Calibrate on Ring: fit the annulus' ring and take Δq from it."),
        AgentParameter("clear_calibration", .boolean, summary: "Drop the ring calibration."),
        AgentParameter("delta_q", .number(1e-6...10), summary: "A typed Δq, Å⁻¹/px (a file with no reciprocal axis)."),
        AgentParameter("beam_kv", .number(1...10_000), summary: "A typed beam energy, kV (a file with no voltage)."),
        AgentParameter("camera", .choice(["none"] + CameraPitches.all.map(\.name)), summary: "The camera, for its pixel pitch."),
        AgentParameter("pixel_pitch", .number(0.0001...10), summary: "The camera's pixel pitch, mm."),
        AgentParameter("crystal", .choice(StandardCrystals.all.map(\.name)), summary: "The crystal to index against."),
        AgentParameter("k_max", .number(0.2...4), summary: "The reflection list's reach, Å⁻¹."),
        AgentParameter("tolerance", .number(0.01...100), summary: "The indexing tolerance, % of q."),
        AgentParameter("inner", .number(0.1...100_000), summary: "The annulus' inner radius, px."),
        AgentParameter("outer", .number(0.1...100_000), summary: "The annulus' outer radius, px."),
        AgentParameter("fit_ring", .boolean, summary: "Fit Ring: fit the ring in the annulus."),
        AgentParameter("tool", .choice(DiffractionViewState.Tool.allCases.map(\.rawValue)), summary: "What a click on the pattern does."),
        AgentParameter("log", .boolean, summary: "Draw the pattern on a log scale."),
        AgentParameter("unit_cell", .boolean, summary: "Draw the unit cell's edges in the crystal pane."),
    ]

    // MARK: Answers

    static func diffraction(_ item: OpenItem, image: CalibratedImage) -> [String: Any] {
        let analysis = item.diffraction, view = item.diffractionView
        let calibration = analysis.calibration(for: image)
        var scale: [String: Any] = ["source": "none"]
        if let calibration {
            scale = ["source": calibration.sourceText, "delta_q_per_px": AgentJSON.number(calibration.deltaQ),
                     "fit_versus_file_percent": AgentJSON.number(analysis.fitVersusFilePercent(for: image))]
            if let ring = calibration.ring {
                scale["ring"] = ["d_angstroms": AgentJSON.number(ring.d), "radius_px": AgentJSON.number(ring.radius),
                                 "wavelength_angstroms": AgentJSON.number(ring.wavelengthAngstroms),
                                 "camera_length_px": AgentJSON.number(ring.lengthPixels),
                                 "camera_length_mm": AgentJSON.number(ring.lengthMillimetres)] as [String: Any]
            }
        }
        let selected = view.selection
        let rows = analysis.readout(image: image).map { r -> [String: Any] in
            [
                "kind": r.kind.rawValue, "number": r.number, "radius_px": AgentJSON.number(r.radiusPx),
                "q_per_angstrom": AgentJSON.number(r.q), "d_angstroms": AgentJSON.number(r.d), "family": AgentJSON.orNull(r.family),
                "d_listed_angstroms": AgentJSON.number(r.dListed), "deviation_percent": AgentJSON.number(r.deltaPercent),
                "odds": AgentJSON.orNull(r.oddsText), "verdict": r.verdict, "calibrating": r.isCalibrating, "selected": r.id == selected,
            ]
        }
        let centre: Any = AgentJSON.orNull(analysis.centre.map { c -> [String: Any] in
            ["row": AgentJSON.number(c.row), "column": AgentJSON.number(c.column), "source": centreSource(c.source)]
        })
        let families: [[String: Any]] = analysis.standardFamilies().enumerated().map { i, f in
            ["index": i, "name": f.name, "d_angstroms": AgentJSON.number(f.d)]
        }
        let rings: [[String: Any]] = analysis.rings.enumerated().map { i, ring in
            ["number": i + 1, "inner": AgentJSON.number(ring.innerRadius), "outer": AgentJSON.number(ring.outerRadius),
             "radius_px": AgentJSON.number(ring.radius), "refusal": AgentJSON.orNull(ring.refusal), "calibrating": ring.isCalibrating,
             "has_centre": ring.fit?.fit != nil]
        }
        let spots: [[String: Any]] = analysis.spots.enumerated().map { i, spot in
            let clicked: [Any] = [AgentJSON.number(spot.clickRow), AgentJSON.number(spot.clickColumn)]
            return ["number": i + 1, "clicked": clicked, "row": AgentJSON.number(spot.row), "column": AgentJSON.number(spot.column),
                    "refusal": AgentJSON.orNull(spot.refusal)]
        }
        let pitch = analysis.pitchMM
        let camera: Any = AgentJSON.orNull(pitch.flatMap { p in CameraPitches.all.first { $0.pitchMM == p }?.name })
        var out: [String: Any] = [
            "file_name": item.url.lastPathComponent, "width": image.width, "height": image.height, "centre": centre, "scale": scale,
            "file_delta_q_per_px": AgentJSON.number(analysis.fileDeltaQ(image)),
            "typed_delta_q_per_px": AgentJSON.number(analysis.typedDeltaQ),
            "beam_kv": AgentJSON.number(analysis.volts(for: image).map { $0 / 1000 }),
            "beam_from_file": image.voltage != nil, "camera": camera, "pixel_pitch_mm": AgentJSON.number(pitch),
        ]
        out.merge([
            "standard": analysis.standard.name, "families": families, "family": analysis.familyIndex,
            "crystal": analysis.crystal.name, "crystal_from_cif": analysis.crystal.sha256 != nil,
            "crystal_lattice": analysis.crystal.lattice, "crystal_phase": AgentJSON.orNull(analysis.crystal.phaseID),
            "crystal_failure": AgentJSON.orNull(analysis.crystalFailure),
            "k_max_per_angstrom": AgentJSON.number(analysis.kMax), "tolerance_percent": AgentJSON.number(analysis.tolerancePercent),
        ]) { _, new in new }
        out.merge([
            "inner": AgentJSON.number(view.annulusInner), "outer": AgentJSON.number(view.annulusOuter),
            "tool": view.tool.rawValue, "log": view.useLog, "rings": rings, "spots": spots, "readout": rows,
            "shows_unit_cell": view.showsUnitCell,
            // A Simulation document's Microscope section (#907): the camera length its Spots table's R in mm is at.
            "camera_length_mm": AgentJSON.number(DemoDocuments.isSimulation(item.url) ? analysis.cameraLengthMM : nil),
            "fitting": analysis.isFitting, "failure": AgentJSON.orNull(analysis.failure),
        ]) { _, new in new }
        return out
    }

    /// The centre's source as Export Readout CSV… words it.
    private static func centreSource(_ source: DiffractionCentre.Source) -> String {
        switch source {
        case .fileCentre: "the image centre"
        case .typed: "typed"
        case .ring: "a fitted ring"
        }
    }

    // MARK: Acting

    /// `set_diffraction`: every check first, so a refused call changes nothing; then the controls' intents in the inspector's order,
    /// the fits last so they use the annulus, the standard and the camera given in the same call.
    static func applyDiffraction(_ a: [String: String], to item: OpenItem, image: CalibratedImage) -> AgentToolOutput? {
        let analysis = item.diffraction, view = item.diffractionView
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        if (a["centre_row"] == nil) != (a["centre_column"] == nil) {
            return .refusal(status: 400, message: "centre_row and centre_column go together.")
        }
        if let n = a["use_ring_centre"].flatMap(Int.init) {
            guard analysis.rings.indices.contains(n - 1), analysis.rings[n - 1].fit?.fit != nil else {
                return .refusal(status: 404, message: "Ring \(n) has no fitted centre; get_diffraction lists the rings.")
            }
        }
        if number("delta_q") != nil, analysis.fileDeltaQ(image) != nil {
            return .refusal(status: 409, message: "The file states its own reciprocal axis; a typed Δq is only for a file without one.")
        }
        if number("beam_kv") != nil, image.voltage != nil {
            return .refusal(status: 409, message: "The file states its beam energy; a typed one is only for a file without it.")
        }
        let standard = a["standard"].flatMap(StandardCrystals.named) ?? analysis.standard
        // The ring is checked against the standard the call sets, before anything changes (#927).
        let families = analysis.standardFamilies(of: standard)
        if let f = a["family"].flatMap(Int.init), !families.indices.contains(f) {
            return .refusal(status: 400, message: "The standard has rings 0 to \(families.count - 1) (get_diffraction's families).")
        }
        let inner = number("inner") ?? view.annulusInner, outer = number("outer") ?? view.annulusOuter
        if a["inner"] != nil || a["outer"] != nil, !(inner < outer) {
            return .refusal(status: 400, message: "The annulus needs inner < outer.")
        }
        if a["calibrate"] == "true" || a["fit_ring"] == "true", analysis.isFitting {
            return .refusal(status: 409, message: "A ring fit is running; ask again when get_diffraction says fitting false.")
        }
        if a["unit_cell"] != nil, !view.showsCrystal {
            return .refusal(status: 409, message: "The crystal pane is hidden, so its Unit cell switch is off; the person shows it with "
                + "View > Show Crystal.")
        }

        if let row = number("centre_row"), let column = number("centre_column") { analysis.setCentre(row: row, column: column) }
        if let n = a["use_ring_centre"].flatMap(Int.init) { analysis.useCentre(ofRing: analysis.rings[n - 1].id) }
        if a["standard"] != nil { analysis.setStandard(standard) }
        if let f = a["family"].flatMap(Int.init) { analysis.familyIndex = f }
        if a["clear_calibration"] == "true" { DiffractionUndo.clearCalibration(in: analysis, undoManager: nil) }
        if let dq = number("delta_q") { analysis.typedDeltaQ = dq }
        if let kv = number("beam_kv") { analysis.typedBeamKV = kv }
        if let camera = a["camera"] { analysis.pitchMM = CameraPitches.all.first { $0.name == camera }?.pitchMM }
        if let pitch = number("pixel_pitch") { analysis.pitchMM = pitch }
        if let name = a["crystal"], let s = StandardCrystals.named(name) { analysis.setCrystal(.preset(s)) }
        if let k = number("k_max") { analysis.setKMax(k) }
        if let t = number("tolerance") { analysis.setTolerance(percent: t) }
        if a["inner"] != nil || a["outer"] != nil { view.setAnnulus(inner: inner, outer: outer) }
        if let tool = a["tool"].flatMap(DiffractionViewState.Tool.init(rawValue:)) { view.tool = tool }
        if let log = a["log"] { view.useLog = log == "true" }
        if let on = a["unit_cell"] { view.showsUnitCell = on == "true" }
        if a["calibrate"] == "true" {
            let families = analysis.standardFamilies()
            guard families.indices.contains(analysis.familyIndex) else {
                return .refusal(status: 409, message: "The standard lists no ring to calibrate on.")
            }
            analysis.fitRing(image: image, inner: view.annulusInner, outer: view.annulusOuter, calibrateOn: families[analysis.familyIndex].family)
        } else if a["fit_ring"] == "true" {
            analysis.fitRing(image: image, inner: view.annulusInner, outer: view.annulusOuter)
        }
        return nil
    }

    /// "ring 2" or "spot 1" → that row's id, as the readout numbers them.
    private static func markID(_ words: String, in analysis: DiffractionAnalysis) -> UUID? {
        let parts = words.lowercased().split(separator: " ").map(String.init)
        guard parts.count == 2, let n = Int(parts[1]), n >= 1 else { return nil }
        switch parts[0] {
        case "ring": return analysis.rings.indices.contains(n - 1) ? analysis.rings[n - 1].id : nil
        case "spot": return analysis.spots.indices.contains(n - 1) ? analysis.spots[n - 1].id : nil
        default: return nil
        }
    }

    /// `set_diffraction_marks`: a spot added as a click adds it, the selection, a removal through the room's undo.
    static func applyDiffractionMarks(_ a: [String: String], to item: OpenItem, image: CalibratedImage) -> AgentToolOutput? {
        let analysis = item.diffraction, view = item.diffractionView
        var spotAt: (row: Double, column: Double)?
        if let words = a["add_spot"] {
            let n = words.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double(String($0)) }.filter(\.isFinite)
            guard n.count == 2, n[0] >= 0, n[1] >= 0, n[0] < Double(image.height), n[1] < Double(image.width) else {
                return .refusal(status: 400, message: "add_spot takes \"row column\" on the \(image.width) × \(image.height) pattern.")
            }
            spotAt = (n[0], n[1])
        }
        var selectID: UUID?
        if let words = a["select"] {
            guard let id = markID(words, in: analysis) else {
                return .refusal(status: 404, message: "No \(words); get_diffraction numbers the rings and spots.")
            }
            selectID = id
        }
        var removeIDs: [UUID]?
        if let words = a["remove"] {
            if words.trimmingCharacters(in: .whitespaces) == "all" {
                removeIDs = []
            } else {
                guard let id = markID(words, in: analysis) else {
                    return .refusal(status: 404, message: "No \(words); get_diffraction numbers the rings and spots.")
                }
                removeIDs = [id]
            }
        }

        if let spotAt { analysis.addSpot(image: image, row: spotAt.row, column: spotAt.column) }
        if let selectID { view.selection = selectID }
        if let removeIDs {
            if removeIDs.isEmpty {
                DiffractionUndo.removeAll(in: analysis, undoManager: nil)
            } else {
                for id in removeIDs { DiffractionUndo.remove(id, in: analysis, undoManager: nil) }
            }
            if let selection = view.selection, !analysis.rings.contains(where: { $0.id == selection }),
               !analysis.spots.contains(where: { $0.id == selection }) {
                view.selection = nil
            }
        }
        return nil
    }
}
