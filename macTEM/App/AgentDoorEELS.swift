//
//  AgentDoorEELS.swift
//  Role: the agent door's tools for the EELS room (#558). `get_eels` reads the room: the file and its microscope values, each stage's
//        state, every Processing and Fitting setting, the picked edges with their windows, the edges the core loss offers, the edge
//        results and the fit's quality, the regions and their rows, the notices and refusals. `get_eels_spectrum` gives the selected
//        region's spectrum as Spectrum CSV… writes it, `get_eels_maps` draws the maps as Maps… does. `set_eels`, `set_eels_edges` and
//        `set_eels_region` set the inspector's sections, the periodic table and the region through the session calls their controls
//        make (`EELSSession`). Run itself is `run_room`, the toolbar verb.
//
//        ONE SOURCE PER FACT: the spectrum and the region rows are the session's export text (`spectrumCSV`, `regionsCSV`); the maps
//        picture is `EDXMapsFigure.png` of `EELSSession.figureContent` over `EELSMapsBlock.shownMaps`, the export's own figure.
//

import Foundation
import ShellAgentDoor
import ShellEDXModel
import ShellSpectroscopy
import SpectroEDX
import SpectroEELS
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let eelsTools: [AgentTool] = [
        AgentTool(name: "get_eels", title: "EELS room",
                  summary: "What the EELS room holds: the file (low loss, core loss, one spectrum or a map), E₀, α and β and where each "
                      + "comes from, each stage's state (align, thickness, deconvolve, edges, fit: not_run, current, stale), every "
                      + "Processing and Fitting setting (in set_eels' names), the picked edges with their windows, the edges the core "
                      + "loss offers, the edge results (intensity, areal density, at% and wt% with σ, the background exponent) and the "
                      + "fit's reduced χ², the regions and their rows, the notices and why Run or the fit is refused.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            return eels(appState)
        },
        AgentTool(name: "get_eels_spectrum", title: "EELS spectrum",
                  summary: "The selected region's spectrum as Spectrum CSV… writes it (energy and counts of the low and core loss, the "
                      + "fit and its parts once fitted), and every kept region's row as Regions CSV… writes it.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let session = appState.eels
            guard session.hasImage else { return noEELS }
            guard let csv = session.spectrumCSV else {
                return .refusal(status: 404, message: "The spectrum is not drawn yet; ask again when get_eels says not busy.")
            }
            return .json(["region": session.selectedRegionName, "spectrum_csv": csv, "regions_csv": AgentJSON.orNull(session.regionsCSV)])
        },
        AgentTool(name: "get_eels_maps", title: "EELS maps",
                  summary: "The maps the room shows (the Maps control's pick: ZLP, t/λ, t, at% or wt%) as Maps… draws them, with the "
                      + "scale bar and the selected region.",
                  input: .windowPicture) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let session = appState.eels, state = appState.eelsRoom
            guard session.hasImage else { return noEELS }
            let maps = EELSMapsBlock.shownMaps(session, state)
            let chosen = Set(EELSMixComposition.selection(state.appearance.mix, maps: maps))
            guard !maps.isEmpty, let content = session.figureContent(maps: maps, mix: maps.filter { chosen.contains($0.id) },
                                                                     appearance: state.appearance, scaleBar: true, regions: true),
                  let png = EDXMapsFigure.png(content) else {
                return .refusal(status: 404, message: session.failure ?? "No map yet: Run maps the thickness (run_room).")
            }
            return .png(smaller(png, side: pictureSide * call.scale) ?? png)
        },
        said(AgentTool(name: "set_eels", title: "EELS room settings",
                       summary: "The Processing, Fitting and Maps sections; only what is given changes, and a change to a stage's input "
                           + "makes it stale (get_eels says so) until run_room runs it again. Processing: the zero-loss alignment's signal "
                           + "range and crop (align true runs Align alone), the zero-loss threshold, the deconvolution (off, fourierLog, "
                           + "fourierRatio with its zero-loss FWHM, richardsonLucy with iterations) and the mean free path (none, given in "
                           + "nm, or estimate: Iakoubovskii's from E₀, α, β and a density). Fitting: the model (exactNNLS or mlls), where "
                           + "the fit ends, the background, low-loss convolution, and E₀, α, β when the file lacks them. Maps: the segment "
                           + "and the display filter.",
                       input: .window, parameters: eelsParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.eels.hasImage else { return noEELS }
            if let refusal = applyEELS(call.arguments, appState: appState) { return refusal }
            return eels(appState)
        }),
        said(AgentTool(name: "set_eels_edges", title: "EELS edges",
                       summary: "The periodic table: add picks each element's default edge (K where bundled, else L₂,₃) to quantify, as a "
                           + "click does; remove takes all of an element's edges off; edges_add and edges_remove pick single edges by id "
                           + "(get_eels lists the offered ones, e.g. Fe-L3); fit_only keeps elements in the fit and out of the composition, "
                           + "quantify puts them back. reset_windows puts every edge's windows back to their defaults. For the MLLS model, "
                           + "reference_from_region makes an edge's reference from the selected region, remove_reference drops one by name.",
                       input: .window,
                       parameters: [
                           AgentParameter("add", .text, summary: "Element symbols, e.g. \"Fe, O\"."),
                           AgentParameter("remove", .text, summary: "Element symbols whose edges come off."),
                           AgentParameter("edges_add", .text, summary: "Edge ids, e.g. \"Fe-L3, O-K1\"."),
                           AgentParameter("edges_remove", .text, summary: "Edge ids to take off."),
                           AgentParameter("fit_only", .text, summary: "Element symbols kept out of the composition."),
                           AgentParameter("quantify", .text, summary: "Element symbols put back into the composition."),
                           AgentParameter("reset_windows", .boolean, summary: "Every edge's windows back to the defaults."),
                           AgentParameter("reference_from_region", .text, summary: "MLLS: an edge id whose reference the region gives."),
                           AgentParameter("remove_reference", .text, summary: "MLLS: a reference's name to drop."),
                       ],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.eels.hasImage else { return noEELS }
            if let refusal = applyEdges(call.arguments, to: appState.eels) { return refusal }
            return eels(appState)
        }),
        said(AgentTool(name: "set_eels_region", title: "EELS region",
                       summary: "The region the spectrum, the thickness line and the region fit are of: whole (the whole map), rectangle "
                           + "or ellipse (x0, y0, x1, y1 in map pixels, ends exclusive; kept as a numbered region, as drawing one does), "
                           + "pin (a kept region by name), or remove (a kept region by name).",
                       input: .window,
                       parameters: [
                           AgentParameter("region", .choice(["whole", "rectangle", "ellipse", "pin", "remove"]), summary: "What to do.", required: true),
                           AgentParameter("x0", .integer(0...100_000), summary: "Left pixel."),
                           AgentParameter("y0", .integer(0...100_000), summary: "Top pixel."),
                           AgentParameter("x1", .integer(1...100_000), summary: "Right end, exclusive."),
                           AgentParameter("y1", .integer(1...100_000), summary: "Bottom end, exclusive."),
                           AgentParameter("pin", .text, summary: "A kept region's name, for pin and remove."),
                       ],
                       acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let session = appState.eels
            guard session.hasImage else { return noEELS }
            let a = call.arguments
            let region = a["region"] ?? ""
            if region != "whole", session.isSingleSpectrum {
                return .refusal(status: 409, message: "This file is one spectrum: it has no map to draw a region on.")
            }
            switch region {
            case "whole":
                session.selectWholeMap()
            case "pin", "remove":
                guard let name = a["pin"], let pin = session.pins.first(where: { $0.name == name }) else {
                    return .refusal(status: 404, message: "No kept region \(a["pin"] ?? ""); the room keeps "
                        + (session.pins.isEmpty ? "none." : session.pins.map(\.name).joined(separator: ", ") + "."))
                }
                if region == "pin" { session.selectPin(pin.id) } else { session.removePin(pin.id) }
            default:
                guard let x0 = a["x0"].flatMap(Int.init), let y0 = a["y0"].flatMap(Int.init),
                      let x1 = a["x1"].flatMap(Int.init), let y1 = a["y1"].flatMap(Int.init), x1 > x0, y1 > y0 else {
                    return .refusal(status: 400, message: "A rectangle or ellipse needs x0 < x1 and y0 < y1.")
                }
                let rect = PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)
                guard session.drawRegion(region == "rectangle" ? .rectangle(rect) : .ellipse(rect)) != nil else {
                    return .refusal(status: 400, message: "That region does not touch the map.")
                }
            }
            return eels(appState)
        }),
    ]

    private static let noEELS = AgentToolOutput.refusal(
        status: 404, message: "No EELS spectrum image is open; open one first (open_demo with demo eels opens the demo spectrum image).")

    static let eelsParameters: [AgentParameter] = [
        AgentParameter("align_from", .number(-1_000...1_000), summary: "The alignment's signal range start, eV."),
        AgentParameter("align_to", .number(-1_000...1_000), summary: "The alignment's signal range end, eV."),
        AgentParameter("align_crop", .boolean, summary: "Crop the channels the shifts leave empty."),
        AgentParameter("align", .boolean, summary: "true runs Align alone, as its button does."),
        AgentParameter("threshold", .choice(["estimated", "fixed"]), summary: "The zero-loss end: estimated, or fixed at threshold_ev."),
        AgentParameter("threshold_ev", .number(0...1_000), summary: "With threshold fixed: the energy, eV."),
        AgentParameter("deconvolution", .choice(EELSDeconvolutionChoice.Kind.allCases.map(\.rawValue)), summary: "The deconvolution."),
        AgentParameter("iterations", .integer(0...10_000), summary: "richardsonLucy's iterations."),
        AgentParameter("zlp_fwhm", .number(0.001...1_000), summary: "fourierRatio's zero-loss FWHM, eV; zlp_fwhm_estimate true estimates it."),
        AgentParameter("zlp_fwhm_estimate", .boolean, summary: "true: the FWHM estimated from the zero-loss peak."),
        AgentParameter("mfp", .choice(["none", "given", "estimate"]), summary: "The mean free path λ."),
        AgentParameter("lambda_nm", .number(0.001...1_000_000), summary: "With mfp given: λ in nm."),
        AgentParameter("density", .number(0.001...100), summary: "With mfp estimate: the density, g/cm³."),
        AgentParameter("mfp_convergence", .number(0...1_000), summary: "With mfp estimate: α, mrad."),
        AgentParameter("mfp_collection", .number(0...1_000), summary: "With mfp estimate: β, mrad."),
        AgentParameter("model", .choice(EELSFitModel.allCases.map(\.rawValue)), summary: "exactNNLS or mlls."),
        AgentParameter("fit_to", .number(0...100_000), summary: "Where the fit ends, eV; fit_to_default true restores the default."),
        AgentParameter("fit_to_default", .boolean, summary: "true: the fit ends where the room's default puts it."),
        AgentParameter("background", .choice(EELSBackgroundChoice.allCases.map(\.rawValue)), summary: "The background under each edge."),
        AgentParameter("convolve", .boolean, summary: "Convolve the model with the low loss (plural scattering)."),
        AgentParameter("beam_energy", .number(0.1...10_000), summary: "E₀ in keV, where the file lacks it or is wrong."),
        AgentParameter("convergence", .number(0...1_000), summary: "α in mrad."),
        AgentParameter("collection", .number(0...1_000), summary: "β in mrad."),
        AgentParameter("maps", .choice(EELSMapsSegment.allCases.map(\.rawValue)), summary: "The Maps control: zlp, tOverLambda, thickness, atomicPercent, weightPercent."),
        AgentParameter("map_filter", .choice(EELSMapFilter.allCases.map(\.rawValue)), summary: "The maps' display filter (the picture only, never the numbers)."),
    ]

    // MARK: Answers

    static func eels(_ appState: AppState) -> AgentToolOutput {
        let session = appState.eels
        guard let source = session.source else { return noEELS }
        let availability = session.mapsAvailability
        let file = EELSFileMicroscope(source)
        let picked = session.pickedEdges.map { edge -> [String: Any] in
            let w = session.windows(for: edge)
            return ["id": EELSFitCompute.id(edge), "element": edge.element, "onset_ev": AgentJSON.number(edge.onsetEV),
                    "fit_only": session.fitOnlyElements.contains(edge.element),
                    "background_window_ev": [AgentJSON.number(w.background.lowerBound), AgentJSON.number(w.background.upperBound)],
                    "signal_window_ev": [AgentJSON.number(w.signal.lowerBound), AgentJSON.number(w.signal.upperBound)]]
        }
        var answer: [String: Any] = [
            "file_name": session.fileName,
            "one_spectrum": session.isSingleSpectrum,
            "map_size": ["width": source.image.nx, "height": source.image.ny],
            "low_loss": session.hasLowLoss, "core_loss": session.workingCoreLoss != nil,
            "beam_energy_kev": AgentJSON.number(session.beamEnergyKeV),
            "beam_energy_typed": session.typedBeamEnergyKeV != nil,
            "convergence_mrad": AgentJSON.number(session.typedConvergenceMrad ?? file?.convergenceMrad),
            "collection_mrad": AgentJSON.number(session.typedCollectionMrad ?? file?.collectionMrad),
            "stages": session.stages.map { ["stage": $0.stage.rawValue, "state": stateWord($0.state)] },
            "processing": processingAnswer(session),
            "fitting": [
                "model": session.fitModel.rawValue, "fit_to": AgentJSON.number(session.fitToEV), "background": session.backgroundChoice.rawValue,
                "convolve": session.effectiveConvolve, "blocker": AgentJSON.orNull(session.fitBlocker),
                "refusal": AgentJSON.orNull(session.fitRefusal), "fit_to_notice": AgentJSON.orNull(session.fitToNotice),
                "background_notice": AgentJSON.orNull(session.backgroundNotice),
                "references": session.references.map(\.name), "reference_notice": AgentJSON.orNull(session.referenceNotice),
            ] as [String: Any],
            "picked_edges": picked,
            "offered_edges": session.offeredEdges.map { EELSFitCompute.id($0) },
            "edge_refusals": session.refusals.map { ["edge": EELSFitCompute.id($0.edge), "reason": $0.reason] },
            "results": session.resultRows.map(edgeRow),
            "fit_quality": AgentJSON.orNull(session.resultQuality.map { q -> [String: Any] in
                ["reduced_chi_squared": AgentJSON.number(q.reducedChiSquared), "rss": AgentJSON.number(q.rss), "channels": q.channels,
                 "parameters": q.parameters, "chi_squared_unavailable": AgentJSON.orNull(q.chiSquaredUnavailable)]
            }),
            "region": session.selectedRegionName,
            "regions": session.pins.map { pin -> [String: Any] in
                ["name": pin.name, "kind": pin.region.shapeName, "selected": pin.id == session.selectedPinID]
            },
            "region_rows": session.pinRows.map { row -> [String: Any] in
                ["region": row.pin.name, "pixels": row.pixels, "total_counts": AgentJSON.number(row.totalCounts),
                 "t_over_lambda": AgentJSON.number(row.tOverLambda), "t_unavailable": AgentJSON.orNull(row.tUnavailable),
                 "edges": row.edges.map(edgeRow), "edges_unavailable": AgentJSON.orNull(row.edgesUnavailable)]
            },
            "maps": appState.eelsRoom.maps.rawValue,
            "maps_shown": availability.effective(appState.eelsRoom.maps).rawValue,
            "maps_off": EELSMapsSegment.allCases.compactMap { s in availability.disabledReason(s).map { ["maps": s.rawValue, "reason": $0] } },
            "map_filter": appState.eelsRoom.mapFilter.rawValue,
            "mean_free_path_nm": AgentJSON.number(session.map?.meanFreePathNM),
            "can_run": session.canRun,
            "failure": AgentJSON.orNull(session.failure),
            "busy": session.isBusy,
            "computing": AgentJSON.orNull(session.computingStage?.rawValue),
            "progress": AgentJSON.number(session.isComputing ? session.progress : nil),
        ]
        answer["alignment"] = AgentJSON.orNull(session.alignmentReadout)
        answer["thickness_line"] = EELSRoomFormat.thicknessLine(session.plot?.thickness, lambdaNM: session.map?.meanFreePathNM,
                                                                lambdaSource: EELSRoomFormat.lambdaSource(session.meanFreePath),
                                                                locale: Locale(identifier: "en_US_POSIX"))
        answer["methods"] = EELSLiterature.tooltip
        return .json(answer)
    }

    private static func processingAnswer(_ session: EELSSession) -> [String: Any] {
        var threshold: Any = "estimated", thresholdEV: Any = NSNull()
        if case .fixed(let eV) = session.threshold { threshold = "fixed"; thresholdEV = AgentJSON.number(eV) }
        var mfp: [String: Any] = [:]
        switch session.meanFreePath {
        case .none: mfp = ["mfp": "none"]
        case .given(let nm): mfp = ["mfp": "given", "lambda_nm": AgentJSON.number(nm)]
        case .iakoubovskii(let rho, let alpha, let beta):
            mfp = ["mfp": "estimate", "density": AgentJSON.number(rho), "mfp_convergence": AgentJSON.number(alpha),
                   "mfp_collection": AgentJSON.number(beta), "blocker": AgentJSON.orNull(session.lambdaEstimateBlocker)]
        }
        var iterations: Any = NSNull()
        if case .richardsonLucy(let n) = session.deconvolutionChoice { iterations = n }
        let range = session.alignChoice.signalRangeEV
        return [
            "align_from": AgentJSON.number(range.lowerBound), "align_to": AgentJSON.number(range.upperBound),
            "align_crop": session.alignChoice.crop, "align_notice": AgentJSON.orNull(session.alignNotice),
            "threshold": threshold, "threshold_ev": thresholdEV,
            "deconvolution": session.deconvolutionChoice.kind.rawValue, "iterations": iterations,
            "zlp_fwhm": AgentJSON.number(session.zeroLossFWHM), "deconvolution_notice": AgentJSON.orNull(session.deconvolutionNotice),
            "mean_free_path": mfp,
        ]
    }

    private static func edgeRow(_ row: EELSEdgeRow) -> [String: Any] {
        ["edge": row.id, "title": row.title, "onset_ev": AgentJSON.number(row.onsetEV), "intensity": AgentJSON.number(row.intensity),
         "intensity_sigma": AgentJSON.number(row.intensityStd), "areal_density_per_nm2": AgentJSON.number(row.arealDensityPerNM2),
         "atomic_percent": AgentJSON.number(row.atomicPercent), "atomic_percent_sigma": AgentJSON.number(row.atomicSigma),
         "weight_percent": AgentJSON.number(row.weightPercent), "background_exponent": AgentJSON.number(row.exponent),
         "exponent_at_bound": row.exponentAtBound, "fit_only": row.fitOnly,
         "unavailable": AgentJSON.orNull(row.unavailable), "atomic_unavailable": AgentJSON.orNull(row.atomicUnavailable)]
    }

    // MARK: Setting

    /// `set_eels`: Processing, then Fitting, then the Maps section, through the calls their controls make.
    static func applyEELS(_ a: [String: String], appState: AppState) -> AgentToolOutput? {
        let session = appState.eels
        let flag = { (key: String) -> Bool? in a[key].map { $0 == "true" } }
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        if a["align_from"] != nil || a["align_to"] != nil {
            let range = session.alignChoice.signalRangeEV
            let from = number("align_from") ?? range.lowerBound, to = number("align_to") ?? range.upperBound
            guard from < to else { return .refusal(status: 400, message: "The signal range must run upward (\(from) to \(to) eV).") }
            session.setAlignSignalRange(fromEV: from, toEV: to)
        }
        if let v = flag("align_crop") { session.setAlignCrop(v) }
        switch a["threshold"] {
        case "estimated": session.setThreshold(.estimated)
        case "fixed":
            guard let eV = number("threshold_ev") else { return .refusal(status: 400, message: "threshold fixed needs threshold_ev.") }
            session.setThreshold(.fixed(eV))
        default:
            if let eV = number("threshold_ev") { session.setThreshold(.fixed(eV)) }
        }
        if let word = a["deconvolution"], let kind = EELSDeconvolutionChoice.Kind(rawValue: word) {
            var iterations = 15
            if case .richardsonLucy(let n) = session.deconvolutionChoice { iterations = n }
            session.setDeconvolution(.make(kind, iterations: a["iterations"].flatMap(Int.init) ?? iterations))
        } else if let n = a["iterations"].flatMap(Int.init) {
            guard case .richardsonLucy = session.deconvolutionChoice else {
                return .refusal(status: 409, message: "iterations are richardsonLucy's; set deconvolution richardsonLucy with them.")
            }
            session.setDeconvolution(.richardsonLucy(iterations: n))
        }
        if flag("zlp_fwhm_estimate") == true { session.setZeroLossFWHM(nil) } else if let v = number("zlp_fwhm") { session.setZeroLossFWHM(v) }
        if let refusal = applyMeanFreePath(a, to: session) { return refusal }
        if let v = a["model"].flatMap(EELSFitModel.init(rawValue:)) { session.setFitModel(v) }
        if flag("fit_to_default") == true { session.setFitTo(nil) } else if let v = number("fit_to") { session.setFitTo(v) }
        if let v = a["background"].flatMap(EELSBackgroundChoice.init(rawValue:)) {
            if let why = v.disabledReason { return .refusal(status: 409, message: "\(v.title) is off: \(why)") }
            session.setBackground(v)
        }
        if let v = flag("convolve") { session.setConvolveLowLoss(v) }
        if let v = number("beam_energy") { session.setBeamEnergy(v) }
        if let v = number("convergence") { session.setConvergence(v) }
        if let v = number("collection") { session.setCollection(v) }
        if let v = a["maps"].flatMap(EELSMapsSegment.init(rawValue:)) {
            if let why = session.mapsAvailability.disabledReason(v) { return .refusal(status: 409, message: "\(v.title) maps are off: \(why)") }
            appState.eelsRoom.maps = v
            appState.eelsRoom.mapsNotice = nil
        }
        if let v = a["map_filter"].flatMap(EELSMapFilter.init(rawValue:)) { appState.eelsRoom.mapFilter = v }
        if flag("align") == true {
            guard session.hasLowLoss else { return .refusal(status: 409, message: "Align needs a low loss; this file holds none.") }
            session.align()
        }
        return nil
    }

    private static func applyMeanFreePath(_ a: [String: String], to session: EELSSession) -> AgentToolOutput? {
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        var rho = 2.7, alpha = 0.0, beta = 0.0
        if case .iakoubovskii(let r, let c, let b) = session.meanFreePath { rho = r; alpha = c; beta = b }
        switch a["mfp"] {
        case "none": session.setMeanFreePath(.none)
        case "given":
            guard let nm = number("lambda_nm") ?? { if case .given(let nm) = session.meanFreePath { return nm } else { return nil } }() else {
                return .refusal(status: 400, message: "mfp given needs lambda_nm.")
            }
            session.setMeanFreePath(.given(nanometres: nm))
        case "estimate":
            if let why = session.lambdaEstimateBlocker { return .refusal(status: 409, message: why) }
            session.setMeanFreePath(.iakoubovskii(density: number("density") ?? rho, convergenceMrad: number("mfp_convergence") ?? alpha,
                                                  collectionMrad: number("mfp_collection") ?? beta))
        default:
            if let nm = number("lambda_nm") { session.setMeanFreePath(.given(nanometres: nm)) }
            if a["density"] != nil || a["mfp_convergence"] != nil || a["mfp_collection"] != nil {
                guard case .iakoubovskii = session.meanFreePath else {
                    return .refusal(status: 409, message: "density, mfp_convergence and mfp_collection are the estimate's; set mfp estimate with them.")
                }
                session.setMeanFreePath(.iakoubovskii(density: number("density") ?? rho, convergenceMrad: number("mfp_convergence") ?? alpha,
                                                      collectionMrad: number("mfp_collection") ?? beta))
            }
        }
        return nil
    }

    /// `set_eels_edges`: the periodic table's picks, roles and windows, and the MLLS references.
    static func applyEdges(_ a: [String: String], to session: EELSSession) -> AgentToolOutput? {
        let list = { (key: String) -> [String] in
            (a[key] ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty }
        }
        let offered = session.offeredEdges
        let window = session.workingCoreLoss.map(EELSEdgeChoices.window(of:))
        let edge = { (id: String) -> CoreLossEdge? in offered.first { EELSFitCompute.id($0) == id } ?? session.pickedEdges.first { EELSFitCompute.id($0) == id } }
        for symbol in list("add") {
            if let why = EELSEdgeChoices.unavailableReason(symbol: symbol, offered: offered, hasCoreLoss: session.workingCoreLoss != nil, windowEV: window) {
                return .refusal(status: 409, message: "\(symbol): \(why).")
            }
        }
        for id in list("edges_add") + list("edges_remove") + list("reference_from_region") where edge(id) == nil {
            return .refusal(status: 404, message: "No edge \(id) here; the core loss offers " + offered.map { EELSFitCompute.id($0) }.joined(separator: ", ") + ".")
        }
        for symbol in list("add") where !session.pickedEdges.contains(where: { $0.element == symbol }) {
            if let picked = EELSEdgeChoices.defaultEdge(symbol: symbol, offered: offered) { session.toggleEdge(picked) }
        }
        for symbol in list("remove") {
            for picked in session.pickedEdges where picked.element == symbol { session.toggleEdge(picked) }
        }
        for id in list("edges_add") { if let e = edge(id), !session.pickedEdges.contains(e) { session.toggleEdge(e) } }
        for id in list("edges_remove") { if let e = edge(id), session.pickedEdges.contains(e) { session.toggleEdge(e) } }
        for symbol in list("fit_only") {
            guard session.pickedEdges.contains(where: { $0.element == symbol }) else {
                return .refusal(status: 409, message: "\(symbol) has no picked edge; add it first.")
            }
            session.setFitOnly(symbol, true)
        }
        for symbol in list("quantify") { session.setFitOnly(symbol, false) }
        if a["reset_windows"] == "true" { session.resetAllWindows() }
        if let id = list("reference_from_region").first, let e = edge(id) {
            guard session.addReferenceFromRegion(edge: e) != nil else {
                return .refusal(status: 409, message: session.referenceNotice ?? "The region gives no reference for \(id).")
            }
        }
        if let name = a["remove_reference"] {
            guard let reference = session.references.first(where: { $0.name == name }) else {
                return .refusal(status: 404, message: "No reference \(name); the room holds "
                    + (session.references.isEmpty ? "none." : session.references.map(\.name).joined(separator: ", ") + "."))
            }
            session.removeReference(reference.id)
        }
        return nil
    }
}
