//
//  DiffractionExport.swift
//  Role: the Diffraction room's readout as one CSV (design section 6): comment lines (file, centre and where it came from, the
//        calibration and its source, the crystal and its sha256, k_max, the tolerance) then one row per ring or spot.
//        Pure text; the numbers are what `DiffractionReadout` rows hold, which are the kit's. The text cells are RFC 4180 and the file
//        and crystal names each stay on their header line (ImagoKit's `CSVText.quoted` and `CSVText.headerValue`).
//

import DiffractoCore
import Foundation
import ImagoCore
import TEMBase
import TEMSEM

/// One line of the readout: a ring or a spot with what the kit says about it.
package nonisolated struct DiffractionReadoutRow: Sendable, Equatable, Identifiable {
    package enum Kind: String, Sendable { case ring, spot }
    package let id: UUID
    package let kind: Kind
    package var number: Int
    package var radiusPx: Double?
    package var q: Double?
    /// Å, measured: 1/q.
    package var d: Double?
    package var family: String?
    package var dListed: Double?
    /// The listed family's kinematic intensity, of 100 for the list's strongest family (#811).
    package var listedIntensity: Double?
    package var deltaPercent: Double?
    package var oddsText: String?
    package var verdict: String
    package var validation: String
    package var isCalibrating: Bool
    /// The kit's sentence for a refused indexing (`DisplayedIndexing.refusalText`): the verdict cell's tooltip, nil otherwise (#1018).
    package var verdictDetail: String?

    package init(id: UUID, kind: Kind, number: Int, radiusPx: Double?, q: Double?, d: Double?, family: String?, dListed: Double?,
                 deltaPercent: Double?, oddsText: String?, verdict: String, validation: String, isCalibrating: Bool = false,
                 listedIntensity: Double? = nil, verdictDetail: String? = nil) {
        self.id = id; self.kind = kind; self.number = number; self.radiusPx = radiusPx; self.q = q; self.d = d
        self.family = family; self.dListed = dListed; self.deltaPercent = deltaPercent; self.oddsText = oddsText
        self.verdict = verdict; self.validation = validation; self.isCalibrating = isCalibrating
        self.listedIntensity = listedIntensity; self.verdictDetail = verdictDetail
    }

    /// `rows` with each spot's hkl, d, expected d and misfit taken from Index's Spots table (`spots`, #1148): an indexed pattern's
    /// figure labels and tabulates what Index found, as the Spots table does, not the ring readout's nearest family. A spot Index left
    /// unexplained (or that has no Index row) has no hkl; rings keep the readout's family.
    package static func takingIndex(_ rows: [DiffractionReadoutRow], spots: [PatternIndexing.SpotRow]) -> [DiffractionReadoutRow] {
        let byID = Dictionary(spots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.map { row in
            guard row.kind == .spot else { return row }
            var out = row
            out.oddsText = nil
            out.listedIntensity = nil
            guard let spot = byID[row.id] else {
                out.family = nil; out.dListed = nil; out.deltaPercent = nil
                return out
            }
            out.q = spot.q
            out.d = spot.d
            out.family = spot.hkl.map { ZoneAxisText.label($0) }
            out.dListed = spot.hkl == nil ? nil : spot.dExpected
            out.deltaPercent = spot.hkl == nil ? nil : spot.deltaPercent
            return out
        }
    }

    /// The verdict as the table, the announcement and the Results room show it: the kit's refusal names (`RingIndexing.Error.name`,
    /// stable keys for the door and the CSV) in plain words (#1018); any other verdict is words already and passes through.
    package var verdictWords: String { Self.words(forVerdict: verdict) }

    /// Plain words for a verdict key: every case of the kit's `RingIndexing.Error` and the accepted verdict.
    package static func words(forVerdict verdict: String) -> String {
        switch verdict {
        case "ambiguous": "ambiguous: more than one family fits"
        case "noneWithinTolerance": "no family of the phase within tolerance"
        case "beyondKMax": "past the list's reach: raise k max"
        case "invalidInput": "cannot index this radius"
        default: verdict
        }
    }
}

package nonisolated struct DiffractionExportHeader: Sendable, Equatable {
    package var fileName: String
    package var centreRow: Double
    package var centreColumn: Double
    package var centreSource: String
    package var calibration: String
    package var deltaQ: Double?
    package var wavelengthAngstroms: Double?
    package var lengthPixels: Double?
    package var lengthMM: Double?
    package var fitVersusFilePercent: Double?
    package var crystal: String
    package var crystalSHA256: String?
    package var kMax: Double
    package var tolerancePercent: Double
    /// The lattice the rows were indexed with, in one line (#780); nil leaves it off.
    package var crystalLattice: String?
    /// A library phase's id and fingerprint (#780); nil for a standard or a loose CIF.
    package var crystalPhase: String?
    package init(fileName: String, centreRow: Double, centreColumn: Double, centreSource: String, calibration: String, deltaQ: Double?,
                 wavelengthAngstroms: Double?, lengthPixels: Double?, lengthMM: Double?, fitVersusFilePercent: Double?, crystal: String,
                 crystalSHA256: String?, kMax: Double, tolerancePercent: Double, crystalLattice: String? = nil, crystalPhase: String? = nil) {
        self.crystalLattice = crystalLattice; self.crystalPhase = crystalPhase
        self.fileName = fileName; self.centreRow = centreRow; self.centreColumn = centreColumn; self.centreSource = centreSource
        self.calibration = calibration; self.deltaQ = deltaQ; self.wavelengthAngstroms = wavelengthAngstroms
        self.lengthPixels = lengthPixels; self.lengthMM = lengthMM; self.fitVersusFilePercent = fitVersusFilePercent
        self.crystal = crystal; self.crystalSHA256 = crystalSHA256; self.kMax = kMax; self.tolerancePercent = tolerancePercent
    }
}

package nonisolated enum DiffractionExport {
    package static let columns = "kind,number,R_px,q_per_A,d_A,family,d_listed_A,delta_percent,odds,verdict,calibrating"

    package static func text(rows: [DiffractionReadoutRow], header h: DiffractionExportHeader) -> String {
        func g(_ v: Double?) -> String { v.map { String(format: "%.9g", $0) } ?? "" }
        // A CIF whose data block names nothing, or only a VESTA placeholder, gives the crystal its file's base name, which may hold a line break.
        let crystal = CSVText.headerValue(h.crystal) + (h.crystalSHA256.map { " sha256 \($0)" } ?? "")
            + (h.crystalPhase.map { " (\(CSVText.headerValue($0)))" } ?? "")
            + (h.crystalLattice.map { "; lattice \(CSVText.headerValue($0))" } ?? "")
        var lines = [
            "# \(AppName.writer) diffraction readout",
            "# file: \(CSVText.headerValue(h.fileName))",
            "# centre: row \(g(h.centreRow)), column \(g(h.centreColumn)) (\(h.centreSource))",
            "# calibration: \(h.calibration); delta_q \(g(h.deltaQ)) per A per px; wavelength \(g(h.wavelengthAngstroms)) A; L \(g(h.lengthPixels)) px; L \(g(h.lengthMM)) mm; fit versus file \(g(h.fitVersusFilePercent)) %",
            "# crystal: \(crystal); k_max \(g(h.kMax)) per A; tolerance \(g(h.tolerancePercent)) % of q",
        ]
        lines.append(columns)
        for r in rows {
            lines.append([r.kind.rawValue, "\(r.number)", g(r.radiusPx), g(r.q), g(r.d), CSVText.quoted(r.family ?? ""), g(r.dListed),
                          g(r.deltaPercent), CSVText.quoted(r.oddsText ?? ""), CSVText.quoted(r.verdict),
                          r.isCalibrating ? "yes" : ""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
