//
//  EBSDFileMaps.swift
//  Role: where the EBSD files FormatoKit reads and writes (FormatoEBSD, since #852) meet the app's crystal maps and words. FormatoKit
//        hands a map over as plain columns (`EBSDMapColumns`) and DiffractoKit makes the `CrystalMap` from them; the two kits meet
//        here and nowhere else (ADR 0005):
//        - a map file's columns become a `CrystalMap` in one place (`EBSDMapColumns.crystalMap()`, `EBSDDataset.crystalMap`), and the
//          phases a room lists come from the same matching without the rotations (`phaseList()`);
//        - a `CrystalMap` becomes the grid the `.ang` and `.ctf` writers write (`EBSDMapGrid(_:)`, orix's `file_writer` arithmetic that
//          the app's writers held before), and the writers are called with the app's own name in the header as before;
//        - a reader's refusal is worded for the app (`EBSDReadError.inAppWords`): the kit's sentences name no app, so the ones that
//          say which room opens a file, or that the app was not given access, are said as the app said them before #852.
//

import DiffractoOrientation
import FormatoEBSD
import Foundation
import TEMBase

// MARK: - Columns to a crystal map

extension EBSDMapColumns {
    /// The map as orix's reader makes it: the Bunge angles to rotations (`eu2qu`), the file's phases matched to the ids in the data,
    /// the shape and steps from x and y. Refused (`CrystalMap.Refusal`) where the columns make no map (lengths that disagree,
    /// coordinates that make no grid).
    package func crystalMap() throws -> CrystalMap {
        try CrystalMap(euler: euler, phaseIDs: phaseIDs, x: x, y: y, properties: properties, phaseHeaders: phaseHeaderTuples,
                       scanUnit: scanUnit, isInData: isInData)
    }

    /// The phases `crystalMap()` holds (orix's matching of the file's phases to the ids in the data), from the distinct ids alone: a
    /// room that lists the phases does not make every rotation for it. nil where the columns make no map.
    package func phaseList() -> PhaseList? {
        guard pointCount > 0 else { return (try? crystalMap())?.phases }
        let ids = Array(Set(phaseIDs ?? [0])).sorted()
        return try? CrystalMap(euler: ids.map { _ in SIMD3<Double>.zero }, phaseIDs: ids, phaseHeaders: phaseHeaderTuples).phases
    }
}

extension EBSDDataset {
    /// The file's own crystal map (`EBSDMapColumns.crystalMap()`), made on each call: a session that reads it more than once holds
    /// it (`EBSDSession.Document.crystalMap`). nil when the file holds no map, or one whose columns make no map (the open refuses
    /// that, `EBSDOpening.open`).
    package var crystalMap: CrystalMap? { (try? map?.crystalMap()) ?? nil }
}

// MARK: - A crystal map to the writers' grid

extension EBSDMapGrid {
    /// The rectangle a writer writes, as the app's writers laid it out before FormatoKit wrote the files (orix 0.15.0's
    /// `file_writer`): the data extent's rows and columns (a 1D map is one row with y step 1), the map's steps, which cells are
    /// indexed (false where no point is in data), the Bunge angles of the rotations in data (`qu2eu`, orix's `to_euler`) and every
    /// property on the extent with 0 elsewhere, the phase ids with NaN where no point is, and each phase with its proper point group
    /// (orix's `proper_subgroup`) and Laue group.
    package init(_ map: CrystalMap) throws {
        let shape = map.shape
        guard shape.count == 1 || shape.count == 2 else { throw Refusal.noGrid }
        let rows = shape.count == 1 ? 1 : shape[0]
        let columns = shape.count == 1 ? shape[0] : shape[1]
        let dy = shape.count == 1 ? 1 : map.dy
        guard rows > 0, columns > 0 else { throw Refusal.noGrid }
        let indexed = map.mapData(map.isIndexed.map { $0 ? 1.0 : 0.0 }, fill: 0).map { $0 == 1 }
        let angles = map.rotationsInData.map(RotationConversions.qu2eu)
        let phi1 = map.mapData(angles.map { $0[0] }, fill: 0)
        let phi = map.mapData(angles.map { $0[1] }, fill: 0)
        let phi2 = map.mapData(angles.map { $0[2] }, fill: 0)
        let euler = (0..<phi1.count).map { SIMD3(phi1[$0], phi[$0], phi2[$0]) }
        var properties: [String: [Double]] = [:]
        for name in map.propertyNames {
            if let values = map.property(name) { properties[name] = map.mapData(values, fill: 0) }
        }
        let phases = map.phases.entries.filter { $0.id != PhaseList.notIndexedID }.map { entry in
            let phase = entry.phase
            return Phase(id: entry.id, name: phase.name, spaceGroup: phase.spaceGroup, lattice: phase.lattice,
                         properPointGroup: phase.pointGroupName.map { PointGroup.named($0)?.properSubgroup.name ?? $0 },
                         laueGroup: PointGroup.laueName(phase.pointGroupName))
        }
        try self.init(rows: rows, columns: columns, dx: map.dx, dy: dy, mapDY: map.dy, indexed: indexed, euler: euler,
                      phaseIDs: map.mapData(map.phaseIDs.map(Double.init), fill: .nan), properties: properties, phases: phases)
    }
}

extension ANGWriter.Options {
    /// orix's columns with the app's name on the `OPERATOR:` line.
    package static var app: ANGWriter.Options { ANGWriter.Options(operatorName: AppName.writer) }
}

extension ANGWriter {
    /// The `.ang` text of `map` (`EBSDMapGrid(map)`, then FormatoKit's writer).
    package static func text(of map: CrystalMap, options: Options = .app) throws -> String {
        try text(of: EBSDMapGrid(map), options: options)
    }

    /// Writes `map` as an `.ang` through `FormatoFileWrite` (a scratch file first, then over `url`).
    package static func write(_ map: CrystalMap, to url: URL, options: Options = .app) throws {
        try write(EBSDMapGrid(map), to: url, options: options)
    }
}

extension CTFWriter {
    /// The `.ctf` text of `map`; `project` and `author` are the app's name unless given.
    package static func text(of map: CrystalMap, project: String = AppName.writer, author: String = AppName.writer,
                             acquisition: EBSDMapAcquisition? = nil) throws -> String {
        try text(of: EBSDMapGrid(map), project: project, author: author, acquisition: acquisition)
    }

    /// Writes `map` as a `.ctf`; `project` defaults to the file's name.
    package static func write(_ map: CrystalMap, to url: URL, project: String? = nil, author: String = AppName.writer) throws {
        try write(EBSDMapGrid(map), to: url, project: project, author: author)
    }
}

/// What the session knows about how a crystal map was acquired and made, for the `.ang` and `.ctf` headers (macEM#616): FormatoKit's
/// `EBSDMapAcquisition`, the app's name for it.
package typealias CrystalMapAcquisition = EBSDMapAcquisition

extension EBSDMapAcquisition {
    /// The names and versions of the Swift packages the app is built with ("FormatoKit 0.15.0, ImagoKit 0.9.2, ...").
    package static var kitVersions: String { SEMReferenceVersions.builtWith.map { "\($0.name) \($0.value)" }.joined(separator: ", ") }
}

// MARK: - Refusals in the app's words

extension EBSDReadError {
    /// A refusal the app words itself (a room's door, a check before a read).
    package init(text: String) { self.init(.unreadable, text) }

    /// The refusal as the app says it: where FormatoKit's sentence names no app ("this process", "these readers") or no room, the
    /// app's own sentence as it read before #852 (#514, #513); every other sentence as the kit says it.
    package var inAppWords: EBSDReadError {
        let app = AppName.display
        var words = text
        func say(_ kit: String, as ours: String) { words = words.replacingOccurrences(of: kit, with: ours) }
        switch reason {
        case .notPermitted:
            say("the system does not let this process read it.",
                as: "\(app) was not given access to it: open it with File > Open…, drop it on the window or open it from the Finder.")
            say("macOS does not let this process open it", as: "macOS does not let \(app) open it")
        case .filter:
            say("compressed with a filter the HDF5 library here does not have.", as: "compressed with a filter \(app) does not have.")
        case .tooLarge:
            say("it holds more than is read in one piece.", as: "it holds more than \(app) reads in one piece.")
        case .unsupportedType:
            say("stores its data in a type that is not read.", as: "stores its data in a type \(app) does not read.")
        case .edsOnly:
            words += " \(app) does not read EDS from an .h5oina file yet; a spectrum AZtec exports as .msa opens in the EDS room."
        case .holdsPatterns:
            say(" holds EBSD patterns; its map comes with them.", as: " holds EBSD patterns: it opens in the Patterns room, which shows its map.")
        case .holdsMapOnly:
            say(" holds an orientation map but no EBSD patterns.", as: " holds an orientation map but no EBSD patterns: it opens in the Maps room.")
        case .notAMap:
            say("is not an orientation map these readers read", as: "is not an orientation map \(app) reads")
        case .manufacturer:
            say("which these readers do not read; they read", as: "which \(app) does not read; it reads")
        default:
            break
        }
        return EBSDReadError(reason, words)
    }

    /// `error` in the app's words when it is a reader's refusal (`inAppWords`), else as it is.
    package static func appWorded(_ error: Error) -> Error {
        (error as? EBSDReadError)?.inAppWords ?? error
    }

    /// `wrap` in the app's words: a reader's own refusal, or an HDF5 or Foundation failure in plain words, naming the file.
    package static func wrapInAppWords(_ error: Error, file: URL) -> EBSDReadError {
        wrap(error, file: file).inAppWords
    }
}
