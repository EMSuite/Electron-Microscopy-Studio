//
//  PhaseCIF.swift
//  Role: a phase of the library saved as CIF (#821, plan row X5 of 2.4): Save as CIF… in a phase row's context menu and File > Save
//        Phase as CIF… for the phase the Diffraction room shows. The text is DiffractoKit's `CIFExport` (DK1): the phase's structure,
//        edited or not, with its operation list and one site per orbit, read back by the kit before it is written; the app adds only
//        the `#` lines (where the phase came from, a Materials Project phase with its id, the date it was fetched and "CC BY 4.0"; a
//        lattice edit said as such), the block name and the writer. The file, added again through Add Phase… > Open CIF…, gives a
//        phase with the same content fingerprint.
//        A hexagonal phase with sites at 1/3 and 2/3 keeps its space group from DiffractoKit's release of #220 on; until the app
//        takes that release, the kit writes such a phase in P1 with every site and says so in the file (still a correct CIF).
//
//  WHY APPKIT (the suite's rule: AppKit only where SwiftUI cannot do the job, named where used): the menu item and the row's context
//  menu reach one save panel on the asking window, as File > Export Spots… does (`ExportPanels`), and `UI/` imports no AppKit.
//

import AppKit
import DiffractoCore
import Foundation
import ShellPhaseLibrary
import TEMCore
import TEMSession
import UniformTypeIdentifiers

nonisolated enum PhaseCIF {
    /// The CIF file type: the system's when it knows `.cif`, else plain text with that extension.
    static let contentType: UTType = UTType(filenameExtension: "cif", conformingTo: .plainText) ?? .plainText

    /// Where the phase came from, as the file's `# Source:` lines: a Materials Project entry with its id, the date it was fetched
    /// (UTC, ISO), its licence and its page; a CIF by its file name.
    static func sourceLines(_ source: ShellPhaseLibrary.PhaseSource) -> [String] {
        switch source {
        case let .materialsProject(id, fetched):
            let day = fetched.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!).year().month().day())
            var lines = ["Materials Project \(id), fetched \(day), CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)"]
            if let page = source.pageURL { lines.append(page.absoluteString) }
            return lines
        case let .cif(fileName):
            return ["CIF \(fileName)"]
        }
    }

    /// The `CIFExport` options for `phase`: the block named after the phase, its source, "lattice edited" when it is, the writer.
    static func options(for phase: Phase) -> CIFExport.Options {
        var comments = ["\(phase.name), saved by \(AppName.writer) with DiffractoKit's CIFExport."]
        if phase.isEdited { comments.append("Lattice edited in \(AppName.writer): the cell is not the source's.") }
        return CIFExport.Options(blockName: phase.name, comments: comments, sourceLines: sourceLines(phase.source),
                                 creator: AppName.writer)
    }

    /// The phase as CIF text, with how the symmetry went in. Throws the kit's refusal (a value that cannot be written).
    static func text(of phase: Phase) throws -> CIFExport.Outcome {
        try CIFExport.text(of: phase.structure(), options: options(for: phase))
    }

    /// The save panel's name: the phase's name with the characters a file name cannot hold replaced, "phase" when nothing is left.
    static func defaultName(_ phase: Phase) -> String {
        let cleaned = phase.name.map { "/:\\".contains($0) ? "-" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "phase" : name
    }

    /// The infobar's line once the file is written; a P1 file says so.
    static func doneLine(name: String, symmetry: CIFExport.Symmetry) -> String {
        switch symmetry {
        case .kept: "Saved \(name)"
        case .p1(reason: nil): "Saved \(name) (P1: the structure has no other symmetry)"
        case .p1(reason: .some(_)): "Saved \(name) in P1 with every site: the file says why"
        }
    }
}

extension PhaseCIF {
    /// The library phase the Diffraction room shows in the selected file, if any: File > Save Phase as CIF… saves this one.
    @MainActor static func shownPhase(in appState: AppState) -> Phase? {
        guard appState.navigation.workspaceArea == .diffraction,
              let id = appState.openItems.selected?.diffraction.crystal.phaseID else { return nil }
        return PhaseServices.library.phases.first { $0.id == id }
    }

    /// Save as CIF…: the save panel on the asking window, then the kit's text written to the place chosen. A window with a sheet up
    /// or an export still writing beeps, as the other exports do.
    @MainActor static func save(_ phase: Phase, appState: AppState) {
        guard appState.exportsWriting == 0, let window = ExportPanels.hostWindow(for: appState) else {
            NSSound.beep()
            return
        }
        let outcome: CIFExport.Outcome
        do { outcome = try text(of: phase) } catch {
            appState.present(error)
            return
        }
        let panel = ExportPanels.savePanel(type: contentType, name: defaultName(phase), directory: nil,
                                           message: "Save \(phase.name) as CIF")
        panel.nameFieldLabel = "Save As:"
        panel.prompt = "Save"
        Task.immediate {
            guard await ExportPanels.present(panel, on: window) == .OK, let url = panel.url else { return }
            do {
                try ExportFile.write(Data(outcome.text.utf8), to: url)
                appState.statusText = doneLine(name: url.lastPathComponent, symmetry: outcome.symmetry)
            } catch {
                appState.present(error)
            }
        }
    }
}
