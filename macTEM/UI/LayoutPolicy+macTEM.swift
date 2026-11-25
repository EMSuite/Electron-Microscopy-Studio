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

    /// The EBSD tables' column widths (#1061): sized to their content, so at the opening window size the Bands table shows every column
    /// (the matched family and the fit too) and the Results table its angles, where each column's default width showed three. A scan
    /// index ("#", row, column), a phase's name, a signed number to two places, a family "{113}".
    static let ebsdIndexColumn: (min: CGFloat, ideal: CGFloat) = (22, 28)
    static let ebsdNameColumn: (min: CGFloat, ideal: CGFloat) = (34, 44)
    static let ebsdNumberColumn: (min: CGFloat, ideal: CGFloat) = (36, 46)
    static let ebsdFamilyColumn: (min: CGFloat, ideal: CGFloat) = (36, 44)
    /// The HRTEM defocus by thickness table sheet's least height, with its readable width (rule 4).
    static let hrtemTableMinimumHeight: CGFloat = 480
    /// The Diffraction room's table strip under the pattern (rule 4, #1041): the Readout · Spots switch, the table's header and
    /// `diffractionTableRows` rows at the system table's row height, so an indexed pattern's Spots table shows eight rows, not four
    /// and a half.
    static let diffractionTableRows = 8
    static let diffractionTableRowHeight: CGFloat = 24
    static let diffractionTableHeaderHeight: CGFloat = 28
    static let diffractionReadoutHeight: CGFloat = paneHeaderHeight + 1 + diffractionTableHeaderHeight
        + CGFloat(diffractionTableRows) * diffractionTableRowHeight
    /// The colour dot before a region's name in the Table tab.
    static let regionSwatchSize: CGFloat = 9
    /// The Indexing room's IPF colour key in the map pane's footer: legible beside the scale bar, small enough not to hide the map.
    static let indexingKeyHeight: CGFloat = 56
    /// The Maps room's colour key in a figure: one phase's key image this wide (its own aspect sets the height); on the map (#1065)
    /// `mapsKeyInsetWidth`, legible beside the scale bar, small enough not to hide the map.
    static let mapsKeyWidth: CGFloat = 150
    static let mapsKeyInsetWidth: CGFloat = 84
    /// The margin either side of a colour key for its corner labels ("[001]" sits centred on the left corner and was cut off).
    static let mapsKeyLabelInset: CGFloat = 18
    /// A phase's colour square in the Maps room's legend and inspector, and the IPF colour swatch on the unit cell.
    static let mapsPhaseSwatchSize: CGFloat = 12
    /// The picked point's inset on the Maps room's map (#1064): the pattern or the unit cell this wide, small enough to leave the map.
    static let mapsInsetSide: CGFloat = 120
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
    /// relationship's index field in Precipitate, the zone-axis map's largest side and a family's line in its legend.
    static let findPhasesSheet: (min: CGSize, idealWidth: CGFloat) = (CGSize(width: 620, height: 360), 700)
    static let findPhasesTableMinimum: CGFloat = 180
    static let powderChartHeight: CGFloat = 140
    static let precipitateIndexFieldWidth: CGFloat = 72
    static let zoneAxisMapMaximum: CGFloat = 260
    /// Wide enough to show a dash and a dot pattern (#923).
    static let zoneAxisLegendLine = CGSize(width: 18, height: 4)

    /// The Settings window (`SettingsWindow`): a sidebar of sections beside a grouped form, mac4DSTEM's size.
    static let settingsWindow: (min: CGSize, ideal: CGSize) = (CGSize(width: 560, height: 380), CGSize(width: 660, height: 600))
}
