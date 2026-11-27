//
//  SimulationSessions.swift
//  Role: a Simulation document's session file in the app (#908): File > Save Simulation (⌘S in the Diffraction room) writes the
//        document's phase and settings (`SimulationSessionFile`, TEMCore; the owner's side in TEMSession), and an Open of an `.emsim`
//        file (the panel, a drop, Finder, the door's open_file) reopens it as a new Simulation document with the same pattern and spot
//        list. A file this build cannot read, or one from a newer build, is refused by name in the Open's alert and nothing opens.
//
//  The first save asks where (the save panel); later saves of the same document, and of a document reopened from a file, write that
//  file again with no panel. A reopened file is read here, then waits in `pending` under its document's URL until the document lands
//  (`AppState.landSimulation`, in whichever window's tab it opens), and is applied there before anything else is set.
//
//  WHY APPKIT (the suite's rule: only where SwiftUI cannot do the job, named where used): `NSSavePanel` presented as a sheet through
//  `ExportPanels.present`, as the room's other files are written; SwiftUI's `fileExporter` would need a document type and a view to
//  hang on, and ⌘S has neither.
//
//  Not kept: Open Recent and Reopen Last Session do not list a session file yet, and closing a changed Simulation document asks nothing.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession

@MainActor
enum SimulationSessions {
    /// The session file each Simulation document saves to, by item: the one it was reopened from or last saved to.
    private static var files: [OpenItem.ID: URL] = [:]
    /// Read and waiting for their document to land, by the document's URL.
    private static var pending: [URL: (session: SimulationSessionFile, file: URL)] = [:]

    /// The file type the save panel writes.
    static var contentType: UTType {
        UTType(filenameExtension: SimulationSessionFile.fileExtension, conformingTo: .json) ?? .json
    }

    /// ⌘S saves a Simulation document: the Diffraction room shows one.
    static func canSave(_ appState: AppState?) -> Bool {
        guard let appState, appState.navigation.workspaceArea == .diffraction, let item = appState.openItems.selected else { return false }
        return DemoDocuments.isSimulation(item.url)
    }

    /// The menu item's title: an ellipsis while the save will ask where.
    static func saveTitle(for item: OpenItem?) -> String {
        guard let item, file(of: item) != nil else { return "Save Simulation…" }
        return "Save Simulation"
    }

    /// The file `item` saves to, if it has one.
    static func file(of item: OpenItem) -> URL? { files[item.id] }

    // MARK: Saving

    /// File > Save Simulation (⌘S).
    static func save(appState: AppState) {
        guard canSave(appState), let item = appState.openItems.selected else {
            NSSound.beep()
            return
        }
        Task.immediate { await run(item, appState: appState) }
    }

    private static func run(_ item: OpenItem, appState: AppState) async {
        if let url = files[item.id], (try? write(item, to: url)) != nil {
            finish(url, appState: appState)
            return
        }
        guard let window = ExportPanels.hostWindow(for: appState) else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = files[item.id]?.deletingPathExtension().lastPathComponent ?? item.url.lastPathComponent
        panel.allowedContentTypes = [contentType]
        panel.prompt = "Save"
        panel.message = "\(AppName.display) keeps this simulation's phase and settings in this file; open it to simulate the same pattern again."
        panel.canCreateDirectories = true
        guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return }
        do {
            try write(item, to: url)
            finish(url, appState: appState)
        } catch {
            appState.present(error)
        }
    }

    /// Writes `item`'s session to `url`, replacing the file whole, and remembers it as the document's file.
    static func write(_ item: OpenItem, to url: URL) throws {
        let data = try SimulationSessionFile(analysis: item.diffraction).encoded()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
        files[item.id] = url
    }

    private static func finish(_ url: URL, appState: AppState) {
        let line = "Saved \(url.lastPathComponent)"
        appState.statusText = line
        AccessibilityNotification.Announcement(ExportPanels.announcement(line)).post()
    }

    // MARK: Reopening

    /// The session in the file at `url`, or the sentence it is refused with.
    nonisolated static func read(_ url: URL) -> Result<SimulationSessionFile, SimulationSessionFile.Refusal> {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= SimulationSessionFile.maxBytes else {
            return .failure(.unreadable(name: name, "it is too large to be a simulation file"))
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable(name: name, "the file could not be read")) }
        do throws(SimulationSessionFile.Refusal) {
            return .success(try SimulationSessionFile.read(data, name: name))
        } catch {
            return .failure(error)
        }
    }

    /// A session read from `file`, to be applied when the document at `document` lands.
    static func hold(_ session: SimulationSessionFile, from file: URL, for document: URL) {
        pending[document] = (session, file)
    }

    /// A landing Simulation document reopened from a file: the owner is bound to its canvas, set to the session, and the file is the
    /// one its ⌘S writes. Nothing for a new simulation.
    static func landReopened(_ item: OpenItem) {
        guard let reopened = pending.removeValue(forKey: item.url) else { return }
        if let image = item.session.image { item.diffraction.bind(image) }
        reopened.session.apply(to: item.diffraction)
        files[item.id] = reopened.file
    }
}

extension AppState {
    /// The session files of an Open (`open(urls:)` hands them here first): each readable one opens as a new Simulation document,
    /// here or in a tab of its own, as New Simulation does; the others are the sentences they are refused with. Returns the last
    /// document's open, and the refusals.
    func openSimulationSessions(_ urls: [URL]) -> (task: Task<Void, Never>?, refusals: [String]) {
        var task: Task<Void, Never>?
        var refusals: [String] = []
        for url in urls {
            switch SimulationSessions.read(url) {
            case .success(let session):
                let document = Self.nextSimulationURL()
                SimulationSessions.hold(session, from: url, for: document)
                task = open(urls: [document]) ?? task
            case .failure(let refusal):
                refusals.append(refusal.sentence)
            }
        }
        return (task, refusals)
    }
}
