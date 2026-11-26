import ShellHelp
import ShellLayout
import SwiftUI
import TEMCore
import TEMSession
import ShellEDXModel
import ShellSpectroscopy
import SpectroCore

/// The detail column: the science, and the infobar + process area along its bottom edge. The column's chassis (the divider,
/// its drag, the infobar, the process area and their scene-stored fractions) is ShellLayout's `WorkspaceColumn` (suite task 8,
/// MacEMUI); what stays here is what the canvas shows (the room switch, welcome, loading, unreadable). The room actions and
/// the file name live in the toolbar, not here. **There is no workspace header**; readiness has one owner, the inspector's
/// Settings tab.
struct WorkspaceView: View {
    @Environment(AppState.self) private var appState

    /// Whether the process area has a document to sit under: the room's own (a spectrum image, the dataset, the map), else an open
    /// image (`ProcessAreaDocuments`, View > Show Output's rule too). An image that is absent or still loading forces the area shut
    /// regardless of the dragged fraction, which is NOT reset for it.
    private var hasDocument: Bool { appState.processAreaHasDocument }

    var body: some View {
        WorkspaceColumn(
            navigation: appState.navigation.panels,
            tabs: [ProcessTab.output { OutputPane(log: appState.activityLog) }] + diffractionTabs + mapsTabs,
            // One tab at a time at full width, chosen in the area's header, one toggle for the area (#1112): side by side, two tables
            // and Output were about 180 pt each and clipped, under up to four look-alike toggles.
            processAreaStyle: .tabs,
            hasDocument: hasDocument,
            statusText: cursorReadout ?? appState.statusText,
            isRunning: showsRun,
            canvas: { content },
            run: { runSlot },
            glance: { glanceSlot })
            // The SEM rows of the EDS room (SEM conditions, exspy's line windows) follow the EDS room's file, and an SEM spectrum gets its
            // elements picked in the room so the room's own Quantify serves it (D-SEM-107). The load hangs here, on a view that is always
            // drawn: a `.task` on inspector rows that draw nothing until it has run never started (drive 2026-11-08).
            .task(id: appState.edx.source?.metadata.filePath) {
                await appState.semEDS.load(path: appState.edx.source?.metadata.filePath)
                await appState.semEDS.pickFileElements(in: appState.edx)
            }
    }

    /// The Maps room's tables (#1095): Grains and Slip while the room shows a map, none elsewhere.
    private var mapsTables: [MapsTable] {
        guard appState.navigation.workspaceArea == .maps, appState.maps.document != nil else { return [] }
        return MapsTable.allCases
    }

    /// The Maps room's tables as tabs of the bottom area beside Output, under the bar the person drags (#1095, #1112); the window
    /// selects each on its own once it has something to list (`MapsRoomState.offer`). When the room or its map goes, a table left
    /// selected shows as Output (`ProcessAreaLayout.shownTab`).
    private var mapsTabs: [ProcessTab] {
        mapsTables.map { table in
            ProcessTab(id: table.paneID, title: table.title, systemImage: table.systemImage) {
                MapsTablePane(table: table)
            }
        }
    }

    /// The Diffraction room's tables (#1094): the part's (`DiffractionPart.tables`) while the room shows a document, none elsewhere.
    private var diffractionTables: [DiffractionTable] {
        guard appState.navigation.workspaceArea == .diffraction, appState.openItems.selected != nil else { return [] }
        return DiffractionPart.tables(appState.diffractionPart)
    }

    /// The Diffraction room's tables as tabs of the bottom area beside Output, under the bar the person drags (#1094, #1112); the
    /// window selects the part's opening table on its own once (`DiffractionRoomState.offer`). When another part or room takes the
    /// tables away, a table left selected shows as Output (`ProcessAreaLayout.shownTab`).
    private var diffractionTabs: [ProcessTab] {
        diffractionTables.map { table in
            ProcessTab(id: table.paneID, title: table.title, systemImage: table.systemImage) {
                DiffractionTablePane(table: table)
            }
        }
    }

    /// The room's cursor readout, which stands in the status line while the pointer is over a picture (control placement §7).
    private var cursorReadout: String? {
        switch appState.navigation.workspaceArea {
        case .edx: appState.edxRoom.readout
        case .eels: appState.eelsRoom.readout
        case .patterns: appState.patternsRoom.readout
        case .indexing: appState.indexingRoom.readout
        // The live pattern pane is the Patterns room's own (it writes that room's readout); the map's words otherwise.
        case .maps: appState.mapsRoom.readout ?? appState.patternsRoom.readout
        case .image: appState.imageRoomTools.readout
        case .fft: appState.imageRoomTools.spectrumReadout
        case .diffraction: appState.diffractionRoom.readout
        default: nil
        }
    }

    private var showsRun: Bool { InfobarRunPolicy.shows(area: appState.navigation.workspaceArea, eelsComputing: appState.eels.isComputing) || showsFit }

    /// The Diffraction room's ring fit or Index, while it runs and the room is shown.
    private var showsFit: Bool {
        InfobarRunPolicy.showsFit(area: appState.navigation.workspaceArea,
                                  fitting: appState.openItems.selected.map { $0.diffraction.isFitting || $0.diffraction.isIndexing } ?? false)
    }

    /// A room's pass in flight, in the infobar where every run of the suite sits (the owner, 2026-10-23: not a bar over the maps): the bar, the percent and Stop.
    @ViewBuilder
    private var runSlot: some View {
        if showsFit, let analysis = appState.openItems.selected?.diffraction {
            // A fit has no fraction to show: the bar is indeterminate.
            if analysis.isIndexing {
                InfobarRunReadout(operation: "Index", progress: nil, line: { _ in "Indexing" }, onCancel: { analysis.stop() })
            } else {
                InfobarRunReadout(operation: "Ring fit", progress: nil, line: { _ in "Fitting" }, onCancel: { analysis.stop() })
            }
        } else if showsRun {
            let eels = appState.eels
            InfobarRunReadout(operation: "EELS", progress: eels.progress, line: { _ in InfobarRunPolicy.percent(eels.progress) }, onCancel: { eels.stop() })
        }
    }

    /// The standing fact: this app's memory, in Finder's decimal style (the engine's name tells nothing).
    private var glanceSlot: some View {
        InfobarGlance(help: "This app's memory footprint") {
            OperationMetricsFormat.glance(residentMB: SystemMonitor.residentMemoryMB() * 1.048576)
        }
    }

    /// The room's pane, the welcome door before any image, and the open in flight over either. The Image and
    /// FFT rooms are built, and a room that is not built cannot be selected (`AppState.selectWorkspace`). An open in
    /// flight is drawn OVER the image already shown: if it fails, that image is still there, at its zoom.
    @ViewBuilder
    private var content: some View {
        if appState.navigation.workspaceArea == .edx {
            EDXRoom(session: appState.edx, state: appState.edxRoom, actions: appState.edxActions, openExtensions: EDXOpening.readableExtensions)
        } else if appState.navigation.workspaceArea == .eels {
            EELSRoom()
        } else if appState.navigation.workspaceArea == .patterns {
            PatternsRoom()
        } else if appState.navigation.workspaceArea == .indexing {
            IndexingRoom()
        } else if appState.navigation.workspaceArea == .maps {
            MapsRoom()
        } else if let item = appState.openItems.selected {
            if item.session.image != nil, item.presentation.canvas != nil {
                // Keyed by the item: switching items is a new pane, which starts from the item's own committed zoom
                // and pan (`ImagePane`), not the last pane's. (Not `canvas.contentVersion`: two files with equal
                // pixels are two items.)
                Group {
                    // The room switch: the FFT room shows the image beside its transform, the Results room the file's
                    // measurements; the Image room its pane.
                    if appState.navigation.workspaceArea == .fft {
                        FFTRoom(item: item)
                    } else if appState.navigation.workspaceArea == .results {
                        ResultsRoom(item: item)
                    } else if appState.navigation.workspaceArea == .diffraction {
                        DiffractionRoom(item: item)
                    } else {
                        ImagePane(item: item)
                    }
                }
                    .id(item.id)
                    // The Image and Diffraction rooms take a stack's frame keys in their own keyed container (`ImageKeyedRoom`,
                    // `DiffractionKeyedPane`), beside the mark and spot cursor's keys: a second focusable ancestor here would take the
                    // keyboard from them on every click (macEM#509).
                    .stackArrowKeys(item: item, items: appState.openItems,
                                    enabled: ![.image, .diffraction].contains(appState.navigation.workspaceArea))
                    .overlay {
                        if item.session.isLoading { loadingState(item).background(.regularMaterial) }
                    }
            } else if let failure = item.readFailure {
                unreadableState(item, failure)
            } else {
                // First read, or a cold item about to be read again once the selection rests.
                loadingState(item)
            }
        } else if appState.navigation.workspaceArea == .results, SEMSessionLedger.hasRows(appState) {
            // The Results room with no image open: the SEM session's rows alone (D-SEM-103); with nothing open, the welcome door.
            ResultsSessionRoom()
        } else {
            WelcomeWorkspace()
        }
    }

    private func unreadableState(_ item: OpenItem, _ failure: String) -> some View {
        ContentUnavailableView {
            Label("Can't read \(item.url.lastPathComponent)", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure)
        } actions: {
            Button("Try Again") { appState.openItems.restoreSelected() }
        }
        .accessibilityIdentifier("welcome.unreadableStatus")
    }

    /// "Opening image", the stage the read reports and the time it has taken, and a Stop that closes the file (which cancels its
    /// read): a 375 MB SEM TIFF takes long enough to look stuck without them (macEM#562).
    private func loadingState(_ item: OpenItem) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Opening image")
            Text("Opening image")
                .font(.headline)
            if let since = item.openingSince {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(OpeningStatus.line(stage: item.openStage, elapsed: context.date.timeIntervalSince(since)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("welcome.loadingStage")
                Button("Stop") { appState.requestClose([item.id]) }
                    .help("Stop opening \(item.url.lastPathComponent) and close it")
                    .accessibilityLabel("Stop opening \(item.url.lastPathComponent)")
                    .accessibilityIdentifier("welcome.stopOpening")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.loadingStatus")
    }
}

/// The line under "Opening image": the stage the reader reported, and from two seconds on the time the open has taken, so a quick
/// open does not flash a clock. Pure, so a test holds it.
nonisolated enum OpeningStatus {
    static func line(stage: OpenStage?, elapsed: TimeInterval) -> String {
        let step = (stage ?? .reading).sentence
        guard elapsed >= 2 else { return step }
        let seconds = Int(elapsed)
        return "\(step) · \(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// The canvas before any image: the app's name, its door, and the demo data beside it for someone with no file at hand.
struct WelcomeWorkspace: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearsActive) private var appearsActive
    private let crash = CrashReportOffer.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // After a crash or a hang: one line offering the report, until it is dismissed (#801).
                if crash.isOffered {
                    HStack(spacing: 10) {
                        Label(CrashReportOffer.line, systemImage: "exclamationmark.bubble")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Report a Problem…") { openWindow(id: FeedbackWindow.id) }
                            .accessibilityIdentifier("welcome.crashReport.report")
                        Button("Dismiss") { crash.dismiss() }
                            .accessibilityIdentifier("welcome.crashReport.dismiss")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: LayoutPolicy.readableWidth)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("welcome.crashReport")
                }
                VStack(spacing: 12) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(AppName.display)
                        .font(.largeTitle.weight(.semibold))
                    Text("TEM and SEM images, EDS and EELS spectra, electron diffraction and EBSD, native on the Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: LayoutPolicy.readableWidth)
                }
                HStack(spacing: 12) {
                    Button("Open Image…") { appState.requestOpenImage() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .help(OpenItemRowFormat.openPrompt)
                        .accessibilityIdentifier("welcome.openImage")
                    // The same documents as Help > Open Demo Data (DemoData.swift): generated ones and the shipped SEM data.
                    Menu("Try Demo Data") {
                        ForEach(DemoDocument.allCases) { demo in
                            Button(demo.title) { appState.openDemo(demo) }
                        }
                    }
                    .controlSize(.large)
                    .fixedSize()
                    .help("Open a demo document in its room")
                    .accessibilityIdentifier("welcome.tryDemo")
                    // File > New Simulation (#788): a simulated pattern with no measured one, from the welcome canvas too (#802).
                    Button("New Simulation") { appState.newSimulation() }
                        .controlSize(.large)
                        .help("Simulate a diffraction pattern with no measured one, in the Diffraction room (⇧⌘N)")
                        .accessibilityIdentifier("welcome.newSimulation")
                }
                // The tutorials on the website, beside the demo data (#753, #802): Help > Tutorials opens the same page.
                Link(destination: HelpMenuLinks.tutorials.url) {
                    Label("Tutorials", systemImage: "book")
                }
                .help("Open the tutorials in your browser: one page per task, in three steps")
                .accessibilityLabel("Tutorials, opens in your browser")
                .accessibilityIdentifier("welcome.tutorials")
                recentList
                Text(WelcomeRecents.dropHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        // macOS hands the report over a little after the launch: read the folder again whenever the window comes forward.
        .onChange(of: appearsActive) { _, active in if active { crash.refresh() } }
    }

    /// The files File > Open Recent lists, each opened by a click (#802); nothing while there are none.
    @ViewBuilder private var recentList: some View {
        let entries = appState.recents.entries
        let rows = WelcomeRecents.rows(paths: entries.map(\.path), titles: entries.map { appState.recents.title(of: $0) })
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    // The rows are made from `entries` in its order, so a row's offset is its entry's.
                    ForEach(Array(rows.enumerated()), id: \.element.path) { index, row in
                        let entry = entries[index]
                        if index > 0 { Divider() }
                        Button { appState.openRecent(entry) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).lineLimit(1).truncationMode(.middle)
                                    Text(row.folder).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(row.path)
                        .accessibilityLabel("Open \(row.title)")
                        .accessibilityHint("in \(row.folder)")
                        .accessibilityIdentifier("welcome.recent.\(index)")
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
            .frame(maxWidth: LayoutPolicy.readableWidth)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("welcome.recent")
        }
    }
}

/// ← and → step through the frames of an image stack (Home and End go to the ends) while the picture has the keyboard; a click on it
/// gives it the keyboard, and it is the default focus of the window while nothing else is being typed in. Nothing for an item that is not a stack.
private struct StackArrowKeys: ViewModifier {
    let item: OpenItem
    let items: OpenItems
    /// Off in a room whose own keyed container steps the frames.
    let enabled: Bool
    @FocusState private var hasFocus: Bool

    func body(content: Content) -> some View {
        if enabled, let stack = item.stack {
            content
                .focusable()
                // DEPARTURE from the system focus ring (#629): the picture fills the pane, so a ring round it reads as a selection of
                // the picture; the pane has the keys after a click on it (below), as `FFTKeyedRoom` and `SEMMapPick` do.
                .focusEffectDisabled()
                .focused($hasFocus)
                .simultaneousGesture(TapGesture().onEnded { hasFocus = true })
                // The picture is the DEFAULT focus: it has the keyboard when nothing else claims it, and never takes it from a field the person is in
                // (an inspector entry) when the pane is rebuilt. A click on it takes the keyboard (above).
                .defaultFocus($hasFocus, true)
                .onKeyPress(.leftArrow) { items.stepFrame(item, by: -1); return .handled }
                .onKeyPress(.rightArrow) { items.stepFrame(item, by: 1); return .handled }
                .onKeyPress(.home) { items.showFrame(item, to: 0); return .handled }
                .onKeyPress(.end) { items.showFrame(item, to: stack.frameCount - 1); return .handled }
        } else {
            content
        }
    }
}

private extension View {
    func stackArrowKeys(item: OpenItem, items: OpenItems, enabled: Bool) -> some View {
        modifier(StackArrowKeys(item: item, items: items, enabled: enabled))
    }
}

/// When the infobar shows a room's run, and its words (pure).
nonisolated enum InfobarRunPolicy {
    /// The EELS room's map or fit pass, while it runs and the room is shown.
    static func shows(area: WorkspaceArea, eelsComputing: Bool) -> Bool { area == .eels && eelsComputing }

    /// The Diffraction room's ring fit, while it runs and the room is shown (control placement: progress in the infobar, not the pane header).
    static func showsFit(area: WorkspaceArea, fitting: Bool) -> Bool { area == .diffraction && fitting }

    static func percent(_ f: Double) -> String { "\(Int((min(max(f, 0), 1) * 100).rounded())) %" }
}
