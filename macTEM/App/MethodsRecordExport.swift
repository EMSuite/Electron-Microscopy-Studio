//
//  MethodsRecordExport.swift
//  Role: File > Export Methods Record… and Copy Methods Paragraph (#818, plan row X2): the methods record of what the room on screen
//        holds, as the JSON file a paper's supplement carries or as the paragraph its methods section quotes. The record is the one
//        the room's exports carry inside them (#817, `ExportMethods`), with "methods-record" as its export kind and nothing drawn.
//        The agent door's `get_methods_record` returns the same record and paragraph.
//
//        WHICH RESULT: the Image room's file (its source and the measurements' lineage); the Results room's finished measurements;
//        the FFT room's transform on screen, with its measured spots when there are some; the Diffraction room's centre, scale and
//        readout once a ring or a spot is measured; the EELS room's method once a stage ran. A room with no result gives no record
//        and both items are disabled. The SEM rooms and the EDS room follow in their own change (#818).
//
//        "Leave out file names" is the save panel's checkbox, remembered with the exports' (`ExportMethods.leaveOutFileNamesKey`);
//        the paragraph keeps the names, as the person copies it into their own text.
//

import AppKit
import ShellExport
import TEMCore
import TEMSession
import UniformTypeIdentifiers

@MainActor
enum MethodsRecordExport {
    /// The export kind every methods record written by these two items carries.
    static let exportKind = "methods-record"

    /// Whether the room on screen holds a result to record, without building the record (the menu reads it at every redraw).
    static func isAvailable(in appState: AppState) -> Bool {
        let item = appState.openItems.selected
        let hasImage = item?.session.image != nil && !appState.imageSession.isLoading
        switch appState.navigation.workspaceArea {
        case .image: return hasImage
        case .results: return hasImage && ExportSnapshot.availability(of: appState).results
        case .fft: return hasImage && ExportSnapshot.fftAvailability(of: appState).transform
        case .diffraction: return hasImage && item.map { !$0.diffraction.rings.isEmpty || !$0.diffraction.spots.isEmpty } == true
        case .eels: return appState.eels.hasMethodRecord
        case .edx, .patterns, .indexing, .maps: return false
        }
    }

    /// The record of what the room on screen holds; nil when it holds no result.
    static func record(of appState: AppState, software: String = ExportSnapshot.softwareName()) -> MethodsRecord? {
        guard isAvailable(in: appState) else { return nil }
        let app = ExportSnapshot.methodsApp()
        if appState.navigation.workspaceArea == .eels {
            return appState.eels.source.map {
                ExportSnapshot.eelsMethods(exportKind: exportKind, source: $0, methodJSON: appState.eels.methodJSON)
            }
        }
        guard let item = appState.openItems.selected, let image = item.session.image else { return nil }
        let source = source(of: item, image: image, software: software)
        switch appState.navigation.workspaceArea {
        case .image, .results:
            var record = ExportMethods.imageRecord(app: app, exportKind: exportKind, source: source, lineage: item.measurements.lineage,
                                                   drawn: [])
            record.room = appState.navigation.workspaceArea.rawValue
            return record
        case .fft:
            // The measured spots when there are some (their record holds the transform's steps too), else the transform.
            if let spots = ExportSnapshot.spotsSnapshot(image: image, url: item.url, analysis: item.fft, software: software) {
                return ExportMethods.fftRecord(app: app, exportKind: exportKind, source: source, header: spots.header,
                                               product: .spots(count: spots.rows.count, maskRadius: spots.maskRadius, maskEdge: spots.maskEdge),
                                               drawn: [])
            }
            guard item.fft.isSpectrumCurrent, let spectrum = item.fft.spectrum else { return nil }
            return ExportMethods.fftRecord(app: app, exportKind: exportKind, source: source,
                                           header: ExportSnapshot.fftHeader(image: image, spectrum: spectrum, software: software),
                                           product: .transform, drawn: [])
        case .diffraction:
            let analysis = item.diffraction
            return ExportMethods.diffractionRecord(app: app, source: source, header: analysis.exportHeader(image: image),
                                                   rows: analysis.readout(image: image), exportKind: exportKind)
        case .eels, .edx, .patterns, .indexing, .maps:
            return nil
        }
    }

    /// The file's image as the record's source; a demo answered from memory has no file, so its pixels stand for it, by their own
    /// fingerprint and size.
    private static func source(of item: OpenItem, image: CalibratedImage, software: String) -> MethodsRecord.Source {
        if let source = ExportSnapshot.imageSource(of: item, image: image, software: software) { return source }
        let identity = SessionSourceIdentity.of(image, fileByteSize: Int64(image.pixels.count * MemoryLayout<Float>.size))
        return ExportMethods.source(ExportSource(image: image, software: software), byteCount: Int(identity.byteSize),
                                    fingerprint: identity.pixelSHA256, kind: "image")
    }

    /// "<file stem> methods": the name the save panel offers.
    nonisolated static func defaultName(fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return (stem.isEmpty ? "analysis" : stem) + " methods"
    }

    /// The record's JSON as the file holds it: as it is, or with each source named "source 1", "source 2", ... .
    nonisolated static func json(_ record: MethodsRecord, leaveOutFileNames: Bool) throws -> String {
        try (leaveOutFileNames ? record.withoutFileNames() : record).json()
    }

    // MARK: Entry points

    /// File > Export Methods Record…: the record as a JSON file the person places with the save panel. With `--export-dir` (a UI
    /// journey) it is written into that folder without a panel.
    static func exportRecord(appState: AppState) {
        guard let record = record(of: appState) else { return }
        let name = defaultName(fileName: record.sources.first?.fileName ?? "")
        if let directory = appState.exportDirectory {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                appState.present(error)
                return
            }
            write(record, leaveOutFileNames: false, to: directory.appendingPathComponent(name + ".json"), appState: appState)
            return
        }
        guard let window = ExportPanels.hostWindow(for: appState) else {
            NSSound.beep()
            return
        }
        let fileNames = ExportPanels.rememberedFileNameChoice()
        let panel = ExportPanels.savePanel(type: .json, name: name,
                                           directory: ExportPanels.defaultFolder(for: appState.openItems.selected?.url),
                                           message: "The methods record of the \(record.room) room's result, as JSON.")
        panel.accessoryView = ExportPanels.fileNameAccessory(for: fileNames)
        Task.immediate {
            guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return }
            ExportPanels.remember(fileNames)
            write(record, leaveOutFileNames: fileNames.leaveOut, to: url, appState: appState)
        }
    }

    /// Copy Methods Paragraph: the record as a paragraph for a paper's methods section, on the pasteboard.
    static func copyParagraph(appState: AppState, writer: any PaneTextWriter = SystemPaneTextWriter()) {
        guard let record = record(of: appState) else { return }
        writer.write(record.paragraph)
        appState.statusText = "Copied the methods paragraph"
    }

    private static func write(_ record: MethodsRecord, leaveOutFileNames: Bool, to url: URL, appState: AppState) {
        do {
            try ExportFile.write(Data(json(record, leaveOutFileNames: leaveOutFileNames).utf8), to: url)
            appState.statusText = "Exported \(url.lastPathComponent)"
        } catch {
            appState.present(error)
        }
    }
}
