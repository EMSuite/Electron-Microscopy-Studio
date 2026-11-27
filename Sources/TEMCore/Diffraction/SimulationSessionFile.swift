//
//  SimulationSessionFile.swift
//  Role: a Simulation document's session file (#908): the small JSON file ⌘S writes and an Open reads back. It holds the phase the
//        document simulates as its frozen copy (#780: the library id, the name and DiffractoKit's `CrystalStructure.Snapshot`, never a
//        reference into the library, so a later edit there does not change a saved simulation) and the settings the pattern is drawn
//        at: the voltage, the camera length, k_max, the zone axis and turn (or the orientation set by hand), and the Simulation
//        section's switches and excitation error. No pixels and no results: the pattern and its spot list are simulated again on
//        open, from the same numbers, so they come back the same.
//
//  THE FILE: `<name>.emsim`, UTF-8 JSON with sorted keys. `kind` is "simulation"; `schema` is the version that wrote it and
//  `minReaderSchema` the oldest reader that can read it without misreading it. A file whose minimum reader is newer than this build,
//  one that is not JSON or not a simulation, one with a value missing or out of range, and one whose phase does not rebuild to the
//  same structure in this version (its fingerprint differs) are each refused by name with a sentence (`Refusal`), and nothing opens.
//  The Diffraction owner's side (`init(analysis:)`, `apply(to:)`) is TEMSession's, `SimulationSessionFile+Analysis.swift`.
//

import Foundation
import DiffractoCore
import TEMBase
import TEMSEM

package nonisolated struct SimulationSessionFile: Codable, Equatable, Sendable {
    /// The extension of a session file; an Open routes it to a Simulation document, never to a room's reader.
    package static let fileExtension = "emsim"
    /// The schema this build writes, and the newest minimum reader it can honour. The one place the number moves.
    package static let currentSchema = 1
    package static let kindName = "simulation"
    /// A session file is a few kilobytes; a file over this is not one, and is not read whole.
    package static let maxBytes = 8 << 20

    /// The phase as the document used it: the library's id and name and the frozen structure.
    package struct SavedPhase: Codable, Equatable, Sendable {
        package var id: String
        package var name: String
        package var structure: CrystalStructure.Snapshot

        package init(id: String, name: String, structure: CrystalStructure.Snapshot) {
            self.id = id; self.name = name; self.structure = structure
        }
    }

    package var kind = SimulationSessionFile.kindName
    package var schema = SimulationSessionFile.currentSchema
    package var minReaderSchema = SimulationSessionFile.currentSchema
    package var writer = AppName.writer
    /// Nil while the document showed no phase (its empty state).
    package var phase: SavedPhase?
    /// The typed beam energy, kV; nil when none was typed.
    package var beamKV: Double?
    package var cameraLengthMM: Double
    package var kMax: Double
    /// [u v w], three integers.
    package var zoneAxis: [Int]
    /// The typed turn about the beam, degrees.
    package var turnDegrees: Double
    /// The orientation set by hand (the Tilt tool, Flip), drawn in place of the zone axis and turn; nil when they draw it.
    package var orientation: CrystalOrientation?
    package var showsLabels: Bool
    package var doubleDiffraction: Bool
    /// σ of the excitation envelope, Å⁻¹.
    package var excitationError: Double

    package init(phase: SavedPhase?, beamKV: Double?, cameraLengthMM: Double, kMax: Double, zoneAxis: SIMD3<Int>, turnDegrees: Double,
                 orientation: CrystalOrientation?, showsLabels: Bool, doubleDiffraction: Bool, excitationError: Double) {
        self.phase = phase
        self.beamKV = beamKV
        self.cameraLengthMM = cameraLengthMM
        self.kMax = kMax
        self.zoneAxis = [zoneAxis.x, zoneAxis.y, zoneAxis.z]
        self.turnDegrees = turnDegrees
        self.orientation = orientation
        self.showsLabels = showsLabels
        self.doubleDiffraction = doubleDiffraction
        self.excitationError = excitationError
    }

    /// The zone axis as the owner holds it (the reader checked it holds three).
    package var zoneAxisVector: SIMD3<Int> {
        zoneAxis.count == 3 ? SIMD3(zoneAxis[0], zoneAxis[1], zoneAxis[2]) : SIMD3(0, 0, 1)
    }

    /// Whether `url` names a session file, by its extension.
    package static func isSessionFile(_ url: URL) -> Bool { url.pathExtension.lowercased() == fileExtension }

    // MARK: Writing

    /// The file's bytes. Throws when a number is not finite (JSON holds none).
    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Reading

    /// Why a file was not opened, in a sentence that names it.
    package struct Refusal: Error, Equatable, LocalizedError {
        package let sentence: String
        package var errorDescription: String? { sentence }

        package static func newer(name: String, reader: Int) -> Refusal {
            Refusal(sentence: "\(name) was saved by a newer version of \(AppName.display) (simulation file version \(reader)); "
                + "update \(AppName.display) to open it.")
        }

        package static func unreadable(name: String, _ why: String) -> Refusal {
            Refusal(sentence: "\(name) cannot be opened as a simulation: \(why).")
        }
    }

    /// The versions and the kind, read before anything else, so a newer file is refused as newer and not as damaged.
    private struct Header: Decodable {
        var kind: String?
        var schema: Int?
        var minReaderSchema: Int?
    }

    /// The session in `data`, the file `name`; refused by name when it cannot be read as one.
    package static func read(_ data: Data, name: String) throws(Refusal) -> SimulationSessionFile {
        guard data.count <= maxBytes else { throw .unreadable(name: name, "it is too large to be a simulation file") }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw .unreadable(name: name, "it is not a simulation file \(AppName.display) saved")
        }
        guard header.kind == kindName, let schema = header.schema, let reader = header.minReaderSchema, schema >= 1, reader >= 1 else {
            throw .unreadable(name: name, "it is not a simulation file \(AppName.display) saved")
        }
        guard reader <= currentSchema else { throw .newer(name: name, reader: reader) }
        guard let file = try? decoder.decode(SimulationSessionFile.self, from: data) else {
            throw .unreadable(name: name, "a setting is missing or damaged")
        }
        guard file.zoneAxis.count == 3, file.zoneAxis != [0, 0, 0] else {
            throw .unreadable(name: name, "its zone axis is not three whole numbers")
        }
        let numbers = [file.cameraLengthMM, file.kMax, file.turnDegrees, file.excitationError] + (file.beamKV.map { [$0] } ?? [])
        guard numbers.allSatisfy(\.isFinite), file.cameraLengthMM > 0, file.kMax > 0, file.excitationError > 0, (file.beamKV ?? 1) > 0 else {
            throw .unreadable(name: name, "a setting is not a usable number")
        }
        if let phase = file.phase, phase.structure.structure().fingerprint != phase.structure.fingerprint {
            throw .unreadable(name: name, "its phase \(phase.name) does not rebuild to the same structure in this version")
        }
        return file
    }
}
