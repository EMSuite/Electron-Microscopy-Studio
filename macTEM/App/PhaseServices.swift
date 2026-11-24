//
//  PhaseServices.swift
//  Role: the app's one Materials Project client, key store and phase library (#778, #779). Settings > Materials Project, the Add
//        Phase sheet and the Diffraction room's Phases section share them, so a saved key, the client's pacing and its day of
//        cached searches, and every added phase hold across every window. The key store is EMSuiteUI's `KeychainAPIKeyStore`,
//        the same item in the App Store build and the website download. The library is a folder per phase in Application
//        Support, read once per launch when the app has finished launching: a phase added once works offline.
//

import Foundation
import ShellPhaseLibrary

enum PhaseServices {
    // Variables only so a test can hand in a stub transport and a temporary folder; the app never reassigns them.
    static var keyStore: any APIKeyStore = KeychainAPIKeyStore()
    static var client = MaterialsProjectClient()
    static var library = PhaseLibrary(store: PhaseLibraryStore.standard()
        ?? PhaseLibraryStore(folder: FileManager.default.temporaryDirectory.appending(path: "Phases", directoryHint: .isDirectory)))
    private static var loadStarted = false
    /// The library has been read from disk; the agent door's phase tools answer only then.
    static var isLoaded = false

    /// Reads the library from disk once per launch (the app delegate starts it); later calls return at once.
    static func loadLibrary() async {
        guard !loadStarted else { return }
        loadStarted = true
        await library.load()
        isLoaded = true
    }
}
