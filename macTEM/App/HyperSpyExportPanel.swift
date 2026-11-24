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
import FormatoCore
import FormatoHSPY
import ShellExport
import TEMCore
import TEMSession
import UniformTypeIdentifiers

@MainActor
enum HyperSpyExportPanel {
    /// What a write needs, taken when the item is chosen: an image's signal (its pixels a copy), or the EELS room's spectrum image
    /// (shared, not copied; its record is made off the main actor, a pass over the cube), and the names.
    nonisolated struct Snapshot: Sendable {
        enum Content: Sendable {
            case signal(FormatoSignal, HSPYSignalKind)
            case eels(LoadedEELS, coreLoss: Bool, methodJSON: String?)
        }

        var content: Content
        var record: MethodsRecord?
        var beamEnergyKeV: Double?
        var convergenceMrad: Double?
        var collectionMrad: Double?
        var name: String
        var directory: URL?

        /// The class HyperSpy builds on load.
        var kind: HSPYSignalKind {
            switch content {
            case .signal(_, let kind): kind
            case .eels: .eels
            }
        }

        /// A cube, written a band at a time with progress and Stop.
        var isCube: Bool {
            switch content {
            case .signal: false
            case .eels: true
            }
        }
    }

    /// The file type the panel writes.
    static let contentType = UTType(filenameExtension: "hspy", conformingTo: .data) ?? .data

    /// Whether the room on screen has something to write: an image in the Image room, a pattern in the Diffraction room, a spectrum
    /// image in the EELS room (its core loss with `coreLoss`); never while a cube is being written.
    static func isAvailable(in appState: AppState, coreLoss: Bool = false) -> Bool {
        guard appState.hyperSpyWrite == nil else { return false }
        switch appState.navigation.workspaceArea {
        case .image, .diffraction:
            return !coreLoss && appState.openItems.selected?.session.image != nil && !appState.imageSession.isLoading
        case .eels:
            guard let loaded = appState.eels.source else { return false }
            return !coreLoss || loaded.coreLoss != nil
        case .fft, .results, .edx, .patterns, .indexing, .maps:
            return false
        }
    }

    /// Whether the EELS room's file has a core loss: the menu then lists its own item.
    static func hasCoreLoss(_ appState: AppState) -> Bool {
        appState.navigation.workspaceArea == .eels && appState.eels.source?.coreLoss != nil
    }

    /// The room on screen's signal; nil when there is none.
    static func snapshot(of appState: AppState, coreLoss: Bool = false, software: String = ExportSnapshot.softwareName()) throws -> Snapshot? {
        guard isAvailable(in: appState, coreLoss: coreLoss) else { return nil }
        if appState.navigation.workspaceArea == .eels {
            let session = appState.eels
            guard let loaded = session.source else { return nil }
            let stem = HyperSpyExport.stem(loaded.fileName)
            return Snapshot(content: .eels(loaded, coreLoss: coreLoss, methodJSON: session.methodJSON), record: nil,
                            beamEnergyKeV: session.beamEnergyKeV, convergenceMrad: session.typedConvergenceMrad ?? loaded.convergenceMrad,
                            collectionMrad: session.typedCollectionMrad ?? loaded.collectionMrad,
                            name: coreLoss ? stem + " core loss" : stem,
                            directory: ExportPanels.defaultFolder(for: URL(fileURLWithPath: loaded.filePath)))
        }
        guard let item = appState.openItems.selected, let image = item.session.image else { return nil }
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
            return Snapshot(content: .signal(try HyperSpyExport.patternSignal(image, scale: scale), .electronDiffraction), record: record,
                            beamEnergyKeV: beam ?? analysis.volts(for: image).map { $0 / 1000 }, name: name, directory: directory)
        }
        let record = ExportSnapshot.imageMethods(of: item, image: image, exportKind: "image-hspy", drawn: [], software: software)
        return Snapshot(content: .signal(try HyperSpyExport.imageSignal(image), .generic), record: record, beamEnergyKeV: beam, name: name,
                        directory: directory)
    }

    /// Writes `snapshot` at `url`, the file's names left out of the title and the record when asked; a cube reports the fraction
    /// written and stops when its task is cancelled.
    nonisolated static func write(_ snapshot: Snapshot, to url: URL, leaveOutFileNames: Bool, software: String,
                                  progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        var record = snapshot.record
        if case .eels(let loaded, let coreLoss, let methodJSON) = snapshot.content {
            record = await eelsRecord(loaded, coreLoss: coreLoss, methodJSON: methodJSON)
        }
        if leaveOutFileNames { record = record?.withoutFileNames() }
        let title = leaveOutFileNames ? ExportMethods.anonymousName(0) : snapshot.name
        var options = try HyperSpyExport.options(title: title, software: software, record: record, beamEnergyKeV: snapshot.beamEnergyKeV)
        switch snapshot.content {
        case .signal(let signal, let kind):
            try await HyperSpyExport.write(signal, kind: kind, options: options, to: url)
        case .eels(let loaded, let coreLoss, _):
            if let mrad = snapshot.convergenceMrad, mrad.isFinite { options.metadata[HyperSpyExport.convergenceKey] = .number(mrad) }
            if let mrad = snapshot.collectionMrad, mrad.isFinite { options.metadata[HyperSpyExport.collectionKey] = .number(mrad) }
            let scan = (step: loaded.scanPixelSize, unit: loaded.scanPixelUnit)
            if coreLoss, let core = loaded.coreLoss {
                let axes = HyperSpyExport.CubeAxes(scanStep: scan.step, scanUnit: scan.unit, energyOffsetEV: core.energyOffsetEV,
                                                   energyScaleEV: core.energyScaleEV)
                try await HyperSpyExport.writeCube(core.storedCounts, nx: core.nx, ny: core.ny, channels: core.channels, axes: axes,
                                                   options: options, to: url, progress: progress)
            } else {
                let low = loaded.image
                let axes = HyperSpyExport.CubeAxes(scanStep: scan.step, scanUnit: scan.unit, energyOffsetEV: low.energyOffsetEV,
                                                   energyScaleEV: low.energyScaleEV)
                try await HyperSpyExport.writeCube(low.storedCounts, nx: low.nx, ny: low.ny, channels: low.channels, axes: axes,
                                                   options: options, to: url, progress: progress)
            }
        }
    }

    /// The EELS room's record of the cube written, off the main actor: its fingerprint is a pass over the counts.
    @concurrent nonisolated private static func eelsRecord(_ loaded: LoadedEELS, coreLoss: Bool, methodJSON: String?) async -> MethodsRecord {
        ExportSnapshot.eelsMethods(exportKind: coreLoss ? "eels-core-loss-hspy" : "eels-hspy", source: loaded, methodJSON: methodJSON)
    }

    /// File > Export as HyperSpy File… (with `coreLoss`, Export Core Loss as HyperSpy File… in the EELS room): the save panel, then
    /// the write. With `--export-dir` (a UI journey) it is written into that folder without a panel.
    @discardableResult
    static func export(appState: AppState, coreLoss: Bool = false) -> Task<Void, Never>? {
        let snapshot: Snapshot?
        do {
            snapshot = try self.snapshot(of: appState, coreLoss: coreLoss)
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

    /// File > Stop HyperSpy Export: the cube's write ends at its next band, and the destination is left as it was.
    static func stop(appState: AppState) {
        appState.hyperSpyWrite?.cancel()
    }

    /// The write, counted as the window's export; a cube's runs as `appState.hyperSpyWrite`, so Stop can cancel it, and its
    /// fraction goes to the infobar.
    private static func finish(_ snapshot: Snapshot, to url: URL, leaveOutFileNames: Bool, software: String, appState: AppState) async {
        appState.exportsWriting += 1
        defer { appState.exportsWriting -= 1 }
        let name = url.lastPathComponent
        appState.statusText = ExportSnapshot.exportingLine(name: name)
        let write = Task {
            try await Self.write(snapshot, to: url, leaveOutFileNames: leaveOutFileNames, software: software) { fraction in
                Task { @MainActor in
                    if appState.hyperSpyWrite != nil { appState.statusText = "Exporting \(name)… \(Int((fraction * 100).rounded())) %" }
                }
            }
        }
        if snapshot.isCube { appState.hyperSpyWrite = write }
        let result = await write.result
        appState.hyperSpyWrite = nil
        switch result {
        case .success:
            appState.statusText = "Exported \(name)"
        case .failure(let error) where error is FormatoCancelled || error is CancellationError:
            appState.statusText = "Stopped the export of \(name); nothing was written."
        case .failure(let error):
            appState.present(error)
        }
    }
}
