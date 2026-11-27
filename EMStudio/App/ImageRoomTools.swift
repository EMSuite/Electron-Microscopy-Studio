//
//  ImageRoomTools.swift
//  Role: the Image room's measuring tool — Pan, Distance, Angle or Profile — one per window, not per
//        file: a mode of the room, as a drawing app's tool is. The marks themselves are the file's
//        (`ImageMeasurements`, TEMSession). Composed by `AppState`; chosen in the Measure section and the Image menu.
//

import Foundation
import Observation
import ShellLayout
import TEMSession

@Observable
final class ImageRoomTools {
    enum Tool: String, CaseIterable, Identifiable {
        case pan, distance, angle, profile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pan: "Pan"
            case .distance: "Distance"
            case .angle: "Angle"
            case .profile: "Profile"
            }
        }

        var systemImage: String {
            switch self {
            case .pan: "hand.raised"
            case .distance: "ruler"
            case .angle: "angle"
            case .profile: "chart.xyaxis.line"
            }
        }

        /// The kind of mark the tool draws; nil for Pan.
        var markKind: ImageMark.Kind? {
            switch self {
            case .pan: nil
            case .distance: .distance
            case .angle: .angle
            case .profile: .profile
            }
        }

        /// The Image menu's ⌃⌘ digit (⌘1–5 are the rooms, ⌥⌘I the inspector).
        var shortcutDigit: Character {
            switch self {
            case .pan: "1"
            case .distance: "2"
            case .angle: "3"
            case .profile: "4"
            }
        }
    }

    var tool: Tool = .pan
    /// The status line's cursor readout over the picture (`ImageReadout`); nil when the pointer is elsewhere.
    var readout: String?
    /// The FFT room's readout over the power spectrum (`FFTSpectrumReadout`): the frequency under the pointer; nil when it is elsewhere.
    var spectrumReadout: String?
    /// The tabs under the image this window has selected on its own (`offer`), each once.
    private(set) var offeredTables: Set<ImageTable> = []

    /// Selects `table`'s tab in the bottom area the first time the window is asked to, and opens the area if it was shut, as the
    /// Diffraction room does (`DiffractionRoomState.offer`). Asked again, it leaves the area as the person left it.
    func offer(_ table: ImageTable?, in panels: PanelNavigation) {
        guard let table, !offeredTables.contains(table) else { return }
        offeredTables.insert(table)
        panels.selectProcessPane(table.paneID)
    }
}
