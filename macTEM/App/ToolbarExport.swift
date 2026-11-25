//
//  ToolbarExport.swift
//  Role: the toolbar's Export button (#1048, Paul's pick of 25 Nov 2026), in the slot beside the verb that `ShellToolbar(documentMenu:)`
//        gives each app: a click runs the room's main export, the chevron lists the room's own exports (`RoomExportItems`, the same view
//        the File menu draws, so the two lists cannot drift). HIG Toolbars: the commands people use most, each with a menu bar command.
//        What the main export is per room, and why the button is off, is this file's, pure so a test reads it as data. The old Image menu
//        repeated File > Open and Close (#629's departure, kept for full screen with the menu bar hidden): ⌘O and ⌘W still work there,
//        and the welcome screen has Open.
//

import Foundation
import ShellSpectroscopy

/// The toolbar's Export: its words, the main export per room, and when it is off. Pure.
nonisolated enum ToolbarExport {
    static let title = "Export"
    static let systemImage = "square.and.arrow.up"
    static let help = "Export from this room"
    /// Why the button is off: no document in the room shown, or it is still opening.
    static let nothingSentence = "Nothing to export yet: open a file in this room"

    /// A click's export: the room's main one, the one ⇧⌘E runs where a room has it, else the first item its File menu lists.
    enum Primary: String, CaseIterable, Sendable {
        case imageFigure, diffractionFigure, transform, results, edsSpectrum, eelsSpectrum, patternsMap, indexingMap, mapsMap

        /// The File menu item a click runs, as that item is titled.
        var menuTitle: String {
            switch self {
            case .imageFigure, .diffractionFigure: "Export Figure…"
            case .transform: "Export Transform…"
            case .results: "Export Results…"
            case .edsSpectrum: "Export Spectrum CSV…"
            case .eelsSpectrum: "Export \(EELSExportKind.spectrum.title)"
            case .patternsMap: "Export \(PatternsExportKind.mapPNG.title)"
            case .indexingMap: "Export \(IndexingExportKind.mapPNG.title)"
            case .mapsMap: "Export \(MapsExportKind.map.title)"
            }
        }
    }

    /// The main export of `area`.
    static func primary(in area: WorkspaceArea) -> Primary {
        switch area {
        case .image: .imageFigure
        case .diffraction: .diffractionFigure
        case .fft: .transform
        case .results: .results
        case .edx: .edsSpectrum
        case .eels: .eelsSpectrum
        case .patterns: .patternsMap
        case .indexing: .indexingMap
        case .maps: .mapsMap
        }
    }

    /// Why the button is off, or nil while the room shown holds a document: the button and its menu need one.
    static func blocker(hasDocument: Bool) -> String? {
        hasDocument ? nil : nothingSentence
    }
}

extension ToolbarExport {
    /// Whether `primary` can run now: its File menu item's own rule.
    @MainActor
    static func isEnabled(_ primary: Primary, appState: AppState) -> Bool {
        switch primary {
        case .imageFigure: ExportSnapshot.availability(of: appState).image
        case .diffractionFigure: ExportSnapshot.diffractionFigureAvailable(in: appState)
        case .transform: ExportSnapshot.fftAvailability(of: appState).transform
        case .results: ExportSnapshot.availability(of: appState).results
        case .edsSpectrum: ExportSnapshot.edsAvailability(of: appState)?.spectrum == true
        case .eelsSpectrum: ExportSnapshot.eelsAvailability(of: appState)?.isEnabled(.spectrum) == true
        case .patternsMap: ExportSnapshot.patternsAvailability(of: appState)?.isEnabled(.mapPNG) == true
        case .indexingMap: ExportSnapshot.indexingAvailability(of: appState)?.indexed == true
        case .mapsMap: ExportSnapshot.mapsAvailability(of: appState)?.isEnabled(.map) == true
        }
    }

    /// Runs `primary` through the call its File menu item makes, when it can run.
    @MainActor
    static func run(_ primary: Primary, appState: AppState) {
        guard isEnabled(primary, appState: appState) else { return }
        switch primary {
        case .imageFigure: ExportPanels.exportImage(appState: appState)
        case .diffractionFigure: ExportPanels.exportDiffractionFigure(appState: appState)
        case .transform: ExportPanels.exportTransform(appState: appState)
        case .results: ExportPanels.exportResults(appState: appState)
        case .edsSpectrum: RoomExports.eds(.spectrum, appState: appState)
        case .eelsSpectrum: RoomExports.eels(.spectrum, appState: appState)
        case .patternsMap: RoomExports.patterns(.mapPNG, appState: appState)
        case .indexingMap: RoomExports.indexing(.mapPNG, appState: appState)
        case .mapsMap: RoomExports.maps(.map, appState: appState)
        }
    }

    /// The button's reason to be off in `appState`'s room shown (`AppState.processAreaHasDocument`: an image still loading is none).
    @MainActor
    static func blocker(_ appState: AppState) -> String? {
        blocker(hasDocument: appState.processAreaHasDocument)
    }
}
