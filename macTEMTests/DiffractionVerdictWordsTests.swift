//
//  DiffractionVerdictWordsTests.swift
//  #1018: a spot's verdict read the kit's code word `noneWithinTolerance`. Every verdict the readout shows is plain words: the table
//  cell, its spoken value, the new spot's announcement and the Results room; the CSV and the door keep the kit's stable key.
//  Red before: `DiffractionReadoutFormat.cell(.verdict, row)` returned `row.verdict`, the raw key.
//

import XCTest
import DiffractoCore
import DiffractoScattering
import DiffractoGeometry
import TEMCore
@testable import macTEM

nonisolated final class DiffractionVerdictWordsTests: XCTestCase {

    private static let au: KinematicReflectionList = {
        guard let list = try? StandardCrystals.list(of: StandardCrystals.named("Au")!, kMax: 1.2) else { fatalError("no Au list") }
        return list
    }()

    private func row(verdict: String, detail: String? = nil) -> DiffractionReadoutRow {
        DiffractionReadoutRow(id: UUID(), kind: .spot, number: 1, radiusPx: 40, q: 0.3, d: 3.3, family: nil, dListed: nil,
                              deltaPercent: nil, oddsText: nil, verdict: verdict, validation: "", verdictDetail: detail)
    }

    /// Every refusal the kit can give (the four cases of `RingIndexing.Error`) reads as words, never its code name.
    func testEveryRefusalReadsAsPlainWords() {
        let g331 = Self.au.families[6].family.g
        let cases: [(Double, Double)] = [(g331, 1.0), (1 / 4.0782, 0.1), (1.25, 0.1), (0, 0.1)]
        var seen = Set<String>()
        for (q, tolerance) in cases {
            let shown = IndexingDisplay.index(q: q, tolerancePercent: tolerance, in: Self.au)
            let r = row(verdict: shown.verdict, detail: shown.refusalText)
            let words = DiffractionReadoutFormat.cell(.verdict, r)
            seen.insert(shown.verdict)
            XCTAssertNotEqual(words, shown.verdict, "\(shown.verdict) is shown as its code name")
            XCTAssertTrue(words.contains(" "), "\(words) is not words")
            XCTAssertEqual(r.verdictWords, words)
            XCTAssertEqual(r.verdictDetail, shown.refusal?.reason, "the tooltip holds the kit's sentence")
        }
        XCTAssertEqual(seen, ["ambiguous", "noneWithinTolerance", "beyondKMax", "invalidInput"])
        XCTAssertEqual(DiffractionReadoutFormat.cell(.verdict, row(verdict: "noneWithinTolerance")), "no family of the phase within tolerance")
    }

    /// Verdicts that are words already pass through; the announcement says the words.
    @MainActor func testWordsPassThroughAndTheAnnouncementSaysThem() {
        XCTAssertEqual(DiffractionReadoutFormat.cell(.verdict, row(verdict: "accepted")), "accepted")
        XCTAssertEqual(DiffractionReadoutFormat.cell(.verdict, row(verdict: "no signal near the click")), "no signal near the click")
        XCTAssertFalse(SpotCursorActions.announcement(row(verdict: "noneWithinTolerance")).contains("noneWithinTolerance"))
    }
}
