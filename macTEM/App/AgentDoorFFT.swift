//
//  AgentDoorFFT.swift
//  Role: the agent door's tools for the FFT room (#558). `get_fft` reads the room for the file shown: the region transformed, what
//        is done to it first, Δq and the Nyquist frequency, the spots with d, |q|, the angle to the first and the neighbour flag, the
//        spot finder's settings, the masked inverse and the HRTEM filters with their last run. `get_fft_data` gives the radial
//        profile or the spots as their CSV exports write them; `get_fft_picture` the transform as Transform PNG… draws it, or what
//        the source pane shows. `set_fft` sets the inspector's Region, Display, Masked Inverse and HRTEM Filters sections and
//        presses Filter; `set_fft_spots` finds spots, measures one at a bin as Measure at… does, selects, removes and puts spots in
//        or out of the mask.
//
//        ONE SOURCE PER FACT: the spot words are `FFTRoomFormat`'s, the CSVs `RadialProfileCSV.text` and `SpotsCSV.text` of the export
//        snapshots, the transform picture the snapshot's display and rings through `ImageExport.render`, the source picture
//        `FFTSourceLayer.make`, the layer the pane draws. Every change goes through `FFTAnalysis`' intents as the controls' do.
//
//        The room hands its file to the analysis when it shows it (`FFTRoom`'s task); a tool does the same when the analysis has not
//        been handed this file's pixels yet, so the room's numbers are there whether or not its view has drawn.
//

import Foundation
import ImagoCore
import ImagoFFT
import ImagoFilters
import ShellAgentDoor
import ShellMetal
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let fftTools: [AgentTool] = [
        AgentTool(name: "get_fft", title: "FFT room",
                  summary: "What the FFT room holds for the file shown: the region transformed (or the whole image), the window, "
                      + "smoothing and band-pass applied first, Δq and the Nyquist frequency, the spots (numbered; each with its bin "
                      + "from the centre, d, |q|, the angle to the first measured spot, the close-neighbour flag, whether it is in the "
                      + "mask, or why it was not measured), the spot finder's settings, the masked inverse, the HRTEM filters' "
                      + "parameters and last run, what the source pane shows and what is computing.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch fftItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item): return .json(fft(item))
            }
        },
        AgentTool(name: "get_fft_data", title: "FFT room numbers",
                  summary: "which radial_profile (the mean |F|² per |q| bin, as Radial profile CSV… writes it) or spots (the measured "
                      + "spots as Spots CSV… writes them: d, |q|, qx, qy, in the mask), provenance lines first.",
                  input: .window,
                  parameters: [AgentParameter("which", .choice(["radial_profile", "spots"]), summary: "The numbers to give.", required: true)]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let item: OpenItem
            switch fftItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let found): item = found
            }
            guard let image = item.session.image else { return noFFTImage }
            if call.arguments["which"] == "spots" {
                guard let snapshot = ExportSnapshot.spotsSnapshot(image: image, url: item.url, analysis: item.fft,
                                                                  software: ExportSnapshot.provenance()),
                      let text = SpotsCSV.text(rows: snapshot.rows, omitted: snapshot.omitted, maskRadius: snapshot.maskRadius,
                                               maskEdge: snapshot.maskEdge, notes: snapshot.notes, header: snapshot.header) else {
                    return .refusal(status: 404, message: "No measured spot on the transform shown: Find Spots or measure one (set_fft_spots).")
                }
                return .json(["csv": text, "spots": snapshot.rows.count, "omitted": snapshot.omitted])
            }
            guard let snapshot = ExportSnapshot.radialProfileSnapshot(image: image, url: item.url, analysis: item.fft,
                                                                      software: ExportSnapshot.provenance()),
                  let text = RadialProfileCSV.text(snapshot.profile, header: snapshot.header) else {
                return .refusal(status: 404, message: item.fft.isSpectrumCurrent
                    ? FFTRoomFormat.profileUnavailable : "The transform is still being computed; ask again when get_fft says current.")
            }
            return .json(["csv": text, "bins": snapshot.bins])
        },
        AgentTool(name: "get_fft_picture", title: "FFT room picture",
                  summary: "which transform (the power spectrum as Transform PNG… draws it, in the Display window, with a reciprocal "
                      + "scale bar and a numbered ring per measured spot, resampled to the pane's shape when the bins are not square) "
                      + "or source (what the source pane shows: the file, the region alone, the masked inverse, ABSF or Wiener, as "
                      + "set_fft view picks).",
                  input: .windowPicture,
                  parameters: [AgentParameter("which", .choice(["transform", "source"]), summary: "The pane to draw.", required: true)]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let item: OpenItem
            switch fftItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let found): item = found
            }
            return fftPicture(item, which: call.arguments["which"] ?? "", side: pictureSide * call.scale)
        },
        said(AgentTool(name: "set_fft", title: "FFT room settings",
                       summary: "The FFT room's inspector, only those given. region \"x y size\" in image pixels (an even square of at "
                           + "least 32 px inside the image), centred (Use Centred Square) or whole (Clear Region); window, smoothing "
                           + "with sigma, bandpass with low_sigma or cutoff (applied before the transform; they replace the spots); "
                           + "view (what the source pane shows); mask_radius and mask_edge (bins); finder_threshold (a fraction of "
                           + "the display range), finder_distance (bins) and finder_count (Find Spots' settings); the HRTEM filters' "
                           + "delta, step, cycles, filter_smoothing, order, ro and low_frequency, and filter true to run them (answers "
                           + "at once; get_fft says filtering, then the source pane shows ABSF).",
                       input: .window, parameters: fftParameters, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch fftItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                if let refusal = applyFFT(call.arguments, to: item) { return refusal }
                return .json(fft(item))
            }
        }),
        said(AgentTool(name: "set_fft_spots", title: "FFT spots",
                       summary: "The Spots section. find true presses Find Spots (the finder's strongest reflections replace the spots, "
                           + "each measured as a click would be; answers at once, get_fft says finding). measure_at \"kx ky\" measures "
                           + "the bin that many whole bins from the centre, as Measure at… and a click on the transform do. select picks "
                           + "a spot by number; remove takes numbers (\"2, 3\") or all; in_mask and out_of_mask take numbers, as the "
                           + "rows' In Mask boxes.",
                       input: .window,
                       parameters: [
                           AgentParameter("find", .boolean, summary: "Find Spots."),
                           AgentParameter("measure_at", .text, summary: "\"kx ky\": whole bins from the centre."),
                           AgentParameter("select", .integer(1...100_000), summary: "The spot to select, by number."),
                           AgentParameter("remove", .text, summary: "Spot numbers to remove, or all."),
                           AgentParameter("in_mask", .text, summary: "Spot numbers the masked inverse passes."),
                           AgentParameter("out_of_mask", .text, summary: "Spot numbers the masked inverse leaves out."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch fftItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item):
                if let refusal = applySpots(call.arguments, to: item.fft) { return refusal }
                return .json(fft(item))
            }
        }),
    ]

    /// The file the FFT room shows, or why a tool cannot work on it.
    enum FFTFound {
        case item(OpenItem)
        case refused(AgentToolOutput)
    }

    private static let noFFTImage = AgentToolOutput.refusal(
        status: 404, message: "No image is shown; open one first (open_demo with demo lattice opens the demo lattice image).")

    /// The file the FFT room shows, its analysis handed the file's pixels as the room's view hands them; refused outside the room.
    static func fftItem(_ appState: AppState) -> FFTFound {
        guard let item = appState.openItems.selected, let image = item.session.image, let canvas = item.presentation.canvas else {
            return .refused(noFFTImage)
        }
        guard appState.navigation.workspaceArea == .fft else {
            return .refused(.refusal(status: 409, message: "The window shows the \(appState.navigation.workspaceArea.title) "
                + "room; select_room fft first."))
        }
        if item.fft.wantedSpectrumKey?.contentVersion != canvas.contentVersion {
            item.fft.show(image, contentVersion: canvas.contentVersion)
        }
        return .item(item)
    }

    static let fftParameters: [AgentParameter] = [
        AgentParameter("region", .text, summary: "\"x y size\" in image pixels, centred, or whole."),
        AgentParameter("taper", .choice(FFTPreprocess.Window.allCases.map(\.rawValue)), summary: "The Window menu: the taper before the transform."),
        AgentParameter("smoothing", .choice(["none", "gaussian"]), summary: "Gaussian smoothing before the transform."),
        AgentParameter("sigma", .number(0.1...50), summary: "The smoothing's σ, px."),
        AgentParameter("bandpass", .choice(["none", "differenceOfGaussians", "highPass", "lowPass"]), summary: "The band-pass before the transform."),
        AgentParameter("low_sigma", .number(0.1...50), summary: "Difference of Gaussians' low σ, px."),
        AgentParameter("cutoff", .number(0.001...0.5), summary: "Butterworth's cutoff, a fraction of Nyquist."),
        AgentParameter("view", .choice(FFTAnalysis.SourceView.allCases.map(\.rawValue)), summary: "What the source pane shows."),
        AgentParameter("mask_radius", .number(FFTMask.radiusRange), summary: "The mask's radius round each spot, bins."),
        AgentParameter("mask_edge", .number(FFTMask.edgeRange), summary: "The mask's soft edge beyond the radius, bins."),
        AgentParameter("finder_threshold", .number(0.05...0.99), summary: "Find Spots: how far above the display's minimum, a fraction."),
        AgentParameter("finder_distance", .integer(2...64), summary: "Find Spots: the least distance between two spots, bins."),
        AgentParameter("finder_count", .integer(1...40), summary: "Find Spots: the most spots."),
        AgentParameter("delta", .number(FFTRoomFormat.FilterParameter.delta.range), summary: "HRTEM filters: Delta, %."),
        AgentParameter("step", .number(FFTRoomFormat.FilterParameter.step.range), summary: "HRTEM filters: Step."),
        AgentParameter("cycles", .integer(1...99), summary: "HRTEM filters: Cycles."),
        AgentParameter("filter_smoothing", .boolean, summary: "HRTEM filters: the Butterworth low-pass on both masks."),
        AgentParameter("order", .integer(1...20), summary: "HRTEM filters: the low-pass's order."),
        AgentParameter("ro", .number(FFTRoomFormat.FilterParameter.ro.range), summary: "HRTEM filters: the low-pass's half-point radius."),
        AgentParameter("low_frequency", .number(FFTRoomFormat.FilterParameter.lowFrequency.range), summary: "HRTEM filters: Low frequency, %."),
        AgentParameter("filter", .boolean, summary: "Press Filter (ABSF and Wiener)."),
        AgentParameter("strain_reference", .choice(FFTStrainReference.allCases.map(\.rawValue)),
                       summary: "Strain: the window taken as undistorted, the whole region or its centred quarter."),
        AgentParameter("strain", .boolean, summary: "Press Map Strain (GPA with the first two measured spots as g1 and g2)."),
    ]

    private static let fftPoint = Locale(identifier: "en_US_POSIX")

    // MARK: Answers

    static func fft(_ item: OpenItem) -> [String: Any] {
        let analysis = item.fft, image = item.session.imageOrBlank
        let p = analysis.preprocess
        var preprocess: [String: Any] = ["taper": p.window.rawValue, "smoothing": "none", "sigma": NSNull(), "bandpass": "none",
                                         "low_sigma": NSNull(), "cutoff": NSNull(), "summary": AgentJSON.orNull(p.isNone ? nil : p.summary)]
        if case .gaussian(let s) = p.smoothing { preprocess["smoothing"] = "gaussian"; preprocess["sigma"] = s }
        switch p.bandpass {
        case .none: break
        case .differenceOfGaussians(let low): preprocess["bandpass"] = "differenceOfGaussians"; preprocess["low_sigma"] = low
        case .butterworth(let c, let high): preprocess["bandpass"] = high ? "highPass" : "lowPass"; preprocess["cutoff"] = c
        }
        let region = analysis.region
        var answer: [String: Any] = [
            "file_name": item.url.lastPathComponent, "width": image.width, "height": image.height,
            "region": AgentJSON.orNull(region.map { ["x": $0.col, "y": $0.row, "size": $0.width] }),
            "transformed": FFTRoomFormat.transformed(region, imageWidth: image.width, imageHeight: image.height),
            "centred_square": AgentJSON.orNull(FFTRegion.centredSquare(width: image.width, height: image.height).map { ["x": $0.col, "y": $0.row, "size": $0.width] }),
            "preprocess": preprocess,
            "view": analysis.sourceView.rawValue,
            "views": FFTSourceViewControl.entries(for: analysis).map { ["view": $0.view.rawValue, "title": $0.title, "available": $0.isEnabled] as [String: Any] },
            "spectrum_failure": AgentJSON.orNull(analysis.spectrumFailure),
            "current": analysis.isSpectrumCurrent,
            "computing": !analysis.isSpectrumCurrent && analysis.spectrumFailure == nil,
        ]
        if let s = analysis.spectrum {
            let steps = FFTRoomFormat.frequencySteps(spacingX: s.spacingX, unitsX: s.unitsX, spacingY: s.spacingY, unitsY: s.unitsY,
                                                     locale: fftPoint)
            answer["spectrum"] = [
                "width": s.width, "height": s.height, "delta_q_x": steps.x, "delta_q_y": steps.y,
                "nyquist_x": FFTRoomFormat.nyquist(spacing: s.spacingX, count: s.width, units: s.unitsX, locale: fftPoint),
                "nyquist_y": FFTRoomFormat.nyquist(spacing: s.spacingY, count: s.height, units: s.unitsY, locale: fftPoint),
                "radial_profile_bins": AgentJSON.orNull(s.profile?.points.count),
            ] as [String: Any]
        } else {
            answer["spectrum"] = NSNull()
        }
        answer["spots"] = spots(analysis, image: image)
        answer["mask"] = [
            "radius": analysis.maskRadius, "edge": analysis.maskEdge, "summary": FFTRoomFormat.maskSummary(analysis.spots),
            "current": analysis.isMaskedInverseCurrent, "failure": AgentJSON.orNull(analysis.maskFailure),
        ] as [String: Any]
        let f = analysis.filterParameters
        answer["filter"] = [
            "delta": f.delta, "step": f.step, "cycles": f.cycles, "filter_smoothing": f.smoothing, "order": f.order, "ro": f.ro,
            "low_frequency": f.lowFrequencyPercent, "filtering": analysis.isFiltering, "failure": AgentJSON.orNull(analysis.filterFailure),
            "last_run": AgentJSON.orNull(analysis.filtered.map {
                ["size": $0.n, "passes": $0.passes, "final_delta": AgentJSON.number($0.finalDelta),
                 "status": FFTRoomFormat.filterStatus(n: $0.n, passes: $0.passes, finalDelta: $0.finalDelta, locale: fftPoint)] as [String: Any]
            }),
        ] as [String: Any]
        answer["strain"] = strain(analysis)
        return answer
    }

    /// The Strain section as the room shows it, with each map's drawn range (± the 99th percentile of its magnitudes, the plates'):
    /// strain in %, rotation in degrees, clockwise positive on screen.
    private static func strain(_ analysis: FFTAnalysis) -> [String: Any] {
        let reflections = analysis.strainReflections
        return [
            "reference": analysis.strainReference.rawValue,
            "spots": AgentJSON.orNull(reflections.map { [$0.0.spot, $0.1.spot] }),
            "computing": analysis.isComputingStrain, "failure": AgentJSON.orNull(analysis.strainFailure),
            "validation": strainValidationNote,
            "last_run": AgentJSON.orNull(analysis.strain.map { product -> [String: Any] in
                func largest(_ c: FFTStrainProduct.Component, _ scale: Double) -> Any {
                    AgentJSON.number(product.canvas(c).rawRange.map { Double($0.upperBound) * scale })
                }
                return [
                    "spots": [product.key.g1.spot, product.key.g2.spot],
                    "g1": [product.key.g1.row, product.key.g1.column], "g2": [product.key.g2.row, product.key.g2.column],
                    "exx_range_percent": largest(.exx, 100), "eyy_range_percent": largest(.eyy, 100),
                    "exy_range_percent": largest(.exy, 100), "rotation_range_degrees_clockwise": largest(.rotation, 180 / .pi),
                    "pixels_without_phase": product.unmeasured, "status": FFTRoomFormat.strainStatus(product),
                ]
            }),
        ]
    }

    private static func spots(_ analysis: FFTAnalysis, image: CalibratedImage) -> [String: Any] {
        let spots = analysis.spots, angles = FFTSpotAngles.angles(spots)
        let width = analysis.spectrum?.width ?? 0, height = analysis.spectrum?.height ?? 0
        let rows: [[String: Any]] = spots.map { spot in
            var row: [String: Any] = [
                "number": spot.number, "kx": spot.col - width / 2, "ky": spot.row - height / 2,
                "selected": spot.id == analysis.selection, "in_mask": spot.inMask && spot.measured != nil,
                "contrast": AgentJSON.number(spot.contrast),
            ]
            switch spot.outcome {
            case .measuring:
                row["state"] = "measuring"
            case .measured(let m):
                row["state"] = "measured"
                row["d"] = AgentJSON.number(m.d); row["d_unit"] = m.units
                row["q"] = AgentJSON.number(m.q); row["q_unit"] = m.reciprocalUnits
                row["neighbour"] = m.neighbour
                row["value"] = FFTRoomFormat.spotValue(spot, locale: fftPoint)
                row["angle_degrees"] = AgentJSON.number(angles[spot.id]?.degrees)
                row["angle_to_spot"] = AgentJSON.orNull(angles[spot.id]?.reference)
            case .refused(let failure):
                row["state"] = "refused"
                row["refusal"] = FFTRoomFormat.refusal(failure)
            }
            return row
        }
        var notes: [String] = []
        if spots.contains(where: { $0.measured != nil }), let key = spots.last?.spectrumKey {
            notes.append(FFTRoomFormat.measuredOn(key.crop, imageWidth: image.width, imageHeight: image.height))
            if spots.contains(where: { $0.measured?.neighbour == true }) { notes.append(FFTRoomFormat.neighbourNote) }
            if let accuracy = FFTRoomFormat.accuracyNote(width: key.crop?.width ?? image.width, height: key.crop?.height ?? image.height,
                                                         locale: fftPoint) {
                notes.append(accuracy)
            }
        }
        let finder = analysis.spotFinder
        return [
            "list": rows, "notes": notes,
            "finder": ["threshold": finder.thresholdFraction, "distance": finder.minDistance, "count": finder.count] as [String: Any],
            "finding": analysis.isFindingSpots, "find_failure": AgentJSON.orNull(analysis.findSpotsFailure),
            "measure_at_range": AgentJSON.orNull(width > 0 ? FFTRoomFormat.binRange(width: width, height: height) : nil),
        ]
    }

    static func fftPicture(_ item: OpenItem, which: String, side: Int) -> AgentToolOutput {
        let analysis = item.fft
        guard let image = item.session.image else { return noFFTImage }
        do {
            let rendered: ImageExport.Rendered
            if which == "source" {
                guard let canvas = item.presentation.canvas,
                      let layer = FFTSourceLayer.make(analysis.sourceView, original: canvas, colormap: item.presentation.colormap,
                                                      window: item.presentation.displayFractions, gamma: Float(item.presentation.gamma),
                                                      spectrum: analysis.spectrum, inverse: analysis.maskedInverse, filtered: analysis.filtered,
                                                      strain: analysis.strain) else {
                    return .refusal(status: 404, message: "The \(analysis.sourceView.rawValue) view has nothing to show yet; get_fft says what is computing.")
                }
                let shown = layer.canvas
                let picture = CalibratedImage(width: shown.width, height: shown.height, pixels: shown.normalized, x: image.x, y: image.y,
                                              fileName: image.fileName, source: "FFT room source pane, \(analysis.sourceView.rawValue)",
                                              voltage: image.voltage, notes: [])
                let display = ImageExport.Display(normalized: shown.normalized, width: shown.width, height: shown.height,
                                                  low: layer.window.low, high: layer.window.high, gamma: Double(layer.gamma),
                                                  lut: Colormaps.lutRGBA(layer.colormap), colormap: layer.colormap.rawValue,
                                                  rawRange: shown.rawRange)
                rendered = try ImageExport.render(source: ExportSource(image: picture, software: ExportSnapshot.provenance()), display: display,
                                                  marks: [], options: ImageExport.Options(scaleBar: true, marks: false))
            } else {
                guard let snapshot = ExportSnapshot.transformSnapshot(image: image, url: item.url, analysis: analysis,
                                                                      software: ExportSnapshot.provenance()) else {
                    return .refusal(status: 404, message: analysis.spectrumFailure ?? "The transform is still being computed; ask again when get_fft says current.")
                }
                let shown = snapshot.offersAsShown
                    ? FFTExport.asShown(display: snapshot.display, marks: snapshot.marks, header: snapshot.header)
                    : (display: snapshot.display, marks: snapshot.marks, header: snapshot.header)
                rendered = try ImageExport.render(source: FFTExport.transformSource(shown.header), display: shown.display, marks: shown.marks,
                                                  options: ImageExport.Options(scaleBar: true, marks: true))
            }
            return .png(smaller(rendered.png, side: side) ?? rendered.png)
        } catch {
            return .refusal(status: 500, message: "The picture could not be drawn: \(error.localizedDescription)")
        }
    }

    // MARK: Acting

    /// `set_fft`: every check first, so a refused call changes nothing; then the region, the preprocess, the view, the mask, the
    /// finder and the filters through the analysis' intents.
    static func applyFFT(_ a: [String: String], to item: OpenItem) -> AgentToolOutput? {
        let analysis = item.fft
        guard let image = item.session.image else { return noFFTImage }
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        var region: PixelCrop??
        if let words = a["region"] {
            switch words.trimmingCharacters(in: .whitespaces) {
            case "whole": region = .some(nil)
            case "centred":
                guard let centred = FFTRegion.centredSquare(width: image.width, height: image.height) else {
                    return .refusal(status: 409, message: FFTRoomFormat.noRegionPossible)
                }
                region = .some(centred)
            default:
                let n = words.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int(String($0)) }
                guard n.count == 3 else { return .refusal(status: 400, message: "region takes \"x y size\", centred or whole.") }
                let crop = PixelCrop(row: n[1], col: n[0], height: n[2], width: n[2])
                guard FFTRegion.isValid(crop, width: image.width, height: image.height) else {
                    return .refusal(status: 400, message: "A region is an even square of at least 32 px inside the \(image.width) × \(image.height) image.")
                }
                region = .some(crop)
            }
        }
        if a["sigma"] != nil, a["smoothing"] != "gaussian", !isGaussian(analysis.preprocess.smoothing) {
            return .refusal(status: 409, message: "sigma is the Gaussian smoothing's; set smoothing gaussian with it.")
        }
        let band = a["bandpass"] ?? bandWord(analysis.preprocess.bandpass)
        if a["low_sigma"] != nil, band != "differenceOfGaussians" {
            return .refusal(status: 409, message: "low_sigma is the Difference of Gaussians'; set bandpass differenceOfGaussians with it.")
        }
        if a["cutoff"] != nil, band != "highPass", band != "lowPass" {
            return .refusal(status: 409, message: "cutoff is a Butterworth band-pass's; set bandpass highPass or lowPass with it.")
        }
        if let view = a["view"].flatMap(FFTAnalysis.SourceView.init(rawValue:)),
           let entry = FFTSourceViewControl.entries(for: analysis).first(where: { $0.view == view }), !entry.isEnabled,
           !(a["filter"] == "true" && (view == .absf || view == .wiener)),
           !(a["strain"] == "true" && view.strainComponent != nil) {
            return .refusal(status: 409, message: "\(entry.title) is not available yet: it needs " + needs(view) + ".")
        }

        if let region { analysis.setRegion(region, committed: true) }
        var p = analysis.preprocess
        if let w = a["taper"].flatMap(FFTPreprocess.Window.init(rawValue:)) { p.window = w }
        if let s = a["smoothing"] {
            p.smoothing = s == "gaussian" ? .gaussian(sigma: number("sigma") ?? sigmaOf(p.smoothing)) : .none
        } else if let s = number("sigma") {
            p.smoothing = .gaussian(sigma: s)
        }
        switch band {
        case "differenceOfGaussians":
            let current: Double = if case .differenceOfGaussians(let l) = p.bandpass { l } else { 2 }
            p.bandpass = .differenceOfGaussians(lowSigma: number("low_sigma") ?? current)
        case "highPass", "lowPass":
            let current: Double = if case .butterworth(let c, _) = p.bandpass { c } else { 0.1 }
            p.bandpass = .butterworth(cutoff: number("cutoff") ?? current, highPass: band == "highPass")
        default:
            p.bandpass = .none
        }
        analysis.setPreprocess(p)
        if a["mask_radius"] != nil || a["mask_edge"] != nil {
            analysis.setMask(radius: number("mask_radius") ?? analysis.maskRadius, edge: number("mask_edge") ?? analysis.maskEdge)
        }
        analysis.setSpotFinder(thresholdFraction: number("finder_threshold"), minDistance: a["finder_distance"].flatMap(Int.init),
                               count: a["finder_count"].flatMap(Int.init))
        var f = analysis.filterParameters
        let typed: [(String, FFTRoomFormat.FilterParameter)] = [("delta", .delta), ("step", .step), ("cycles", .cycles), ("order", .order),
                                                                ("ro", .ro), ("low_frequency", .lowFrequency)]
        for (key, parameter) in typed { if let v = number(key) { f = parameter.applying(v, to: f) } }
        if let s = a["filter_smoothing"] { f.smoothing = s == "true" }
        analysis.setFilterParameters(f)
        if a["filter"] == "true" { analysis.runFilter() }
        if let r = a["strain_reference"].flatMap(FFTStrainReference.init(rawValue:)) { analysis.setStrainReference(r) }
        if a["strain"] == "true" { analysis.runStrain() }
        if let view = a["view"].flatMap(FFTAnalysis.SourceView.init(rawValue:)) { analysis.setSourceView(view) }
        return nil
    }

    private static func isGaussian(_ s: FFTPreprocess.Smoothing) -> Bool { if case .gaussian = s { true } else { false } }
    private static func sigmaOf(_ s: FFTPreprocess.Smoothing) -> Double { if case .gaussian(let v) = s { v } else { 1 } }
    private static func bandWord(_ b: FFTPreprocess.Bandpass) -> String {
        switch b {
        case .none: "none"
        case .differenceOfGaussians: "differenceOfGaussians"
        case .butterworth(_, let high): high ? "highPass" : "lowPass"
        }
    }

    private static func needs(_ view: FFTAnalysis.SourceView) -> String {
        switch view {
        case .original: "nothing"
        case .region: "the transform"
        case .maskedInverse: "a measured spot in the mask"
        case .absf, .wiener: "a Filter run (set_fft filter true)"
        case .strainXX, .strainYY, .strainXY, .rotation: "a Map Strain run (set_fft strain true)"
        }
    }

    /// `set_fft_spots`: Find Spots, Measure at…, the selection, removals and In Mask, as the Spots section's controls.
    static func applySpots(_ a: [String: String], to analysis: FFTAnalysis) -> AgentToolOutput? {
        var measureBin: (row: Int, col: Int)?
        if let words = a["measure_at"] {
            guard let spectrum = analysis.spectrum, analysis.isSpectrumCurrent else {
                return .refusal(status: 409, message: "The transform is still being computed; ask again when get_fft says current.")
            }
            let n = words.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int(String($0)) }
            guard n.count == 2, let bin = SpectrumBin.at(kx: n[0], ky: n[1], width: spectrum.width, height: spectrum.height) else {
                return .refusal(status: 400, message: "measure_at takes \"kx ky\" in whole bins: " + FFTRoomFormat.binRange(width: spectrum.width, height: spectrum.height))
            }
            measureBin = bin
        }
        if a["find"] == "true", !analysis.isSpectrumCurrent {
            return .refusal(status: 409, message: "The transform is still being computed; ask again when get_fft says current.")
        }
        var lists: [String: [FFTSpot.ID]] = [:]
        for key in ["remove", "in_mask", "out_of_mask"] {
            guard let words = a[key] else { continue }
            if words.trimmingCharacters(in: .whitespaces) == "all" {
                lists[key] = analysis.spots.map(\.id)
                continue
            }
            let parts = words.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            let numbers = parts.compactMap(Int.init)
            guard !numbers.isEmpty, numbers.count == parts.count else {
                return .refusal(status: 400, message: "\(key) takes spot numbers separated by commas, or all.")
            }
            var ids: [FFTSpot.ID] = []
            for n in numbers {
                guard let spot = analysis.spots.first(where: { $0.number == n }) else {
                    return .refusal(status: 404, message: "There is no spot \(n); get_fft lists the spots.")
                }
                ids.append(spot.id)
            }
            lists[key] = ids
        }
        if let n = a["select"].flatMap(Int.init), !analysis.spots.contains(where: { $0.number == n }) {
            return .refusal(status: 404, message: "There is no spot \(n); get_fft lists the spots.")
        }

        for id in lists["in_mask"] ?? [] { analysis.setInMask(id, true) }
        for id in lists["out_of_mask"] ?? [] { analysis.setInMask(id, false) }
        if let n = a["select"].flatMap(Int.init) { analysis.selection = analysis.spots.first { $0.number == n }?.id }
        if let ids = lists["remove"] { FFTSpotUndo.remove(ids, in: analysis, undoManager: nil) }
        if a["find"] == "true" { analysis.findSpots() }
        if let bin = measureBin { analysis.measureSpot(row: bin.row, col: bin.col) }
        return nil
    }
}
