//
//  MethodsRecordExport.swift
//  Role: File > Export Methods Record… and Copy Methods Paragraph (#818, plan row X2): the methods record of what the room on screen
//        holds, as the JSON file a paper's supplement carries or as the paragraph its methods section quotes. The record is the one
//        the room's exports carry inside them (#817, `ExportMethods`), with "methods-record" as its export kind and nothing drawn.
//        The agent door's `get_methods_record` returns the same record and paragraph.
//
//        WHICH RESULT: the Image room's file (its source and the measurements' lineage); the Results room's finished measurements;
//        the FFT room's transform on screen, with its measured spots when there are some; the Diffraction room's centre, scale and
//        readout once a ring or a spot is measured; the EELS room's method once a stage ran; the EDS room's fit; the Patterns
//        room's dataset and processing, the Indexing room's run, the Maps room's map, grains and texture (the SEM session's rows,
//        `SEMSessionLedger`). A room with no result gives no record and both items are disabled. An SEM room's file and the EDS
//        spectrum image are read once for their fingerprint, off the main actor (`prepare`), before the first record of them.
//
//        "Leave out file names" is the save panel's checkbox, remembered with the exports' (`ExportMethods.leaveOutFileNamesKey`);
//        the paragraph keeps the names, as the person copies it into their own text.
//

import AppKit
import ShellEDXModel
import ShellExport
import SpectroCore
import SpectroEELS
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
        case .edx: return appState.edx.methodJSON != nil
        case .patterns: return appState.ebsd.document?.url != nil
        case .indexing: return appState.ebsd.document?.url != nil && ExportSnapshot.indexingAvailability(of: appState)?.indexed == true
        case .maps: return appState.maps.hasMap && appState.maps.document?.url != nil
        }
    }

    /// The record of what the room on screen holds; nil when it holds no result.
    static func record(of appState: AppState, software: String = ExportSnapshot.softwareName()) -> MethodsRecord? {
        guard isAvailable(in: appState) else { return nil }
        let app = ExportSnapshot.methodsApp()
        let area = appState.navigation.workspaceArea
        if let slow = slowSource(of: appState) {
            guard let source = read[slow.key] else { return nil }
            if area == .eels {
                return ExportMethods.eelsRecord(app: app, exportKind: exportKind, source: source, methodJSON: appState.eels.methodJSON)
            }
            if area == .edx {
                return ExportMethods.edsRecord(app: app, exportKind: exportKind, source: source, methodJSON: appState.edx.methodJSON)
            }
            let kinds = sessionKinds(in: area)
            let rows = SEMSessionLedger.rows(of: appState, locale: ExportSnapshot.labelLocale).filter { kinds.contains($0.kind) }
            return ExportMethods.sessionRecord(app: app, room: area.rawValue, exportKind: exportKind, source: source, rows: rows)
        }
        guard let item = appState.openItems.selected, let image = item.session.image else { return nil }
        let origin = source(of: item, image: image, software: software)
        switch appState.navigation.workspaceArea {
        case .image, .results:
            var record = ExportMethods.imageRecord(app: app, exportKind: exportKind, source: origin, lineage: item.measurements.lineage,
                                                   drawn: [])
            record.room = appState.navigation.workspaceArea.rawValue
            return record
        case .fft:
            // The measured spots when there are some (their record holds the transform's steps too), else the transform.
            if let spots = ExportSnapshot.spotsSnapshot(image: image, url: item.url, analysis: item.fft, software: software) {
                return ExportMethods.fftRecord(app: app, exportKind: exportKind, source: origin, header: spots.header,
                                               product: .spots(count: spots.rows.count, maskRadius: spots.maskRadius, maskEdge: spots.maskEdge),
                                               drawn: [])
            }
            guard item.fft.isSpectrumCurrent, let spectrum = item.fft.spectrum else { return nil }
            return ExportMethods.fftRecord(app: app, exportKind: exportKind, source: origin,
                                           header: ExportSnapshot.fftHeader(image: image, spectrum: spectrum, software: software),
                                           product: .transform, drawn: [])
        case .diffraction:
            let analysis = item.diffraction
            return ExportMethods.diffractionRecord(app: app, source: origin, header: analysis.exportHeader(image: image),
                                                   rows: analysis.readout(image: image), exportKind: exportKind)
        case .eels, .edx, .patterns, .indexing, .maps:
            return nil
        }
    }

    /// The SEM session's rows each SEM room's record holds: the Patterns room's dataset and processing, the Indexing room's run on
    /// that dataset, the Maps room's map, grains and texture.
    static func sessionKinds(in area: WorkspaceArea) -> Set<SEMSessionRow.Kind> {
        switch area {
        case .patterns: [.dataset, .processing, .scanMaps]
        case .indexing: [.dataset, .indexing]
        case .maps: [.orientationMap, .grains, .texture]
        case .image, .fft, .diffraction, .results, .edx, .eels: []
        }
    }

    // MARK: Sources read once

    /// A source too large to read on the main actor: an SEM room's file (gigabytes of patterns) and the EELS spectrum image by their
    /// bytes, the EDS spectrum image by its summed spectrum and shape (a lazy cube is read from its file). Read once per file as it is
    /// on disk now (`prepare`).
    struct SlowSource {
        /// The file by its path, size and modification date, so a file replaced at the same path is read again.
        let key: Key
        let read: @Sendable () async -> MethodsRecord.Source?
    }

    nonisolated struct Key: Hashable, Sendable {
        let path: String
        let byteCount: Int
        let modified: Date

        /// The key of the file at `path` as it is on disk now. A source with no file to look at (a cube made in memory, a file
        /// gone) is keyed by its name and shape alone.
        static func of(_ path: String, room: String, name: String, shape: [Int]) -> Key {
            guard !path.isEmpty, let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date else {
                return Key(path: "\(room):memory:\(name):\(shape)", byteCount: 0, modified: .distantPast)
            }
            return Key(path: room + ":" + path, byteCount: size, modified: modified)
        }
    }

    /// The sources read, and the reads running: one read per file at a time. A failure is remembered only to say so; the next
    /// `prepare` reads again (access may come back).
    private static var read: [Key: MethodsRecord.Source] = [:]
    private static var reading: [Key: Task<MethodsRecord.Source?, Never>] = [:]
    private static var failed: Set<Key> = []

    /// The room's slow source, or nil for a room whose source is the image in memory.
    static func slowSource(of appState: AppState) -> SlowSource? {
        switch appState.navigation.workspaceArea {
        case .patterns, .indexing:
            guard let document = appState.ebsd.document, let url = document.url else { return nil }
            let dataset = document.dataset, fileName = document.fileName
            let shape = [dataset.scanColumns, dataset.scanRows, dataset.patternColumns, dataset.patternRows]
            return SlowSource(key: .of(url.path, room: "ebsd", name: fileName, shape: shape)) { fileSource(url, fileName: fileName, kind: "EBSD patterns", shape: shape) }
        case .maps:
            guard let document = appState.maps.document, let url = document.url else { return nil }
            let fileName = document.fileName, kind = MapsRoomState.sourceKind(document.source), shape = [document.columns, document.rows]
            return SlowSource(key: .of(url.path, room: "maps", name: fileName, shape: shape)) { fileSource(url, fileName: fileName, kind: kind, shape: shape) }
        case .eels:
            guard let loaded = appState.eels.source else { return nil }
            let image = loaded.image
            return SlowSource(key: .of(loaded.filePath, room: "eels", name: loaded.fileName, shape: [image.nx, image.ny, image.channels])) {
                await ExportSnapshot.eelsSource(loaded)
            }
        case .edx:
            guard let source = appState.edx.source else { return nil }
            let metadata = source.metadata
            let shape = [source.nx, source.ny, source.channels]
            return SlowSource(key: .of(metadata.filePath, room: "eds", name: metadata.fileName, shape: shape)) {
                guard let sum = try? source.sum(mask: nil, cancelled: { false }, progress: nil) else { return nil }
                // The summed spectrum and the shape: a weaker identity than the file's bytes, and the kind says so.
                let values = sum.map(Double.init) + shape.map(Double.init)
                let size = (try? FileManager.default.attributesOfItem(atPath: metadata.filePath)[.size] as? Int) ?? 0
                return MethodsRecord.Source(fileName: metadata.fileName, byteCount: size,
                                            fingerprint: values.withUnsafeBytes { ExportMethods.fingerprint(ofBytes: $0) },
                                            kind: "EDS spectrum image, by its summed spectrum and shape", shape: shape)
            }
        case .image, .fft, .diffraction, .results:
            return nil
        }
    }

    /// The file at `url` by its bytes, streamed in blocks.
    nonisolated private static func fileSource(_ url: URL, fileName: String, kind: String, shape: [Int]) -> MethodsRecord.Source? {
        guard let found = try? ExportMethods.fingerprint(ofFileAt: url) else { return nil }
        return MethodsRecord.Source(fileName: fileName, byteCount: found.byteCount, fingerprint: found.sha256, kind: kind, shape: shape)
    }

    /// Whether the room's record waits for its source to be read (`prepare`).
    static func isReading(_ appState: AppState) -> Bool {
        guard let slow = slowSource(of: appState) else { return false }
        return read[slow.key] == nil
    }

    /// Whether the last read of the room's source failed and none runs now.
    static func lastReadFailed(_ appState: AppState) -> Bool {
        guard let slow = slowSource(of: appState) else { return false }
        return failed.contains(slow.key) && reading[slow.key] == nil
    }

    /// Reads the room's slow source off the main actor when it is not read yet, joining a read already running for the same file;
    /// false when it cannot be read (the file moved, or the sandbox no longer grants it).
    @discardableResult
    static func prepare(_ appState: AppState) async -> Bool {
        guard let slow = slowSource(of: appState) else { return true }
        let key = slow.key
        if read[key] != nil { return true }
        let task = reading[key] ?? Task { await readOff(slow.read) }
        reading[key] = task
        let found = await task.value
        reading[key] = nil
        if let found {
            read[key] = found
            failed.remove(key)
        } else {
            failed.insert(key)
        }
        return found != nil
    }

    @concurrent nonisolated private static func readOff(_ read: @Sendable () async -> MethodsRecord.Source?) async -> MethodsRecord.Source? {
        await read()
    }

    /// The words when the source cannot be read for its fingerprint.
    static let unreadableLine = "The source file could not be read for its fingerprint, so no methods record was made."

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
    /// journey) it is written into that folder without a panel. An SEM or EDS source is read for its fingerprint first.
    @discardableResult
    static func exportRecord(appState: AppState) -> Task<Void, Never>? {
        guard isAvailable(in: appState) else { return nil }
        return Task.immediate {
            guard await prepare(appState) else {
                appState.statusText = unreadableLine
                return
            }
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
            let panel = ExportPanels.savePanel(type: .json, name: name, directory: defaultFolder(of: appState),
                                               message: "The methods record of the \(appState.navigation.workspaceArea.title) room's result, as JSON.")
            panel.accessoryView = ExportPanels.fileNameAccessory(for: fileNames)
            guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return }
            ExportPanels.remember(fileNames)
            write(record, leaveOutFileNames: fileNames.leaveOut, to: url, appState: appState)
        }
    }

    /// Copy Methods Paragraph: the record as a paragraph for a paper's methods section, on the pasteboard.
    @discardableResult
    static func copyParagraph(appState: AppState, writer: any PaneTextWriter = SystemPaneTextWriter()) -> Task<Void, Never>? {
        guard isAvailable(in: appState) else { return nil }
        return Task.immediate {
            guard await prepare(appState) else {
                appState.statusText = unreadableLine
                return
            }
            guard let record = record(of: appState) else { return }
            writer.write(record.paragraph)
            appState.statusText = "Copied the methods paragraph"
        }
    }

    /// The panel opens in the source's folder: the image's, or the SEM room's file's.
    private static func defaultFolder(of appState: AppState) -> URL? {
        switch appState.navigation.workspaceArea {
        case .patterns, .indexing: ExportPanels.defaultFolder(for: appState.ebsd.document?.url)
        case .maps: ExportPanels.defaultFolder(for: appState.maps.document?.url)
        case .edx: ExportPanels.defaultFolder(for: appState.edx.source.map { URL(fileURLWithPath: $0.metadata.filePath) })
        case .eels: ExportPanels.defaultFolder(for: appState.eels.source.map { URL(fileURLWithPath: $0.filePath) })
        case .image, .fft, .diffraction, .results: ExportPanels.defaultFolder(for: appState.openItems.selected?.url)
        }
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
