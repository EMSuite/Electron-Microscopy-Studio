//
//  DiffractionNumberLocaleTests.swift
//  One number format in the Diffraction room (#1039, design-dna D30): the header row's Index line and orientation line, the Phases
//  list's lattice and the powder notes and peak list draw their numbers in the reader's locale, so a Mac set to a decimal comma
//  reads "2,1° from [001] · misfit 0,07 %" beside "Δq 0,01000 Å⁻¹/px"; the CSV, the methods record and the door keep the point
//  (the functions' default locale and the `ascii` lattice).
//  Red before: `PatternIndexing.header`, `place`, `DiffractionCrystal.latticeText` and `PowderTable.positionText` wrote
//  `String(format:)` and took no locale, so the header read "misfit 0.07 %" beside comma numbers.
//

import XCTest
import DiffractoCore
import DiffractoOrientation
import DiffractoScattering
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class DiffractionNumberLocaleTests: XCTestCase {

    private let german = Locale(identifier: "de_DE")

    private func outcome(_ verdict: PatternIndexing.Verdict, scale: Double = 1.0004) -> PatternIndexing.Outcome {
        PatternIndexing.Outcome(phase: "Al", verdict: verdict, spots: [], explained: 22, indexed: 24,
                                orientation: try? CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell), alternatives: [],
                                zoneAxis: SIMD3(0, 0, 1), zoneAxisAngle: 2.1 * .pi / 180, scale: scale, misfitPercent: 0.0712)
    }

    func testTheHeaderLineTakesTheReadersDecimalMark() {
        let line = PatternIndexing.header(outcome(.found), locale: german)
        XCTAssertEqual(line, "Al · 2,1° from [001] · 22 of 24 spots explained · misfit 0,07 %")
        XCTAssertFalse(line.contains("."), line)
        XCTAssertEqual(PatternIndexing.header(outcome(.scaleAtLimit, scale: 1.03), locale: german),
                       "Al · 2,1° from [001] · scale at its limit (+3,0 %): check the calibration · 22 of 24 spots explained · misfit 0,07 %")
        XCTAssertEqual(PatternIndexing.place(phase: "Si", zoneAxis: SIMD3(1, 1, 0), angle: 5 * .pi / 180, locale: german), "Si · 5,0° from [110]")
    }

    /// The CSV's line and the door's answer read the default: a point, as before.
    func testTheFileLineKeepsThePoint() {
        XCTAssertEqual(PatternIndexing.header(outcome(.found)), "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.scaleAtLimit, scale: 1.03)),
                       "Al · 2.1° from [001] · scale at its limit (+3.0 %): check the calibration · 22 of 24 spots explained · misfit 0.07 %")
    }

    func testTheLatticeLineTakesTheReadersDecimalMark() {
        let cubic = UnitCell(a: 5.4309, b: 5.4309, c: 5.4309, alphaDeg: 90, betaDeg: 90, gammaDeg: 90)
        let hexagonal = UnitCell(a: 3.1355, b: 3.1355, c: 5.1, alphaDeg: 90, betaDeg: 90, gammaDeg: 120)
        XCTAssertEqual(DiffractionPhases.latticeText(cubic, locale: german), "a 5,4309 Å")
        let line = DiffractionPhases.latticeText(hexagonal, locale: german)
        XCTAssertEqual(line, "a 3,1355; b 3,1355; c 5,1000 Å · 90,00°; 90,00°; 120,00°")
        XCTAssertFalse(line.contains("."), line)
        // The door's text and the methods record's ascii line keep the point.
        XCTAssertEqual(DiffractionPhases.latticeText(hexagonal), "a 3.1355, b 3.1355, c 5.1000 Å; 90.00°, 90.00°, 120.00°")
        XCTAssertEqual(DiffractionCrystal.latticeText(hexagonal, ascii: true, locale: german),
                       "a 3.1355, b 3.1355, c 5.1000 A; 90.00 deg, 90.00 deg, 120.00 deg")
    }

    func testThePowderNotesTakeTheReadersDecimalMark() {
        let table = PowderTable.make(phases: [PowderPhase(name: "Al", structure: CrystalPresets.aluminum)], settings: PowderSettings())
        XCTAssertEqual(table.headline(phase: 0, locale: german), "Al · Cu Kα · 5 peaks from 10° to 90° · strongest 111 at 38,51°")
        XCTAssertEqual(table.headline(phase: 0), "Al · Cu Kα · 5 peaks from 10° to 90° · strongest 111 at 38.51°", "the door's words")
        XCTAssertEqual(table.positionText(38.5149, locale: german), "38,51°")
    }
}
