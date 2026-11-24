//
//  AppState.swift
//  Role: the window's composition root — the app's one window (ADR 007). It composes the owners, holds the shell's own
//        feedback channels, and stores the few facts listed under "Stored here", each with the reason it has no owner.
//        A feature's state lives in its owner: a new stored property names its owner first, or joins that list with
//        its reason.
//
//  Owners (each a `let` below; in brackets, where its type lives):
//  - the window: `navigation` (rooms and panes, App/), `openItems` (the files open in the window, each with its own
//    session, presentation, marks and viewport, TEMSession), `activityLog` (the Output pane, MacEMUI), `recents` (File >
//    Open Recent's last eight files, TEMSession), `lastSession` (File > Reopen Last Session's record, TEMSession),
//    `runActivity` (the activity held while a room works, App/), `launch` (the launch arguments, a value, App/).
//  - Image and Results: `imageRoomTools` (the Image room's measuring tool and readout, App/), `resultsRoom` (the Results
//    room's selection and shown groups, App/).
//  - Diffraction: `diffractionRoom` (the readout over the pattern, App/); the pattern's analysis and view state are each
//    open file's own, in `openItems`.
//  - EDS: `edx` (the spectrum image, picks and fit) and `edxRoom` (its spectrum window and export in flight), both the
//    shared room's, MacEMUI; `semEDS` (the SEM rows of an SEM spectrum, App/).
//  - EELS: `eels` (the spectrum image and what the room makes of it, TEMSession) and `eelsRoom` (its view state, App/).
//  - Patterns: `ebsd` (the dataset, position and pictures, TEMSession) and `patternsRoom` (its view state, App/).
//  - Indexing: `indexing` (the phases, settings and run on the Patterns room's dataset, TEMSession) and `indexingRoom`
//    (its view state, App/).
//  - Maps: `maps` (the orientation map, layer and pictures, TEMSession) and `mapsRoom` (its view state, App/).
//  - the SEM session: `semRecord` (the SEM rooms' exports and Output lines for the session report, App/).
//  - the files: `spectrumFiles` (what the Open found out about each file that spans rooms, and the rules that read it,
//    TEMSession).
//  `imageSession`, `presentation` and `measurements` are the selected item's, forwarded, so the views that read them did
//  not change with V1-13.
//
//  The shell's feedback channels: `statusText` (the infobar's line, each also an Output line), `errorMessage` (the alert),
//  `closeRequest` (the question before files with unsaved marks close), `openImageRequest` (the open panel's request
//  counter) and `lastOpen` (the newest Open in flight, which a test awaits).
//
//  Stored here, against the rule, for its reason:
//  - `busySince`, when each room last became busy, for the toolbar's busy clock (`RunClock`): it spans the rooms and is
//    not observed (the clock ticks on its own), so it is no room's view state.
//

import ShellLayout
import Foundation
import TEMCore
import TEMSession
import ShellEDXModel
import ShellSpectroscopy

@Observable
final class AppState {
    let navigation = WorkspaceNavigation()
    let openItems = OpenItems(frameReader: AppState.readFrame(_:_:), reader: AppState.read(_:))
    let activityLog = ActivityLog()
    let imageRoomTools = ImageRoomTools()
    let resultsRoom = ResultsRoomState()
    let diffractionRoom = DiffractionRoomState()
    let edx = EDXSession(host: .macTEM)
    let edxRoom = EDXRoomState()
    /// The EDS room's SEM rows for an SEM `.hspy` spectrum (line intensities with background windows, window quantification).
    let semEDS = SEMEDSState()
    let eels = EELSSession()
    /// The Patterns room's dataset, position and pictures (TEMSession) and its view state (App/).
    let ebsd: EBSDSession
    let patternsRoom = PatternsRoomState()
    /// The Indexing room's phases, settings and run on the Patterns room's dataset (TEMSession) and its view state (App/).
    let indexing: IndexingSession
    let indexingRoom = IndexingRoomState()
    /// The Maps room's orientation map, layer and pictures (TEMSession) and its view state (App/).
    let maps = OrientationMapSession()
    let mapsRoom = MapsRoomState()
    /// What the SEM rooms did that none of them keeps: every file they wrote and their Output lines with times (App/), for the Results
    /// room's session rows and the session report.
    let semRecord = SEMSessionRecord()
    /// File > Open Recent's list (TEMSession): every file an Open has opened (`rememberOpened`), with the bookmark that opens it again. The app passes
    /// the list kept in UserDefaults (`RecentFiles.stored()`); a bare `AppState()`, a test's, keeps one in memory and writes nothing.
    let recents: RecentFiles
    /// File > Reopen Last Session's record (TEMSession): the files open, the selected one and the room, written as they change
    /// (`recordLastSession`), and the previous launch's, which the menu offers. The app passes the record kept in UserDefaults
    /// (`LastSession.stored()`); a bare `AppState()`, a test's, keeps one in memory and writes nothing.
    let lastSession: LastSession
    /// The `ProcessInfo` activity held while any room works (`RunActivity`), so App Nap and idle sleep never slow a long run; a test
    /// passes one that counts.
    let runActivity: RunActivity
    /// What the Open found out about each file that spans rooms (spectrum images, their scans, the files of the EDS and EELS rooms) and
    /// the rules that read it (TEMSession).
    let spectrumFiles = SpectrumFiles()

    /// The window's title: the file of the room that is shown (the spectrum image in the EDX and EELS rooms, the image elsewhere).
    var windowTitle: String {
        let name: String? = switch navigation.workspaceArea {
        case .edx: edx.fileName
        case .eels: eels.fileName
        case .patterns, .indexing: ebsd.fileName
        case .maps: maps.fileName
        default: imageSession.image?.fileName
        }
        if let name, !name.isEmpty { return name }
        return imageSession.image?.fileName ?? AppName.display
    }
    let eelsRoom = EELSRoomState()

    /// What the views read with no file open: an empty session and presentation, never written.
    @ObservationIgnored private let idleSession = ImageSession()
    @ObservationIgnored private let idlePresentation = ImagePresentation()
    @ObservationIgnored private let idleMeasurements = ImageMeasurements()

    /// The selected item's session (the open image, its file, whether it is being read), else an empty one.
    var imageSession: ImageSession { openItems.selected?.session ?? idleSession }
    /// The selected item's presentation (the canvas and the colormap), else an empty one.
    var presentation: ImagePresentation { openItems.selected?.presentation ?? idlePresentation }
    /// The selected item's marks (V1-5), else an empty owner.
    var measurements: ImageMeasurements { openItems.selected?.measurements ?? idleMeasurements }

    /// The infobar's one line, events only (an open, an error), empty otherwise; every non-empty change is also an
    /// Output line.
    var statusText = "" {
        didSet { activityLog.record(statusText) }
    }

    /// The alert's text; nil when no alert is up. Dismissing it puts the title back to the generic one, so an alert raised by
    /// setting this alone is never titled by the one before.
    var errorMessage: String? {
        didSet { if errorMessage == nil { errorTitle = ErrorDetail.genericTitle } }
    }

    /// The alert's title (#529): "macEM can't open this file" for a file that could not be opened, else "Something went wrong".
    var errorTitle = ErrorDetail.genericTitle

    /// The question up before files with unsaved marks close (`requestClose`, CloseGuard.swift); nil when none is asked.
    var closeRequest: CloseRequest?

    /// Bumped by every "Open Image…" gesture; `ContentView` presents the open panel when it changes.
    private(set) var openImageRequest = 0

    var hasImage: Bool { imageSession.image != nil }

    /// The newest Open in flight (routing, then the reads): a test awaits it.
    @ObservationIgnored var lastOpen: Task<Void, Never>?
    /// The app's windows, once this one is on screen (`AppWindows.enroll`): a file opened into a window that holds one already goes
    /// to a tab of its own through them (`open(urls:refused:)`), and the last-session record is made over all of them. Nil for a
    /// state no window shows (a test's, or before the window appears): everything then opens here, as it did with one window.
    @ObservationIgnored weak var windows: AppWindows?
    /// The launch's `--open` files after the first, each for a tab of its own once the window is on screen (taken once).
    @ObservationIgnored var launchFilesForTabs: [URL] = []
    /// Opens whose routing or reads are still running: a window with one is taken, though it holds nothing yet.
    @ObservationIgnored var opensInFlight = 0
    /// This Mac's memory, in bytes, which the size rule holds each file against before it is read (`RoomSizeRule`, #905). A test sets
    /// a smaller one.
    @ObservationIgnored var physicalMemory = ProcessInfo.processInfo.physicalMemory
    /// The window was closed and its files let go (`AppWindows.windowWillClose`): an Open still on its way loads nothing more into
    /// this state and leaves the last-session record to the windows on screen (#925).
    @ObservationIgnored var windowClosed = false
    /// Brings this state's window forward (`WindowTabbing`, the one place the `NSWindow` is known); nil while no window shows it.
    @ObservationIgnored var showWindow: (() -> Void)?
    /// This state's own window (an `NSWindow`, from `WindowTabbing`; typed `AnyObject` so this file needs no AppKit): the window a
    /// save panel, an alert or a question this state asks is a sheet on, never whichever window is main (#625). nil while none shows it.
    @ObservationIgnored var sheetWindow: (() -> AnyObject?)?
    /// Exports of this window being rendered and written right now (never more than one: a second is refused with a beep). Per window,
    /// so a write in one window never blocks an export in another (#625).
    @ObservationIgnored var exportsWriting = 0
    /// A HyperSpy file being written from the EELS room's cube (#819): the room's running work, which the toolbar shows with its
    /// fraction and ⌘. stops (`isEELSRoomBusy`); nil while none is.
    var hyperSpyWrite: HyperSpyCubeWrite?
    /// Whether the EELS room has work in flight: its run, or a HyperSpy file being written from its cube.
    var isEELSRoomBusy: Bool { eels.isBusy || hyperSpyWrite != nil }

    /// Ends the EELS room's work: a cube's write at its next band (the destination is left as it was), and the room's run. While
    /// both are in flight the toolbar names the run, and one ⌘. stops both.
    func stopEELSRoom() {
        hyperSpyWrite?.task.cancel()
        if eels.isBusy { eels.stop() }
    }
    /// When each room with a busy line last became busy (`markBusy`): the start of the toolbar's busy clock (`RunClock`). Not
    /// observed: the clock ticks on its own.
    @ObservationIgnored var busySince: [WorkspaceArea: Date] = [:]

    /// The launch arguments this window started with (`--export-dir` is read where an export chooses its URL).
    let launch: LaunchOptions

    /// Where an export journey writes without a panel (`--export-dir`): an absolute path as given, a relative one inside the app's
    /// temporary folder (the sandbox lets the app write there, a test runner outside it cannot name it). nil for a person.
    var exportDirectory: URL? {
        guard let dir = launch.exportDirectory else { return nil }
        return dir.path.hasPrefix("/") && !launch.exportDirectoryIsRelative ? dir : FileManager.default.temporaryDirectory.appendingPathComponent(launch.exportDirectoryName ?? "export", isDirectory: true)
    }

    init(launch: LaunchOptions = LaunchOptions(), recents: RecentFiles? = nil, lastSession: LastSession? = nil,
         runActivity: RunActivity? = nil) {
        self.launch = launch
        self.recents = recents ?? RecentFiles()
        self.lastSession = lastSession ?? LastSession()
        self.runActivity = runActivity ?? RunActivity()
        let ebsd = EBSDSession()
        self.ebsd = ebsd
        indexing = IndexingSession(patterns: ebsd)
        // The spectrum rooms follow the selected file through the list's own callback (a view's observation did not fire on screen, drive 6),
        // and the last-session record takes the new selection.
        openItems.onSelect = { [weak self] _ in
            self?.spectrumRoomsFollowSelection()
            self?.recordLastSession()
        }
        openItems.onReadFailure = { [weak self] _, error in self?.present(FileOpenFailure(error)) }
        // A stack frame that could not be read: the status line, Output and VoiceOver say which and why (the slider is back on the frame shown).
        openItems.onFrameFailure = { [weak self] in self?.report(event: $0, in: nil) }
        // Every session's event line: the infobar, the SEM rooms' session record, and VoiceOver for a line that ends something.
        edx.onEvent = { [weak self] in self?.report(event: $0, in: nil) }
        edx.onFailure = { [weak self] in self?.present($0) }
        eels.onEvent = { [weak self] in self?.report(event: $0, in: nil) }
        eels.onFailure = { [weak self] in self?.present($0) }
        ebsd.onEvent = { [weak self] in self?.report(event: $0, in: .patterns) }
        ebsd.onFailure = { [weak self] in self?.present($0) }
        maps.onEvent = { [weak self] in self?.report(event: $0, in: .maps) }
        maps.onFailure = { [weak self] in self?.present($0) }
        // Every dataset the Patterns room binds: the Indexing room starts over on it, and the Maps room drops the old dataset's maps
        // (its own and an Indexing run on it) and shows the new one's crystal map with the patterns beside (a map opened on its own
        // gives way to it); both go back when the dataset closes, a map opened on its own stays.
        ebsd.onBind = { [weak self] document in
            guard let self else { return }
            self.indexing.bind(document)
            self.maps.patternsChanged(to: OrientationMapSession.patternsDocument(fileName: document.fileName, url: document.url,
                                                                                 dataset: document.dataset))
        }
        ebsd.onClose = { [weak self] in
            self?.indexing.close()
            self?.maps.patternsClosed()
        }
        indexing.onEvent = { [weak self] in self?.report(event: $0, in: .indexing) }
        // Every file the SEM rooms write is kept for the Results room and the session report (D-SEM-104).
        patternsRoom.onWritten = { [weak self] in self?.semRecord.wrote($0) }
        indexingRoom.onWritten = { [weak self] in self?.semRecord.wrote($0) }
        mapsRoom.onWritten = { [weak self] in self?.semRecord.wrote($0) }
        indexing.onFailure = { [weak self] in self?.present($0) }
        applyLaunchOptions(launch)
        holdActivityWhileRoomsWork()
    }

    /// The UI tests' and the demo's starting state (`LaunchOptions`): saved geometry cleared, the generated documents opened.
    private func applyLaunchOptions(_ launch: LaunchOptions) {
        if launch.isUITesting { LaunchOptions.resetSavedState(); UITestingPlacement.installIfTesting() }
        if launch.demoImage { open(urls: [DemoDocuments.latticeURL]) }
        if launch.demoPattern { openDemo(.diffraction) }
        if launch.demoStack, let url = try? DemoDocuments.stackFile() { open(urls: [url]) }
        if let side = launch.demoLargeImageSide, let url = try? DemoDocuments.largeImageFile(side: side) { open(urls: [url]) }
        if launch.demoSEMImage, let url = try? DemoDocuments.semImageFile() { open(urls: [url]) }
        if launch.demoSpectrumFile, let url = try? DemoDocuments.spectrumFile() { open(urls: [url]) }
        if launch.demoSEMSpectrum { openDemo(.semSpectrum) }
        if launch.demoOrientationMap { openDemo(.orientationMap) }
        if launch.demoSpectrum {
            edx.bind(DemoDocuments.edx())
            if launch.demoRegions { DemoDocuments.drawRegions(on: edx) }
        }
        if launch.demoEELS, let loaded = try? DemoDocuments.eels() {
            eels.bind(loaded)
            if launch.demoRegions { DemoDocuments.drawRegions(on: eels) }
        }
        if launch.demoEBSD, let document = try? DemoDocuments.ebsd() {   // the generated set: planted numbers for the journey
            ebsd.bind(document); navigation.workspaceArea = .patterns
        }
        // `--open`: the path a drop takes. One file per window: the first opens here, each other in a tab of its own once this window
        // is on screen (`launchFilesForTabs`, taken by `ImageWindow`); a state no window shows (a test's) never hands them on.
        if let first = launch.openFiles.first { open(urls: [first]) }
        launchFilesForTabs = Array(launch.openFiles.dropFirst())
        reconcileRoom()
    }

    func requestOpenImage() {
        openImageRequest &+= 1
    }

    /// A room can be entered when the window holds data for it (`RoomAvailability`); one that is not built never can.
    func selectWorkspace(_ area: WorkspaceArea) {
        guard roomUnavailableReason(area) == nil else { return }
        navigation.workspaceArea = area
        recordLastSession()
    }

    /// The room Show Next Room (`forward`) or Show Previous Room goes to (`WorkspaceArea.neighbour`), nil when there is none.
    func neighbourRoom(forward: Bool) -> WorkspaceArea? {
        navigation.workspaceArea.neighbour(forward: forward) { roomUnavailableReason($0) == nil }
    }

    /// Go to a workspace: the room it was last in when that can still be entered, else its first room that can. A workspace none of
    /// whose rooms can be entered is not entered (`workspaceUnavailableReason`).
    func selectWorkspaceGroup(_ group: WorkspaceGroup) {
        guard group != navigation.workspaceArea.group else { return }
        let candidates = [navigation.lastRoom[group]].compactMap { $0 } + group.parts
        if let room = candidates.first(where: { roomUnavailableReason($0) == nil }) { navigation.workspaceArea = room }
    }

    /// Indexing's `Open in Maps` (D-SEM-99): the last run's crystal map to the Maps room without a file, at the pattern pinned in
    /// Patterns and Indexing, and the Maps room in front. The returned task ends when the map is drawn; nil when nothing went across
    /// (`IndexingSession.openInMapsRefusal`, said in the status line, or the map could not be built, said in the error sheet).
    @discardableResult
    func openIndexingInMaps() -> Task<Void, Never>? {
        if let refusal = indexing.openInMapsRefusal { statusText = refusal; return nil }
        do {
            guard let run = try indexing.mapsDocument() else { statusText = "Index first"; return nil }
            let drawn = maps.bind(run, pinned: ebsd.pinned)
            followMapsPin()
            selectWorkspace(.maps)
            return drawn
        } catch {
            present(error)
            return nil
        }
    }

    /// The Maps room's `Source` pop-up: the map held as `id`, at the same point where it has it (`OrientationMapSession.showSource`),
    /// the pattern pane beside it on the same point.
    @discardableResult
    func showMapsSource(_ id: OrientationMapSession.Document.ID) -> Task<Void, Never>? {
        let drawn = maps.showSource(id)
        followMapsPin()
        return drawn
    }

    /// A map on the Patterns room's scan takes the pattern pinned there, or the origin when it does not reach it (a stopped run's
    /// rows): the Patterns room follows, so the crosshair and the live pattern pane beside it show the same point. The Maps room also
    /// calls it on every change of its pick, whatever made it (the map, the arrows, ⌘-click, a Grains-table row).
    func followMapsPin() {
        guard let dataset = ebsd.dataset, maps.isOnScan(of: dataset), ebsd.pinned != maps.pinned else { return }
        ebsd.pin(maps.pinned)
    }

    /// The other way, as the Maps room shows and while it does: a map on the Patterns room's scan takes the point picked in Patterns or
    /// Indexing, so its marker and the live pattern pane beside it name one point; where the map does not reach it (a stopped run's
    /// rows) the Patterns room takes the map's (`followMapsPin`). Only when the two differ: `OrientationMapSession.pin` re-selects the
    /// grain under the point, which would collapse a ⌘-click selection.
    func mapsFollowPatternsPin() {
        guard let dataset = ebsd.dataset, maps.isOnScan(of: dataset), ebsd.pinned != maps.pinned else { return }
        maps.pin(ebsd.pinned)
        followMapsPin()
    }

    /// What the Maps room says of the map it shows when that is an Indexing run (`IndexingSession.staleness(ofRun:method:)`), nil
    /// otherwise.
    var mapsStaleness: String? {
        guard case .indexing(let run, let method) = maps.document?.source else { return nil }
        return indexing.staleness(ofRun: run, method: method)
    }

    /// What the shared EDS room's views ask of this window: the status line, the error sheet, a UI journey's export folder, the app's Open.
    var edxActions: EDXRoomActions {
        // The room's own Open goes through the app's one Open, as the EELS, Patterns, Indexing and Maps rooms' buttons do (#318): the file
        // gets its Open Files and Results rows, and Open Recent remembers it.
        EDXRoomActions(report: { [weak self] in self?.statusText = $0 }, present: { [weak self] in self?.present($0) },
                       exportDirectory: { [weak self] in self?.exportDirectory },
                       open: { [weak self] url in _ = self?.open(urls: [url]) })
    }

    /// The alert and the status line for `error`: its sentence, and for a system error its domain, code and underlying error
    /// (`ErrorDetail`), so a sandbox denial and a missing file read apart.
    func present(_ error: any Error) {
        let detail = ErrorDetail.text(error)
        errorMessage = detail
        errorTitle = ErrorDetail.title(error)
        statusText = "Error: \(detail)"
    }
}

/// A HyperSpy file being written from the EELS cube: the write, the file's name for the toolbar's busy line, and how far it is.
struct HyperSpyCubeWrite {
    let task: Task<Void, any Error>
    let fileName: String
    var fraction = 0.0
}
