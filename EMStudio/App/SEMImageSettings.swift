//
//  SEMImageSettings.swift
//  Role: the one document-independent switch of the SEM image display: whether the databar the vendor drew under a Thermo or
//        Tescan scan is hidden (on by default) or shown as a strip under the picture (`ImagePane`). The picture itself is always
//        the scan alone (`AppState.read`). Kept in UserDefaults so it holds
//        across launches; set in Settings > Images (`ImageSettingsSection`, control-placement §10: it changes no number in a document
//        and outlives it) and read by every window through `@AppStorage`, so a change shows at once.
//

import Foundation

nonisolated enum SEMImageSettings {
    /// The key since #341: a choice made in an earlier version is read as it was.
    static let cropDatabarKey = "sem.cropDatabar"
    /// Hidden unless the person chose to show it: the `@AppStorage` default wherever the choice is read.
    static let cropDatabarDefault = true
}
