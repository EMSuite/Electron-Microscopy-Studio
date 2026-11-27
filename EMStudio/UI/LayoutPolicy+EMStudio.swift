//
//  LayoutPolicy+EMStudio.swift
//  Role: what is macTEM's of the layout vocabulary: the sidebar's rows and the rooms' fixed sizes.
//        `LayoutPolicy` (the window's numbers), `ProcessAreaLayout`, `OperationMetricsFormat` and `displayByteString` are
//        ShellLayout's (suite task 8, MacEMUI).
//

import ShellLayout
import SwiftUI

extension LayoutPolicy {
    /// A new window's size (review of 2026-11-26): at ShellLayout's `datasetWindowIdealSize` (1280 × 800) the two-panel rooms drew
    /// 350 pt pictures in mostly empty panes. ShellLayout's size stays the other app's.
    static let windowDefaultSize = CGSize(width: 1440, height: 900)

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

    /// The EBSD tables' column widths (#1061): sized to their content, so at the opening window size the Bands table shows every column
    /// (the matched family and the fit too) and the Results table its angles, where each column's default width showed three. A scan
    /// index ("#", row, column), a phase's name, a signed number to two places, a family "{113}".
    static let ebsdIndexColumn: (min: CGFloat, ideal: CGFloat) = (22, 28)
    static let ebsdNameColumn: (min: CGFloat, ideal: CGFloat) = (34, 44)
    static let ebsdNumberColumn: (min: CGFloat, ideal: CGFloat) = (36, 46)
    static let ebsdFamilyColumn: (min: CGFloat, ideal: CGFloat) = (36, 44)
    /// The HRTEM defocus by thickness table sheet's least height, with its readable width (rule 4).
    static let hrtemTableMinimumHeight: CGFloat = 480
    /// The Diffraction room's tables (#1041), tabs of the shell's bottom area since #1094 and #1112: the table's header and
    /// `diffractionTableRows` rows at the system table's row height, which the bottom area at its ideal height holds in a 1400 × 876
    /// window under the area's tab header (`LayoutPolicy.paneHeaderHeight` and a divider), so an indexed pattern's Spots table shows
    /// seven rows, not four and a half (eight before #1112, when the area had no header of its own). The area's height is the
    /// person's to drag.
    static let diffractionTableRows = 7
    static let diffractionTableRowHeight: CGFloat = 24
    static let diffractionTableHeaderHeight: CGFloat = 28
    /// The colour dot before a region's name in the Table tab.
    static let regionSwatchSize: CGFloat = 9
    /// The Indexing room's IPF colour key in the map pane's footer: legible beside the scale bar, small enough not to hide the map.
    static let indexingKeyHeight: CGFloat = 56
    /// The Maps room's colour key in a figure: one phase's key image this wide (its own aspect sets the height); in the Detail panel
    /// (#1089) `mapsDetailKeyWidth`, so two phases' keys with their corner labels sit side by side in the panel at its default width.
    static let mapsKeyWidth: CGFloat = 150
    static let mapsDetailKeyWidth: CGFloat = 120
    /// The margin either side of a colour key for its corner labels ("[001]" sits centred on the left corner and was cut off).
    static let mapsKeyLabelInset: CGFloat = 18
    /// A phase's colour square in the Maps room's legend and inspector, and the IPF colour swatch on the unit cell.
    static let mapsPhaseSwatchSize: CGFloat = 12
    /// The picked point in the Maps room's Detail panel (#1089): the pattern or the unit cell this wide and tall.
    static let mapsPointSide: CGFloat = 200
    /// The kinematical master pattern's picture in the Simulation section: wide enough to read its zone axes (rule 4).
    static let overlayMasterPictureWidth: CGFloat = 180
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
