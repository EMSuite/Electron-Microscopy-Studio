//
//  PowderTableTests.swift
//  The powder pattern core of plan rows R11 and R12 (#810, #811): the peak table of the shown phases, the overlap and diagnostic
//  marks, the sentences the Simulation document says, the peak table as CSV and one phase's profile as .xy. Every number is the
//  kit's (`PowderPattern`, pins P49 and P4); the table is held to the kit's own lists, and to the design's numbers for Al with Cu Kα
//  (5 peaks, 111 at 38.51°) and Al + Mg2Si + Si at 0.1° (diagnostic peaks 38.51°, 40.16°, 28.47°). Red before: the app had no
//  powder pattern.
//

import XCTest
import DiffractoCore
import DiffractoScattering
import TEMCore

nonisolated final class PowderTableTests: XCTestCase {

    /// Mg2Si, antifluorite, a = 6.351 Å (the kit's planted case).
    private static var mg2Si: CrystalStructure {
        let fcc: [SIMD3<Double>] = [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]
        var sites = fcc.map { AtomSite(z: 14, fractional: $0) }
        for p in fcc {
            for o in [SIMD3<Double>(0.25, 0.25, 0.25), SIMD3<Double>(0.75, 0.75, 0.75)] {
                var f = p + o
                for k in 0..<3 where f[k] >= 1 { f[k] -= 1 }
                sites.append(AtomSite(z: 12, fractional: f))
            }
        }
        return CrystalPresets.structure(a: 6.351, b: 6.351, c: 6.351, sites: sites)
    }

    /// Al with Cu Kα on the defaults: 5 peaks from 10° to 90°, the strongest 111 at 38.51°, the rows the kit's peaks.
    func testAluminiumWithCopperKAlpha() throws {
        let table = PowderTable.make(phases: [PowderPhase(name: "Al", structure: CrystalPresets.aluminum)], settings: PowderSettings())
        let kit = try PowderPattern.xray(structure: CrystalPresets.aluminum, radiation: .cuKAlpha, twoThetaRange: 10...90)
        XCTAssertEqual(table.rows.count, 5)
        XCTAssertEqual(table.rows.map(\.position), kit.peaks.map(\.position))
        XCTAssertEqual(table.rows.map(\.intensity), kit.peaks.map(\.intensity))
        XCTAssertEqual(table.rows.map(\.d), kit.peaks.map(\.d))
        XCTAssertEqual(table.rows.map(\.hkl), ["111", "200", "220", "311", "222"])
        XCTAssertEqual(table.rows[0].multiplicity, 8)
        XCTAssertEqual(table.rows[0].position, 38.5057, accuracy: 1e-4)
        XCTAssertEqual(table.headline(phase: 0), "Al · Cu Kα · 5 peaks from 10° to 90° · strongest 111 at 38.51°")
        // one phase: nothing overlaps, so nothing is said about overlaps
        XCTAssertNil(table.marksSentence(phase: 0))
        XCTAssertTrue(table.rows.allSatisfy { !$0.isOverlapped })
        XCTAssertNil(table.calculatedLatticeSentence(phase: 0))
    }

    /// Al + Mg2Si + Si at 0.1°: the overlapped rows name each other, and each phase's diagnostic peak is the kit's.
    func testOverlapsAndDiagnosticPeaksAreTheKits() throws {
        let structures = [CrystalPresets.aluminum, Self.mg2Si, CrystalPresets.silicon]
        let phases = zip(["Al", "Mg2Si", "Si"], structures).map { PowderPhase(name: $0, structure: $1) }
        let table = PowderTable.make(phases: phases, settings: PowderSettings())
        let kit = try structures.map { try PowderPattern.xray(structure: $0, twoThetaRange: 10...90) }
        let marks = PowderPattern.marks(kit, resolution: .absolute(0.1))
        XCTAssertEqual(table.marks, marks)
        for i in 0..<3 {
            let diagnostic = try XCTUnwrap(table.rows.first { $0.phaseIndex == i && $0.isDiagnostic })
            let kitIndex = try XCTUnwrap(marks[i].firstIndex { $0.isDiagnostic })
            XCTAssertEqual(diagnostic.position, kit[i].peaks[kitIndex].position)
        }
        XCTAssertEqual(table.marksSentence(phase: 0), "Al: 1 of 5 peaks overlapped. Diagnostic peak 111 at 38.51°")
        XCTAssertEqual(table.marksSentence(phase: 2), "Si: 0 of 6 peaks overlapped. Diagnostic peak 111 at 28.47°")
        let alOver = try XCTUnwrap(table.rows.first { $0.phaseIndex == 0 && $0.isOverlapped })
        XCTAssertEqual(alOver.position, 78.3069, accuracy: 1e-4)
        XCTAssertEqual(alOver.overlaps.count, 1)
        XCTAssertTrue(alOver.overlaps[0].hasPrefix("Mg2Si "), alOver.overlaps[0])
        let diagnostics = table.rows.filter(\.isDiagnostic).map { ($0.phase, String(format: "%.2f", $0.position)) }
        XCTAssertEqual(diagnostics.map(\.0), ["Al", "Mg2Si", "Si"])
        XCTAssertEqual(diagnostics.map(\.1), ["38.51", "40.16", "28.47"])
        // Mark overlaps off: no marks, no sentence
        var off = PowderSettings()
        off.markOverlaps = false
        let unmarked = PowderTable.make(phases: phases, settings: off)
        XCTAssertTrue(unmarked.rows.allSatisfy { !$0.isOverlapped && !$0.isDiagnostic })
        XCTAssertNil(unmarked.marksSentence(phase: 0))
    }

    /// Rings: the kit's electron pattern at the beam's wavelength to the reach, positions in Å⁻¹.
    func testRingsAreTheKitsElectronPattern() throws {
        var settings = PowderSettings()
        settings.kind = .rings
        let table = PowderTable.make(phases: [PowderPhase(name: "Al", structure: CrystalPresets.aluminum)], settings: settings)
        let kit = try PowderPattern.electron(structure: CrystalPresets.aluminum, wavelengthAngstroms: 0.025079, kMax: 1.5)
        let shown = kit.peaks.filter { $0.intensity >= 1 }
        XCTAssertEqual(table.rows.map(\.position), shown.map(\.position))
        XCTAssertEqual(table.rows.first?.hkl, "111")
        XCTAssertTrue(table.headline(phase: 0).hasPrefix("Al · 200 kV · \(shown.count) rings to 1.5 Å⁻¹ · strongest 111 at 0.42"),
                      table.headline(phase: 0))
        XCTAssertEqual(table.settings.resolution, .fraction(0.01))
    }

    /// A Materials Project phase says its lattice is calculated and what 1 % does near 40°.
    func testCalculatedLatticeSentence() {
        let table = PowderTable.make(phases: [PowderPhase(name: "Al", structure: CrystalPresets.aluminum, calculatedLattice: true)],
                                     settings: PowderSettings())
        XCTAssertEqual(table.calculatedLatticeSentence(phase: 0),
                       "Lattice calculated (Materials Project). A 1 % cell error moves a peak near 40° by about 0.4°.")
    }

    /// A phase the kit refuses keeps its place, gives no rows, and its headline is the kit's reason.
    func testRefusedPhaseSaysWhy() {
        let unknown = CrystalPresets.structure(a: 4, b: 4, c: 4, sites: [AtomSite(z: 150, fractional: [0, 0, 0])])
        let table = PowderTable.make(phases: [PowderPhase(name: "X", structure: unknown),
                                              PowderPhase(name: "Al", structure: CrystalPresets.aluminum)], settings: PowderSettings())
        XCTAssertNil(table.patterns[0])
        XCTAssertEqual(table.refusals.map(\.phase), ["X"])
        XCTAssertTrue(table.rows.allSatisfy { $0.phaseIndex == 1 })
        XCTAssertTrue(table.headline(phase: 0).hasPrefix("X: "))
        XCTAssertNil(table.xy(phase: 0))
        XCTAssertNil(table.marksSentence(phase: 1), "one drawn phase overlaps nothing")
    }

    /// The CSV rows equal the table (R12): one line per row after the header, the same numbers.
    func testCSVRowsEqualTheTable() throws {
        let phases = [PowderPhase(name: "Al", structure: CrystalPresets.aluminum), PowderPhase(name: "Si", structure: CrystalPresets.silicon)]
        let table = PowderTable.make(phases: phases, settings: PowderSettings())
        let lines = table.csv().split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let header = try XCTUnwrap(lines.firstIndex { !$0.hasPrefix("#") })
        XCTAssertEqual(lines[header], "phase,hkl,multiplicity,d_A,two_theta_deg,intensity,overlaps,diagnostic")
        let body = Array(lines[(header + 1)...])
        XCTAssertEqual(body.count, table.rows.count)
        for (line, row) in zip(body, table.rows) {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(cells.count, 8, line)
            XCTAssertEqual(cells[0], row.phase)
            XCTAssertEqual(cells[1], row.hkl)
            XCTAssertEqual(Int(cells[2]), row.multiplicity)
            XCTAssertEqual(try XCTUnwrap(Double(cells[3])), row.d, accuracy: 1e-8 * row.d)
            XCTAssertEqual(try XCTUnwrap(Double(cells[4])), row.position, accuracy: 1e-8 * row.position)
            XCTAssertEqual(try XCTUnwrap(Double(cells[5])), row.intensity, accuracy: 1e-8 * max(1, row.intensity))
            XCTAssertEqual(cells[7], row.isDiagnostic ? "yes" : "")
        }
        XCTAssertTrue(lines.contains("# phase: Al") && lines.contains("# phase: Si"))
    }

    /// The .xy file is two columns of numbers: the kit's profile over the shown range at a tenth of the width.
    func testXYIsTwoColumnsOfNumbers() throws {
        let table = PowderTable.make(phases: [PowderPhase(name: "Al", structure: CrystalPresets.aluminum)], settings: PowderSettings())
        let text = try XCTUnwrap(table.xy(phase: 0))
        let lines = text.split(separator: "\n").map(String.init)
        let kit = try XCTUnwrap(table.patterns[0]).profile(width: 0.1, range: 10...90, step: 0.01)
        XCTAssertEqual(lines.count, kit.count)
        XCTAssertEqual(lines.count, 8001)
        for (k, line) in lines.enumerated() where k % 97 == 0 {
            let cells = line.split(separator: " ").map(String.init)
            XCTAssertEqual(cells.count, 2, line)
            let x = try XCTUnwrap(Double(cells[0])), y = try XCTUnwrap(Double(cells[1]))
            XCTAssertEqual(x, 10 + Double(k) * 0.01, accuracy: 1e-6)
            XCTAssertEqual(y, kit[k], accuracy: 1e-8 * max(1, kit[k]))
        }
    }

    /// The radiation's name in words.
    func testRadiationNames() {
        XCTAssertEqual(PowderTable.radiationName(.cuKAlpha), "Cu Kα")
        XCTAssertEqual(PowderTable.radiationName(XRayRadiation.named("CuKa1")!), "Cu Kα₁")
        XCTAssertEqual(PowderTable.radiationName(XRayRadiation.named("MoKb1")!), "Mo Kβ₁")
        XCTAssertEqual(PowderTable.radiationName(XRayRadiation(wavelengthAngstroms: 1.5)), "1.5 Å")
    }

    /// Indices run together only while each is one digit and not negative: (11 1 0) and (1 1 10) never read alike.
    func testALabelKeepsTwoDigitAndSignedIndicesApart() {
        XCTAssertEqual(PowderTable.family(indices: [1, 1, 1]), "111")
        XCTAssertEqual(PowderTable.family(indices: [11, 1, 0]), "11 1 0")
        XCTAssertEqual(PowderTable.family(indices: [1, 1, 10]), "1 1 10")
        XCTAssertEqual(PowderTable.family(indices: [-1, 1, 1]), "-1 1 1")
        XCTAssertEqual(PowderTable.family(indices: [1, 0, -1, 2]), "1 0 -1 2")
    }
}
