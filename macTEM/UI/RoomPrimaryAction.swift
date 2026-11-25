//
//  RoomPrimaryAction.swift
//  Role: the toolbar's one verb for the room that has one (design 2026-10-22, §2.2): EDS has Quantify, EELS has Run (the stages that are not current,
//        in order), Patterns has Process, Indexing has Index, Maps has Segment, Diffraction has Index (#783), the Image room has Simulate for a
//        frozen-phonon HRTEM image (#896) and a STEM image (#1047), and the Diffraction room has Simulate for a CBED pattern of a
//        Simulation document while a Simulation document itself, live, has none (#1047); the FFT and Results rooms have none yet. The
//        button and its glass styles are ShellLayout's `PrimaryActionButton`; what the verb is, when it is enabled and what it says while blocked is this file's. Workspace > Run (⌘R)
//        runs the same verb from the menu, on exactly when the button can run it (`canRun`). A room without a verb shows Cancel in the
//        verb's place while a run left going in another room is the toolbar's busy line (`BusyOperation.backgroundRoom`).
//

import ShellControls
import ShellLayout
import SwiftUI
import TEMCore
import TEMSession
import ShellEDXModel

/// How far the running work is, for the toolbar's busy display: the EDS room's open, the EELS room's pass (align, thickness, fit), the
/// Patterns room's run or pass, the Indexing room's run; nil while idle or when the work reports no fraction (the Maps room's Segment and
/// texture report none).
enum RoomProgress {
    @MainActor
    static func fraction(room: WorkspaceArea, appState: AppState) -> Double? {
        switch room {
        case .edx: appState.edx.isOpening ? appState.edx.openProgress : nil
        case .eels: appState.eels.isComputing ? min(max(appState.eels.progress, 0), 1) : appState.hyperSpyWrite.map { min(max($0.fraction, 0), 1) }
        case .patterns: patternsFraction(appState.ebsd)
        case .indexing: appState.indexing.isIndexing ? min(max(appState.indexing.progress, 0), 1) : nil
        case .image:
            appState.simulatingDocument?.multislice.thermalProgress.map(BusyOperation.simulationFraction)
                ?? appState.scanningSTEMDocument?.stem.progress.map { min(max($0, 0), 1) }
        default: nil
        }
    }

    /// The Patterns room's running work in the order `BusyOperation.patterns` names it: Process, the map's pass, the quality pass.
    @MainActor
    private static func patternsFraction(_ session: EBSDSession) -> Double? {
        let fraction: Double
        if session.isProcessing {
            fraction = session.processProgress
        } else if session.isMapping {
            fraction = session.mapProgress
        } else if session.isQualityMapping {
            fraction = session.qualityProgress
        } else {
            return nil
        }
        return min(max(fraction, 0), 1)
    }
}

enum RoomPrimaryAction {
    /// The value for the toolbar, or nil when this room's verb does not apply (no verb, no document, or the document still opening).
    /// A room without a verb answers a Cancel alone (no title, running) while the toolbar shows another room's run.
    @MainActor
    static func current(_ appState: AppState) -> PrimaryAction? {
        switch appState.navigation.workspaceArea {
        case .edx:
            let session = appState.edx
            if session.isOpening {
                // Opening: the verb is the running state, so the toolbar shows Stop (as ⌘.); the read ends at its next check and the room
                // returns to what it showed (the owner's drive, 2026-10-23: an open could not be stopped from the window).
                return PrimaryAction(title: "Quantify", isEnabled: false, help: "Opening the spectrum image", hint: "Opening the spectrum image",
                                     isRunning: true, operationName: BusyOperation.name(room: .edx, appState: appState), stop: { session.stop() }, run: {})
            }
            guard session.hasImage else { return nil }
            return PrimaryAction(
                title: "Quantify",
                isEnabled: session.canQuantify,
                help: session.quantifyBlocker ?? "Fit the region's spectrum and compute the composition; from then on it follows every change",
                hint: "Fits the region's spectrum and computes the composition",
                isRunning: session.isBusy,
                operationName: BusyOperation.name(room: .edx, appState: appState),
                stop: { session.stop() },
                run: { session.quantify() })
        case .eels:
            let session = appState.eels
            guard session.hasImage, !session.isOpening else { return nil }
            let next = session.stages.first { $0.stage.isRun && $0.state != .current && ($0.stage != .fit || session.fitBlocker == nil) }
            return PrimaryAction(
                title: "Run",
                isEnabled: session.canRun,
                help: next.map { "Run the stages that are not current, starting with \($0.stage.title)" } ?? "Every stage is current",
                hint: "Aligns the zero-loss peak, maps the thickness and fits the picked edges",
                isRunning: appState.isEELSRoomBusy,
                operationName: BusyOperation.name(room: .eels, appState: appState),
                stop: { appState.stopEELSRoom() },
                run: { session.run() })
        case .patterns:
            // Process (pattern-processing design §4): the stages that are not current, over the whole scan, into memory.
            let session = appState.ebsd
            guard session.hasDataset, !session.isOpening else { return nil }
            return PrimaryAction(
                title: "Process",
                isEnabled: session.canProcess,
                help: session.processingRefusal?.sentence
                    ?? session.firstStaleStage.map { "Run the stages that are not current, starting with \($0.title)" } ?? "Every stage is current",
                hint: "Removes the backgrounds, rescales and bins every pattern of the scan",
                isRunning: session.isBusy,
                operationName: BusyOperation.name(room: .patterns, appState: appState),
                stop: { session.stop() },
                run: { session.process() })
        case .indexing:
            // Index (indexing-room design §3): the method picked over the whole scan, row by row (Hough) or block by block (dictionary)
            // onto the map; Stop keeps the indexed rows.
            let session = appState.indexing
            guard session.hasDataset, !session.patterns.isOpening else { return nil }
            return PrimaryAction(
                title: "Index",
                isEnabled: session.canIndex,
                help: session.verbHelp,
                hint: session.method == .hough ? "Detects the bands of every pattern and indexes them against the phases (Hough)"
                    : "Matches every pattern against patterns simulated from the master pattern (Dictionary)",
                isRunning: session.isBusy,
                operationName: BusyOperation.name(room: .indexing, appState: appState),
                stop: { session.stop() },
                run: { session.index() })
        case .maps:
            // Segment (orientation-maps-room design §2): the grain analysis of the whole map with the Grains and Misorientation
            // sections' settings: grains, boundaries, KAM, GOS, GND, the grain table and each grain's slip.
            let session = appState.maps
            guard session.hasMap, !session.isOpening else { return nil }
            return PrimaryAction(
                title: "Segment",
                isEnabled: session.canSegment,
                help: session.segmentBlocker
                    ?? (session.analysisIsStale ? "Segment again with the changed settings" : "Find the grains, their boundaries, KAM, GOS and GND"),
                hint: "Finds the grains of the map and computes KAM, GOS, GND and each grain's Schmid factors",
                isRunning: session.isSegmenting,
                operationName: BusyOperation.name(room: .maps, appState: appState),
                stop: { session.stop() },
                run: { session.segment() })
        case .image:
            // Simulate (#896): the frozen-phonon configurations of the selected HRTEM image's document; Stop keeps those done. A STEM
            // image's Simulate scans the probe (#1047).
            if let action = simulateAction(appState) ?? stemAction(appState) { return action }
            return backgroundCancel(appState)
        case .diffraction:
            guard let item = appState.openItems.selected, let image = item.session.image else { return nil }
            switch DiffractionSections.kind(of: item.url) {
            case .simulation:
                // A Simulation document's pattern is live: no verb and no Index (#1047). The Cancel of its CBED run while that goes.
                return cbedCancel(item) ?? backgroundCancel(appState)
            case .cbed:
                // The CBED pattern of a Simulation document: Simulate computes it for the settings now (#1047).
                guard let simulation = appState.simulationDocument(ofCBED: item) else { return backgroundCancel(appState) }
                return cbedAction(appState, simulation: simulation)
            case .measured:
                break
            }
            // Index (#783): the kit finds the spots and the crystal's full orientation, off the main actor; Stop drops the answer.
            let analysis = item.diffraction
            let blocker = analysis.indexBlocker(image: image)
            return PrimaryAction(
                title: "Index",
                isEnabled: blocker == nil,
                help: blocker ?? "Find the spots and the full orientation of \(analysis.crystal.name)",
                hint: "Finds the spots and the crystal's full orientation",
                isRunning: analysis.isIndexing || analysis.isFitting,
                operationName: BusyOperation.name(room: .diffraction, appState: appState),
                stop: { analysis.stop() },
                run: { PendingEdits.run { analysis.index(image: image) } })
        default:
            return backgroundCancel(appState)
        }
    }

    /// A room without a verb keeps the Cancel of a run left going in another room, the one the toolbar's centre shows (ShellLayout's
    /// `PrimaryAction.title`: nil, "but a run may still be in flight and keep its Cancel"; mac4DSTEM's `isRunning: appState.isBusy`
    /// whatever the room). It is ⌘.'s Stop as a button. A room with a verb keeps its verb: rooms run side by side, the shown room's
    /// verb may start its own run, and ⌘. still reaches the other one.
    @MainActor
    private static func backgroundCancel(_ appState: AppState) -> PrimaryAction? {
        guard let other = BusyOperation.backgroundRoom(appState), canStop(room: other, appState: appState) else { return nil }
        return PrimaryAction(
            title: nil,
            isRunning: true,
            operationName: BusyOperation.name(room: other, appState: appState).map { "\(other.title) · \($0)" } ?? other.title,
            stop: { RoomPrimaryAction.stopActive(appState) },
            run: {})
    }

    /// The Image room's Simulate, for a selected HRTEM image whose document has frozen phonons on (a static lattice is live and
    /// has no verb): Continue when configurations are stored and more are asked for.
    @MainActor
    private static func simulateAction(_ appState: AppState) -> PrimaryAction? {
        guard let item = appState.openItems.selected, let simulation = appState.simulationDocument(ofHRTEM: item) else { return nil }
        let model = simulation.multislice
        guard model.thermal != nil else { return nil }
        let analysis = simulation.diffraction
        let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
        let resumes = model.canContinue(crystal: crystal, zoneAxis: zoneAxis)
        let blocker = model.isSimulating ? nil : model.simulateBlocker(crystal: crystal, zoneAxis: zoneAxis)
        return PrimaryAction(
            title: resumes ? "Continue" : "Simulate",
            isEnabled: blocker == nil,
            help: blocker ?? (resumes ? "Run the configurations not yet averaged" : "Run the frozen-phonon configurations and average their images"),
            hint: "Runs the frozen-phonon configurations one at a time and averages their images",
            isRunning: model.isSimulating,
            operationName: BusyOperation.name(room: .image, appState: appState),
            stop: { model.stop() },
            run: { Task { await appState.simulateHRTEM(of: simulation) } })
    }

    /// A STEM image's Simulate (#1047): the scan of its Simulation document's settings now; Continue when a scan of them is held and
    /// incomplete. The section keeps the plan line; the button, its Stop and the progress are the toolbar's.
    @MainActor
    private static func stemAction(_ appState: AppState) -> PrimaryAction? {
        guard let item = appState.openItems.selected, let simulation = appState.simulationDocument(ofSTEM: item) else { return nil }
        let model = simulation.stem
        let refusal: String?
        let holds: Bool
        switch appState.stemRun(of: simulation) {
        case .failure(let why):
            refusal = why.sentence
            holds = false
        case .success(let run):
            refusal = model.blocker
            holds = model.holds(run.key)
        }
        let words = SimulateVerb.stem(refusal: refusal, holdsRun: holds, isComplete: model.scan?.isComplete == true)
        return PrimaryAction(
            title: words.title,
            isEnabled: words.isEnabled,
            help: words.help,
            hint: "Scans the probe over one projected unit; the image fills as it is computed",
            isRunning: model.isRunning,
            operationName: BusyOperation.name(room: .image, appState: appState),
            stop: { model.stop() },
            run: { Task { await appState.simulateSTEM(of: simulation) } })
    }

    /// The Simulate of a Simulation document's CBED pattern (#1047): enabled while the stored patterns are not those of the settings
    /// now (or there are none); Stop while the run goes, the patterns already stored staying.
    @MainActor
    private static func cbedAction(_ appState: AppState, simulation: OpenItem) -> PrimaryAction {
        let model = simulation.cbed
        let refusal = appState.cbedVerbRefusal(of: simulation)
        let current: Bool
        if case .success(let run) = appState.cbedRun(of: simulation) { current = model.isCurrent(run.key) } else { current = false }
        let words = SimulateVerb.cbed(refusal: refusal, isCurrent: current)
        return PrimaryAction(
            title: words.title,
            isEnabled: words.isEnabled,
            help: words.help,
            hint: "Runs the probe through the slab and stores a pattern at every thickness step",
            isRunning: model.isComputing,
            operationName: model.isComputing ? SimulateVerb.cbedOperation : nil,
            stop: { model.stop() },
            run: { Task { await appState.simulateCBED(of: simulation) } })
    }

    /// The Cancel of a Simulation document's own CBED run while that document is shown (it has no verb, #1047); nil while none goes.
    @MainActor
    private static func cbedCancel(_ document: OpenItem) -> PrimaryAction? {
        let model = document.cbed
        guard model.isComputing else { return nil }
        return PrimaryAction(title: nil, isRunning: true, operationName: SimulateVerb.cbedOperation, stop: { model.stop() }, run: {})
    }

    /// Workspace > Run (⌘R): the shown room's verb as its title ("Process", "Index"), "Run" in a room without one or with no window.
    @MainActor
    static func runTitle(_ appState: AppState?) -> String {
        appState.flatMap { current($0)?.title } ?? "Run"
    }

    /// Whether ⌘R runs `action` now: a verb that applies, is enabled and is not running. The toolbar button's own readiness, so ⌘R is
    /// never a dead key (mac4DSTEM's Run Current Task).
    @MainActor
    static func canRun(_ action: PrimaryAction?) -> Bool {
        guard let action, action.title != nil else { return false }
        return action.isEnabled && !action.isRunning
    }

    /// ⌘R: runs the shown room's verb when it can run now.
    @MainActor
    static func runActive(_ appState: AppState) {
        guard let action = current(appState), canRun(action) else { return }
        action.run()
    }

    /// The room ⌘. acts on: the shown room while it runs something Stop ends; else the room whose run the toolbar shows in its place
    /// (`BusyOperation.backgroundRoom`) when Stop ends it, so a run left going in another room can be stopped from any room; else the
    /// shown room.
    @MainActor
    static func stopTarget(_ appState: AppState) -> WorkspaceArea {
        let shown = appState.navigation.workspaceArea
        guard !canStop(room: shown, appState: appState), let other = BusyOperation.backgroundRoom(appState),
              canStop(room: other, appState: appState) else { return shown }
        return other
    }

    /// ⌘.: ends whatever the shown room is running, or, while it is idle, the run of another room the toolbar shows (`stopTarget`).
    @MainActor
    static func stopActive(_ appState: AppState) {
        switch stopTarget(appState) {
        case .edx: appState.edx.stop()
        case .eels: appState.stopEELSRoom()
        case .patterns: appState.ebsd.stop()
        case .indexing:
            // The room's own run first; else the open of the scan, which this room shows and draws with a Stop of its own (`canStop`).
            if appState.indexing.isBusy {
                appState.indexing.stop()
            } else if appState.ebsd.isOpening {
                appState.ebsd.stop()
            }
        case .maps: appState.maps.stop()
        case .diffraction:
            if let cbed = appState.runningCBEDDocument?.cbed { cbed.stop() } else { appState.openItems.selected?.diffraction.stop() }
        case .image:
            if let simulating = appState.simulatingDocument { simulating.multislice.stop() } else { appState.scanningSTEMDocument?.stem.stop() }
        default: break
        }
    }

    @MainActor
    static func canStop(_ appState: AppState) -> Bool {
        canStop(room: stopTarget(appState), appState: appState)
    }

    /// The Stop item's title: "Stop" for the shown room's run, "Stop Indexing" for the run of another room (`stopTarget`).
    @MainActor
    static func stopTitle(_ appState: AppState) -> String {
        let target = stopTarget(appState)
        return target == appState.navigation.workspaceArea ? "Stop" : "Stop \(target.title)"
    }

    /// Whether `room` runs something Stop ends (a layer's picture in the Maps room is not stopped; the open of the scan is the
    /// Indexing room's too, which shows it: `BusyOperation.isBusy`).
    @MainActor
    static func canStop(room: WorkspaceArea, appState: AppState) -> Bool {
        switch room {
        case .edx: appState.edx.isBusy
        case .eels: appState.isEELSRoomBusy
        case .patterns: appState.ebsd.isBusy
        case .indexing: appState.indexing.isBusy || appState.ebsd.isOpening
        case .maps: appState.maps.isOpening || appState.maps.isSegmenting || appState.maps.isTexturing
        case .diffraction: appState.openItems.selected.map { $0.diffraction.isFitting || $0.diffraction.isIndexing } ?? false
            || appState.runningCBEDDocument != nil
        case .image: appState.simulatingDocument != nil || appState.scanningSTEMDocument != nil
        default: false
        }
    }
}

/// The Simulate verb's title, readiness and help for a computed document (#1047), from plain facts. Pure, so a test reads the verb
/// per state as data.
nonisolated enum SimulateVerb {
    nonisolated struct Words: Equatable, Sendable {
        let title: String
        let isEnabled: Bool
        let help: String
    }

    /// The toolbar's busy line and Cancel's name while a CBED run goes (#1021's words).
    static let cbedOperation = "Computing the CBED patterns…"

    /// Why a CBED pattern cannot be computed with a Parallel beam.
    static let cbedParallelSentence = "The beam is Parallel: choose Convergent in the Simulation section to compute the CBED pattern."

    /// A STEM image: Continue while a scan of these settings is held and incomplete, else Simulate; off with `refusal` (the run's
    /// own refusal or another document's run) or when the image is complete for these settings.
    static func stem(refusal: String?, holdsRun: Bool, isComplete: Bool) -> Words {
        let resumes = holdsRun && !isComplete
        let complete = holdsRun && isComplete
        let help = refusal ?? (complete ? "The image is complete for these settings: change one to simulate again"
            : resumes ? "Scan the positions not yet done; what is finished stays"
            : "Scan the probe over one projected unit; the image fills as it is computed")
        return Words(title: resumes ? "Continue" : "Simulate", isEnabled: refusal == nil && !complete, help: help)
    }

    /// A CBED pattern of a Simulation document: Simulate, on while the stored patterns are not those of the settings now.
    static func cbed(refusal: String?, isCurrent: Bool) -> Words {
        let help = refusal ?? (isCurrent ? "The pattern shown is the one for these settings: change one to simulate again"
            : "Run the probe through the slab for the settings now, storing a pattern at every thickness step")
        return Words(title: "Simulate", isEnabled: refusal == nil && !isCurrent, help: help)
    }
}
