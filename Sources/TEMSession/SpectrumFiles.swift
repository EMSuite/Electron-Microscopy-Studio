//
//  SpectrumFiles.swift
//  Role: what the window's Open found out about each file that spans rooms, and the pure rules that read it. One file can open into
//        several rooms (a Velox spectrum image into Image, EDS and Results), so no room owns these facts; the window's `AppState`
//        holds one `SpectrumFiles` (#276). The Open writes it (`AppState.open(urls:)`); the spectrum rooms follow the selection by
//        `roomsToFollow`, and the Results room lists a room's numbers under a file by `edsFitBelongs` and `eelsResultsBelong`.
//

import Foundation
import Observation
import TEMCore

@Observable
package final class SpectrumFiles {
    /// Files opened into the Image room that are also spectrum images (the HAADF of a Velox SI): their image is a scan image, which the
    /// Diffraction room does not take.
    package var companionImages: Set<URL> = []
    /// The scan of each opened DM4 spectrum image, from its header: the scan's size, not the survey image's.
    package var scans: [URL: FileInventory.Scan] = [:]
    /// The files that opened into the EDS room and into the EELS room: a room follows the selected file (`roomsToFollow`).
    package var edsFiles: Set<URL> = []
    package var eelsFiles: Set<URL> = []

    package init() {}

    /// Which spectrum rooms must reopen the selected file: the EDS and EELS sessions hold one document each, so a file that opened into a room is
    /// read into it again when its row is selected while another file holds the room (drive 6, 2026-10-22: clicking another open file did nothing
    /// in the EDS room). The room holds the file whose path its reader states, so two files of one name in two folders are told apart (as
    /// `edsFitBelongs`); by name only when the reader states no path. Pure, so a test holds it; a room that is opening is left alone.
    package nonisolated static func roomsToFollow(selected: URL?, edsFiles: Set<URL>, eelsFiles: Set<URL>, edsFile: String, eelsFile: String,
                                                  edsPath: String = "", eelsPath: String = "", edsOpening: Bool, eelsOpening: Bool)
        -> (eds: Bool, eels: Bool) {
        guard let url = selected else { return (false, false) }
        // The open-files list keeps a resolved, standardised URL (symlinks and /private resolved); compare both sides the same way.
        let k = key(url), name = url.lastPathComponent
        func holds(file: String, path: String) -> Bool { path.isEmpty ? file == name : key(URL(fileURLWithPath: path)) == k }
        let eds = edsFiles.contains { key($0) == k }, eels = eelsFiles.contains { key($0) == k }
        return (eds && !holds(file: edsFile, path: edsPath) && !edsOpening, eels && !holds(file: eelsFile, path: eelsPath) && !eelsOpening)
    }

    /// Whether the EDS room's fit is `url`'s: the file opened into the EDS room, the room holds it (by its path when the reader states one,
    /// so two files of one name in two folders are told apart; else by name, as `roomsToFollow` compares) and is not opening another.
    /// Pure, so a test holds it.
    package nonisolated static func edsFitBelongs(to url: URL, edsFiles: Set<URL>, edsFile: String, edsPath: String = "",
                                                  edsOpening: Bool) -> Bool {
        let k = key(url)
        guard !edsOpening, edsFile == url.lastPathComponent, edsFiles.contains(where: { key($0) == k }) else { return false }
        return edsPath.isEmpty || key(URL(fileURLWithPath: edsPath)) == k
    }

    /// Whether the EELS room's results are `url`'s: the same rule as the EDS room's (`edsFitBelongs`), as the window holds one EELS document too.
    package nonisolated static func eelsResultsBelong(to url: URL, eelsFiles: Set<URL>, eelsFile: String, eelsPath: String = "",
                                                      eelsOpening: Bool) -> Bool {
        edsFitBelongs(to: url, edsFiles: eelsFiles, edsFile: eelsFile, edsPath: eelsPath, edsOpening: eelsOpening)
    }

    /// A file's path with symbolic links and `/private` resolved, so two spellings of one file compare equal.
    private nonisolated static func key(_ u: URL) -> String { u.resolvingSymlinksInPath().standardizedFileURL.path }
}
