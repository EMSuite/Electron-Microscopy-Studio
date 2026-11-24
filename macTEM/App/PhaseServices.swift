//
//  PhaseServices.swift
//  Role: the app's one Materials Project client and key store (#778). Settings > Materials Project and the Add Phase sheet
//        share them, so a saved key, the client's pacing and its day of cached searches hold across every window. The key
//        store is EMSuiteUI's `KeychainAPIKeyStore`, the same item in the App Store build and the website download.
//

import ShellPhaseLibrary

enum PhaseServices {
    static let keyStore: any APIKeyStore = KeychainAPIKeyStore()
    static let client = MaterialsProjectClient()
}
