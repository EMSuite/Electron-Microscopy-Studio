//
//  TableCopyFormat.swift
//  Role: the words of four tables rows are selected in, and ⌘C's text for them (#353): the Image room's object table (Particles), the
//        Diffraction room's readout, the Maps room's Grains table and the EELS room's results table (one row per fitted edge). They copy
//        as the Indexing room's Results table does (`IndexingTableFormat.copyText`): one header line with the column titles, then one line
//        per selected row in the table's order, the cells as the table shows them, tab-separated, numbers in the reader's locale without
//        grouping (a spreadsheet in that locale reads a plain number as one; an EELS cell with its ± is text there; the CSV exports are the
//        locale-free channel). The first three tables draw their cells through these functions, and the EELS table through the same
//        `EELSRoomFormat` texts its copy uses, so what is copied is what is shown. The readout's columns also carry what VoiceOver calls
//        them (#320): its headers are symbols and units, and one is empty; the Grains table's symbol headers are said through
//        `SEMColumnSpeech`. Pure: no view, no session.
//

import Foundation
import TEMCore
import DiffractoCore

/// Rows of a table as tab-separated text for the pasteboard.
nonisolated enum TableCopyText {
    /// One line: the cells joined by tabs. A tab or a line break inside a cell becomes a space, so a cell never opens a column or a row.
    static func line(_ cells: [String]) -> String {
        cells.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
            .joined(separator: "\t")
    }

    /// The header line, then one line per row; "" for no rows (nothing selected copies nothing).
    static func text(titles: [String], rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        return ([line(titles)] + rows.map { line($0) }).joined(separator: "\n")
    }
}

/// The object table (Image room, Particles): its column titles and a row's cells as the table shows them.
nonisolated enum ParticleTableFormat {
    /// The titles, with the unit the lengths are shown in ("nm", or "px" for an image that is not calibrated).
    static func titles(unit: String) -> [String] {
        ["#", "Length (\(unit))", "Width (\(unit))", "Angle (°)", "Area (\(unit)²)", "Note"]
    }

    /// The long axis' angle, one decimal.
    static func angle(_ row: ParticleRow, locale: Locale = .autoupdatingCurrent) -> String { Num.fixed(row.angle, 1, locale: locale) }

    /// "counted", or why the object is not ("edge").
    static func note(_ row: ParticleRow) -> String { row.note.isEmpty ? "counted" : row.note }

    /// A row's cells in `titles` order: the object's number as it is (never grouped), then length, width and area to three
    /// significant digits (`ParticleFormat.number`), the angle and the note.
    static func cells(_ row: ParticleRow, locale: Locale = .autoupdatingCurrent) -> [String] {
        ["\(row.id)", ParticleFormat.number(row.length, locale: locale), ParticleFormat.number(row.width, locale: locale),
         angle(row, locale: locale), ParticleFormat.number(row.area, locale: locale), note(row)]
    }

    /// ⌘C's text for `rows` (in the order given: the table's); "" for no rows.
    static func copyText(_ rows: [ParticleRow], unit: String, locale: Locale = .autoupdatingCurrent) -> String {
        TableCopyText.text(titles: titles(unit: unit), rows: rows.map { cells($0, locale: locale) })
    }
}

/// The Diffraction room's readout table: its columns in the table's order, each cell as the table shows it, and ⌘C's text.
nonisolated enum DiffractionReadoutFormat {
    nonisolated enum Column: CaseIterable, Sendable {
        case name, radius, q, d, family, dListed, intensity, delta, odds, verdict

        /// The header the table draws. The first column's is empty: its cells name themselves ("Ring 1", "Spot 2").
        var title: String {
            switch self {
            case .name: ""
            case .radius: "R px"
            case .q: "q Å⁻¹"
            case .d: "d Å"
            case .family: "family"
            case .dListed: "d listed"
            case .intensity: "Σ|F|² listed"
            case .delta: "Δd/d %"
            case .odds: "odds"
            case .verdict: "verdict"
            }
        }

        /// The header in the copied text: the drawn one, and for the first column what it lists.
        var copiedTitle: String { self == .name ? "Ring or spot" : title }

        /// What VoiceOver calls the column: a header of symbols and units in words ("q Å⁻¹" was read sign by sign), the first
        /// column, drawn without a title, by what it lists; a header that is words already is spoken as drawn.
        var spoken: String {
            switch self {
            case .name: "Ring or spot"
            case .radius: "radius, pixels"
            case .q: "q, inverse ångströms"
            case .d: "d, ångströms"
            case .family: "family"
            case .dListed: "d listed"
            case .intensity: "listed sum of F squared, of a hundred"
            case .delta: "delta d over d, percent"
            case .odds: "odds"
            case .verdict: "verdict"
            }
        }
    }

    /// A row's name without its mark, "Ring 1" or "Spot 2": what the first cell is called aloud.
    static func spokenName(_ row: DiffractionReadoutRow) -> String { "\(row.kind == .ring ? "Ring" : "Spot") \(row.number)" }

    /// What the ● beside a ring's name means, as the first cell's spoken value: "sets the scale" for the ring the scale was fitted
    /// on, "" for every other row. The mark's meaning was in its tooltip only.
    static func spokenMark(_ row: DiffractionReadoutRow) -> String { row.isCalibrating ? "sets the scale" : "" }

    /// One cell as the table shows it: "Ring 1 ●" (the ● marks the ring that sets the scale), R to two decimals, q to five, d and the
    /// listed d to four, the family, its listed Σ|F|² of 100 (kinematic, as diffsims lists it: outer rings read strong against a
    /// measured profile, DiffractoKit#223), Δd/d with its sign, the odds and the verdict; a dash where there is no value.
    static func cell(_ column: Column, _ row: DiffractionReadoutRow, locale: Locale = .autoupdatingCurrent) -> String {
        switch column {
        case .name: return "\(spokenName(row))\(row.isCalibrating ? " ●" : "")"
        case .radius: return row.radiusPx.map { Num.fixed($0, 2, locale: locale) } ?? UnitDisplay.noValue
        case .q: return row.q.map { Num.fixed($0, 5, locale: locale) } ?? UnitDisplay.noValue
        case .d: return row.d.map { Num.fixed($0, 4, locale: locale) } ?? UnitDisplay.noValue
        case .family: return row.family ?? UnitDisplay.noValue
        case .dListed: return row.dListed.map { Num.fixed($0, 4, locale: locale) } ?? UnitDisplay.noValue
        case .intensity: return row.listedIntensity.map { Num.fixed($0, 0, locale: locale) } ?? UnitDisplay.noValue
        case .delta: return row.deltaPercent.map { Num.signed($0, 2, locale: locale) } ?? UnitDisplay.noValue
        case .odds: return row.oddsText ?? UnitDisplay.noValue
        case .verdict: return row.verdict
        }
    }

    /// A row's cells in the table's order.
    static func cells(_ row: DiffractionReadoutRow, locale: Locale = .autoupdatingCurrent) -> [String] {
        Column.allCases.map { cell($0, row, locale: locale) }
    }

    /// ⌘C's text for `rows` (in the order given: the table's); "" for no rows.
    static func copyText(_ rows: [DiffractionReadoutRow], locale: Locale = .autoupdatingCurrent) -> String {
        TableCopyText.text(titles: Column.allCases.map(\.copiedTitle), rows: rows.map { cells($0, locale: locale) })
    }
}

/// The Diffraction room's Spots table (#785): its columns in the table's order, each cell as the table shows it, and its sorting.
nonisolated enum DiffractionSpotFormat {
    nonisolated enum Column: CaseIterable, Sendable {
        case spot, hkl, radius, q, d, dExpected, delta, phase

        var title: String {
            switch self {
            case .spot: "Spot"
            case .hkl: "hkl"
            case .radius: "R px"
            case .q: "q Å⁻¹"
            case .d: "d Å"
            case .dExpected: "d expected"
            case .delta: "Δd/d %"
            case .phase: "Phase"
            }
        }

        /// What VoiceOver calls the column: symbols and units in words.
        var spoken: String {
            switch self {
            case .spot: "Spot"
            case .hkl: "h k l"
            case .radius: "radius, pixels"
            case .q: "q, inverse ångströms"
            case .d: "d, ångströms"
            case .dExpected: "d expected, ångströms"
            case .delta: "delta d over d, percent"
            case .phase: "Phase"
            }
        }
    }

    /// One cell as the table shows it: the spot's number, the hkl with its bars, R to two decimals, q to five, d and the expected d
    /// to four, Δd/d with its sign, the phase; a dash where there is no value.
    static func cell(_ column: Column, _ row: PatternIndexing.SpotRow, locale: Locale = .autoupdatingCurrent) -> String {
        switch column {
        case .spot: return "\(row.number)"
        case .hkl: return row.hkl == nil ? UnitDisplay.noValue : row.hklText
        case .radius: return Num.fixed(row.radiusPx, 2, locale: locale)
        case .q: return Num.fixed(row.q, 5, locale: locale)
        case .d: return Num.fixed(row.d, 4, locale: locale)
        case .dExpected: return row.dExpected.map { Num.fixed($0, 4, locale: locale) } ?? UnitDisplay.noValue
        case .delta: return row.deltaPercent.map { Num.signed($0, 2, locale: locale) } ?? UnitDisplay.noValue
        case .phase: return row.phase.isEmpty ? UnitDisplay.noValue : row.phase
        }
    }

    /// The hkl in words for VoiceOver ("1, minus 1, 1"): the overbar is not read aloud.
    static func spokenHKL(_ row: PatternIndexing.SpotRow) -> String {
        guard let hkl = row.hkl else { return "not explained" }
        return [hkl.h, hkl.k, hkl.l].map { $0 < 0 ? "minus \(-$0)" : "\($0)" }.joined(separator: ", ")
    }

    /// The rows in the table's sort order; rows that tie keep the order of their spot numbers.
    static func sorted(_ rows: [PatternIndexing.SpotRow], by order: [KeyPathComparator<PatternIndexing.SpotRow>]) -> [PatternIndexing.SpotRow] {
        rows.sorted(using: order + [KeyPathComparator(\PatternIndexing.SpotRow.number)])
    }
}

/// The Maps room's Grains table: its column titles, a grain's cells as the table shows them, and ⌘C's text.
nonisolated enum GrainTableFormat {
    /// The titles, with the unit the equivalent circle diameter is shown in (the scan's: "µm", or "px" for a map without one).
    static func titles(unit: String) -> [String] {
        ["Grain", "Phase", "Points", "ECD \(unit)", "φ₁ °", "Φ °", "φ₂ °", "GOS °", "Schmid", "Neighbours"]
    }

    /// Each grain's largest Schmid factor for the Slip section's systems, by grain number (the first entry of a grain listed twice):
    /// looked up per cell, where a search of `slip` per cell made a table render O(rows × grains) (#271).
    static func schmidByGrain(_ slip: [GrainSlip]) -> [Int: Double] { GrainSlip.maximumSchmidByGrain(slip) }

    /// The grain's largest Schmid factor (`schmidByGrain`), three decimals; a dash for a grain the systems leave out.
    static func schmid(_ row: GrainRow, byGrain: [Int: Double], locale: Locale = .autoupdatingCurrent) -> String {
        MapsRoomFormat.fraction(byGrain[row.id] ?? .nan, locale: locale)
    }

    /// A grain's cells in `titles` order: its number, phase, points and neighbours as they are (never grouped), the diameter at the
    /// table's `places` decimals (`MapsRoomFormat.lengthPlaces`), the mean orientation's Euler angles to one decimal, GOS to two, the
    /// largest Schmid factor to three.
    static func cells(_ row: GrainRow, slip: [GrainSlip], places: Int = 2, locale: Locale = .autoupdatingCurrent) -> [String] {
        cells(row, schmidByGrain: schmidByGrain(slip), places: places, locale: locale)
    }

    /// The same, with the Schmid factors already by grain (`schmidByGrain`, made once for a whole copy).
    static func cells(_ row: GrainRow, schmidByGrain byGrain: [Int: Double], places: Int = 2, locale: Locale = .autoupdatingCurrent) -> [String] {
        ["\(row.id)", row.phaseName, "\(row.points)", MapsRoomFormat.length(row.diameter, places: places, locale: locale),
         MapsRoomFormat.angle(row.euler.x, locale: locale), MapsRoomFormat.angle(row.euler.y, locale: locale),
         MapsRoomFormat.angle(row.euler.z, locale: locale), MapsRoomFormat.angle(row.gosDegrees, digits: 2, locale: locale),
         schmid(row, byGrain: byGrain, locale: locale), "\(row.neighbours)"]
    }

    /// ⌘C's text for `rows` (in the order given: the table's); "" for no rows.
    static func copyText(_ rows: [GrainRow], unit: String, slip: [GrainSlip], places: Int = 2,
                         locale: Locale = .autoupdatingCurrent) -> String {
        let byGrain = schmidByGrain(slip)
        return TableCopyText.text(titles: titles(unit: unit), rows: rows.map { cells($0, schmidByGrain: byGrain, places: places, locale: locale) })
    }
}

/// The EELS room's results table, one row per fitted edge: its column titles, an edge's cells as the table shows them, and ⌘C's text.
nonisolated enum EELSEdgeTableFormat {
    /// The titles as the table draws them.
    static let titles = ["Edge", "I", "at%", "wt%"]

    /// An edge's cells in `titles` order: its title, then I, at% and wt% with their 1σ as the table draws them (`EELSRoomFormat`'s
    /// intensity, atomic and weight texts, a dash where there is no value).
    static func cells(_ row: EELSEdgeRow, locale: Locale = .autoupdatingCurrent) -> [String] {
        [row.title, EELSRoomFormat.intensityText(row, locale: locale), EELSRoomFormat.atomicText(row, locale: locale),
         EELSRoomFormat.weightText(row, locale: locale)]
    }

    /// ⌘C's text for `rows` (in the order given: the table's); "" for no rows.
    static func copyText(_ rows: [EELSEdgeRow], locale: Locale = .autoupdatingCurrent) -> String {
        TableCopyText.text(titles: titles, rows: rows.map { cells($0, locale: locale) })
    }
}
