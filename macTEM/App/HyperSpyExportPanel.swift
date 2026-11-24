//
//  HyperSpyExportPanel.swift
//  Role: File > Export as HyperSpy File… (#819, plan row X3) in the Image and Diffraction rooms: the selected file's image, or the
//        pattern on screen, as a `.hspy` that HyperSpy loads as Signal2D or pyxem's ElectronDiffraction2D (`HyperSpyExport`, TEMCore),
//        its methods record in the metadata tree. The pixels keep their stored type; a pattern the room has a scale for gets its
//        reciprocal axes in Å⁻¹ with the zero at the centre. The EELS and EDS rooms' cubes follow in their own change (#819).
//
//        The save panel offers "<file stem>" in the file's folder, with "Leave out file names" as every export does; the write runs off
//        the main actor and the infobar reports it, or the app's alert says why it was refused (too little free space among them,
//        before anything is written).
//

import AppKit
import FormatoHSPY
import ShellExport
import TEMCore
import TEMSession
import UniformTypeIdentifiers

@MainActor
enum HyperSpyExportPanel {
    /// What a write needs, taken when the item is chosen: the signal (its pixels a copy), its class, the record and the names.
    nonisolated struct Snapshot: Sendable {
        var signal: FormatoSignal
        var kind: HSPYSignalKind
        var record: MethodsRecord?
        var beamEnergyKeV: Double?
        var name: String
        var directory: URL?
    }

    /// The file type the panel writes.
    static let contentType = UTType(filenameExtension: "hspy", conformingTo: .data) ?? .data

    /// Whether the room on screen has something to write: an image in the Image room, a pattern in the Diffraction room.
    static func isAvailable(in appState: AppState) -> Bool {
        switch appState.navigation.workspaceArea {
        case .image, .diffraction: return appState.openItems.selected?.session.image != nil && !appState.imageSession.isLoading
        case .fft, .results, .edx, .eels, .patterns, .indexing, .maps: return false
        }
    }

    /// The selected item's signal for the room on screen; nil when there is none.
    static func snapshot(of appState: AppState, software: String = ExportSnapshot.softwareName()) throws -> Snapshot? {
        guard isAvailable(in: appState), let item = appState.openItems.selected, let image = item.session.image else { return nil }
        let name = HyperSpyExport.stem(image.fileName)
        let directory = ExportPanels.defaultFolder(for: item.url)
        let beam = image.voltage.map { $0 / 1000 }
        if appState.navigation.workspaceArea == .diffraction {
            let analysis = item.diffraction
            let header = analysis.exportHeader(image: image)
            let scale = header.deltaQ.map { HyperSpyExport.PatternScale(deltaQ: $0, centreRow: header.centreRow, centreColumn: header.centreColumn) }
            let record = ExportSnapshot.imageSource(of: item, image: image, software: software).map {
                ExportMethods.diffractionRecord(app: ExportSnapshot.methodsApp(), source: $0, header: header,
                                                rows: analysis.readout(image: image), exportKind: "diffraction-hspy")
            }
            return Snapshot(signal: try HyperSpyExport.patternSignal(image, scale: scale), kind: .electronDiffraction, record: record,
                            beamEnergyKeV: beam ?? analysis.volts(for: image).map { $0 / 1000 }, name: name, directory: directory)
        }
        let record = ExportSnapshot.imageMethods(of: item, image: image, exportKind: "image-hspy", drawn: [], software: software)
        return Snapshot(signal: try HyperSpyExport.imageSignal(image), kind: .generic, record: record, beamEnergyKeV: beam, name: name,
                        directory: directory)
    }

    /// Writes `snapshot` at `url`, the file's names left out of the title and the record when asked.
    nonisolated static func write(_ snapshot: Snapshot, to url: URL, leaveOutFileNames: Bool, software: String) async throws {
        let record = leaveOutFileNames ? snapshot.record?.withoutFileNames() : snapshot.record
        let title = leaveOutFileNames ? ExportMethods.anonymousName(0) : snapshot.name
        let options = try HyperSpyExport.options(title: title, software: software, record: record, beamEnergyKeV: snapshot.beamEnergyKeV)
        try await HyperSpyExport.write(snapshot.signal, kind: snapshot.kind, options: options, to: url)
    }

    /// File > Export as HyperSpy File…: the save panel, then the write. With `--export-dir` (a UI journey) it is written into that
    /// folder without a panel.
    @discardableResult
    static func export(appState: AppState) -> Task<Void, Never>? {
        let snapshot: Snapshot?
        do {
            snapshot = try self.snapshot(of: appState)
        } catch {
            appState.present(error)
            return nil
        }
        guard let snapshot else { return nil }
        let software = ExportSnapshot.softwareName()
        if let directory = appState.exportDirectory {
            return Task.immediate {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    appState.present(error)
                    return
                }
                await finish(snapshot, to: directory.appendingPathComponent(snapshot.name + ".hspy"), leaveOutFileNames: false,
                             software: software, appState: appState)
            }
        }
        guard let window = ExportPanels.hostWindow(for: appState), appState.exportsWriting == 0 else {
            NSSound.beep()
            return nil
        }
        let fileNames = ExportPanels.rememberedFileNameChoice()
        let panel = ExportPanels.savePanel(type: contentType, name: snapshot.name, directory: snapshot.directory,
                                           message: "A HyperSpy file (.hspy) that hs.load opens, with the methods record in its metadata.")
        panel.accessoryView = ExportPanels.fileNameAccessory(for: fileNames)
        return Task.immediate {
            guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return }
            ExportPanels.remember(fileNames)
            await finish(snapshot, to: url, leaveOutFileNames: fileNames.leaveOut, software: software, appState: appState)
        }
    }

    private static func finish(_ snapshot: Snapshot, to url: URL, leaveOutFileNames: Bool, software: String, appState: AppState) async {
        appState.exportsWriting += 1
        defer { appState.exportsWriting -= 1 }
        let name = url.lastPathComponent
        appState.statusText = ExportSnapshot.exportingLine(name: name)
        do {
            try await write(snapshot, to: url, leaveOutFileNames: leaveOutFileNames, software: software)
            appState.statusText = "Exported \(name)"
        } catch {
            appState.present(error)
        }
    }
}
