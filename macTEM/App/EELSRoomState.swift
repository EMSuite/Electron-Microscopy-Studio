//
//  EELSRoomState.swift
//  Role: the EELS room's own view state (the import request, the Maps control, the zoom the maps share, the tool, the export in flight, the status line's
//        readout). The room's facts are `EELSSession`'s (TEMSession); this holds only what the views share between the centre and the inspector.
//        Window-wide, not saved; composed by `AppState` as `EDXRoomState` is.
//

import Foundation
import Observation
import UniformTypeIdentifiers
import ShellExport
import ShellSpectroscopy
import TEMCore
import TEMSession
import ShellEDXModel

@Observable
final class EELSRoomState {
    /// Bumped by every "Open EELS Spectrum Image…" gesture; the room presents the open panel when it changes.
    private(set) var importRequest = 0
    /// The tile shown alone (nil: the block).
    var soloTile: String?
    /// The zoom and position every map shares (pinch, scroll, drag; a double click resets).
    var mapView = MapViewTransform()
    /// How the maps are coloured (the scale bar's popover); window-wide, reset with a new file.
    var appearance = MapAppearance()
    /// The drawing tool (the inspector's Tools section) and whether the Regions list's selection belongs to a line (the last thing touched).
    var tool: RegionTool = .pointer
    var linesFocused = false
    /// The Maps control's pick, and the sentence for a segment the person tried while it was off (cleared by the next pick).
    var maps: EELSMapsSegment = .tOverLambda
    var mapsNotice: String?
    /// The Maps section's display filter (control placement §11): the kernel the quantified tiles are DRAWN through, never their numbers
    /// (`EELSMapDisplay`). Window-wide; the 3 × 3 average by default, as the EDS room's.
    var mapFilter: EELSMapFilter = .mean3x3
    /// The status line's cursor readout: the pixel and its values over a map, the energy and counts over the spectrum; nil when the pointer is elsewhere.
    var readout: String?
    /// What the spectrum last wrote to `readout` (`setSpectrumReadout`).
    private var spectrumText: String?
    /// `readout` while it is the spectrum's own (the energy and the counts under the pointer); nil while it is a map's pixel, or nothing. The spectrum's
    /// accessibility value says this, so it never speaks a map's pixel as its own.
    var spectrumReadout: String? { readout != nil && readout == spectrumText ? readout : nil }
    /// The map pixel under the pointer (nil off the maps), and whether ⌥ is down: while both hold, the plot draws that pixel's spectra as a temporary
    /// layer (control placement §7), gone when the key is released.
    var hoverPixel: EELSHoverPixel?
    var optionHeld = false
    /// The pixel whose spectra the plot draws now: the hovered one while ⌥ is down. Reads `hoverPixel` only then, so a plain hover redraws no plot.
    var spectrumPixel: EELSHoverPixel? { optionHeld ? hoverPixel : nil }
    /// The spectrum's counts axis: log (the room's default) or linear.
    var spectrumIsLog = true
    /// The spectrum's energy window (nil: the whole axis) and its counts zoom (1: the automatic top), as the EDS spectrum's `window` and `yZoom`.
    var spectrumWindow: ClosedRange<Double>?
    var spectrumYZoom = 1.0
    /// The export whose save panel is up.
    var exporting: EELSExportKind?
    /// An export being made (its record's fingerprint can take a second on a large file): a second click waits for it.
    private(set) var isMakingExport = false
    /// The spectrum image's source as its records name it, kept for the file it was worked out for, so the next export does not
    /// hash the file again; a fingerprint of the counts held is never kept, since Align replaces the cube.
    @ObservationIgnored private var keptSource: (filePath: String, source: MethodsRecord.Source)?
    /// The bytes of the export in flight (made before the panel opens, as the EDS room's).
    private(set) var exportData = Data()
    /// What the maps export draws besides the pictures: the scale bar (when the file states a pixel size) and the selected region.
    var exportScaleBar = true
    var exportRegions = true

    /// Makes the bytes of `kind` and opens the save panel, or, with `directory` (the UI journeys' export folder), writes the file there through
    /// `ExportDirectoryFile`; says why when there is nothing to write or the file cannot be written. The EDS room's `EDXRoomState.export`.
    @MainActor func export(_ kind: EELSExportKind, from session: EELSSession, maps: [EELSMapTile], directory: URL? = nil,
                           report: (String) -> Void) async {
        let made: Data?
        var figure: (scene: FigureScene, format: FigureExport.Format)?
        switch kind {
        case .results: made = session.resultsCSV.map { Data($0.utf8) }
        case .spectrum: made = session.spectrumCSV.map { Data($0.utf8) }
        case .spectrumMSA:
            do { made = try session.spectrumMSA() } catch { report("MSA export failed: \(error.localizedDescription)"); return }
        case .regions: made = session.regionsCSV.map { Data($0.utf8) }
        case .diagnostics: made = session.diagnosticsCSV.map { Data($0.utf8) }
        case .method: made = session.methodJSON.map { Data($0.utf8) }
        case .mapsPNG:
            made = mapsContent(session, maps: maps).flatMap { EDXMapsFigure.png($0) }
        case .spectrumPDF, .spectrumSVG, .mapsPDF, .mapsSVG:
            // The figures for a paper (#902): the scene here, the bytes below, with the methods record in their metadata.
            let scene = kind == .spectrumPDF || kind == .spectrumSVG
                ? session.plot.map { FigurePlot.spectrum(EELSFigures.spectrum($0), style: FigureStyle(width: .mm90)) }
                : mapsContent(session, maps: maps)?.vectorScene()
            if let scene, let format = kind.figureFormat { figure = (scene, format) }
            made = figure == nil ? nil : Data()
        }
        guard let made else { report("Nothing to export yet for \(kind.title.dropLast())."); return }
        guard !isMakingExport else { return }
        let ext = kind.contentType.preferredFilenameExtension ?? "txt"
        // Taken before the wait: another file opened meanwhile drops this export rather than naming its bytes after the new file.
        let fileName = session.fileName, loaded = session.source, methodJSON = session.methodJSON
        var data = made
        if let figure {
            // A figure is drawn with its methods record in its metadata (#902): PDF Subject, SVG <metadata>.
            isMakingExport = true
            defer { isMakingExport = false }
            var record: String?
            if let loaded {
                let source = await recordSource(loaded)
                record = try? ExportMethods.eelsRecord(app: ExportSnapshot.methodsApp(), exportKind: "eels-" + kind.rawValue, source: source,
                                                       methodJSON: methodJSON).json()
            }
            let metadata = FigureMetadata(title: fileName, creator: ExportSnapshot.provenance(), methodsRecord: record)
            do { data = try FigureExport.data(figure.scene, format: figure.format, metadata: metadata) } catch {
                report("Export failed: \(error.localizedDescription)"); return
            }
            guard session.source?.filePath == loaded?.filePath, session.fileName == fileName else { return }
        } else if let loaded, ExportSnapshot.eelsExportCarriesRecord(fileExtension: ext) {
            // The bytes with their methods record inside (#817).
            isMakingExport = true
            defer { isMakingExport = false }
            let source = await recordSource(loaded)
            data = await ExportSnapshot.eelsExport(made, exportKind: "eels-" + kind.rawValue, fileExtension: ext, source: source,
                                                   methodJSON: methodJSON)
            guard session.source?.filePath == loaded.filePath, session.fileName == fileName else { return }
        }
        if let directory {
            let name = (fileName as NSString).deletingPathExtension + kind.suffix + "." + ext
            do {
                let url = try ExportDirectoryFile.write(data, named: name, into: directory)
                report("Exported \(url.lastPathComponent)")
            } catch { report("Export failed: \(error.localizedDescription)") }
            return
        }
        exportData = data
        exporting = kind
    }

    /// The source a record names, kept per file: the file is hashed once, and a fingerprint of the counts held never kept.
    @MainActor private func recordSource(_ loaded: LoadedEELS) async -> MethodsRecord.Source {
        if let kept = keptSource, kept.filePath == loaded.filePath, !kept.filePath.isEmpty { return kept.source }
        let source = await ExportSnapshot.eelsSource(loaded)
        if !source.kind.contains("as held") { keptSource = (loaded.filePath, source) }
        return source
    }

    /// What the maps figure draws: the maps the Maps control shows, the colour mix the person chose, by the export's two toggles.
    @MainActor private func mapsContent(_ session: EELSSession, maps: [EELSMapTile]) -> EDXFigureContent? {
        let chosen = Set(EELSMixComposition.selection(appearance.mix, maps: maps))
        return session.figureContent(maps: maps, mix: maps.filter { chosen.contains($0.id) }, appearance: appearance, scaleBar: exportScaleBar,
                                     regions: exportRegions)
    }

    /// The save panel is done, written or not: the export's bytes are let go (#619), not kept until the next export.
    func didFinishExport() { exportData = Data() }

    func requestImport() { importRequest &+= 1 }

    /// The spectrum's hover: the status line's readout, marked as the spectrum's (`spectrumReadout`); nil when the pointer leaves the plot.
    func setSpectrumReadout(_ text: String?) {
        spectrumText = text
        readout = text
    }

    /// A new file starts the view over.
    func reset() {
        soloTile = nil; mapView.reset(); appearance = MapAppearance(); maps = .tOverLambda; mapsNotice = nil; readout = nil; hoverPixel = nil; spectrumWindow = nil; spectrumYZoom = 1
        spectrumText = nil
    }
}
