//
//  AgentDoorImage.swift
//  Role: the agent door's tools for the Image room (#558). `get_image_room` reads the room for the file shown: its stack and frame,
//        the measuring tool, the marks with their values as the Measure section words them, the SEM rows and vendor fields, and the
//        Particles section (settings, region, the last Show Objects' counts, sizes and density). `get_particles` gives the object
//        table (a page of it) or Export CSV…'s text; `get_profile` a profile mark's samples as Export Profile… writes them.
//        `set_image_room` sets the tool, the stack's frame and its held contrast; `set_marks` adds, selects and removes marks and
//        sets a profile's width; `set_particles` sets the Particles section and presses Show Objects or Hide.
//
//        ONE SOURCE PER FACT: a mark's value is `MarkFormat.value`, the row's own text; the SEM rows are `SEMRows.rows`; the counts,
//        sizes and density lines are `ParticleFormat`'s; the CSVs are `ParticleFormat.csv` and `ProfileCSV.text`, what the exports
//        write. A mark goes through `ImageMeasurements.add` as the pane's drag does (`MarkMaking`), a removal through `MarkUndo.remove`,
//        a width through `MarkEdits.setWidth`; a frame through `OpenItems.showFrame` and `stepFrame`, as the slider and the steps.
//

import Foundation
import ImagoCore
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let imageTools: [AgentTool] = [
        AgentTool(name: "get_image_room", title: "Image room",
                  summary: "What the Image room holds for the file shown: its size and calibration, the stack's frame, the measuring "
                      + "tool, the marks (numbered from 1, each with its points in image pixels and its value as the Measure section "
                      + "words it), an SEM file's rows and vendor fields, and the Particles section: every setting (in set_particles' "
                      + "names), the region, the image's raw range, and the last Show Objects' counts, sizes and areal density.",
                  input: .window) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, item.session.image != nil else { return noImage }
            return .json(imageRoom(appState, item))
        },
        AgentTool(name: "get_particles", title: "Particle objects",
                  summary: "After Show Objects: the object table (a page of it, by number or largest first; counted_only as the table's "
                      + "switch), or with csv true the CSV Export CSV… writes, its provenance lines first.",
                  input: .window,
                  parameters: [
                      AgentParameter("first", .integer(1...10_000_000), summary: "The first row, from 1. Default 1."),
                      AgentParameter("count", .integer(1...10_000), summary: "Rows to give. Default 100."),
                      AgentParameter("sort", .choice(["number", "area"]), summary: "number (the default) or area, largest first."),
                      AgentParameter("counted_only", .boolean, summary: "Only the counted objects, as the table's switch."),
                      AgentParameter("csv", .boolean, summary: "The whole CSV instead of rows."),
                  ]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, let image = item.session.image else { return noImage }
            guard let report = item.particles.report else {
                return .refusal(status: 404, message: "No objects yet: Show Objects first (set_particles with show true).")
            }
            let scale = ParticleCompute.scale(of: image)
            if call.arguments["csv"] == "true" {
                return .json(["csv": ParticleFormat.csv(report, scale: scale, fileName: image.fileName), "current": item.particles.isCurrent])
            }
            var rows = report.objects.map { ParticleRow($0, scale: scale) }
            if call.arguments["counted_only"] == "true" { rows = rows.filter(\.counted) }
            if call.arguments["sort"] == "area" { rows.sort { $0.area != $1.area ? $0.area > $1.area : $0.id < $1.id } }
            let first = max((call.arguments["first"].flatMap(Int.init) ?? 1) - 1, 0)
            let count = call.arguments["count"].flatMap(Int.init) ?? 100
            let page = rows.dropFirst(first).prefix(count)
            return .json([
                "unit": scale.unit, "rows": rows.count, "first": first + 1, "current": item.particles.isCurrent,
                "objects": page.map { r in
                    ["number": Int(r.id), "counted": r.counted, "note": r.note, "length": AgentJSON.number(r.length),
                     "width": AgentJSON.number(r.width), "angle_degrees": AgentJSON.number(r.angle), "area": AgentJSON.number(r.area)] as [String: Any]
                },
            ])
        },
        AgentTool(name: "get_profile", title: "Line profile",
                  summary: "A profile mark's samples as Export Profile… writes them (CSV, provenance lines first): the selected mark, "
                      + "or the mark numbered.",
                  input: .window,
                  parameters: [AgentParameter("mark", .integer(1...100_000), summary: "The mark's number, as get_image_room lists it.")]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, let image = item.session.image else { return noImage }
            let measurements = item.measurements
            let picked: ImageMark?
            if let n = call.arguments["mark"].flatMap(Int.init) {
                guard measurements.marks.indices.contains(n - 1) else { return noMark(n, measurements) }
                picked = measurements.marks[n - 1]
            } else {
                picked = measurements.mark(measurements.selection)
            }
            guard let mark = picked, mark.kind == .profile, let profile = measurements.profiles[mark.id], mark.points.count == 2 else {
                return .refusal(status: 409, message: "That is not a profile mark; give the number of one (get_image_room lists the marks).")
            }
            guard let text = ProfileCSV.text(profile, start: mark.points[0], end: mark.points[1],
                                             source: ExportSource(image: image, software: ExportSnapshot.provenance()),
                                             shown: ExportSnapshot.shownPositions(of: profile, x: image.x, y: image.y)) else {
                return .refusal(status: 409, message: "The profile has no samples.")
            }
            return .json(["mark": (measurements.marks.firstIndex { $0.id == mark.id } ?? 0) + 1, "samples": profile.samples.count, "csv": text])
        },
        said(AgentTool(name: "set_image_room", title: "Image room settings",
                       summary: "The Measure section's tool (pan, distance, angle, profile: what a drag on the picture draws for the "
                           + "person; an agent adds marks with set_marks), and a stack's Stack section: frame (from 1), step (next or "
                           + "previous, as the arrows), hold_contrast (Same contrast for every frame). Only those given.",
                       input: .window,
                       parameters: [
                           AgentParameter("tool", .choice(ImageRoomTools.Tool.allCases.map(\.rawValue)), summary: "The measuring tool."),
                           AgentParameter("frame", .integer(1...1_000_000), summary: "The stack's frame to show, from 1."),
                           AgentParameter("step", .choice(["next", "previous"]), summary: "One frame on or back."),
                           AgentParameter("hold_contrast", .boolean, summary: "Pin the contrast window at this frame's range."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, item.session.image != nil else { return noImage }
            let a = call.arguments
            if a["frame"] != nil || a["step"] != nil || a["hold_contrast"] != nil {
                guard let stack = item.stack else { return .refusal(status: 409, message: "This file is one image, not a stack.") }
                if let frame = a["frame"].flatMap(Int.init) {
                    guard frame <= stack.frameCount else {
                        return .refusal(status: 400, message: "The stack has frames 1 to \(stack.frameCount).")
                    }
                }
            }
            if let tool = a["tool"].flatMap(ImageRoomTools.Tool.init(rawValue:)) { appState.imageRoomTools.tool = tool }
            if let frame = a["frame"].flatMap(Int.init) { appState.openItems.slideFrame(item, to: frame - 1) }
            if let step = a["step"] { appState.openItems.stepFrame(item, by: step == "next" ? 1 : -1) }
            if let hold = a["hold_contrast"] {
                if hold == "true" { item.presentation.holdCurrentRange() } else { item.presentation.resetWindow() }
            }
            return .json(imageRoom(appState, item))
        }),
        said(AgentTool(name: "set_marks", title: "Image marks",
                       summary: "The Measure section's marks on the file shown. add (distance, angle or profile) with points "
                           + "\"x0 y0 x1 y1\" in image pixels (an angle's three: A, the vertex, C) adds a mark as a drag does, "
                           + "selected; select picks a mark by number; remove takes a number, several (\"2, 3\") or all; width sets the "
                           + "selected profile's width in pixels. The record can refuse an add or a width; the refusal is the alert's.",
                       input: .window,
                       parameters: [
                           AgentParameter("add", .choice(ImageMark.Kind.allCases.map(\.rawValue)), summary: "The kind of mark to add."),
                           AgentParameter("points", .text, summary: "With add: x y pairs in image pixels, e.g. \"10 20 200 20\"."),
                           AgentParameter("select", .integer(1...100_000), summary: "The mark to select, by number."),
                           AgentParameter("remove", .text, summary: "Mark numbers to remove, e.g. \"2\" or \"2, 3\", or all."),
                           AgentParameter("width", .integer(1...ImageMeasurements.maximumWidth), summary: "The selected profile's width, px."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, let image = item.session.image else { return noImage }
            if let refusal = applyMarks(call.arguments, item: item, image: image, appState: appState) { return refusal }
            return .json(imageRoom(appState, item))
        }),
        said(AgentTool(name: "set_particles", title: "Particles settings",
                       summary: "The Image room's Particles section, only those given: polarity (bright or dark objects), method "
                           + "(manual or otsu), threshold (the Level slider's raw intensity, manual only), sigma (smoothing, px), "
                           + "connectivity (4 or 8), minimum_area (px²), region (\"x y width height\" in image pixels, as Draw Region) "
                           + "or whole_image, tint_mask; show true presses Show Objects (answers at once; get_image_room says "
                           + "computing), hide true hides the objects; select picks an object by number as the table does, 0 none.",
                       input: .window,
                       parameters: [
                           AgentParameter("polarity", .choice(ParticleSettings.Polarity.allCases.map(\.rawValue)), summary: "Bright or dark objects."),
                           AgentParameter("method", .choice(ParticleSettings.Method.allCases.map(\.rawValue)), summary: "How the level is chosen."),
                           AgentParameter("threshold", .number(-1e30...1e30), summary: "The level in the image's raw intensity (manual)."),
                           AgentParameter("sigma", .number(0...1_000), summary: "Gaussian smoothing before the threshold, px; 0 none."),
                           AgentParameter("connectivity", .choice(["4", "8"]), summary: "4- or 8-connected objects."),
                           AgentParameter("minimum_area", .integer(1...100_000), summary: "Smaller objects are removed, px²."),
                           AgentParameter("region", .text, summary: "The region to analyse: \"x y width height\" in image pixels."),
                           AgentParameter("whole_image", .boolean, summary: "Analyse the whole image again (clears the region)."),
                           AgentParameter("tint_mask", .boolean, summary: "Tint the object side of the threshold while editing."),
                           AgentParameter("show", .boolean, summary: "Show Objects: find, count and outline the objects."),
                           AgentParameter("hide", .boolean, summary: "Hide the objects' outlines."),
                           AgentParameter("select", .integer(0...10_000_000), summary: "The object to outline heavier, by number; 0 none."),
                       ], acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard let item = appState.openItems.selected, let image = item.session.image else { return noImage }
            if let refusal = applyParticles(call.arguments, item: item, image: image, rawRange: item.presentation.canvas?.rawRange) {
                return refusal
            }
            return .json(imageRoom(appState, item))
        }),
    ]

    private static let noImage = AgentToolOutput.refusal(
        status: 404, message: "No image is shown; open one first (open_demo with demo lattice opens the demo lattice image).")

    private static func noMark(_ n: Int, _ measurements: ImageMeasurements) -> AgentToolOutput {
        .refusal(status: 404, message: measurements.marks.isEmpty
            ? "There is no mark \(n): the file has no marks."
            : "There is no mark \(n); the file has marks 1 to \(measurements.marks.count).")
    }

    private static let imagePoint = Locale(identifier: "en_US_POSIX")

    // MARK: Answers

    static func imageRoom(_ appState: AppState, _ item: OpenItem) -> [String: Any] {
        let image = item.session.imageOrBlank
        var answer: [String: Any] = [
            "file_name": item.url.lastPathComponent,
            "width": image.width, "height": image.height,
            "x_calibration": calibration(image.x), "y_calibration": calibration(image.y),
            "tool": appState.imageRoomTools.tool.rawValue,
            "marks": marks(item.measurements, image: image),
            "selected_mark": AgentJSON.orNull(item.measurements.marks.firstIndex { $0.id == item.measurements.selection }.map { $0 + 1 }),
            "particles": particles(item, image: image),
            "loading": item.session.isLoading,
        ]
        if let stack = item.stack {
            answer["stack"] = [
                "frames": stack.frameCount, "frame": item.frame + 1, "asked_for": item.requestedFrame + 1,
                "failed_frame": AgentJSON.orNull(item.failedFrame.map { $0 + 1 }), "frame_failure": AgentJSON.orNull(item.frameFailure),
                "hold_contrast": item.presentation.windowLow != nil || item.presentation.windowHigh != nil,
            ] as [String: Any]
        } else {
            answer["stack"] = NSNull()
        }
        if let sem = item.session.sem {
            let hidden = UserDefaults.standard.object(forKey: SEMImageSettings.cropDatabarKey) as? Bool ?? SEMImageSettings.cropDatabarDefault
            answer["sem"] = [
                "rows": SEMRows.rows(sem, locale: imagePoint).map { r in
                    ["id": r.id, "label": r.label, "value": r.value, "note": AgentJSON.orNull(r.note)] as [String: Any]
                },
                "vendor_fields": sem.rawFields.map { ["key": $0.key, "value": $0.value] },
                "databar_rows": AgentJSON.orNull(sem.databarRows),
                "databar_note": AgentJSON.orNull(sem.databarRows.map { SEMDatabarNote.note(rows: $0, hidden: hidden) }),
            ] as [String: Any]
        } else {
            answer["sem"] = NSNull()
        }
        return answer
    }

    private static func marks(_ measurements: ImageMeasurements, image: CalibratedImage) -> [[String: Any]] {
        measurements.marks.enumerated().map { index, mark in
            [
                "number": index + 1, "kind": mark.kind.rawValue,
                "points": mark.points.map { [AgentJSON.number($0.x), AgentJSON.number($0.y)] },
                "width": mark.width,
                "value": MarkFormat.value(mark, x: image.x, y: image.y, locale: imagePoint),
                "selected": mark.id == measurements.selection,
                "profile_samples": AgentJSON.orNull(measurements.profiles[mark.id]?.samples.count),
            ]
        }
    }

    private static func particles(_ item: OpenItem, image: CalibratedImage) -> [String: Any] {
        let analysis = item.particles, s = analysis.settings
        let range = item.presentation.canvas?.rawRange
        let region = ParticleRegion.clamped(s.region, width: image.width, height: image.height)
        let scale = ParticleCompute.scale(of: image)
        var answer: [String: Any] = [
            "polarity": s.polarity.rawValue, "method": s.method.rawValue,
            "threshold": AgentJSON.number(range.map { Double($0.lowerBound) + s.thresholdFraction * Double($0.upperBound - $0.lowerBound) }),
            "threshold_fraction": AgentJSON.number(s.thresholdFraction),
            "sigma": AgentJSON.number(s.sigma), "connectivity": s.connectivity.rawValue, "minimum_area": s.minimumArea,
            "region": AgentJSON.orNull(region.map { ["x": $0.col, "y": $0.row, "width": $0.width, "height": $0.height] }),
            "region_text": ParticleRegion.text(region),
            "raw_range": AgentJSON.orNull(range.map { [AgentJSON.number($0.lowerBound), AgentJSON.number($0.upperBound)] }),
            "can_show": range != nil && !analysis.isComputing,
            "tint_mask": analysis.previewsMask, "computing": analysis.isComputing, "failure": AgentJSON.orNull(analysis.failure),
            "shows_objects": analysis.showsObjects,
            "selected_object": AgentJSON.orNull(analysis.selectedLabel.map { Int($0) }),
            "render_note": AgentJSON.orNull(ParticleFormat.renderNote(notes: image.notes)),
            "unit": scale.unit,
        ]
        if let report = analysis.report {
            let summary = report.summary
            answer["result"] = [
                "current": analysis.isCurrent,
                "level": AgentJSON.number(report.thresholdValue),
                "total": summary.total, "counted": summary.counted, "edge": summary.edge, "small": summary.small,
                "median_length": AgentJSON.number(summary.medianLengthPx.map { $0 * scale.perPixel }),
                "mean_width": AgentJSON.number(summary.meanWidthPx.map { $0 * scale.perPixel }),
                "areal_density_per_unit_squared": AgentJSON.number(scale.isCalibrated ? summary.arealDensity : nil),
                "counts_line": ParticleFormat.counts(summary),
                "sizes_line": ParticleFormat.sizes(summary, scale: scale, locale: imagePoint),
                "density_line": ParticleFormat.density(summary, scale: scale),
            ] as [String: Any]
        } else {
            answer["result"] = NSNull()
        }
        return answer
    }

    // MARK: Acting

    /// `set_marks`: add, then select, then the width of the selected profile, then remove, so one call can add a profile and widen it.
    static func applyMarks(_ a: [String: String], item: OpenItem, image: CalibratedImage, appState: AppState) -> AgentToolOutput? {
        let measurements = item.measurements
        if let kind = a["add"].flatMap(ImageMark.Kind.init(rawValue:)) {
            let words = (a["points"] ?? "").split(whereSeparator: { $0 == "," || $0 == " " })
            let values = words.compactMap { Double(String($0)) }.filter(\.isFinite)
            guard words.count == 2 * kind.pointCount, values.count == words.count else {
                return .refusal(status: 400, message: "A \(kind.rawValue) takes \(kind.pointCount) points: \(2 * kind.pointCount) numbers in points.")
            }
            let points = stride(from: 0, to: values.count, by: 2).map { ImagePoint(x: values[$0], y: values[$0 + 1]) }
            if let refusal = measurements.add(ImageMark(kind: kind, points: points), on: image) {
                SessionPanels.markRefused(refusal, .added, appState: appState)
                return .refusal(status: 409, message: MarkRefusalText.refused(refusal, .added))
            }
        } else if a["points"] != nil {
            return .refusal(status: 400, message: "points go with add (distance, angle or profile).")
        }
        if let n = a["select"].flatMap(Int.init) {
            guard measurements.marks.indices.contains(n - 1) else { return noMark(n, measurements) }
            measurements.selection = measurements.marks[n - 1].id
        }
        if let width = a["width"].flatMap(Int.init) {
            guard let mark = measurements.mark(measurements.selection), mark.kind == .profile else {
                return .refusal(status: 409, message: "width is a profile's: select a profile mark first.")
            }
            if MarkEdits.setWidth(mark.id, width, on: image, in: measurements) {
                SessionPanels.markRefused(nil, .widthChanged, appState: appState)
                return .refusal(status: 409, message: MarkRefusalText.refused(nil, .widthChanged))
            }
        }
        if let words = a["remove"] {
            let ids: [ImageMark.ID]
            if words.trimmingCharacters(in: .whitespaces) == "all" {
                ids = measurements.marks.map(\.id)
            } else {
                let parts = words.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
                let numbers = parts.compactMap(Int.init)
                guard !numbers.isEmpty, numbers.count == parts.count else {
                    return .refusal(status: 400, message: "remove takes mark numbers separated by commas, or all.")
                }
                if let missing = numbers.first(where: { !measurements.marks.indices.contains($0 - 1) }) { return noMark(missing, measurements) }
                ids = numbers.map { measurements.marks[$0 - 1].id }
            }
            MarkUndo.remove(ids, in: measurements, session: item.session, undoManager: nil)
        }
        return nil
    }

    /// `set_particles`: the settings through the section's own `setSettings`, then Show Objects or Hide and the selection.
    static func applyParticles(_ a: [String: String], item: OpenItem, image: CalibratedImage, rawRange: ClosedRange<Float>?) -> AgentToolOutput? {
        let analysis = item.particles
        let number = { (key: String) -> Double? in a[key].flatMap(Double.init) }
        // Every check before any change, so a refused call changes nothing.
        let method = a["method"].flatMap(ParticleSettings.Method.init(rawValue:)) ?? analysis.settings.method
        var fraction: Double?
        if let level = number("threshold") {
            guard method == .manual else {
                return .refusal(status: 409, message: "Otsu chooses the level; set method manual to give a threshold.")
            }
            guard let range = rawRange, range.upperBound > range.lowerBound else {
                return .refusal(status: 409, message: "The image has no range to threshold (constant or no finite value).")
            }
            guard level >= Double(range.lowerBound), level <= Double(range.upperBound) else {
                return .refusal(status: 400, message: "The level runs from \(range.lowerBound) to \(range.upperBound).")
            }
            fraction = (level - Double(range.lowerBound)) / Double(range.upperBound - range.lowerBound)
        }
        var region: PixelCrop??
        if let words = a["region"] {
            let n = words.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int(String($0)) }
            guard n.count == 4, n[2] > 0, n[3] > 0 else {
                return .refusal(status: 400, message: "region takes \"x y width height\" in image pixels.")
            }
            guard let clamped = ParticleRegion.clamped(PixelCrop(row: n[1], col: n[0], height: n[3], width: n[2]), width: image.width, height: image.height)
            else { return .refusal(status: 400, message: "That region is off the image or covers all of it; whole_image analyses all of it.") }
            region = .some(clamped)
        }
        if a["whole_image"] == "true" { region = .some(nil) }
        if a["show"] == "true", rawRange == nil {
            return .refusal(status: 409, message: "The image has no range to threshold (constant or no finite value).")
        }
        if let select = a["select"].flatMap(Int.init), select != 0 {
            guard let report = analysis.report else { return .refusal(status: 409, message: "No objects yet: Show Objects first.") }
            guard report.objects.contains(where: { $0.id == Int32(select) }) else {
                return .refusal(status: 404, message: "There is no object \(select) in the table.")
            }
        }

        analysis.setSettings { s in
            if let v = a["polarity"].flatMap(ParticleSettings.Polarity.init(rawValue:)) { s.polarity = v }
            s.method = method
            if let fraction { s.thresholdFraction = fraction }
            if let v = number("sigma") { s.sigma = v }
            if let v = a["connectivity"].flatMap(Int.init).flatMap(Segmentation.Connectivity.init(rawValue:)) { s.connectivity = v }
            if let v = a["minimum_area"].flatMap(Int.init) { s.minimumArea = v }
            if let region { s.region = region }
        }
        if region != nil { analysis.setDrawingRegion(false) }
        if let tint = a["tint_mask"] {
            analysis.setPreviewsMask(tint == "true")
            if tint == "true" { analysis.updatePreview(image: image) }
        }
        if a["hide"] == "true" { analysis.hideObjects() }
        if a["show"] == "true" { analysis.analyse(image: image) }
        if let select = a["select"].flatMap(Int.init) { analysis.selectedLabel = select == 0 ? nil : Int32(select) }
        return nil
    }
}
