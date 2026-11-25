//
//  HowToCite.swift
//  Role: Help > How to Cite (#828, plan row RL19 of 2.3): how to cite the app, as text or as BibTeX, each copied with one button, and
//        the references of the methods the room in front follows. The app's citation is the repository's CITATION.cff (its title,
//        author, licence and repository; the version is the running app's), and the room's references are entries of the same file's
//        references list; `HowToCiteTests` reads CITATION.cff and holds both to it. A room whose methods the file names no package for
//        says that each export's methods record names them. AppKit: NSPasteboard for the two Copy buttons.
//

import AppKit
import SwiftUI

nonisolated enum HowToCite {
    static let title = "Electron Microscopy Studio"
    static let familyName = "Lobpreis"
    static let givenNames = "Paul"
    static let license = "GPL-3.0-only"
    static let repository = "https://github.com/EMSuite/Electron-Microscopy-Studio"

    /// One reference of CITATION.cff's list, as the window lists it.
    nonisolated struct Reference: Equatable, Sendable {
        let title: String
        /// The DOI, or the address where CITATION.cff gives none.
        let link: String
    }

    static let hyperspy = Reference(title: "HyperSpy", link: "10.5281/zenodo.592838")
    static let exspy = Reference(title: "eXSpy", link: "10.5281/zenodo.10252344")
    static let kikuchipy = Reference(title: "kikuchipy", link: "10.5281/zenodo.3597646")
    static let pyebsdindex = Reference(title: "PyEBSDIndex", link: "https://github.com/USNavalResearchLaboratory/PyEBSDIndex")
    static let orix = Reference(title: "orix", link: "10.1107/S1600576720011103")
    static let diffsims = Reference(title: "diffsims", link: "10.5281/zenodo.3337900")
    static let defdap = Reference(title: "DefDAP", link: "10.5281/zenodo.3688096")

    /// The references of the methods `area` follows, from CITATION.cff; empty where the file names none for the room (the Diffraction
    /// room follows py4DSTEM, which the file does not list).
    static func references(for area: WorkspaceArea) -> [Reference] {
        switch area {
        case .edx, .eels: [hyperspy, exspy]
        case .patterns: [kikuchipy]
        case .indexing: [kikuchipy, pyebsdindex, diffsims, orix]
        case .maps: [orix, defdap]
        case .diffraction, .image, .fft, .results: []
        }
    }

    /// The citation as text: "Lobpreis, P. (2026). Electron Microscopy Studio (version 2.3.0) [Computer software]. GPL-3.0-only. <repo>".
    static func text(version: String, year: Int) -> String {
        "\(familyName), \(givenNames.prefix(1)). (\(year)). \(title) (version \(version)) [Computer software]. \(license). \(repository)"
    }

    /// The citation as a BibTeX @software entry.
    static func bibtex(version: String, year: Int) -> String {
        """
        @software{\(familyName.lowercased())_electron_microscopy_studio_\(year),
          author = {\(familyName), \(givenNames)},
          title = {\(title)},
          version = {\(version)},
          year = {\(year)},
          license = {\(license)},
          url = {\(repository)}
        }
        """
    }
}

/// The How to Cite window: the app's citation as text and BibTeX, each with Copy, and the room in front's references.
struct HowToCiteWindow: Scene {
    nonisolated static let id = "howToCite"
    let windows: AppWindows

    var body: some Scene {
        Window("How to Cite", id: Self.id) { HowToCiteView(windows: windows) }
            // Help > How to Cite opens it; the Window menu's own item for the scene was a second How to Cite there (#1032).
            .commandsRemoved()
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .windowResizability(.contentSize)
    }
}

private struct HowToCiteView: View {
    /// Read in the body, so the references follow the room in front while the window stays open.
    let windows: AppWindows
    private let version = MacTEMAgentDoor.version()
    private let year = Calendar(identifier: .gregorian).component(.year, from: Date())

    var body: some View {
        let text = HowToCite.text(version: version, year: year)
        let bibtex = HowToCite.bibtex(version: version, year: year)
        VStack(alignment: .leading, spacing: 14) {
            Text("If you use \(HowToCite.title) in published work, please cite it, and the packages whose methods the room you used follows.")
                .fixedSize(horizontal: false, vertical: true)
            citation("As text", text, copy: copyButton("As text", text).accessibilityIdentifier("howToCite.copyText"))
            citation("BibTeX", bibtex, copy: copyButton("BibTeX", bibtex).accessibilityIdentifier("howToCite.copyBibTeX"))
            if let room = windows.front?.navigation.workspaceArea {
                Text("The \(room.title) room's methods").font(.headline)
                let references = HowToCite.references(for: room)
                if references.isEmpty {
                    Text("Each export's methods record names the packages and versions this room follows.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(references, id: \.title) { reference in
                        Text("\(reference.title) · \(reference.link)").textSelection(.enabled)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, alignment: .leading)
        .accessibilityIdentifier("howToCite")
    }

    /// The identifiers stay literal at the call sites, where the door coverage test reads them.
    private func citation(_ title: String, _ words: String, copy: some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                copy
            }
            Text(words)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func copyButton(_ title: String, _ words: String) -> some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(words, forType: .string)
        }
        .accessibilityLabel("Copy the citation \(title.lowercased())")
    }
}
