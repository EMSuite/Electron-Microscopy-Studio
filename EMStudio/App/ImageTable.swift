//
//  ImageTable.swift
//  Role: the Image room's results under the image (#864): the selected line's profile chart and the found objects, as tabs of the
//        shell's bottom area beside Output, as the Diffraction and Maps rooms' tables are (control placement §1: results sit beside
//        the data, never in an inspector section). The window selects each tab on its own the first time it has something to show
//        (`ImageRoomTools.offer`). The panes are `ImageTablePane` (UI/ImageRoomTables.swift).
//

import Foundation
import ShellLayout

/// One of the Image room's results under the image: a tab of the bottom area, chosen in the area's header as Output is.
nonisolated enum ImageTable: String, CaseIterable, Sendable {
    case profile, objects

    /// The tab's name in the area's header, and its VoiceOver label.
    var title: String {
        switch self {
        case .profile: "Profile"
        case .objects: "Objects"
        }
    }

    /// The tab's symbol: the Profile tool's and the Objects window's.
    var systemImage: String {
        switch self {
        case .profile: "chart.xyaxis.line"
        case .objects: "circle.dashed"
        }
    }

    /// The table's tab in the shell's bottom area: "image.profile", "image.objects".
    var paneID: ProcessPaneID { ProcessPaneID("image.\(rawValue)") }

}
