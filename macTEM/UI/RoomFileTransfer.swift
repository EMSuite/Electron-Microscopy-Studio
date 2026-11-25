//
//  RoomFileTransfer.swift
//  Role: the one export file and the one open and save panels of the rooms that present SwiftUI's panels (#269): Patterns, Indexing,
//        Maps and EELS, and the Diffraction readout and the Particles CSV. `RoomExportFile` is the bytes a room made, for every type a
//        room passes to the save panel; `roomImporter` opens the file chosen (the app's Open unless the room says otherwise) and says
//        why it could not; `roomExporter` writes, puts "Exported <name>" in the status line and tells the room it wrote (the session
//        record) or that the panel is done (the bytes let go, #619). Writing into the launch's `--export-dir` without a panel is
//        `ExportDirectoryFile` (App/InspectorFileIO.swift), through `ExportFile.write`. The EDS room keeps MacEMUI's `EDXExportFile`.
//

import SwiftUI
import UniformTypeIdentifiers

/// A file a room's save panel writes: the bytes the room made (a PNG, a CSV, a JSON, an MSA spectrum, an .ang or .ctf map).
struct RoomExportFile: FileDocument {
    /// Every type a room passes to the save panel: a type missing here makes the panel fall back to the first one, with its name and
    /// format (MacEMUI#106), so the list is built from the rooms' own export kinds.
    static var readableContentTypes: [UTType] {
        // PDF and SVG: the Maps room's vector figures (#902); a type missing here makes the panel fall back to the first one's name.
        var types: [UTType] = [.png, .pdf, .svg, .json, .commaSeparatedText, .plainText, .pythonScript]
        let kinds = PatternsExportKind.allCases.map(\.contentType) + IndexingExportKind.allCases.map(\.contentType)
            + EELSExportKind.allCases.map(\.contentType) + [DiffractionPowderExport.xyType]
        for type in kinds where !types.contains(type) { types.append(type) }
        return types
    }

    var data: Data

    init(data: Data) { self.data = data }
    init(text: String) { data = Data(text.utf8) }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension View {
    /// The room's Open panel for `types`: the chosen file goes to `open` (the app's Open when nil); a failure is presented.
    func roomImporter(isPresented: Binding<Bool>, types: [UTType], open: ((URL) -> Void)? = nil) -> some View {
        modifier(RoomImporter(isPresented: isPresented, types: types, open: open))
    }

    /// The room's save panel for `data`: written, the status line says so and `didWrite` gets where; cancelled or refused,
    /// `didFinish` runs (and a refusal is presented).
    func roomExporter(isPresented: Binding<Bool>, data: Data, contentType: UTType, defaultFilename: String,
                      didWrite: @escaping (URL) -> Void, didFinish: @escaping () -> Void) -> some View {
        modifier(RoomExporter(isPresented: isPresented, data: data, contentType: contentType, defaultFilename: defaultFilename,
                              didWrite: didWrite, didFinish: didFinish))
    }
}

private struct RoomImporter: ViewModifier {
    @Binding var isPresented: Bool
    let types: [UTType]
    let open: ((URL) -> Void)?
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: types, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let open { open(url) } else { appState.open(urls: [url]) }
            case .failure(let error): appState.present(error)
            }
        }
    }
}

private struct RoomExporter: ViewModifier {
    @Binding var isPresented: Bool
    let data: Data
    let contentType: UTType
    let defaultFilename: String
    let didWrite: (URL) -> Void
    let didFinish: () -> Void
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.fileExporter(isPresented: $isPresented, document: RoomExportFile(data: data), contentType: contentType,
                             defaultFilename: defaultFilename) { result in
            switch result {
            case .success(let url):
                appState.statusText = "Exported \(url.lastPathComponent)"
                didWrite(url)
            case .failure(let error):
                didFinish()
                appState.present(error)
            }
        }
    }
}
