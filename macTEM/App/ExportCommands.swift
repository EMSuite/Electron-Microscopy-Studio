//
//  ExportCommands.swift
//  Role: the File menu's export items, in their own `Commands`, so `ImageCommands` and `AppState` stay as they are; the scene adds
//        `ExportCommands()` to its `.commands`. They act on the focused window's `AppState`. The menu lists only the room on
//        screen's exports, as mac4DSTEM's File menu does (#631, Paul's pick): Export Image… (⇧⌘E) and Export Profile… in the Image
//        room, Export Transform… (⌥⌘E), Export Radial Profile… and Export Spots… in the FFT room, Export Results… (⇧⌥⌘E) in the
//        Results room, and Export Session Report… in the Results room and the rooms that feed it (`FixedExports.listed(in:)`);
//        each still enabled only where it can act (`ExportSnapshot.availability`, `ExportSnapshot.fftAvailability`,
//        `SEMSessionLedger.hasRows`). The EDS room's nine (`ExportSnapshot.edsAvailability`), the EELS room's eleven
//        (`eelsAvailability`), the Patterns room's six (`patternsAvailability`), the Indexing room's five
//        (`indexingAvailability`) and the Maps room's six (`mapsAvailability`) are listed while their room shows its document,
//        each through the room's own export (`RoomExports`), the call its inspector button makes. Every room ends the group with
//        Export Methods Record… and puts Copy Methods Paragraph (⌥⌘C, the design's F3) in the Edit menu after the pasteboard's items (#818,
//        `MethodsRecordExport`), both enabled while the room holds a result. The Image, Diffraction and EELS rooms list Export
//        HyperSpy File… before it (#819, `HyperSpyExportPanel`) and the EELS room's core loss on its own item; a cube's write is
//        the room's running work, which ⌘. stops.
//
//        PLACEMENT: after the Save group, which this app's File menu fills with Close Image and Close Window (`ImageCommands`
//        replaces it) — the anchor already known to render here. `.importExport`, the HIG's home of Export, would put the items
//        in a group of their own, but it is not checked on screen in this window, and an item that silently does not appear
//        costs more than one without its own section; a Divider keeps them apart from Close. The drive confirms the menu,
//        and moving them is this one placement. ⇧⌘E collides with nothing in macTEM (⌘E is the system's Use Selection
//        for Find).
//

import ShellSpectroscopy
import SwiftUI

struct ExportCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        // Read once: both items follow the same state, and a second read of the focused value is a second dependency.
        let availability = appState.map(ExportSnapshot.availability(of:))
        let fft = appState.map(ExportSnapshot.fftAvailability(of:))
        let session = appState.map(SEMSessionLedger.hasRows(_:))
        let eds = appState.flatMap(ExportSnapshot.edsAvailability(of:))
        let eels = appState.flatMap(ExportSnapshot.eelsAvailability(of:))
        let patterns = appState.flatMap(ExportSnapshot.patternsAvailability(of:))
        let indexing = appState.flatMap(ExportSnapshot.indexingAvailability(of:))
        let maps = appState.flatMap(ExportSnapshot.mapsAvailability(of:))
        let fixed = FixedExports.listed(in: appState?.navigation.workspaceArea)
        let methods = appState.map(MethodsRecordExport.isAvailable(in:))
        let hyperSpy = appState.map { HyperSpyExportPanel.isAvailable(in: $0) }
        let diffractionFigure = appState.map { ExportSnapshot.diffractionFigureAvailable(in: $0) }
        CommandGroup(after: .saveItem) {
            // Export Figure…: the Image room's picture, or the Diffraction room's figure of the pattern on screen (#822). One item on
            // one key, as one room is on screen at a time.
            let inDiffraction = appState?.navigation.workspaceArea == .diffraction
            if fixed.contains(.image) || inDiffraction {
                Divider()
                Button("Export Figure…") {
                    guard let appState else { return }
                    if inDiffraction { ExportPanels.exportDiffractionFigure(appState: appState) } else { ExportPanels.exportImage(appState: appState) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(inDiffraction ? diffractionFigure != true : availability?.image != true)
            }
            // The Image room's profile.
            if fixed.contains(.image) {
                Button("Export Profile…") {
                    if let appState { ExportPanels.exportProfile(appState: appState) }
                }
                .disabled(availability?.profile != true)
            }
            // The FFT room's three, enabled with the spectrum on screen current.
            if fixed.contains(.fft) {
                Divider()
                Button("Export Transform…") {
                    if let appState { ExportPanels.exportTransform(appState: appState) }
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(fft?.transform != true)
                Button("Export Radial Profile…") {
                    if let appState { ExportPanels.exportRadialProfile(appState: appState) }
                }
                .disabled(fft?.profile != true)
                Button("Export Spots…") {
                    if let appState { ExportPanels.exportSpots(appState: appState) }
                }
                .disabled(fft?.spots != true)
            }
            if fixed.contains(.results) || fixed.contains(.sessionReport) { Divider() }
            // The Results room's one: every finished measurement of the file as one CSV. ⇧⌥⌘E is free (⌘E is the
            // system's Use Selection for Find; ⇧⌘E and ⌥⌘E are the Image and FFT rooms').
            if fixed.contains(.results) {
                Button("Export Results…") { if let appState { ExportPanels.exportResults(appState: appState) } }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(availability?.results != true)
            }
            // The SEM session as one report (D-SEM-103): enabled wherever the SEM rooms hold a result; no key.
            if fixed.contains(.sessionReport) {
                Button("Export Session Report…") {
                    if let appState { ExportPanels.exportSessionReport(appState: appState) }
                }
                .disabled(session != true)
            }
            // The EDS room's nine, in the menu only while that room shows a spectrum image.
            if let appState, let eds { edsItems(eds, appState: appState) }
            // The EELS room's eleven, on the same terms.
            if let appState, let eels { eelsItems(eels, appState: appState) }
            // The Patterns room's six, while that room shows a dataset.
            if let appState, let patterns { patternsItems(patterns, appState: appState) }
            // The Indexing room's five, on the same terms.
            if let appState, let indexing { indexingItems(indexing, appState: appState) }
            // The Maps room's six, while that room shows a map.
            if let appState, let maps { mapsItems(maps, appState: appState) }
            // Every room's methods record of its result (#818), last: it describes what the exports above hold. Before it, in the
            // Image and Diffraction rooms, the image or pattern as a HyperSpy file (#819).
            Divider()
            if let appState, [.image, .diffraction, .eels].contains(appState.navigation.workspaceArea) {
                hyperSpyItems(appState, available: hyperSpy == true)
            }
            Button("Export Methods Record…") { if let appState { MethodsRecordExport.exportRecord(appState: appState) } }
                .disabled(methods != true)
                .accessibilityIdentifier("menu.exportMethodsRecord")
        }
        // The figure and the paragraph go where a copy goes: Edit, after the pasteboard's items, always listed and dimmed where they
        // cannot act (HIG, Menus). Copy Figure (#823) puts the Diffraction room's figure on the clipboard as PDF and PNG on ⇧⌘C, beside
        // Copy's ⌘C, which stays the system's for the inspector's fields; free in this app's key table.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Figure") { if let appState { ExportPanels.copyDiffractionFigure(appState: appState) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(diffractionFigure != true)
            Button("Copy Methods Paragraph") { if let appState { MethodsRecordExport.copyParagraph(appState: appState) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(methods != true)
                .accessibilityIdentifier("menu.copyMethodsParagraph")
        }
    }

    /// Export HyperSpy File… (#819) in the Image, Diffraction and EELS rooms, and the EELS room's core loss on an item of its own. A
    /// cube's write is the EELS room's running work, which ⌘. stops.
    @ViewBuilder
    private func hyperSpyItems(_ appState: AppState, available: Bool) -> some View {
        Button("Export HyperSpy File…") { HyperSpyExportPanel.export(appState: appState) }
            .disabled(!available)
            .accessibilityIdentifier("menu.exportHyperSpy")
        if HyperSpyExportPanel.hasCoreLoss(appState) {
            Button("Export Core Loss HyperSpy File…") { HyperSpyExportPanel.export(appState: appState, coreLoss: true) }
                .disabled(!HyperSpyExportPanel.isAvailable(in: appState, coreLoss: true))
                .accessibilityIdentifier("menu.exportHyperSpyCoreLoss")
        }
    }

    /// The EDS room's exports, named and ordered as mac4DSTEM's Spectroscopy exports are: each enabled by the rule of its button in
    /// the room's inspector (`ExportSnapshot.edsAvailability`) and written by the room's own export (`RoomExports.eds`). No keys.
    @ViewBuilder
    private func edsItems(_ eds: EDSExportAvailability, appState: AppState) -> some View {
        Divider()
        Button("Export Spectrum CSV…") { RoomExports.eds(.spectrum, appState: appState) }
            .disabled(!eds.spectrum)
        Button("Export Maps…") { RoomExports.eds(.mapsPNG, appState: appState) }
            .disabled(!eds.maps)
        Button("Export Results CSV…") { RoomExports.eds(.results, appState: appState) }
            .disabled(!eds.results)
        Button("Export Method JSON…") { RoomExports.eds(.method, appState: appState) }
            .disabled(!eds.results)
        Button("Export Regions CSV…") { RoomExports.eds(.pins, appState: appState) }
            .disabled(!eds.regions)
        // The figures for a paper (#902), named as the inspector's buttons.
        Button("Export Spectrum PDF…") { RoomExports.eds(.spectrumPDF, appState: appState) }
            .disabled(!eds.spectrum)
        Button("Export Spectrum SVG…") { RoomExports.eds(.spectrumSVG, appState: appState) }
            .disabled(!eds.spectrum)
        Button("Export Maps PDF…") { RoomExports.eds(.mapsPDF, appState: appState) }
            .disabled(!eds.maps)
        Button("Export Maps SVG…") { RoomExports.eds(.mapsSVG, appState: appState) }
            .disabled(!eds.maps)
    }

    /// The EELS room's exports, each named "Export" and its inspector button's title, in the EDS items' order with the two the EELS
    /// room adds (`EELSExportAvailability.menuKinds`): enabled by the button's rule and written by the room's own export. No keys.
    @ViewBuilder
    private func eelsItems(_ eels: EELSExportAvailability, appState: AppState) -> some View {
        Divider()
        ForEach(EELSExportAvailability.menuKinds) { kind in
            Button("Export \(kind.title)") { RoomExports.eels(kind, appState: appState) }
                .disabled(!eels.isEnabled(kind))
        }
    }

    /// The Patterns room's exports, each named "Export" and its inspector button's title, in the inspector's order: the map and the
    /// overlay items enabled by `ExportSnapshot.patternsAvailability`, each written by the room's own export. No keys.
    @ViewBuilder
    private func patternsItems(_ patterns: PatternsExportAvailability, appState: AppState) -> some View {
        Divider()
        ForEach(PatternsExportKind.allCases) { kind in
            Button("Export \(kind.title)") { RoomExports.patterns(kind, appState: appState) }
                .disabled(!patterns.isEnabled(kind))
        }
    }

    /// The Indexing room's exports, each named "Export" and its inspector button's title, in the inspector's order: all enabled once
    /// the run on screen has reached a point (`ExportSnapshot.indexingAvailability`), each written by the room's own export. No keys.
    @ViewBuilder
    private func indexingItems(_ indexing: IndexingExportAvailability, appState: AppState) -> some View {
        Divider()
        ForEach(IndexingExportKind.allCases) { kind in
            Button("Export \(kind.title)") { RoomExports.indexing(kind, appState: appState) }
                .disabled(!indexing.indexed)
        }
    }

    /// The Maps room's exports, each named "Export" and its inspector button's title, in the inspector's order: enabled by the
    /// button's rule (`ExportSnapshot.mapsAvailability`) and written by the room's own export. No keys.
    @ViewBuilder
    private func mapsItems(_ maps: MapsExportAvailability, appState: AppState) -> some View {
        Divider()
        ForEach(MapsExportKind.allCases) { kind in
            Button("Export \(kind.title)") { RoomExports.maps(kind, appState: appState) }
                .disabled(!maps.isEnabled(kind))
        }
    }
}

/// Which of the File menu's fixed export groups a room lists (#631): each room only its own, as mac4DSTEM's File menu does. No window
/// in focus lists none. The rooms with their own items (EDS, EELS, Patterns, Indexing, Maps) list them through their availability.
nonisolated enum FixedExports: Hashable, Sendable {
    case image, fft, results, sessionReport

    static func listed(in area: WorkspaceArea?) -> Set<FixedExports> {
        guard let area else { return [] }
        switch area {
        case .image: return [.image]
        case .fft: return [.fft]
        case .results: return [.results, .sessionReport]
        case .edx, .patterns, .indexing, .maps: return [.sessionReport]
        case .diffraction, .eels: return []
        }
    }
}
