//
//  DiffractionPhases.swift
//  Role: the Diffraction room's phases from the library (#779): each phase's marker shape and colour, by its place in the
//        library, and the crystal the room indexes against when a phase is shown. In this first slice one phase is shown at a
//        time: showing a phase makes it the crystal Index, the readout and the simulated spots use; hiding it returns the room to
//        the calibration standard, which only calibrates: Index waits for a phase again (#1139). The room keeps its own copy of the phase it uses (#780), so a later change to the
//        library changes no result until Update from Library. The numbers stay DiffractoKit's; this file only names and chooses.
//

import DiffractoCore
import ShellPhaseLibrary
import SwiftUI
import TEMCore
import TEMSession

nonisolated enum PhaseMarker: String, CaseIterable, Sendable {
    case circle, square, triangle, diamond, hexagon

    var systemImage: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .hexagon: "hexagon"
        }
    }

    var spoken: String { rawValue }
}

enum DiffractionPhases {
    /// The marker colours, one per phase in turn (distinct in light and dark, and for the common colour deficiencies).
    static let colours: [(name: String, color: Color)] = [
        ("blue", .blue), ("orange", .orange), ("green", .green), ("pink", .pink), ("purple", .purple), ("brown", .brown),
    ]

    /// The library's phases in the order they were added, so a phase keeps its marker when another is added.
    nonisolated static func ordered(_ phases: [Phase]) -> [Phase] {
        phases.sorted { ($0.added, $0.id) < ($1.added, $1.id) }
    }

    /// The marker shape and colour of the phase at `index` in `ordered(_:)`, each in turn: no two of the first 30 phases share both.
    nonisolated static func style(at index: Int) -> (marker: PhaseMarker, colourIndex: Int) {
        let markers = PhaseMarker.allCases
        let i = max(0, index)
        return (markers[i % markers.count], i % 6)
    }

    /// The crystal the room uses for a library phase.
    static func crystal(for phase: Phase) -> DiffractionCrystal {
        .phase(PhaseCrystal(id: phase.id, name: phase.name, structure: phase.structure()))
    }

    /// Shows `phase` (it becomes the crystal in use) or hides it (the room returns to its calibration standard).
    static func set(_ phase: Phase, shown: Bool, in analysis: DiffractionAnalysis) {
        if shown {
            analysis.setCrystal(crystal(for: phase))
        } else if analysis.crystal.phaseID == phase.id {
            analysis.clearCrystal()
        }
    }

    /// The lattice in one line (DiffractionCrystal's words, which the exports write too): with a decimal point for the door, in the
    /// reader's locale for the Phases list (#1039).
    nonisolated static func latticeText(_ cell: UnitCell, locale: Locale = UnitDisplay.point) -> String {
        DiffractionCrystal.latticeText(cell, locale: locale)
    }

    /// The room keeps its own copy of a shown phase (#780): an edit of the library's phase reaches the room's results only
    /// through Update from Library. True when `phase` is the one in use and the library's copy differs from it.
    static func isOutdated(_ phase: Phase, in analysis: DiffractionAnalysis) -> Bool {
        guard case .phase(let inUse) = analysis.crystal, inUse.id == phase.id else { return false }
        return inUse.fingerprint != CrystalStructure.Snapshot(phase.structure()).fingerprint || inUse.name != phase.name
    }

    /// The library id of a CIF's phase: its content hash.
    static func phaseID(ofCIF loaded: LoadedCrystal) -> String { "cif-" + loaded.sha256.prefix(16) }

    /// A CIF shown as a phase without adding it to the library (the silicon demo's, #1111): the crystal `addCIF` then `set` would
    /// show, with the same id, so the library's copy, if the person added the file, is the one ticked.
    static func crystal(forCIF loaded: LoadedCrystal) -> DiffractionCrystal {
        .phase(PhaseCrystal(id: phaseID(ofCIF: loaded), name: loaded.displayName, structure: loaded.structure))
    }

    /// A CIF the person chose in the Add Phase sheet's Open CIF…, added to the library with its bytes (it then works offline
    /// like any phase). Its id is its content hash, so the same file added twice is one phase.
    static func addCIF(_ loaded: LoadedCrystal, bytes: Data, fileName: String, to library: PhaseLibrary) throws -> Phase {
        let id = phaseID(ofCIF: loaded)
        if let existing = library.phases.first(where: { $0.id == id }) { return existing }
        let phase = Phase(id: id, name: loaded.displayName, source: .cif(fileName: fileName), structure: loaded.structure)
        try library.add(phase, source: bytes, sourceExtension: "cif")
        return phase
    }

    /// The precipitates the Precipitate section and the door's `set_relationship` offer (#1137): the library's phases, the
    /// standards, then the crystals of the other open patterns, each name once and the matrix left out. Nothing sample-specific:
    /// no literature example is built in (#1152).
    static func precipitates(besides matrix: String, library: [Phase], others: [(name: String, structure: CrystalStructure)])
        -> [DiffractionVariants.Precipitate] {
        var seen: Set<String> = [matrix]
        var out: [DiffractionVariants.Precipitate] = []
        func add(_ name: String, _ structure: CrystalStructure) {
            if seen.insert(name).inserted { out.append(.init(name: name, structure: structure)) }
        }
        ordered(library).forEach { add($0.name, $0.structure()) }
        StandardCrystals.all.forEach { add($0.name, $0.structure) }
        others.forEach { add($0.name, $0.structure) }
        return out
    }
}
