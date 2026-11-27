//
//  AgentDoorIndex.swift
//  Role: the agent door's tools for Index in the Diffraction room (#791, plan row R8). `index_pattern` presses Index (the toolbar's
//        verb) and answers at once with `get_spot_table`'s answer and indexing true; `get_spot_table` reads Index's answer (the
//        verdict, its line in the header's words, the solutions with their zone axis, tilt off it and score, the fitted scale and
//        misfit, and the flags: tied, zone axis only, a scale or the spots changed since), the Spots table's rows and the spots marked
//        (found or clicked), or the Spots CSV's text; `set_zone_axis` types the Index section's zone axis and turn, steps to a
//        solution, tilts the drawn orientation as the Tilt tool does and flips it; `simulate_pattern` sets the Simulation section
//        (overlay, labels, double diffraction, excitation error); `get_diffraction_picture` draws the pattern shown as the room shows it, with
//        the annulus, the fitted rings, the marked spots (yellow, numbered as the table numbers them) and the simulated spots (cyan,
//        the strongest labelled with hkl), making the room's pass itself when the room has not drawn the pixels shown (#1003).
//
//        ONE SOURCE PER FACT: the answer is `DiffractionAnalysis.indexOutcome` and `indexLine`, the rows `indexSpotRows`, the CSV
//        `ExportSnapshot.diffractionSpotsCSV` (Export Spots CSV…'s, its methods record inside), the simulated spots
//        `simulatedSpots`, as the room shows them. Every change goes through the analysis'
//        intents as the controls' do (`index`, `setZoneAxis`, `setTurn`, `selectSolution`, `turnByHand` with the Tilt tool's
//        `ZoneAxisOverlay.tilted`, `flip`, `setExcitationError`, the simulation's settings, `fitScale`).
//

import DiffractoCore
import DiffractoGeometry
import Foundation
import ShellAgentDoor
import ShellMetal
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let indexTools: [AgentTool] = [
        AgentTool(name: "get_spot_table", title: "Diffraction spot table",
                  summary: "Index's answer for the pattern shown and the Spots table: indexing (true while it runs), the verdict (found, "
                      + "found but poor, tied, one row, not found, scale at its limit) and its line as the header writes it, the "
                      + "solutions (at most five, the best first, then those the pattern cannot tell from it: zone axis, degrees off it, orix "
                      + "quaternion), the score, the fitted scale (measured |q| over |g|), the misfit, spots explained, zone_axis_only "
                      + "(clicked spots: no tilt), scale_changed and spots_changed (Index again), the rows (spot, hkl, R px, R mm, "
                      + "q, d, d expected, Δd/d %, phase, the dynamical intensity) and every spot marked, found (with its intensity) "
                      + "or clicked. A Simulation document's rows are its simulated spots, strongest first, as its Spots table "
                      + "lists them. With csv true, the Spots CSV as Export Spots CSV… writes it.",
                  input: .window,
                  parameters: [AgentParameter("csv", .boolean, summary: "The Spots CSV instead.")]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noIndexPattern }
                if call.arguments["csv"] == "true" {
                    // A Simulation document's Export Spots CSV… writes its simulated spots (#907), as the section's button does.
                    return .json(["csv": ExportSnapshot.diffractionSpotsCSV(item.diffraction, image: image, openItems: appState.openItems,
                                                                            simulation: DemoDocuments.isSimulation(item.url))])
                }
                return .json(spotTable(item))
            }
        },
        said(AgentTool(name: "index_pattern", title: "Index",
                       summary: "Presses Index, the Diffraction room's verb: with no spot marked it finds the spots (they become marks) "
                           + "and the crystal's full orientation; with spots marked it reads those (a clicked one gives the zone axis "
                           + "only). remove_spots true first removes every spot, so Index finds them again; fit_scale (on by default) "
                           + "fits the scale within ±3 %, off holds the room's. Answers at once with "
                           + "get_spot_table's answer and indexing true; ask get_spot_table until indexing is false. Refused, in the "
                           + "room's words, without a centre, a scale, a beam energy or a crystal.",
                       input: .window,
                       parameters: [
                           AgentParameter("remove_spots", .boolean, summary: "Remove Spots first."),
                           AgentParameter("fit_scale", .boolean, summary: "The Index section's Fit scale."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noIndexPattern }
                let analysis = item.diffraction
                if analysis.isIndexing || analysis.isFitting {
                    return .refusal(status: 409, message: "\(analysis.isIndexing ? "Index" : "A ring fit") is running; ask again when get_spot_table says indexing false.")
                }
                if let why = analysis.indexBlocker(image: image) { return .refusal(status: 409, message: why + ".") }
                if call.arguments["remove_spots"] == "true" { DiffractionUndo.removeSpots(in: analysis, undoManager: nil) }
                if let fit = call.arguments["fit_scale"] { analysis.fitScale = fit == "true" }
                analysis.index(image: image)
                return .json(spotTable(item))
            }
        }),
        said(AgentTool(name: "set_zone_axis", title: "Zone axis",
                       summary: "The Index section's zone axis and turn, as typed: zone_axis \"[1 1 0]\", \"1 1 0\", \"110\" or \"-1 1 0\" "
                           + "(three whole numbers, not all 0) and turn (degrees about the beam, counter-clockwise from down the rows "
                           + "toward along the columns). Either takes the simulated spots off Index's orientation. solution n draws "
                           + "Index's n-th solution (1 the best; the Index section's Solution stepper). tilt_down and tilt_across tilt "
                           + "the drawn orientation as a Tilt-tool drag that far down the rows and along the columns would (degrees), "
                           + "turn_by degrees about the beam as an ⌥ drag, and flip true turns it 180° (Flip 180°); they apply in that "
                           + "order. Answers with get_spot_table's answer and the simulation, whose place names the nearest zone axis "
                           + "and the angle off it once the orientation was set by hand.",
                       input: .window,
                       parameters: [
                           AgentParameter("zone_axis", .text, summary: "The beam direction [u v w]."),
                           AgentParameter("turn", .number(-3600...3600), summary: "The in-plane turn, degrees."),
                           AgentParameter("solution", .integer(1...PatternIndexing.solutionLimit), summary: "Index's solution to draw."),
                           AgentParameter("tilt_down", .number(-45...45), summary: "Tilt as a drag down the rows, degrees."),
                           AgentParameter("tilt_across", .number(-45...45), summary: "Tilt as a drag along the columns, degrees."),
                           AgentParameter("turn_by", .number(-360...360), summary: "Turn about the beam, degrees."),
                           AgentParameter("flip", .boolean, summary: "Flip 180°."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                let analysis = item.diffraction
                var uvw: SIMD3<Int>?
                if let text = call.arguments["zone_axis"] {
                    guard let parsed = ZoneAxisText.parse(text) else {
                        return .refusal(status: 400, message: "\"\(text)\" is not a zone axis: type three whole numbers, not all 0, such as [1 1 0] or 1̄10.")
                    }
                    uvw = parsed
                }
                let solution = call.arguments["solution"].flatMap(Int.init)
                if let n = solution, !analysis.solutions.indices.contains(n - 1) {
                    return .refusal(status: 409, message: "Index has \(analysis.solutions.count) solution\(analysis.solutions.count == 1 ? "" : "s"); solution \(n) is not one.")
                }
                let down = call.arguments["tilt_down"].flatMap(Double.init) ?? 0, across = call.arguments["tilt_across"].flatMap(Double.init) ?? 0
                let by = call.arguments["turn_by"].flatMap(Double.init) ?? 0
                let turnsByHand = down != 0 || across != 0 || by != 0 || call.arguments["flip"] == "true"
                // Every refusal before anything changes: a refused call has not acted.
                if turnsByHand, uvw == nil, solution == nil, analysis.drawnOrientation == nil {
                    return .refusal(status: 409, message: "No orientation is drawn to tilt or flip: type a zone axis or Index first.")
                }
                if let uvw { analysis.setZoneAxis(uvw) }
                if let turn = call.arguments["turn"].flatMap(Double.init) { analysis.setTurn(degrees: turn) }
                if let n = solution { analysis.selectSolution(n - 1) }
                if down != 0 || across != 0, let base = analysis.drawnOrientation {
                    let points = SIMD2(down, across) / ZoneAxisOverlay.degreesPerPoint
                    analysis.turnByHand(to: ZoneAxisOverlay.tilted(base, drag: points))
                }
                if by != 0, let base = analysis.drawnOrientation { analysis.turnByHand(to: base.rotatedInPlane(by: by * .pi / 180)) }
                if call.arguments["flip"] == "true" { analysis.flip() }
                return .json(spotTable(item).merging(["simulation": simulation(item)]) { _, new in new })
            }
        }),
        said(AgentTool(name: "simulate_pattern", title: "Simulated spots",
                       summary: "The Simulation section, only those given: overlay (the crystal's kinematical spots over the pattern, at "
                           + "Index's orientation or the typed zone axis), labels (hkl on the strongest), double_diffraction (also the "
                           + "spots g₁ + g₂ adds where the crystal forbids a reflection, drawn dashed) and excitation_error (σ in Å⁻¹, "
                           + "0.02 by default; spots up to 3σ are kept; 0.001 to 1). Answers with the "
                           + "simulation: the zone axis, the turn, whether Index's orientation is drawn, and the spots on the pattern "
                           + "(hkl, row, column, relative intensity) or why there are none.",
                       input: .window,
                       parameters: [
                           AgentParameter("overlay", .boolean, summary: "Show the simulated spots."),
                           AgentParameter("labels", .boolean, summary: "Show their hkl (on: the label mode chosen, else strongest; off: none)."),
                           AgentParameter("label_mode", .choice(HKLLabelMode.allCases.map(\.rawValue)),
                                          summary: "The hkl labels pop-up: strongest (up to 16 that fit), all (every one that fits) or off."),
                           AgentParameter("double_diffraction", .boolean, summary: "Also the double-diffraction spots."),
                           AgentParameter("excitation_error", .number(0.001...1), summary: "σ of the excitation envelope, Å⁻¹."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                if let overlay = call.arguments["overlay"] { item.diffraction.simulation.isShown = overlay == "true" }
                if let labels = call.arguments["labels"] { item.diffraction.simulation.showsLabels = labels == "true" }
                if let text = call.arguments["label_mode"] {
                    guard let mode = HKLLabelMode(rawValue: text) else {
                        return .refusal(status: 400, message: "label_mode is strongest, all or off.")
                    }
                    item.diffraction.simulation.labelMode = mode
                }
                if let double = call.arguments["double_diffraction"] { item.diffraction.simulation.doubleDiffraction = double == "true" }
                if let sigma = call.arguments["excitation_error"].flatMap(Double.init), !item.diffraction.setExcitationError(sigma) {
                    return .refusal(status: 400, message: "The excitation error is a number from 0.001 to 1 Å⁻¹.")
                }
                return .json(["simulation": simulation(item)])
            }
        }),
        AgentTool(name: "get_diffraction_picture", title: "Diffraction picture",
                  summary: "The pattern shown now as the Diffraction room draws it (its log or linear display, colormap, window and "
                      + "gamma; a CBED pattern at the stored thickness shown), with the Ring tool's annulus as two dashed white circles, "
                      + "the fitted rings as yellow outlines with their d, the spots marked as yellow rings numbered as the Spots table "
                      + "numbers them and, with the overlay on, the simulated spots as cyan rings, the strongest labelled with their hkl.",
                  input: .windowPicture) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noIndexPattern }
                return diffractionPicture(item, image: image, side: pictureSide * call.scale)
            }
        },
        said(AgentTool(name: "save_diffraction", title: "Save diffraction file",
                       summary: "Writes into the Agent folder what the Diffraction room's Export section writes, the same text: which "
                           + "spots_csv (Export Spots CSV…: Index's spots, or a Simulation document's simulated spots with R in px and "
                           + "mm), readout_csv (Export Readout CSV…), or png (the pattern with its marked and simulated spots, at its "
                           + "own size, as get_diffraction_picture draws it). file names it, relative to the Agent folder (the "
                           + "section's name by default). Refused, writing nothing, while the section's button is off (nothing to "
                           + "write) or when the name leads outside the folder. Changes nothing in the room.",
                       input: .window,
                       parameters: [
                           AgentParameter("which", .choice(["spots_csv", "readout_csv", "png"]), summary: "The file to write.",
                                          required: true),
                           AgentParameter("file", .text, summary: "The file to write, relative to the Agent folder."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                guard let image = item.session.image else { return noIndexPattern }
                switch saveDiffraction(call.arguments["which"] ?? "", file: call.arguments["file"], item: item, image: image,
                                       openItems: appState.openItems) {
                case .written(let name): return .json(["written": name])
                case .refused(let refusal): return refusal
                }
            }
        }),
    ]

    /// `save_diffraction`: the Export section's file, written into the Agent folder; refused where the section's button is off.
    static func saveDiffraction(_ which: String, file: String?, item: OpenItem, image: CalibratedImage, openItems: OpenItems) -> Written {
        let analysis = item.diffraction
        let simulation = DemoDocuments.isSimulation(item.url)
        switch which {
        case "spots_csv":
            let empty = simulation ? SimulationEmptyState.spotRows(of: item, image: image).isEmpty : analysis.indexSpotRows.isEmpty
            guard !empty else {
                return .refused(.refusal(status: 409, message: simulation
                    ? "No simulated spots to write: show them (simulate_pattern overlay true)."
                    : "No indexed spots to write: index_pattern first."))
            }
            return writeAgentFile(ExportSnapshot.diffractionSpotsCSV(analysis, image: image, openItems: openItems, simulation: simulation),
                                  file: file, fallback: DiffractionReadoutExport.spotsBaseName(of: image.fileName) + ".csv")
        case "readout_csv":
            guard !(analysis.rings.isEmpty && analysis.spots.isEmpty) else {
                return .refused(.refusal(status: 409, message: "No rings or spots to write: fit a ring or add a spot first."))
            }
            return writeAgentFile(ExportSnapshot.diffractionCSV(analysis, image: image, openItems: openItems),
                                  file: file, fallback: DiffractionReadoutExport.baseName(of: image.fileName) + ".csv")
        case "png":
            switch diffractionPicture(item, image: image, side: max(image.width, image.height)) {
            case .png(let data):
                return writeAgentFile(data, file: file, fallback: (image.fileName as NSString).deletingPathExtension + " pattern.png")
            case .refusal(let status, let message):
                return .refused(.refusal(status: status, message: message))
            default:
                return .refused(.refusal(status: 500, message: "The picture could not be drawn."))
            }
        default:
            return .refused(.refusal(status: 400, message: "which is spots_csv, readout_csv or png."))
        }
    }

    private static let noIndexPattern = AgentToolOutput.refusal(
        status: 404, message: "No pattern is shown; open one first (open_demo with demo diffraction opens the demo Au pattern).")

    // MARK: Answers

    /// Index's answer, the Spots table's rows and the spots marked.
    static func spotTable(_ item: OpenItem) -> [String: Any] {
        let analysis = item.diffraction
        var out: [String: Any] = ["indexing": analysis.isIndexing, "fit_scale": analysis.fitScale]
        let crystal = analysis.crystal
        if let o = analysis.indexOutcome {
            let cell = crystal.structure.cell
            // The solutions the Solution stepper and set_zone_axis solution n step through (at most five), so n here is n there.
            let solutions: [[String: Any]] = ([o.orientation].compactMap { $0 } + o.alternatives).prefix(PatternIndexing.solutionLimit).map { orientation in
                let near = orientation.nearestZoneAxis(cell: cell)
                let q = orientation.orixQuaternion
                return ["zone_axis": AgentJSON.orNull(near.map { [$0.uvw.x, $0.uvw.y, $0.uvw.z] }),
                        "degrees_off_zone_axis": AgentJSON.number(near.map { $0.angle * 180 / .pi }),
                        "orix_quaternion": [q.x, q.y, q.z, q.w].map { AgentJSON.number($0) }]
            }
            var refusal: Any = NSNull()
            if case .notFound(let why) = o.verdict { refusal = why }
            var tied = 0
            if case .tied(let count) = o.verdict { tied = count }
            out["answer"] = [
                "phase": o.phase, "verdict": o.verdict.word, "line": AgentJSON.orNull(analysis.indexLine), "refusal": refusal,
                "solutions": solutions, "tied": tied, "score": AgentJSON.number(o.agreement), "scale": AgentJSON.number(o.scale),
                "misfit_percent": AgentJSON.number(o.misfitPercent), "explained": o.explained, "indexed": o.indexed,
                "zone_axis_only": o.zoneAxisOnly, "scale_changed": analysis.indexIsStale, "spots_changed": analysis.indexSpotsChanged,
                "solution": analysis.solutionIndex + 1,
            ] as [String: Any]
        } else {
            out["answer"] = NSNull()
        }
        // The rows the room's Spots table lists: a Simulation document's simulated spots (#907), none while it shows no phase
        // (#1158), else Index's.
        if DemoDocuments.isSimulation(item.url) {
            let rows: [[String: Any]] = item.session.image.map { SimulationEmptyState.spotRows(of: item, image: $0).map(spotRow) } ?? []
            out["rows"] = rows
        } else {
            let rows: [[String: Any]] = item.indexSpotRows.map(spotRow)
            out["rows"] = rows
        }
        out["spots"] = analysis.spots.enumerated().map { i, s -> [String: Any] in
            ["number": i + 1, "row": AgentJSON.number(s.row), "column": AgentJSON.number(s.column),
             "found": s.intensity != nil, "intensity": AgentJSON.number(s.intensity), "refusal": AgentJSON.orNull(s.refusal)]
        }
        return out
    }

    /// A row of the Spots table, its columns as the table and the Spots CSV name them.
    static func spotRow(_ r: PatternIndexing.SpotRow) -> [String: Any] {
        ["spot": r.number, "hkl": AgentJSON.orNull(r.hkl.map { [$0.h, $0.k, $0.l] }), "r_px": AgentJSON.number(r.radiusPx),
         "r_mm": AgentJSON.number(r.radiusMM), "q_per_angstrom": AgentJSON.number(r.q), "d_angstroms": AgentJSON.number(r.d),
         "d_expected_angstroms": AgentJSON.number(r.dExpected), "delta_percent": AgentJSON.number(r.deltaPercent),
         "phase": r.phase, "dynamical_percent": AgentJSON.number(r.dynamicalPercent)]
    }

    /// The Simulation section and its spots on the pattern.
    static func simulation(_ item: OpenItem) -> [String: Any] {
        let analysis = item.diffraction, settings = analysis.simulation
        var out: [String: Any] = [
            "overlay": settings.isShown, "labels": settings.showsLabels, "label_mode": settings.labelMode.rawValue,
            "zone_axis": [settings.zoneAxis.x, settings.zoneAxis.y, settings.zoneAxis.z],
            "turn_degrees": AgentJSON.number(settings.inPlaneDegrees), "from_index": settings.indexed != nil,
            "scale": AgentJSON.number(settings.scale), "crystal": analysis.crystal.name,
            "double_diffraction": settings.doubleDiffraction, "excitation_error": AgentJSON.number(settings.excitationError),
            "set_by_hand": analysis.isTurnedByHand, "place": AgentJSON.orNull(analysis.orientationLine),
        ]
        guard let image = item.session.image else { return out }
        switch analysis.simulatedSpots(image: image) {
        case nil:
            out["spots"] = NSNull()
        case .success(let spots)?:
            out["spots"] = spots.map { s -> [String: Any] in
                ["hkl": [s.hkl.h, s.hkl.k, s.hkl.l], "row": AgentJSON.number(s.row), "column": AgentJSON.number(s.column),
                 "relative": AgentJSON.number(s.relative), "double_diffraction": s.isDoubleDiffraction]
            }
        case .failure(let why)?:
            out["spots"] = NSNull()
            out["absence"] = why.sentence
        }
        return out
    }

    /// The room's pass for the pattern shown, at once, when the room has not drawn those pixels with Log as it is (it is off screen,
    /// or its pass is still to land): the door's picture and figure are then the pattern shown, never an earlier canvas (#1003).
    static func showPatternNow(_ item: OpenItem, image: CalibratedImage) {
        let generation = item.session.generation
        if !item.diffractionView.showsCanvas(generation: generation) {
            item.diffractionView.showNow(image: image, generation: generation, analysis: item.diffraction)
        }
    }

    /// The pattern as the room draws it now, with the marked and simulated spots, the fitted rings and the Ring tool's annulus. When
    /// the room has not drawn the pixels shown (it is off screen, or its pass for a new pattern, a CBED pattern at another thickness or
    /// a Log switch is still to land), the door makes the room's pass at once (`DiffractionViewState.showNow`), so the picture is the
    /// pattern shown with the room's display, never an earlier canvas (#1003).
    static func diffractionPicture(_ item: OpenItem, image: CalibratedImage, side: Int) -> AgentToolOutput {
        let view = item.diffractionView, analysis = item.diffraction
        guard max(image.width, image.height) <= ImageExport.maximumSide else {
            return .refusal(status: 413, message: "The pattern is larger than \(ImageExport.maximumSide) px on a side; the picture is refused.")
        }
        showPatternNow(item, image: image)
        guard let canvas = view.presentation.canvas, canvas.width == image.width, canvas.height == image.height else {
            return .refusal(status: 404, message: "The pattern is still being drawn; ask again in a moment.")
        }
        let simulated = analysis.simulation.isShown ? ((try? item.simulatedSpots(image: image)?.get()) ?? []) : []
        let labels = Dictionary(uniqueKeysWithValues: analysis.figureReadout(image: image).map { ($0.id, ExportSnapshot.figureLabel($0)) })
        let rings = analysis.rings.compactMap { ring -> DiffractionPicture.Ring? in
            guard let ellipse = ring.ellipse else { return nil }
            return DiffractionPicture.Ring(points: RingOverlay.polyline(ellipse).map { ImagePoint(x: $0.x, y: $0.y) }, label: labels[ring.id] ?? "")
        }
        let annulus = analysis.centre.flatMap { DiffractionViewState.drawsAnnulus(url: item.url) ? $0 : nil }.map {
            DiffractionPicture.Annulus(centre: ImagePoint(x: $0.column, y: $0.row), inner: view.annulusInner, outer: view.annulusOuter)
        }
        let marks = DiffractionPicture.marks(annulus: annulus, rings: rings, spots: analysis.spots, simulated: simulated,
                                             labels: analysis.simulation.showsLabels)
        do {
            let rendered = try ImageExport.render(source: ExportSource(image: image, software: ExportSnapshot.provenance()),
                                                  display: ExportSnapshot.display(canvas: canvas, presentation: view.presentation),
                                                  marks: marks, options: ImageExport.Options(scaleBar: false, marks: true))
            return .png(smaller(rendered.png, side: side) ?? rendered.png)
        } catch {
            return .refusal(status: 500, message: "The picture could not be drawn: \(error.localizedDescription)")
        }
    }
}

/// The Diffraction picture's marks, in the room's order: the simulated spots under the measured marks, then the annulus, the fitted
/// rings and the marked spots, so a measured spot reads on top. Pure.
nonisolated enum DiffractionPicture {
    /// A fitted ring as the room draws it: its ellipse as a polyline (image pixels, x the column) and its d label.
    nonisolated struct Ring: Equatable, Sendable {
        let points: [ImagePoint]
        let label: String
    }

    /// The Ring tool's annulus about the pattern's centre, radii in pixels.
    nonisolated struct Annulus: Equatable, Sendable {
        let centre: ImagePoint
        let inner: Double
        let outer: Double
    }

    /// The points of each annulus edge.
    static let annulusPoints = 128

    /// Simulated spots as cyan rings (hkl on the room's labelled ones when `labels`); the annulus' two edges dashed white; each fitted
    /// ring as a yellow outline with its d; then each marked spot with a centre as a yellow ring numbered as the readout and the Spots
    /// table number it.
    static func marks(annulus: Annulus? = nil, rings: [Ring] = [], spots: [MeasuredSpot], simulated: [ZoneAxisOverlay.Spot],
                      labels: Bool) -> [ImageExport.Mark] {
        let labelled = labels ? Set(ZoneAxisOverlay.labelled(simulated).map(\.hkl)) : []
        var out = simulated.map { s in
            ImageExport.Mark(kind: .simulatedSpot, points: [ImagePoint(x: s.column, y: s.row)], width: 1,
                             label: labelled.contains(s.hkl) ? s.label : "")
        }
        if let annulus {
            for radius in [annulus.inner, annulus.outer] {
                let points = (0 ..< annulusPoints).map { i -> ImagePoint in
                    let phi = 2 * Double.pi * Double(i) / Double(annulusPoints)
                    return ImagePoint(x: annulus.centre.x + radius * cos(phi), y: annulus.centre.y + radius * sin(phi))
                }
                out.append(ImageExport.Mark(kind: .annulus, points: points, width: 1, label: ""))
            }
        }
        for ring in rings {
            out.append(ImageExport.Mark(kind: .ring, points: ring.points, width: 1, label: ring.label))
        }
        for (i, spot) in spots.enumerated() {
            guard let row = spot.row, let column = spot.column else { continue }
            out.append(ImageExport.Mark(kind: .spot, points: [ImagePoint(x: column, y: row)], width: 1, label: "\(i + 1)"))
        }
        return out
    }
}
