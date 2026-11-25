//
//  LayoutPolicy+macTEM.swift
//  Role: what is macTEM's of the layout vocabulary: the sidebar's rows and the rooms' fixed sizes.
//        `LayoutPolicy` (the window's numbers), `ProcessAreaLayout`, `OperationMetricsFormat` and `displayByteString` are
//        ShellLayout's (suite task 8, MacEMUI).
//

import ShellLayout
import SwiftUI

extension LayoutPolicy {
    /// The rooms' row height per system sidebar size, a little more than the system's own (23, 30, 38 pt) so the list breathes (Paul,
    /// 2026-10-22: the sidebar was cramped). The list itself fills the column: with the Open Files list gone (2026-11-10) it has no
    /// height of its own to keep.
    static func sidebarRoomRowHeight(_ size: SidebarRowSize) -> CGFloat {
        switch size {
        case .small: 30
        case .large: 42
        default: 34
        }
    }

    /// The Patterns room's map progress bar in the pane header: short, beside the title (rule 4).
    static let paneHeaderProgressWidth: CGFloat = 80
    /// The HRTEM defocus by thickness table sheet's least height, with its readable width (rule 4).
    static let hrtemTableMinimumHeight: CGFloat = 480
    /// The Diffraction room's readout table under the pattern: room content, named once (rule 4).
    static let diffractionReadoutHeight: CGFloat = 170
    /// The colour dot before a region's name in the Table tab.
    static let regionSwatchSize: CGFloat = 9
    /// The Indexing room's IPF colour key in the map pane's footer: legible beside the scale bar, small enough not to hide the map.
    static let indexingKeyHeight: CGFloat = 56
    /// The Maps room's colour key in the bottom pane: one phase's key image this wide (its own aspect sets the height).
    static let mapsKeyWidth: CGFloat = 150
    /// The margin either side of a colour key for its corner labels ("[001]" sits centred on the left corner and was cut off).
    static let mapsKeyLabelInset: CGFloat = 18
    /// The Maps room's bottom pane under the map: the keys' height plus their titles (rule 4).
    static let mapsKeyPaneMinimum: CGFloat = 140
    /// A phase's colour square in the Maps room's legend and inspector, and the IPF colour swatch under the unit cell.
    static let mapsPhaseSwatchSize: CGFloat = 12
    static let mapsColourSwatchSize: CGFloat = 22
    /// The kinematical master pattern's picture in the Simulation section: wide enough to read its zone axes (rule 4).
    static let overlayMasterPictureWidth: CGFloat = 180
    /// One stereogram or ODF section in the Maps room's Pole figures and ODF tabs (its title and colour bar under it).
    static let mapsTextureFigureSide: CGFloat = 150
    /// An ODF φ₂ section's width: three times wider than tall (φ₁ over 0–360°, Φ over 0–90° for cubic), it read as a strip at 150 pt.
    static let mapsODFSectionWidth: CGFloat = 240
    /// The colour bar under a texture figure, and the boundary and trace line widths on the map (points).
    static let mapsColourBarHeight: CGFloat = 8
    static let mapsBoundaryLineWidth: CGFloat = 1
    static let mapsOutlineLineWidth: CGFloat = 2
    static let mapsTraceLineWidth: CGFloat = 1.5
    /// A selected grain's pole on a pole figure: a ring this radius (points), and the room under the histogram's bars for the ticks.
    static let mapsPoleMarkerRadius: CGFloat = 3.5
    static let mapsHistogramTickHeight: CGFloat = 8

    /// The Diffraction room's 2.4 sections (rule 4): the Find Phases sheet and its ranking table, the powder chart, a
    /// relationship's index field in Precipitate and a family's line in the zone-axis map's legend.
    static let findPhasesSheet: (min: CGSize, idealWidth: CGFloat) = (CGSize(width: 620, height: 360), 700)
    static let findPhasesTableMinimum: CGFloat = 180
    static let powderChartHeight: CGFloat = 140
    static let precipitateIndexFieldWidth: CGFloat = 72
    /// Wide enough to show a dash and a dot pattern (#923).
    static let zoneAxisLegendLine = CGSize(width: 18, height: 4)

    /// The Settings window (`SettingsWindow`): a sidebar of sections beside a grouped form, mac4DSTEM's size.
    static let settingsWindow: (min: CGSize, ideal: CGSize) = (CGSize(width: 560, height: 380), CGSize(width: 660, height: 600))
}
