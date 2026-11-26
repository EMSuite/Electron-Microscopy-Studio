//
//  AgentDoorDiffractionScience.swift
//  Role: the agent door's tools for the Diffraction room's 2.4 science (plan row R17, #816): `set_relationship` (the Precipitate
//        section: the precipitate, its two parallel pairs, which variants are shown, double diffraction with the matrix),
//        `powder_pattern` (the Powder section, and its CSV or .xy written into the Agent folder), `find_phases` (the Find Phases
//        sheet: Rank, Fit scale, Use Phase) and `plan_tilt` (the Holder section and its map: the tilts now, the limits, the
//        axis typed or calibrated, the β sense, a zone axis picked, the Tilt List CSV into the Agent folder).
//
//        ONE SOURCE PER FACT: each tool goes through the intents the section's controls call (`DiffractionVariants`,
//        `DiffractionPowder`, `DiffractionPhaseFinder`, `DiffractionHolder`) and answers with what the section shows: the same
//        rows, the same sentences, the same refusals. Every check comes first, so a refused call changes nothing.
//

import DiffractoCore
import DiffractoGeometry
import DiffractoScattering
import Foundation
import ShellAgentDoor
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let diffractionScienceTools: [AgentTool] = [
        said(AgentTool(name: "set_relationship", title: "Diffraction precipitate",
                       summary: "The Precipitate section, only those given: precipitate (β″, a standard, or the crystal of another open "
                           + "pattern), first and second (a pair as \"[1 0 0] || [3 2 0]\": the precipitate's plane (h k l) or "
                           + "direction [u v w], then the matrix's), show (draw the variants), hide and unhide (variant numbers, "
                           + "\"2, 5\"), double_diffraction. Answers the variants with their groups, the sentences and any refusal.",
                       input: .window,
                       parameters: [
                           AgentParameter("precipitate", .text, summary: "β″, a standard's name, or an open pattern's crystal."),
                           AgentParameter("first", .text, summary: "The first pair, kept exact: \"[1 0 0] || [3 2 0]\"."),
                           AgentParameter("second", .text, summary: "The second pair: \"[0 0 1] || [1 -3 0]\"."),
                           AgentParameter("show", .boolean, summary: "Draw the shown variants' spots over the pattern."),
                           AgentParameter("hide", .text, summary: "Variant numbers to hide, \"2, 5\"."),
                           AgentParameter("unhide", .text, summary: "Variant numbers to show again, or all."),
                           AgentParameter("double_diffraction", .boolean, summary: "Also the spots double diffraction adds between the crystals."),
                       ], acts: true) { call in
            withDiffraction(call) { item, image in
                if let refusal = applyRelationship(call.arguments, to: item, image: image, others: openCrystals(call, besides: item)) {
                    return refusal
                }
                return .json(relationship(item, image: image))
            }
        }),
        said(AgentTool(name: "powder_pattern", title: "Diffraction powder pattern",
                       summary: "The Powder section, only those given: kind (rings or xray), radiation (pymatgen's line names, CuKa by "
                           + "default), two_theta_from and two_theta_to (°), reach (Å⁻¹, rings), compare (a second phase, or none), "
                           + "mark_overlaps. write csv or xy saves the peak table or this crystal's profile into the Agent folder as "
                           + "file (a name relative to it). Answers each phase's headline, the marks, and the peaks: hkl, d, 2θ or q, "
                           + "intensity of 100, overlaps, diagnostic.",
                       input: .window,
                       parameters: [
                           AgentParameter("kind", .choice(PowderKind.allCases.map(\.rawValue)), summary: "Electron rings or X-ray."),
                           AgentParameter("radiation", .choice(XRayRadiation.pymatgenLines.compactMap(\.name)), summary: "The X-ray line."),
                           AgentParameter("two_theta_from", .number(1...179), summary: "The range's low end, °."),
                           AgentParameter("two_theta_to", .number(1...179), summary: "The range's high end, °."),
                           AgentParameter("reach", .number(0.2...4), summary: "The rings' reach, Å⁻¹."),
                           AgentParameter("compare", .text, summary: "A second phase's name, or none."),
                           AgentParameter("mark_overlaps", .boolean, summary: "Mark overlapped and diagnostic peaks."),
                           AgentParameter("write", .choice(["csv", "xy"]), summary: "Save the peak table (csv) or the profile (xy)."),
                           AgentParameter("file", .text, summary: "The file to write, relative to the Agent folder."),
                       ], acts: true) { call in
            withDiffraction(call) { item, image in
                if SimulationEmptyState.isShown(for: item) { return .refusal(status: 409, message: SimulationEmptyState.paneSentence) }
                let others = openCrystals(call, besides: item)
                if let refusal = applyPowder(call.arguments, to: item, others: others) { return refusal }
                let table = powderTable(item, image: image, others: others)
                var out = powder(table)
                if let kind = call.arguments["write"] {
                    switch writePowder(table, kind: kind, file: call.arguments["file"], image: image, call: call) {
                    case .written(let name): out["written"] = name
                    case .refused(let refusal): return refusal
                    }
                }
                return .json(out)
            }
        }),
        said(AgentTool(name: "find_phases", title: "Find Phases",
                       summary: "The Find Phases sheet: elements (typed, e.g. \"Al, Cu, Mg\") or elements_from_eds true (the EDS room's "
                           + "quantified elements) fill the Elements field, search_materials_project true searches the Materials Project "
                           + "(open data, no key) for the phases of every combination of them and answers at once (materials_project.state "
                           + "searching until it lands; ask again), stop_search stops it. fit_scale; rank true ranks My Phases (the room's crystal, the library, "
                           + "the standards, the open crystals) and the Materials Project's candidates against the measured rings (or the "
                           + "marked spots) and answers at once (running true until it lands); use a phase's name makes it the room's "
                           + "crystal as Use Phase does. Answers the rows in the ranking's order (explains, strong rings not seen, misfit, "
                           + "scale, tie, source), each row's sentence, the ties and the notes, how many candidates came from each source "
                           + "and which search limits applied, never a verdict the sheet does not show.",
                       input: .window,
                       parameters: [
                           AgentParameter("elements", .text, summary: "The elements to search the Materials Project for, at most four."),
                           AgentParameter("elements_from_eds", .boolean, summary: "Take the elements from the EDS room's quantified elements."),
                           AgentParameter("search_materials_project", .boolean, summary: "Search the Materials Project for the elements now."),
                           AgentParameter("stop_search", .boolean, summary: "Stop the Materials Project search in flight, as its Stop does."),
                           AgentParameter("fit_scale", .boolean, summary: "Each phase takes its own scale (true) or the calibration holds."),
                           AgentParameter("rank", .boolean, summary: "Rank the candidates now."),
                           AgentParameter("use", .text, summary: "A ranked phase to make the room's crystal."),
                       ], acts: true) { call in
            withDiffraction(call) { item, image in
                guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
                let a = call.arguments, search = appState.phaseSearch
                // Every check of the search before any change (the sheet's Search button is disabled in the same cases).
                if a["elements"] != nil, a["elements_from_eds"] == "true" {
                    return .refusal(status: 400, message: "Give elements or elements_from_eds, not both.")
                }
                var elementsText = a["elements"] ?? search.elementsText
                if a["elements_from_eds"] == "true" {
                    guard let eds = MaterialsProjectPhaseSearch.edsElements(appState.edx) else {
                        return .refusal(status: 409, message: MaterialsProjectPhaseSearch.noEDSReason + ".")
                    }
                    elementsText = eds.joined(separator: ", ")
                }
                if a["search_materials_project"] == "true", a["stop_search"] == "true" {
                    return .refusal(status: 400, message: "Give search_materials_project or stop_search, not both.")
                }
                if a["search_materials_project"] == "true" {
                    do {
                        _ = try MaterialsProjectSearch.elements(typed: elementsText)
                    } catch {
                        return .refusal(status: 400, message: String(describing: error))
                    }
                }
                let candidates = DiffractionPhaseCandidate.all(for: item, appState: appState)
                if let refusal = applyFindPhases(a, to: item, image: image, candidates: candidates) { return refusal }
                search.elementsText = elementsText
                if a["stop_search"] == "true" { search.stop() }
                if a["search_materials_project"] == "true" { search.run() }
                var out = phases(item, image: image)
                out["materials_project"] = materialsProject(search, candidates: DiffractionPhaseCandidate.all(for: item, appState: appState))
                return .json(out)
            }
        }),
        said(AgentTool(name: "plan_tilt", title: "Diffraction holder",
                       summary: "The Holder section, only those given: alpha and beta (the stage now, °), alpha_limit and beta_limit, "
                           + "axis (the tilt axis in the pattern, °) or clear, beta_sense, calibrate_from (another open pattern of this crystal, "
                           + "indexed, by file name), zone_axis (\"[u v w]\" to pick on the map). write true saves the Tilt List "
                           + "CSV into the Agent folder as file. Answers the map's zone axes around the beam (angle, and α, β and "
                           + "reachable once the axis is calibrated), the calibration sentence and the picked zone axis' sentence; "
                           + "uncalibrated it says so and gives no α or β.",
                       input: .window,
                       parameters: [
                           AgentParameter("alpha", .number(-90...90), summary: "The stage's α now, °."),
                           AgentParameter("beta", .number(-90...90), summary: "The stage's β now, °."),
                           AgentParameter("alpha_limit", .number(0.1...90), summary: "The holder's α limit, °."),
                           AgentParameter("beta_limit", .number(0.1...90), summary: "The holder's β limit, °."),
                           AgentParameter("axis", .number(-360...360), summary: "The tilt axis in the pattern, °."),
                           AgentParameter("clear", .boolean, summary: "Clear the tilt axis."),
                           AgentParameter("beta_sense", .choice(["found", "positive", "reversed"]),
                                          summary: "β sense: found by the calibration, or set by hand (clears a calibrated axis "
                                              + "it changes)."),
                           AgentParameter("calibrate_from", .text, summary: "Another open, indexed pattern's file name."),
                           AgentParameter("zone_axis", .text, summary: "The zone axis to pick, \"[u v w]\"."),
                           AgentParameter("write", .boolean, summary: "Save the Tilt List CSV."),
                           AgentParameter("file", .text, summary: "The file to write, relative to the Agent folder."),
                       ], acts: true) { call in
            withDiffraction(call) { item, image in
                guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
                if let refusal = applyHolder(call.arguments, to: item, image: image, openItems: appState.openItems) { return refusal }
                var out = holder(item, image: image)
                if call.arguments["write"] == "true" {
                    guard let plan = item.diffractionHolder.plan(analysis: item.diffraction, image: image) else {
                        return .refusal(status: 409, message: "Index the pattern first: the tilt list is placed from its orientation.")
                    }
                    let text = ExportSnapshot.tiltListCSV(plan, image: image, openItems: appState.openItems)
                    switch writeAgentFile(text, file: call.arguments["file"],
                                          fallback: DiffractionTiltListExport.baseName(of: image.fileName) + ".csv") {
                    case .written(let name): out["written"] = name
                    case .refused(let refusal): return refusal
                    }
                }
                return .json(out)
            }
        }),
    ]

    // MARK: Shared

    /// Runs `body` on the pattern the Diffraction room shows, or answers why not.
    private static func withDiffraction(_ call: AgentToolCall, _ body: (OpenItem, CalibratedImage) -> AgentToolOutput) -> AgentToolOutput {
        guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
        switch diffractionItem(appState) {
        case .refused(let refusal): return refusal
        case .item(let item):
            guard let image = item.session.image else { return .refusal(status: 404, message: "No pattern is shown; open one first.") }
            return body(item, image)
        }
    }

    /// The crystals of the other open patterns, by name.
    private static func openCrystals(_ call: AgentToolCall, besides item: OpenItem) -> [PowderPhase] {
        guard let appState = call.window?.state as? AppState else { return [] }
        return appState.openItems.items.filter { $0.id != item.id }
            .map { PowderPhase(name: $0.diffraction.crystal.name, structure: $0.diffraction.crystal.structure) }
    }

    /// A file written into the Agent folder, or why not.
    enum Written {
        case written(String)
        case refused(AgentToolOutput)
    }

    /// Writes `text` into the Agent folder as `file` (or `fallback`), answering the name written.
    static func writeAgentFile(_ text: String, file: String?, fallback: String) -> Written {
        writeAgentFile(Data(text.utf8), file: file, fallback: fallback)
    }

    /// Writes `data` into the Agent folder as `file` (or `fallback`), answering the name written.
    static func writeAgentFile(_ data: Data, file: String?, fallback: String) -> Written {
        let name = file.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        switch folder.resolve(name) {
        case .failure(let refusal): return .refused(.refusal(status: 403, message: refusal.message))
        case .success(let url):
            do {
                let written = try ExportDirectoryFile.write(data, named: url.lastPathComponent, into: url.deletingLastPathComponent())
                return .written(folder.relativePath(of: written))
            } catch {
                return .refused(.refusal(status: 500, message: "Could not write \(name): \(error.localizedDescription)"))
            }
        }
    }

    /// "2, 5" → [1, 4] (0-based); nil when a number is not a variant of `count`.
    private static func variantNumbers(_ words: String, count: Int) -> [Int]? {
        let parts = words.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        let numbers = parts.compactMap(Int.init)
        guard count > 0, !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ (1...count).contains($0) }) else { return nil }
        return numbers.map { $0 - 1 }
    }

    // MARK: set_relationship

    /// "[1 0 0] || [3 2 0]" (also ∥) → the pair; nil for anything else.
    static func pair(_ words: String) -> (RelationshipVector, RelationshipVector)? {
        let sides = words.replacingOccurrences(of: "∥", with: "||").components(separatedBy: "||")
        guard sides.count == 2, let p = RelationshipVector.parse(sides[0]), let m = RelationshipVector.parse(sides[1]) else { return nil }
        return (p, m)
    }

    static func applyRelationship(_ a: [String: String], to item: OpenItem, image: CalibratedImage, others: [PowderPhase])
        -> AgentToolOutput? {
        let variants = item.diffractionVariants
        var precipitate: DiffractionVariants.Precipitate?
        if let name = a["precipitate"] {
            let options = [DiffractionVariants.Precipitate.betaDoublePrime]
                + StandardCrystals.all.map { .init(name: $0.name, structure: $0.structure) }
                + others.map { .init(name: $0.name, structure: $0.structure) }
            guard let chosen = options.first(where: { $0.name == name }), chosen.name != item.diffraction.crystal.name else {
                return .refusal(status: 404, message: "No precipitate \(name): β″, a standard other than the matrix, or an open pattern's crystal.")
            }
            precipitate = chosen
        }
        var relationship = variants.relationship
        if let words = a["first"] {
            guard let p = pair(words) else { return .refusal(status: 400, message: "first takes \"[1 0 0] || [3 2 0]\": (h k l) or [u v w] each.") }
            relationship.firstPrecipitate = p.0; relationship.firstMatrix = p.1
        }
        if let words = a["second"] {
            guard let p = pair(words) else { return .refusal(status: 400, message: "second takes \"[0 0 1] || [1 -3 0]\": (h k l) or [u v w] each.") }
            relationship.secondPrecipitate = p.0; relationship.secondMatrix = p.1
        }
        // Hiding numbers the variants of the relationship this call ends with: counted before anything changes, so a refused call
        // changes nothing.
        var count = 0
        if a["hide"] != nil || a["unhide"] != nil, var asked = variants.inputs(analysis: item.diffraction, image: image) {
            asked.precipitate = precipitate ?? variants.precipitate
            asked.relationship = relationship
            asked.hidden = []
            asked.doubleDiffraction = false
            if case .success(let set) = DiffractionVariants.compute(asked).set { count = set.rows.count }
        }
        var hide: [Int] = [], unhide: [Int] = []
        if let words = a["hide"] {
            guard let n = variantNumbers(words, count: count) else {
                return .refusal(status: 400, message: count == 0 ? "No variants are placed to hide: index the matrix first."
                                : "hide takes variant numbers 1 to \(count), \"2, 5\".")
            }
            hide = n
        }
        if let words = a["unhide"] {
            if words.trimmingCharacters(in: .whitespaces) == "all" {
                unhide = Array(0..<count)
            } else {
                guard let n = variantNumbers(words, count: count) else {
                    return .refusal(status: 400, message: "unhide takes variant numbers 1 to \(count), or all.")
                }
                unhide = n
            }
        }
        if let precipitate { variants.setPrecipitate(precipitate) }
        variants.setRelationship(relationship)
        for v in hide { variants.setHidden(v, true) }
        for v in unhide { variants.setHidden(v, false) }
        if let show = a["show"] { variants.isShown = show == "true" }
        if let dd = a["double_diffraction"] { variants.doubleDiffraction = dd == "true" }
        return nil
    }

    /// The door's answer is the placement it describes: placed now, not left to the section's next placement.
    private static func placeNow(_ variants: DiffractionVariants, item: OpenItem, image: CalibratedImage) {
        if let inputs = variants.inputs(analysis: item.diffraction, image: image) { variants.placeNow(inputs) }
    }

    static func relationship(_ item: OpenItem, image: CalibratedImage) -> [String: Any] {
        let variants = item.diffractionVariants
        placeNow(variants, item: item, image: image)
        var out: [String: Any] = [
            "precipitate": variants.precipitate.name, "matrix": item.diffraction.crystal.name,
            "relationship": variants.relationship.text(matrix: item.diffraction.crystal.name),
            "show": variants.isShown, "double_diffraction": variants.doubleDiffraction,
        ]
        switch variants.variants(analysis: item.diffraction, image: image) {
        case nil: out["refusal"] = "Variants need the beam energy: type it under Calibration."
        case .failure(let refusal)?: out["refusal"] = refusal.sentence
        case .success(let set)?:
            out["summary"] = set.summarySentence
            out["sheet"] = set.sheetSentence
            out["look_alike"] = set.lookAlikeSentences
            out["second_pair_misfit_deg"] = AgentJSON.number(set.secondPairMisfitDeg)
            out["variants"] = set.rows.map { r -> [String: Any] in
                ["number": r.number, "group": r.group + 1, "label": r.label, "shown": !r.isHidden]
            }
            out["groups"] = set.groupCount
            out["spots"] = set.spots.count
            switch variants.addedSpots(analysis: item.diffraction, image: image) {
            case .success(let added)?:
                out["added"] = ["sentence": added.countSentence, "total": added.total, "drawn": added.spots.count,
                                "routes": added.spots.prefix(20).map { $0.routes }] as [String: Any]
            case .failure(let refusal)?: out["added"] = ["refusal": refusal.sentence]
            case nil: break
            }
        }
        return out
    }

    // MARK: powder_pattern

    static func applyPowder(_ a: [String: String], to item: OpenItem, others: [PowderPhase]) -> AgentToolOutput? {
        let powder = item.diffractionPowder
        let from = a["two_theta_from"].flatMap(Double.init) ?? powder.settings.twoThetaFrom
        let to = a["two_theta_to"].flatMap(Double.init) ?? powder.settings.twoThetaTo
        if a["two_theta_from"] != nil || a["two_theta_to"] != nil, !(from < to) {
            return .refusal(status: 400, message: "two_theta_from must be below two_theta_to.")
        }
        var compare: String??
        if let name = a["compare"] {
            if name == "none" {
                compare = .some(nil)
            } else {
                let names = StandardCrystals.all.map(\.name) + others.map(\.name)
                guard names.contains(name), name != item.diffraction.crystal.name else {
                    return .refusal(status: 404, message: "No phase \(name) to compare with: a standard other than this crystal, or an open pattern's crystal.")
                }
                compare = .some(name)
            }
        }
        if let kind = a["kind"].flatMap(PowderKind.init(rawValue:)) { powder.setKind(kind) }
        if let line = a["radiation"].flatMap(XRayRadiation.named) { powder.setRadiation(line) }
        if a["two_theta_from"] != nil || a["two_theta_to"] != nil { powder.setTwoTheta(from: from, to: to) }
        if let reach = a["reach"].flatMap(Double.init) { powder.setReach(reach) }
        if let compare { powder.setCompareWith(compare) }
        if let marks = a["mark_overlaps"] { powder.setMarkOverlaps(marks == "true") }
        return nil
    }

    static func powderTable(_ item: OpenItem, image: CalibratedImage, others: [PowderPhase]) -> PowderTable {
        let options = StandardCrystals.all.map { PowderPhase(name: $0.name, structure: $0.structure) } + others
        let phases = item.diffractionPowder.phases(crystal: item.diffraction.crystal, others: options)
        return item.diffractionPowder.table(phases: phases, volts: item.diffraction.volts(for: image))
    }

    static func powder(_ table: PowderTable) -> [String: Any] {
        let s = table.settings
        var out: [String: Any] = [
            "kind": s.kind.rawValue, "phases": table.phases.map(\.name),
            "headlines": table.phases.indices.map { table.headline(phase: $0) },
            "marks": table.phases.indices.compactMap { table.marksSentence(phase: $0) },
            "position_unit": s.kind == .xray ? "two_theta_deg" : "q_per_angstrom",
        ]
        if s.kind == .xray {
            out["radiation"] = s.radiation.name ?? "typed"
            out["wavelength_angstroms"] = AgentJSON.number(s.radiation.wavelengthAngstroms)
            out["two_theta_from"] = AgentJSON.number(s.range.lowerBound)
            out["two_theta_to"] = AgentJSON.number(s.range.upperBound)
        } else {
            out["beam_kv"] = AgentJSON.number(s.volts / 1000)
            out["reach_per_angstrom"] = AgentJSON.number(s.ringReach)
        }
        out["peaks"] = table.rows.map { r -> [String: Any] in
            ["phase": r.phase, "hkl": r.hkl, "multiplicity": r.multiplicity, "d_angstroms": AgentJSON.number(r.d),
             "position": AgentJSON.number(r.position), "intensity": AgentJSON.number(r.intensity), "overlaps": r.overlaps,
             "diagnostic": r.isDiagnostic]
        }
        out["refusals"] = table.refusals.map { ["phase": $0.phase, "reason": $0.reason] }
        return out
    }

    private static func writePowder(_ table: PowderTable, kind: String, file: String?, image: CalibratedImage,
                                    call: AgentToolCall) -> Written {
        guard let appState = call.window?.state as? AppState else { return .refused(notAWindowRefusal) }
        let base = DiffractionPowderExport.baseName(of: image.fileName)
        if kind == "xy" {
            guard let text = table.xy(phase: 0) else {
                return .refused(.refusal(status: 409, message: "This crystal has no profile to write: \(table.headline(phase: 0))"))
            }
            return writeAgentFile(text, file: file,
                                  fallback: DiffractionPowderExport.baseName(of: image.fileName, phase: table.phases[0].name) + ".xy")
        }
        guard !table.rows.isEmpty else {
            return .refused(.refusal(status: 409, message: "The pattern has no peaks to write."))
        }
        return writeAgentFile(ExportSnapshot.powderCSV(table, image: image, openItems: appState.openItems), file: file, fallback: base + ".csv")
    }

    // MARK: find_phases

    static func applyFindPhases(_ a: [String: String], to item: OpenItem, image: CalibratedImage,
                                candidates: [DiffractionPhaseCandidate]) -> AgentToolOutput? {
        let finder = item.diffractionPhases
        var chosen: DiffractionPhaseCandidate?
        if let name = a["use"] {
            guard let row = finder.current(analysis: item.diffraction, image: image)?.rows.first(where: { $0.name == name }),
                  row.refusal == nil,
                  let candidate = candidates.first(where: { $0.id == name }) else {
                return .refusal(status: 404, message: "No ranked phase \(name); rank first and use a row's name.")
            }
            chosen = candidate
        }
        if a["rank"] == "true", let why = DiffractionPhaseFinder.blocker(analysis: item.diffraction, image: image) {
            return .refusal(status: 409, message: why + ".")
        }
        if let fit = a["fit_scale"] { finder.fitScale = fit == "true" }
        if a["rank"] == "true" { finder.run(analysis: item.diffraction, image: image, candidates: candidates.map(\.candidate)) }
        if let chosen { item.diffraction.setCrystal(chosen.crystal) }
        return nil
    }

    /// The Materials Project search as the sheet shows it: the elements, the state, how many candidates came from each source and
    /// the search's sentence with its limits.
    static func materialsProject(_ search: MaterialsProjectPhaseSearch, candidates: [DiffractionPhaseCandidate]) -> [String: Any] {
        let fromMP = candidates.filter { $0.source == .materialsProject }.count
        var out: [String: Any] = [
            "elements": search.elementsText,
            "candidates_my_phases": candidates.count - fromMP,
            "candidates_materials_project": fromMP,
            "sources": MaterialsProjectSearch.sourcesSentence(myPhases: candidates.count - fromMP, materialsProject: fromMP),
            "limits": ["maximum_elements": MaterialsProjectSearch.maximumElements, "per_system": MaterialsProjectSearch.perSystem,
                       "hull_limit_ev_per_atom": MaterialsProjectSearch.hullLimit, "maximum_candidates": MaterialsProjectSearch.maximumCandidates],
        ]
        switch search.state {
        case .idle: out["state"] = "idle"
        case .searching(let elements): out["state"] = "searching"; out["searching"] = elements
        case .done(let summary):
            out["state"] = "done"
            out["sentence"] = summary.sentence
            out["systems"] = summary.systems
            out["found"] = summary.found
            out["near_hull"] = summary.nearHull
            out["taken"] = summary.taken
            out["unread"] = summary.unread
            out["not_searched"] = summary.failedSystems
        case .refused(let why): out["state"] = "refused"; out["refusal"] = why
        case .failed(let why): out["state"] = "failed"; out["failure"] = why
        }
        return out
    }

    static func phases(_ item: OpenItem, image: CalibratedImage) -> [String: Any] {
        let finder = item.diffractionPhases
        var out: [String: Any] = [
            "fit_scale": finder.fitScale, "running": finder.isRunning, "crystal": item.diffraction.crystal.name,
            "blocker": AgentJSON.orNull(DiffractionPhaseFinder.blocker(analysis: item.diffraction, image: image)),
            "refusal": AgentJSON.orNull(finder.refusal),
        ]
        guard let result = finder.result else { return out }
        // A ranking of a pattern that has since changed is not answered as current, as the sheet does not show it.
        guard result == finder.current(analysis: item.diffraction, image: image) else {
            out["stale"] = DiffractionPhaseFinder.staleSentence
            return out
        }
        out["pattern"] = "\(result.pattern.count) \(result.pattern.noun)"
        out["rows"] = result.rows.map { r -> [String: Any] in
            ["name": r.name, "formula": r.formula, "space_group": r.spaceGroup, "explains": r.explained, "measured": r.measured,
             "strong_not_seen": AgentJSON.orNull(r.strongMissing), "strong_expected": AgentJSON.orNull(r.strongExpected),
             "misfit_percent": AgentJSON.number(r.misfitPercent), "rms_distance_per_angstrom": AgentJSON.number(r.rmsDistance),
             "scale": AgentJSON.number(r.scale), "tie": r.tie + 1, "tied": result.isTied(r),
             "zone_axis": AgentJSON.orNull(r.zoneAxis.map { "[\($0.u) \($0.v) \($0.w)]" }), "refusal": AgentJSON.orNull(r.refusal),
             "sentence": result.sentence(for: r), "source": r.source.name]
        }
        out["ties"] = Set(result.rows.map(\.tie)).sorted().compactMap { result.tieSentence($0) }
        out["weak"] = AgentJSON.orNull(result.weakSentence)
        out["materials_project_note"] = AgentJSON.orNull(result.materialsProjectNote)
        return out
    }

    // MARK: plan_tilt

    static func applyHolder(_ a: [String: String], to item: OpenItem, image: CalibratedImage, openItems: OpenItems) -> AgentToolOutput? {
        let holder = item.diffractionHolder, analysis = item.diffraction
        var partner: OpenItem?
        if let name = a["calibrate_from"] {
            guard let other = openItems.items.first(where: { $0.id != item.id && $0.session.image?.fileName == name }) else {
                return .refusal(status: 404, message: "No other open pattern named \(name).")
            }
            guard other.diffraction.crystal.name == analysis.crystal.name, other.diffraction.indexOutcome?.orientation != nil,
                  analysis.indexOutcome?.orientation != nil else {
                return .refusal(status: 409, message: "Calibration needs both patterns indexed on the same crystal.")
            }
            partner = other
        }
        // nil: not given; .some(nil): found by the calibration.
        var sense: DoubleTiltHolder.BetaSense??
        if let words = a["beta_sense"] {
            switch words {
            case "found": sense = .some(nil)
            case "positive": sense = .positive
            case "reversed": sense = .negative
            default: return .refusal(status: 400, message: "beta_sense takes found, positive or reversed.")
            }
        }
        var pick: SIMD3<Int>?
        if let words = a["zone_axis"] {
            guard let uvw = ZoneAxisText.parse(words) else { return .refusal(status: 400, message: "zone_axis takes \"[u v w]\".") }
            guard let plan = holder.plan(analysis: analysis, image: image) else {
                return .refusal(status: 409, message: "Index the pattern first: the zone axes are placed from its orientation.")
            }
            guard plan.row(uvw) != nil else {
                return .refusal(status: 404, message: "\(TiltPlanning.zoneText(uvw)) is not on the map (to index 3, within 60° of the beam).")
            }
            pick = uvw
        }
        let s = holder.settings
        if a["alpha"] != nil || a["beta"] != nil {
            holder.setTilts(alphaDeg: a["alpha"].flatMap(Double.init) ?? s.alphaDeg, betaDeg: a["beta"].flatMap(Double.init) ?? s.betaDeg)
        }
        if a["alpha_limit"] != nil || a["beta_limit"] != nil {
            holder.setLimits(alphaDeg: a["alpha_limit"].flatMap(Double.init) ?? s.alphaLimitDeg,
                             betaDeg: a["beta_limit"].flatMap(Double.init) ?? s.betaLimitDeg)
        }
        if let sense { holder.setBetaSense(sense) }
        if a["clear"] == "true" { holder.forgetAxis() }
        if let axis = a["axis"].flatMap(Double.init) { holder.setAxis(degrees: axis) }
        if let partner {
            holder.calibrate(analysis: analysis, other: partner.diffraction, otherHolder: partner.diffractionHolder,
                             otherName: partner.session.image?.fileName ?? "")
        }
        if let pick { holder.selected = pick }
        return nil
    }

    static func holder(_ item: OpenItem, image: CalibratedImage) -> [String: Any] {
        let holder = item.diffractionHolder, s = holder.settings
        var out: [String: Any] = [
            "alpha_deg": AgentJSON.number(s.alphaDeg), "beta_deg": AgentJSON.number(s.betaDeg), "tilts_from": s.source.rawValue,
            "alpha_limit_deg": AgentJSON.number(s.alphaLimitDeg), "beta_limit_deg": AgentJSON.number(s.betaLimitDeg),
            "axis_deg": AgentJSON.number(s.axisAngleDeg), "calibration_refusal": AgentJSON.orNull(holder.calibrationRefusal),
            "beta_sense": TiltPlanning.betaSenseWord(s.betaSense), "beta_sense_from": s.betaSenseSource.rawValue,
        ]
        guard let plan = holder.plan(analysis: item.diffraction, image: image) else {
            out["refusal"] = "Index the pattern first: the zone axes and the tilts to them are placed from its orientation."
            return out
        }
        out["calibration"] = plan.calibrationSentence
        out["zone_axes"] = plan.rows.map { r -> [String: Any] in
            ["zone_axis": r.id, "angle_from_beam_deg": AgentJSON.number(r.angleFromBeamDeg),
             "alpha_deg": AgentJSON.number(r.target?.alpha), "beta_deg": AgentJSON.number(r.target?.beta),
             "reachable": AgentJSON.orNull(r.reachable)]
        }
        out["plane_families"] = DiffractionZoneAxisMapText.families(plan)
        if let uvw = holder.selected, let row = plan.row(uvw) {
            out["selected"] = row.id
            out["sentence"] = plan.sentence(for: row)
        }
        return out
    }
}
