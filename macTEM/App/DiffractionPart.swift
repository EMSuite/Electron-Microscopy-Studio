//
//  DiffractionPart.swift
//  Role: the Diffraction workspace's parts in the sidebar (#1044, Paul's design review of 25 Nov 2026): Calibrate, Index, Simulate,
//        Tilt Plan, Powder, Thickness, as 4DSTEM Studio lists the parts of the workspace in front, each with a status mark, and the
//        inspector shows that part's few sections. HIG Layout: "Use progressive disclosure… An interface with too much content and
//        too many choices makes it harder to find information quickly" — the room stacked up to fifteen sections in one inspector.
//        A regrouping of what exists: no new feature, no changed number. The pattern stays in the centre in every part (zoom,
//        selection and overlays carry over); only the inspector's sections, the side pane and the table strip follow the part.
//
//        One `WorkspaceArea.diffraction` stays, so no switch over the rooms changes; the part the window shows is
//        `WorkspaceNavigation.diffractionPart`, its sidebar row `SidebarRoute.diffractionPart`. What each part lists, when it can be
//        entered and which one a document opens on are this file's, pure, so a test reads them as data.
//

import Foundation
import TEMSession

nonisolated enum DiffractionPart: String, CaseIterable, Identifiable, Sendable {
    case calibrate, index, simulate, tiltPlan, powder, thickness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calibrate: "Calibrate"
        case .index: "Index"
        case .simulate: "Simulate"
        case .tiltPlan: "Tilt Plan"
        case .powder: "Powder"
        case .thickness: "Thickness"
        }
    }

    var subtitle: String {
        switch self {
        case .calibrate: "The centre, the scale from a standard's ring, and the rings and spots measured"
        case .index: "The phases, Index's orientation and the simulated spots over the pattern"
        case .simulate: "The simulation's microscope, specimen and orientation, and its spots over the pattern"
        case .tiltPlan: "The holder's tilts to the zone axes near the orientation"
        case .powder: "The powder pattern of the phases"
        case .thickness: "The specimen's thickness from the two-beam intensity across a disc"
        }
    }

    var systemImage: String {
        switch self {
        case .calibrate: "scope"
        case .index: "number"
        case .simulate: "wand.and.rays"
        case .tiltPlan: "rotate.3d"
        case .powder: "chart.bar.xaxis"
        case .thickness: "square.stack.3d.down.right"
        }
    }

    /// The toolbar's centre display names the part: "Diffraction · Index".
    static func toolbarRoom(_ part: DiffractionPart) -> String { "\(WorkspaceArea.diffraction.title) · \(part.title)" }

    /// The sidebar row's and the door's identifier.
    var identifier: String { "diffraction.part.\(rawValue)" }

    // MARK: What a part shows

    /// The inspector's sections of `part` for a document of `kind`, in order (Export is drawn after them where `showsExport`).
    /// Empty for a part the document has nothing for. Calibrate and Index are a measured pattern's; Simulate stands where they do
    /// for a computed one, with its read-only Calibration first (#1043), and holds what a computed pattern had beside Index (the
    /// Precipitate's variants, the rings and spots clicked), so no section of the document is lost. Tools (Ring · Spot · Tilt) stay
    /// where a click on the pattern is the work: Calibrate's rings and spots, Index's spots and the Tilt drag of Index and Simulate.
    static func sections(_ part: DiffractionPart, kind: DiffractionSections.Kind) -> [DiffractionSections.Section] {
        // Only sections the document has (#1043's list): a part regroups them and adds none.
        let has = Set(DiffractionSections.order(kind))
        let list: [DiffractionSections.Section] = switch (part, kind) {
        case (.calibrate, .measured): [.centre, .calibration, .display, .tools, .rings]
        case (.index, .measured): [.phases, .index, .simulation, .crystalView, .precipitate, .tools, .display]
        case (.simulate, .simulation):
            [.simulatedCalibration, .microscope, .phases, .orientation, .simulation, .specimen, .crystalView, .precipitate, .tools, .rings,
             .display]
        case (.simulate, .cbed):
            [.simulatedCalibration, .phases, .index, .simulation, .crystalView, .precipitate, .tools, .rings, .display]
        case (.tiltPlan, _): [.holder]
        case (.powder, _): [.phases, .powder]
        case (.thickness, _): [.thickness, .display]
        case (.calibrate, _), (.index, _), (.simulate, _): []
        }
        return list.filter(has.contains)
    }

    /// Whether the part ends with the Export section: every part but Thickness, which has nothing of its own to export.
    static func showsExport(_ part: DiffractionPart) -> Bool { part != .thickness }

    /// The sections that start closed in `part`: Display, where the part's job is not the picture.
    static func startsClosed(_ section: DiffractionSections.Section, in part: DiffractionPart) -> Bool {
        section == .display && part != .calibrate
    }

    /// The pane beside the pattern: the crystal in Index and Simulate (View > Show Crystal shows and hides it there), none elsewhere.
    static func showsCrystalPane(_ part: DiffractionPart) -> Bool { part == .index || part == .simulate }

    /// What the pane beside the pattern shows in `part` (#921): the crystal in Index and Simulate, the zone-axis map in Tilt Plan, the
    /// powder pattern in Powder; none in Calibrate and Thickness, where the pattern has the room.
    static func sidePane(_ part: DiffractionPart) -> DiffractionViewState.SidePane? {
        switch part {
        case .index, .simulate: .crystal
        case .tiltPlan: .zoneAxisMap
        case .powder: .powder
        case .calibrate, .thickness: nil
        }
    }

    /// The strip of tables under the pattern.
    enum TableStrip: Sendable, Equatable { case readout, spots, peaks, none }

    /// Calibrate lists the readout; Index and Simulate the spots (with the readout beside them, picked in the strip's header); Powder
    /// the powder pattern's peaks (#921); the others none.
    static func tableStrip(_ part: DiffractionPart) -> TableStrip {
        switch part {
        case .calibrate: .readout
        case .index, .simulate: .spots
        case .powder: .peaks
        case .tiltPlan, .thickness: .none
        }
    }

    // MARK: When a part can be entered

    /// What the document in front holds, for the parts' availability.
    struct Facts: Sendable, Equatable {
        var kind: DiffractionSections.Kind
        /// The pattern has a scale: fitted, typed or the file's (a computed pattern's is the simulation's).
        var hasScale = false
        /// Index has an answer.
        var isIndexed = false
        /// The room has a crystal whose reflections can be listed (an atom model's pattern has none, #953).
        var hasPhase = true
    }

    static let measuredOnlySentence = "A measured pattern's: a computed pattern's scale and centre are the simulation's"
    static let simulationOnlySentence = "A Simulation document's: open one with File > New Simulation"
    static let noOrientationSentence = "Needs an orientation: index the pattern first"
    static let noPhaseSentence = "Needs a phase: choose one in Phases"

    /// Why `part` cannot be entered for the document `facts` describes, nil when it can. Listed, dimmed, with this as its help, as
    /// an unavailable room is.
    static func unavailableReason(_ part: DiffractionPart, facts: Facts) -> String? {
        switch part {
        case .calibrate, .index: facts.kind == .measured ? nil : measuredOnlySentence
        case .simulate: facts.kind == .measured ? simulationOnlySentence : nil
        case .tiltPlan: facts.isIndexed || facts.kind != .measured ? nil : noOrientationSentence
        case .powder: facts.hasPhase ? nil : noPhaseSentence
        case .thickness: nil
        }
    }

    /// The part a document opens on: a measured pattern on Calibrate until it has a scale, then on Index; a Simulation document on
    /// Simulate; the CBED pattern derived from one on Thickness.
    static func opening(_ facts: Facts) -> DiffractionPart {
        switch facts.kind {
        case .measured: facts.hasScale ? .index : .calibrate
        case .simulation: .simulate
        case .cbed: .thickness
        }
    }

    /// The part shown: `chosen` while it can be entered, else the one the document opens on.
    static func shown(chosen: DiffractionPart?, facts: Facts) -> DiffractionPart {
        if let chosen, unavailableReason(chosen, facts: facts) == nil { return chosen }
        return opening(facts)
    }

    // MARK: Status marks

    /// A part's trailing mark where there is a fact to show: Calibrate once the scale is known, Index once Index has an answer. A
    /// glyph with a spoken value, never colour alone.
    struct Status: Sendable, Equatable {
        let systemImage: String
        let spoken: String
    }

    static func status(_ part: DiffractionPart, facts: Facts) -> Status? {
        switch part {
        case .calibrate where facts.kind == .measured && facts.hasScale: Status(systemImage: "checkmark.circle", spoken: "Scale known")
        case .index where facts.kind == .measured && facts.isIndexed: Status(systemImage: "checkmark.circle", spoken: "Indexed")
        default: nil
        }
    }

    // MARK: Show Next Room and Show Previous Room

    /// The next part that can be entered, in sidebar order, round from the last to the first; nil when no other can.
    func neighbour(forward: Bool, facts: Facts) -> DiffractionPart? {
        let parts = Self.allCases
        guard let index = parts.firstIndex(of: self) else { return nil }
        for step in 1 ..< parts.count {
            let part = parts[(index + (forward ? step : parts.count - step)) % parts.count]
            if Self.unavailableReason(part, facts: facts) == nil { return part }
        }
        return nil
    }
}

extension AppState {
    /// What the selected document holds, for the parts (`DiffractionPart.Facts`); nil with no document.
    var diffractionPartFacts: DiffractionPart.Facts? {
        guard let item = openItems.selected else { return nil }
        let kind = DiffractionSections.kind(of: item.url)
        let analysis = item.diffraction
        let image = item.session.imageOrBlank
        let model = kind == .measured ? nil : (DemoDocuments.isSimulation(item.url) ? item : simulationDocument(ofCBED: item))
        return DiffractionPart.Facts(kind: kind, hasScale: analysis.calibration(for: image) != nil, isIndexed: analysis.indexOutcome != nil,
                                     hasPhase: model?.multislice.atomModel == nil)
    }

    /// The part the window's Diffraction workspace shows.
    var diffractionPart: DiffractionPart {
        guard let facts = diffractionPartFacts else { return navigation.diffractionPart ?? .calibrate }
        return DiffractionPart.shown(chosen: navigation.diffractionPart, facts: facts)
    }

    /// Why `part` cannot be entered now, nil when it can.
    func diffractionPartUnavailableReason(_ part: DiffractionPart) -> String? {
        guard let facts = diffractionPartFacts else { return RoomAvailability.reason(.diffraction, holdings: roomHoldings) }
        return DiffractionPart.unavailableReason(part, facts: facts)
    }

    /// Shows `part`, and the Diffraction workspace with it; a part that cannot be entered is not.
    func selectDiffractionPart(_ part: DiffractionPart) {
        guard diffractionPartUnavailableReason(part) == nil else { return }
        navigation.diffractionPart = part
        if navigation.workspaceArea != .diffraction { selectWorkspace(.diffraction) }
    }

    /// The part the window shows when the Diffraction workspace first draws: `restored` (the scene's) when it can be entered, else
    /// the one the document opens on (`DiffractionPart.opening`). Pinned, so a scale found while calibrating does not move the
    /// inspector to Index under the person's hands. A part already chosen in this window is kept.
    func settleDiffractionPart(restored: DiffractionPart?) {
        guard navigation.diffractionPart == nil, let facts = diffractionPartFacts else { return }
        if let restored, DiffractionPart.unavailableReason(restored, facts: facts) == nil {
            navigation.diffractionPart = restored
        } else {
            navigation.diffractionPart = DiffractionPart.opening(facts)
        }
    }

    /// Another document in front: it opens on its own part.
    func diffractionDocumentChanged() {
        guard let facts = diffractionPartFacts else { return }
        navigation.diffractionPart = DiffractionPart.opening(facts)
    }

    /// Show Next Room and Show Previous Room in the Diffraction workspace: its parts, as they step through Image and FFT.
    func neighbourDiffractionPart(forward: Bool) -> DiffractionPart? {
        guard navigation.workspaceArea == .diffraction, let facts = diffractionPartFacts else { return nil }
        return diffractionPart.neighbour(forward: forward, facts: facts)
    }

    /// Whether Show Next Room (`forward`) or Show Previous Room has somewhere to go: another room of the workspace, or another part.
    func canShowNeighbour(forward: Bool) -> Bool {
        neighbourRoom(forward: forward) != nil || neighbourDiffractionPart(forward: forward) != nil
    }

    /// Show Next Room (`forward`) or Show Previous Room.
    func showNeighbour(forward: Bool) {
        if let part = neighbourDiffractionPart(forward: forward) {
            selectDiffractionPart(part)
        } else if let room = neighbourRoom(forward: forward) {
            selectWorkspace(room)
        }
    }
}
