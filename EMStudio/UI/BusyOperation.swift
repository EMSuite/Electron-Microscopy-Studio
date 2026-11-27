//
//  BusyOperation.swift
//  Role: the name of the work a room is running, for the toolbar's busy line and the Stop button's help. The status line holds
//        the last event ("Opened … · 4096 channels"), which is not what runs: Quantify, the line check, Auto ID and the maps set no
//        sentence when they start, so the busy line named the open while the fit ran. The name is read from the room's own busy flags;
//        an open keeps its own sentence ("Opening <file>…"), which it sets as it starts. The Patterns toolbar read "Reading the scan for
//        the map…" during Process and the quality pass, and the Maps toolbar showed the file while Segment and the texture ran: both
//        rooms now take their busy line from here too (`toolbarOperation`). A run in a room not on screen (an Index left running while
//        the Maps room is shown) showed nowhere and ⌘. could not reach it: while the shown room is idle, the toolbar shows that run under
//        its room's name and ⌘. stops it (`backgroundRoom`), as mac4DSTEM shows and cancels its busy work whatever the room. Which room
//        the work belongs to is `isBusy`: the scan's open is the Indexing room's too while it is shown, and a layer's picture in the
//        Maps room is not work that hides another room's run.
//

import Foundation
import ShellEDXModel
import TEMCore
import TEMSession

enum BusyOperation {
    /// The EDS room's running work, the first of its busy flags in the order a Quantify sets them (the fit runs inside a refresh).
    nonisolated static func edx(opening: Bool, openSentence: String, fitting: Bool, checking: Bool, identifying: Bool, mapping: Bool,
                                refreshing: Bool) -> String? {
        if opening { return openSentence.hasPrefix("Opening") ? openSentence : "Opening the spectrum image…" }
        if fitting { return "Quantifying…" }
        if checking { return "Checking for unlisted lines…" }
        if identifying { return "Identifying elements…" }
        if mapping { return "Computing the composition maps…" }
        if refreshing { return "Updating the spectrum and maps…" }
        return nil
    }

    /// The EELS room's running work: the open, else the stage a pass is computing (the first run stage that is not current, as Run goes
    /// through them in order).
    nonisolated static func eels(opening: Bool, openSentence: String, computing: Bool, stage: EELSStage?) -> String? {
        if opening { return openSentence.hasPrefix("Opening") ? openSentence : "Opening the spectrum image…" }
        guard computing else { return nil }
        switch stage {
        case .align: return "Aligning the zero-loss peak…"
        case .thickness: return "Mapping the thickness…"
        case .deconvolve: return "Deconvolving…"
        case .fit: return "Fitting the edges…"
        case .edges, nil: return "Computing…"
        }
    }

    /// The Patterns room's running work: the open, the processing run (named by its first stage that is not current), else the map's
    /// pass, the quality pass and the scan's mean on its own pass, in the order the map pane's header shows them.
    nonisolated static func patterns(opening: Bool, processing: Bool, mapping: Bool, qualityMapping: Bool, computingMean: Bool = false,
                                     stage: PatternPipeline.Stage?) -> String? {
        if opening { return "Opening the dataset…" }
        if processing { return stage.map { "Processing: \($0.title)…" } ?? "Processing the patterns…" }
        if mapping { return "Reading the scan…" }
        if qualityMapping { return "Computing the quality maps…" }
        if computingMean { return "Computing the scan's mean pattern…" }
        return nil
    }

    /// The Maps room's running work: the open, Segment, the texture the bottom pane asked for, else a layer's picture.
    nonisolated static func maps(opening: Bool, segmenting: Bool, texturing: Bool, drawing: Bool) -> String? {
        if opening { return "Opening the orientation map…" }
        if segmenting { return "Segmenting grains…" }
        if texturing { return "Computing the texture…" }
        if drawing { return "Drawing the map…" }
        return nil
    }

    /// The Diffraction room's running work: the CBED run of the shown pattern's Simulation document (#1021), else Index, else the
    /// ring fit.
    nonisolated static func diffraction(computingCBED: Bool, indexing: Bool, fitting: Bool) -> String? {
        if computingCBED { return cbedSentence }
        if indexing { return "Indexing the pattern…" }
        if fitting { return "Fitting the ring…" }
        return nil
    }

    /// The busy line of a CBED run (#1021).
    nonisolated static let cbedSentence = "Computing the CBED patterns…"

    /// What `room` is running now, or nil when it is idle.
    @MainActor
    static func name(room: WorkspaceArea, appState: AppState) -> String? {
        switch room {
        case .edx:
            let s = appState.edx
            return edx(opening: s.isOpening, openSentence: appState.statusText, fitting: s.isFitting, checking: s.isChecking,
                       identifying: s.autoID == .running, mapping: s.mapsState == .running, refreshing: s.isRefreshing)
        case .eels:
            let s = appState.eels
            let next = s.stages.first { $0.stage.isRun && $0.state != .current }?.stage
            return eels(opening: s.isOpening, openSentence: appState.statusText, computing: s.isComputing, stage: next)
                ?? appState.hyperSpyWrite.map { "Exporting \($0.fileName)…" }
        case .patterns:
            let s = appState.ebsd
            return patterns(opening: s.isOpening, processing: s.isProcessing, mapping: s.isMapping, qualityMapping: s.isQualityMapping,
                            computingMean: s.isComputingMean, stage: s.firstStaleStage)
        case .indexing:
            let session = appState.indexing
            guard session.isIndexing else { return nil }
            if session.isRefining { return "Refining against the master pattern…" }
            return session.result?.method == .dictionary ? "Indexing with the dictionary…" : "Indexing with Hough…"
        case .maps:
            let s = appState.maps
            return maps(opening: s.isOpening, segmenting: s.isSegmenting, texturing: s.isTexturing, drawing: s.isDrawing)
        case .diffraction:
            let analysis = appState.openItems.selected?.diffraction
            return diffraction(computingCBED: appState.runningCBEDDocument != nil, indexing: analysis?.isIndexing == true,
                               fitting: analysis?.isFitting == true)
        case .image:
            if let thermal = appState.simulatingDocument?.multislice.thermalProgress { return simulating(thermal) }
            return appState.scanningSTEMDocument != nil ? scanningSentence : nil
        default:
            return nil
        }
    }

    /// The toolbar's busy line for `room`: what it runs (`name`) while its session is busy, the room's title for busy work without a
    /// name; nil while it is idle, when the toolbar shows the file. The Patterns and Maps rooms show it as it is.
    @MainActor
    static func toolbarOperation(room: WorkspaceArea, appState: AppState) -> String? {
        let busy: Bool = switch room {
        case .edx: appState.edx.isBusy
        case .eels: appState.isEELSRoomBusy
        case .patterns: appState.ebsd.isBusy
        case .indexing: appState.indexing.isBusy
        case .maps: appState.maps.isBusy
        case .image: appState.simulatingDocument != nil || appState.scanningSTEMDocument != nil
        // The CBED run only: Index and the ring fit show on the room's own button, as before (#1021).
        case .diffraction: appState.runningCBEDDocument != nil
        case .fft, .results: false
        }
        guard busy else { return nil }
        return name(room: room, appState: appState) ?? room.title
    }

    /// The Indexing toolbar's busy line: "Hough · 2340 of 4125", the points indexed so far (whole rows land at once); "Dictionary · 1
    /// of 3 chunks · NCC", the dictionary's chunks every block runs through (design §3); "Dictionary · Al · 23 of 40 chunks · NCC"
    /// against several phases, the dictionary matching named (D-SEM-98). The counts are written as the map's count line writes them,
    /// never grouped (`IndexingInfoFormat.count`): the toolbar read "2.340 of 4.125" in German beside the map's "2340 of 4125".
    @MainActor
    static func indexingLine(_ session: IndexingSession, dataset: EBSDDataset, locale: Locale = .autoupdatingCurrent) -> String {
        let done = IndexingInfoFormat.count((session.result?.rowsDone ?? 0) * dataset.scanColumns, locale: locale)
        let total = IndexingInfoFormat.count(dataset.patternCount, locale: locale)
        if session.isRefining, let target = session.refinedRun?.refinement?.settings.target {   // "Refine · Orientation · 450 of 4125"
            return "Refine · \(target.title) · \(done) of \(total)"
        }
        let phase = session.chunkPhase.map { "\($0) · " } ?? ""
        return session.result?.method == .dictionary
            ? "Dictionary · \(phase)\(session.chunksDone) of \(session.chunksTotal) chunks · \(session.result?.scoreTitle ?? "NCC")"
            : "Hough · \(done) of \(total)"
    }

    // MARK: A run in another room

    /// The rooms whose runs go on while another room is shown, in the Workspace menu's order.
    nonisolated static let runningRooms: [WorkspaceArea] = [.image, .edx, .eels, .patterns, .indexing, .maps]

    /// The room whose run the toolbar shows and ⌘. stops in place of the shown room's: the first busy room of `runningRooms`; nil while
    /// the shown room is busy itself (it keeps its own) or nothing else runs.
    nonisolated static func backgroundRoom(shown: WorkspaceArea, busy: Set<WorkspaceArea>) -> WorkspaceArea? {
        guard !busy.contains(shown) else { return nil }
        return runningRooms.first { busy.contains($0) }
    }

    /// `backgroundRoom` of the window: the room shown and the rooms with work in flight.
    @MainActor
    static func backgroundRoom(_ appState: AppState) -> WorkspaceArea? {
        let busy = Set(WorkspaceArea.allCases.filter { isBusy($0, appState: appState) })
        return backgroundRoom(shown: appState.navigation.workspaceArea, busy: busy)
    }

    /// Whether `room` has work in flight that keeps the toolbar's line and ⌘. while the room is shown: its session's busy flag, but for
    /// three rooms. The Indexing room shows the scan too and draws its open with a Stop of its own, so the open of the scan is its
    /// work as well as the Patterns room's (from any other room it stays "Patterns · Opening the dataset…": Patterns comes first in
    /// `runningRooms`). The Maps room counts the work Stop ends (`RoomPrimaryAction.canStop`) and not a layer's picture, which would
    /// hide another room's run and turn ⌘. off for the length of every draw. The Diffraction room's is the selected file's ring fit,
    /// which ⌘. stops there.
    @MainActor
    static func isBusy(_ room: WorkspaceArea, appState: AppState) -> Bool {
        switch room {
        case .edx: appState.edx.isBusy
        case .eels: appState.isEELSRoomBusy
        case .patterns: appState.ebsd.isBusy
        case .indexing: appState.indexing.isBusy || appState.ebsd.isOpening
        case .maps: appState.maps.isOpening || appState.maps.isSegmenting || appState.maps.isTexturing
        case .diffraction: appState.openItems.selected.map { $0.diffraction.isFitting || $0.diffraction.isIndexing } ?? false
            || appState.runningCBEDDocument != nil
        case .image: appState.simulatingDocument != nil || appState.scanningSTEMDocument != nil
        case .fft, .results: false
        }
    }

    /// The busy line of a STEM image's run (#1047): the section's own progress words.
    nonisolated static let scanningSentence = "Scanning the probe…"

    /// "Simulating: configuration 3 of 10": the Image room's frozen-phonon run (#896).
    nonisolated static func simulating(_ progress: SimulationModel.ThermalProgress) -> String {
        "Simulating: configuration \(progress.configuration) of \(progress.configurations)"
    }

    /// The run's fraction done: the configurations finished and the part of the one running.
    nonisolated static func simulationFraction(_ progress: SimulationModel.ThermalProgress) -> Double {
        let n = Double(max(progress.configurations, 1))
        return min(max((Double(progress.configuration - 1) + (progress.fraction ?? 0)) / n, 0), 1)
    }

    /// The toolbar's busy line for `room`'s run while another room is shown: the room, then the line it shows itself ("Maps · Segmenting
    /// grains…", "Indexing · Hough · 2340 of 4125"); nil while it is idle.
    @MainActor
    static func backgroundOperation(room: WorkspaceArea, appState: AppState) -> String? {
        if room == .indexing, appState.indexing.isBusy, let dataset = appState.indexing.patterns.dataset {
            return "\(room.title) · \(indexingLine(appState.indexing, dataset: dataset))"
        }
        return toolbarOperation(room: room, appState: appState).map { "\(room.title) · \($0)" }
    }
}

extension AppState {
    /// The Simulation document whose CBED run the selected item shows, while that run goes (#1021): the selected Simulation document,
    /// or the document of the selected CBED pattern. The CBED pattern opens in a tab of its own, where the document's Stop and progress
    /// sit far down the inspector; the toolbar's busy line, its Stop and ⌘. read this one, as the Image room's do for a simulation.
    var runningCBEDDocument: OpenItem? {
        guard let item = openItems.selected else { return nil }
        let document = DemoDocuments.isSimulation(item.url) ? item : simulationDocument(ofCBED: item)
        return document?.cbed.isComputing == true ? document : nil
    }
}
