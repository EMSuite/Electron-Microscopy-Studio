//
//  PowderTable.swift
//  Role: the powder pattern of the shown phases as the Simulation document and the agent door read it (plan rows R11 and R12,
//        #810, #811): X-ray peaks (`PowderPattern.xray`, pymatgen's `XRDCalculator`, kit pin P49) or electron rings
//        (`PowderPattern.electron`, the held ring list, pin P4), which peaks overlap another shown phase and which is each phase's
//        diagnostic peak (`PowderPattern.marks`), the peak table, the sentences the document says, and the two files a pattern
//        leaves as: the peak table as CSV and one phase's drawn profile as .xy. Every number is the kit's; this file names them.
//        Pure and nonisolated: the document and the door call the same `PowderTable.make`.
//
//        Defaults are pymatgen's and the design's (EMSuite docs/design/diffraction-indexing.md, B5): Cu Kα, 10 to 90° shown,
//        width 0.1° (rings 0.01 Å⁻¹), overlaps within 0.1° (rings 1 % of q, Index's tolerance), the table from 1 of 100.
//        The peaks are computed over the shown range, so the strongest peak inside it is 100.
//        EXACT: every number in the two files is written `%.17g` (`CSVText.number`), as FFTExport's are.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoScattering
import ImagoCore

/// What a powder pattern shows: electron rings against q, or an X-ray pattern against 2θ.
package nonisolated enum PowderKind: String, Sendable, Codable, CaseIterable, Equatable {
    case rings
    case xray
}

/// The settings of a powder pattern (the Powder section). Derived peaks are never stored, only these.
package nonisolated struct PowderSettings: Sendable, Codable, Equatable {
    package var kind: PowderKind = .xray
    /// The X-ray line (pymatgen's list) or a typed wavelength.
    package var radiation: XRayRadiation = .cuKAlpha
    /// The 2θ range shown and computed, degrees.
    package var twoThetaFrom: Double = 10
    package var twoThetaTo: Double = 90
    /// The rings' reach, Å⁻¹.
    package var ringReach: Double = 1.5
    /// The beam energy for rings, volts (the Microscope section's).
    package var volts: Double = 200_000
    /// Full width at half maximum of a drawn peak: degrees of 2θ, or Å⁻¹ for rings.
    package var xrayWidth: Double = 0.1
    package var ringWidth: Double = 0.01
    /// Mark the peaks that overlap another shown phase, and each phase's diagnostic peak.
    package var markOverlaps = true
    /// Two peaks closer than this are one in a drawing: degrees of 2θ; for rings a fraction of q.
    package var xrayResolution: Double = 0.1
    package var ringResolutionFraction: Double = 0.01
    /// Peaks under this (of 100) are left out of the table and never mark another as overlapped.
    package var floor: Double = 1

    package init() {}

    /// The drawn width in the pattern's unit.
    package var width: Double { kind == .xray ? xrayWidth : ringWidth }
    /// The range drawn: 2θ in degrees, or q from 0 in Å⁻¹.
    package var range: ClosedRange<Double> {
        kind == .xray ? min(twoThetaFrom, twoThetaTo)...max(twoThetaFrom, twoThetaTo) : 0...ringReach
    }
    /// The overlap resolution as the kit takes it.
    package var resolution: PowderResolution {
        kind == .xray ? .absolute(xrayResolution) : .fraction(ringResolutionFraction)
    }
}

/// One phase a powder pattern is drawn for.
package nonisolated struct PowderPhase: Sendable, Equatable {
    package let name: String
    package let structure: CrystalStructure
    /// The lattice is calculated, not measured (a Materials Project phase).
    package let calculatedLattice: Bool

    package init(name: String, structure: CrystalStructure, calculatedLattice: Bool = false) {
        self.name = name; self.structure = structure; self.calculatedLattice = calculatedLattice
    }
}

/// One row of the peak table.
package nonisolated struct PowderRow: Sendable, Equatable, Identifiable {
    /// "phase index:peak index": stable while the phases and settings stay.
    package let id: String
    package let phase: String
    package let phaseIndex: Int
    /// The peak's families, pymatgen's labels: "111" or "111, 115" (four indices on a hexagonal lattice).
    package let hkl: String
    package let multiplicity: Int
    /// Å.
    package let d: Double
    /// 2θ in degrees, or q in Å⁻¹.
    package let position: Double
    /// Of 100, the phase's strongest peak.
    package let intensity: Double
    /// The other shown phases' peaks within the resolution: "Mg2Si 220".
    package let overlaps: [String]
    /// The phase's strongest peak that is not overlapped.
    package let isDiagnostic: Bool

    package var isOverlapped: Bool { !overlaps.isEmpty }
}

/// A phase the kit drew no pattern for, and the kit's reason.
package nonisolated struct PowderRefusal: Sendable, Equatable {
    /// The phase's place in `PowderTable.phases`: two phases may share a name.
    package let index: Int
    package let phase: String
    package let reason: String
}

/// The powder pattern of the shown phases: the kit's patterns, the table, the sentences and the files.
package nonisolated struct PowderTable: Sendable, Equatable {
    package let settings: PowderSettings
    package let phases: [PowderPhase]
    /// One per phase, in the phases' order; nil where the kit refused the phase (its sentence is in `refusals`).
    package let patterns: [PowderPattern?]
    /// The kit's marks per phase (empty for a refused phase, or with Mark overlaps off).
    package let marks: [[PowderPeakMark]]
    /// The rows of the table: every peak of at least the floor, phase by phase, in ascending position.
    package let rows: [PowderRow]
    /// Each phase the kit refused, with its reason.
    package let refusals: [PowderRefusal]

    // MARK: Building

    /// The patterns of `phases` under `settings`, their marks and the table.
    package static func make(phases: [PowderPhase], settings: PowderSettings) -> PowderTable {
        var patterns: [PowderPattern?] = []
        var refusals: [PowderRefusal] = []
        for (i, phase) in phases.enumerated() {
            do throws(PowderPatternError) {
                patterns.append(try pattern(of: phase.structure, settings: settings))
            } catch {
                patterns.append(nil)
                refusals.append(PowderRefusal(index: i, phase: phase.name, reason: error.description))
            }
        }
        // the kit's marks over the computed patterns, mapped back to the phases' order
        let computed = patterns.indices.filter { patterns[$0] != nil }
        let kitMarks = settings.markOverlaps
            ? PowderPattern.marks(computed.map { patterns[$0]! }, resolution: settings.resolution, floor: settings.floor)
            : computed.map { patterns[$0]!.peaks.map { _ in PowderPeakMark(partners: [], isDiagnostic: false) } }
        var marks: [[PowderPeakMark]] = Array(repeating: [], count: phases.count)
        for (k, i) in computed.enumerated() { marks[i] = kitMarks[k] }

        var rows: [PowderRow] = []
        for i in phases.indices {
            guard let pattern = patterns[i] else { continue }
            for (k, peak) in pattern.peaks.enumerated() where peak.intensity >= settings.floor {
                let mark = marks[i].indices.contains(k) ? marks[i][k] : nil
                let overlaps = (mark?.partners ?? []).map { ref -> String in
                    let j = computed[ref.pattern]
                    return "\(phases[j].name) \(label(patterns[j]!.peaks[ref.peak]))"
                }
                rows.append(PowderRow(id: "\(i):\(k)", phase: phases[i].name, phaseIndex: i, hkl: label(peak),
                                      multiplicity: peak.multiplicity, d: peak.d, position: peak.position, intensity: peak.intensity,
                                      overlaps: overlaps, isDiagnostic: mark?.isDiagnostic ?? false))
            }
        }
        return PowderTable(settings: settings, phases: phases, patterns: patterns, marks: marks, rows: rows, refusals: refusals)
    }

    /// One phase's pattern: X-rays over the shown 2θ range at the chosen line, or the rings to the reach at the beam's wavelength.
    package static func pattern(of structure: CrystalStructure, settings: PowderSettings) throws(PowderPatternError) -> PowderPattern {
        switch settings.kind {
        case .xray:
            return try PowderPattern.xray(structure: structure, radiation: settings.radiation, twoThetaRange: settings.range)
        case .rings:
            return try PowderPattern.electron(structure: structure,
                                              wavelengthAngstroms: ElectronWavelength.angstroms(volts: settings.volts),
                                              kMax: settings.ringReach)
        }
    }

    /// A peak's families as the table names them: "111", or "111, 115" for a peak of two families. Indices run together only
    /// while each is one digit and not negative; otherwise a space parts them, so (11 1 0) and (1 1 10) never read alike.
    package static func label(_ peak: PowderPattern.Peak) -> String {
        peak.families.map { family(indices: $0.indices) }.joined(separator: ", ")
    }

    /// "111", or "1 1 10" and "-1 1 1" where an index has two digits or a sign.
    package static func family(indices: [Int]) -> String {
        let parts = indices.map(String.init)
        return indices.allSatisfy { (0...9).contains($0) } ? parts.joined() : parts.joined(separator: " ")
    }

    // MARK: Words

    /// "Cu Kα", "Cu Kα₁", "Mo Kβ₁"; a typed wavelength "1.5 Å".
    package static func radiationName(_ radiation: XRayRadiation) -> String {
        guard let name = radiation.name, name.count >= 4 else { return String(format: "%g Å", radiation.wavelengthAngstroms) }
        let element = String(name.prefix(2))
        var line = String(name.dropFirst(2))
        line = line.replacingOccurrences(of: "Ka", with: "Kα").replacingOccurrences(of: "Kb", with: "Kβ")
        line = line.replacingOccurrences(of: "1", with: "₁").replacingOccurrences(of: "2", with: "₂")
        return "\(element) \(line)"
    }

    /// A position in the pattern's unit: "38.51°" or "0.428 Å⁻¹". `locale`: the point (the default) for the door, the reader's for
    /// the room's peak list and notes (#1039).
    package func positionText(_ position: Double, locale: Locale = UnitDisplay.point) -> String {
        settings.kind == .xray ? UnitDisplay.fixed(position, places: 2, locale: locale) + "°"
            : UnitDisplay.fixed(position, places: 3, locale: locale) + " Å⁻¹"
    }

    /// The phase's headline: "Al · Cu Kα · 5 peaks from 10° to 90° · strongest 111 at 38.51°", or for rings
    /// "Al · 200 kV · 7 rings to 1.5 Å⁻¹ · strongest 111 at 0.428 Å⁻¹". A refused phase gives the kit's reason.
    package func headline(phase i: Int, locale: Locale = UnitDisplay.point) -> String {
        let name = phases[i].name
        guard let pattern = patterns[i] else {
            return "\(name): " + (refusals.first { $0.index == i }?.reason ?? "no pattern")
        }
        let shown = rows.filter { $0.phaseIndex == i }.count
        let range = settings.range
        let source: String, extent: String, noun: String
        switch settings.kind {
        case .xray:
            source = Self.radiationName(settings.radiation)
            extent = "from \(UnitDisplay.number(range.lowerBound, locale: locale))° to \(UnitDisplay.number(range.upperBound, locale: locale))°"
            noun = shown == 1 ? "peak" : "peaks"
        case .rings:
            source = "\(UnitDisplay.number(settings.volts / 1000, locale: locale)) kV"
            extent = "to \(UnitDisplay.number(range.upperBound, locale: locale)) Å⁻¹"
            noun = shown == 1 ? "ring" : "rings"
        }
        var parts = [name, source, "\(shown) \(noun) \(extent)"]
        if let strongest = pattern.strongest { parts.append("strongest \(Self.label(strongest)) at \(positionText(strongest.position, locale: locale))") }
        return parts.joined(separator: " · ")
    }

    /// With two or more shown phases and Mark overlaps on: "Al: 1 of 5 peaks overlapped. Diagnostic peak 111 at 38.51°", or
    /// "Al: every peak is overlapped; no peak tells it apart". nil for one phase, marks off, or a refused phase.
    package func marksSentence(phase i: Int, locale: Locale = UnitDisplay.point) -> String? {
        guard settings.markOverlaps, patterns.compactMap({ $0 }).count >= 2, patterns[i] != nil else { return nil }
        let own = rows.filter { $0.phaseIndex == i }
        let overlapped = own.filter(\.isOverlapped).count
        let noun = settings.kind == .xray ? "peaks" : "rings"
        let head = "\(phases[i].name): \(overlapped) of \(own.count) \(noun) overlapped."
        guard let diagnostic = own.first(where: \.isDiagnostic) else {
            return head + " No \(settings.kind == .xray ? "peak" : "ring") tells it apart."
        }
        let word = settings.kind == .xray ? "peak" : "ring"
        return head + " Diagnostic \(word) \(diagnostic.hkl) at \(positionText(diagnostic.position, locale: locale))"
    }

    /// For a phase with a calculated lattice: what a cell error does to its peaks. 1 % in every length moves a peak by
    /// Δ(2θ) = 2 tan θ · 0.01 rad, said at 40° 2θ for X-rays; for rings it moves q by 1 %.
    package func calculatedLatticeSentence(phase i: Int) -> String? {
        guard phases[i].calculatedLattice else { return nil }
        switch settings.kind {
        case .xray:
            let shift = 2 * tan(20 * Double.pi / 180) * 0.01 * 180 / Double.pi
            return String(format: "Lattice calculated (Materials Project). A 1 %% cell error moves a peak near 40° by about %.1f°.", shift)
        case .rings:
            return "Lattice calculated (Materials Project). A 1 % cell error moves every ring by 1 % of q."
        }
    }

    // MARK: Files

    /// The peak table as CSV (R12): comment lines naming the pattern, then one row per table row, the same numbers.
    package func csv() -> String {
        func g(_ v: Double) -> String { CSVText.number(v) }
        let positionColumn = settings.kind == .xray ? "two_theta_deg" : "q_per_A"
        var lines = ["# \(AppName.writer) powder pattern"]
        switch settings.kind {
        case .xray:
            lines.append("# kind: X-ray; radiation \(settings.radiation.name ?? "typed") \(g(settings.radiation.wavelengthAngstroms)) A; "
                         + "two theta \(g(settings.range.lowerBound)) to \(g(settings.range.upperBound)) deg")
            lines.append("# method: pymatgen XRDCalculator (atomic scattering factors, structure factor, Lorentz-polarisation); no Debye-Waller factor")
        case .rings:
            lines.append("# kind: electron rings; \(g(settings.volts)) V; q to \(g(settings.ringReach)) per A (no 2 pi)")
            lines.append("# method: kinematic ring list (sum of |F|^2 over each ring's reflections)")
        }
        let resolution = settings.kind == .xray ? "\(g(settings.xrayResolution)) deg" : "\(g(100 * settings.ringResolutionFraction)) % of q"
        lines.append("# overlaps: \(settings.markOverlaps ? "within \(resolution), peaks from \(g(settings.floor)) of 100" : "not marked")")
        for (i, p) in phases.enumerated() {
            lines.append("# phase: \(CSVText.headerValue(p.name))\(p.calculatedLattice ? " (lattice calculated)" : "")"
                         + (patterns[i] == nil ? " refused: \(CSVText.headerValue(refusals.first { $0.index == i }?.reason ?? ""))" : ""))
        }
        lines.append("phase,hkl,multiplicity,d_A,\(positionColumn),intensity,overlaps,diagnostic")
        for r in rows {
            lines.append([CSVText.quoted(r.phase), CSVText.quoted(r.hkl), "\(r.multiplicity)", g(r.d), g(r.position), g(r.intensity),
                          CSVText.quoted(r.overlaps.joined(separator: "; ")), r.isDiagnostic ? "yes" : ""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The drawn step: a tenth of the width.
    package var profileStep: Double { settings.width / 10 }

    /// One phase's drawn profile (the kit's sum of unit-area Gaussians) as .xy: two columns of numbers, position and intensity,
    /// one line per step over the shown range. nil for a refused phase or a profile the kit refuses to draw.
    package func xy(phase i: Int) -> String? {
        guard phases.indices.contains(i), let pattern = patterns[i] else { return nil }
        let range = settings.range, step = profileStep
        let ys = pattern.profile(width: settings.width, range: range, step: step)
        guard !ys.isEmpty else { return nil }
        var out = ""
        out.reserveCapacity(ys.count * 24)
        for (k, y) in ys.enumerated() {
            out += CSVText.number(range.lowerBound + Double(k) * step) + " " + CSVText.number(y) + "\n"
        }
        return out
    }
}
