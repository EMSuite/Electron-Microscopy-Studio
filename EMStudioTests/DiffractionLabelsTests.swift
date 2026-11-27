//
//  DiffractionLabelsTests.swift
//  An indexed pattern is readable (#1045): the hkl labels go only where they meet no other label and not the centre's mark,
//  Strongest up to 16 from the brightest down, All without the cap, None none; a found spot's d label only on the selected row and
//  under the pointer (rings keep theirs); one legend chip naming the marks while the simulated spots are drawn. Read as data from
//  `HKLLabelPlacement`, `DiffractionMarkLabels` and `DiffractionLegend`. Red before: none of the three existed; the room labelled the
//  60 strongest simulated spots and every found spot, so after Index on silicon [110] 52 labels collided across the picture.
//

import DiffractoCore
import Foundation
import TEMCore
import XCTest
@testable import EMStudio

nonisolated final class DiffractionLabelsTests: XCTestCase {
    // MARK: hkl placement

    /// A square lattice of `count` spots `spacing` points apart about a beam at the origin, strongest first (as the kit gives them).
    private func lattice(count: Int, spacing: Double) -> [ZoneAxisOverlay.Spot] {
        var spots: [ZoneAxisOverlay.Spot] = []
        var n = 1
        while spots.count < count {
            for h in -n ... n {
                for k in -n ... n where max(abs(h), abs(k)) == n && spots.count < count {
                    let relative = 1 - Double(spots.count) / Double(count + 1)
                    spots.append(ZoneAxisOverlay.Spot(hkl: MillerIndex(h, k, 0), row: Double(k) * spacing, column: Double(h) * spacing,
                                                      intensity: relative, relative: relative))
                }
            }
            n += 1
        }
        return spots
    }

    private func place(_ spots: [ZoneAxisOverlay.Spot], _ mode: HKLLabelMode) -> [HKLLabelPlacement.Placed] {
        HKLLabelPlacement.place(spots, mode: mode, point: { SIMD2($0.column, $0.row) },
                                radius: { 3 + 6 * $0.relative.squareRoot() }, beam: SIMD2(0, 0))
    }

    private func assertNoOverprint(_ placed: [HKLLabelPlacement.Placed], file: StaticString = #filePath, line: UInt = #line) {
        let beam = (low: SIMD2(-HKLLabelPlacement.beamMarkHalfSide, -HKLLabelPlacement.beamMarkHalfSide),
                    high: SIMD2(HKLLabelPlacement.beamMarkHalfSide, HKLLabelPlacement.beamMarkHalfSide))
        for (i, a) in placed.enumerated() {
            XCTAssertFalse(HKLLabelPlacement.meet((a.low, a.high), beam), "\(a.spot.label) covers the centre's mark", file: file, line: line)
            for b in placed[(i + 1)...] {
                XCTAssertFalse(HKLLabelPlacement.meet((a.low, a.high), (b.low, b.high)), "\(a.spot.label) meets \(b.spot.label)",
                               file: file, line: line)
            }
        }
    }

    /// Mutation: no collision test, the cap dropped, the strongest skipped, All capped - red.
    func testNoLabelMeetsAnotherOrTheBeamAndTheCapHolds() {
        for spacing in [14.0, 24.0, 50.0] {
            let spots = lattice(count: 52, spacing: spacing)
            let strongest = place(spots, .strongest), all = place(spots, .all)
            assertNoOverprint(strongest)
            assertNoOverprint(all)
            XCTAssertLessThanOrEqual(strongest.count, HKLLabelPlacement.strongestCap)
            XCTAssertEqual(strongest.first?.spot, spots[0], "the strongest spot is always labelled (spacing \(spacing))")
            XCTAssertEqual(all.first?.spot, spots[0])
            XCTAssertTrue(place(spots, .off).isEmpty)
        }
        // Room for every label: Strongest stops at its cap, All goes on.
        let sparse = lattice(count: 52, spacing: 50)
        XCTAssertEqual(place(sparse, .strongest).count, HKLLabelPlacement.strongestCap)
        XCTAssertGreaterThan(place(sparse, .all).count, place(sparse, .strongest).count)
    }

    /// The labels are placed from the brightest down whatever order the spots come in.
    func testTheBrightestComesFirst() {
        let spots = lattice(count: 20, spacing: 50)
        XCTAssertEqual(place(Array(spots.reversed()), .strongest).first?.spot, spots[0])
    }

    /// The session file and the door's `labels` read the pop-up: off is None; on keeps a mode chosen, from None it is Strongest.
    /// Mutation: showsLabels stored apart from the mode - red.
    func testTheOldSwitchReadsThePopUp() {
        var settings = ZoneAxisOverlay.Settings()
        XCTAssertEqual(settings.labelMode, .strongest, "the default")
        XCTAssertTrue(settings.showsLabels)
        settings.showsLabels = false
        XCTAssertEqual(settings.labelMode, .off)
        settings.showsLabels = true
        XCTAssertEqual(settings.labelMode, .strongest)
        settings.labelMode = .all
        settings.showsLabels = true
        XCTAssertEqual(settings.labelMode, .all)
        XCTAssertEqual(HKLLabelMode.allCases.map(\.title), ["Strongest", "All", "None"])
    }

    // MARK: Measured labels

    /// 52 found spots and one selected: one label; the spot under the pointer adds its own; rings keep theirs.
    /// Mutation: every spot labelled, the pointer ignored, a ring's label dropped - red.
    func testOnlyTheSelectedAndHoveredSpotCarryTheirD() {
        let spots = (0 ..< 52).map { i in (id: UUID(), point: SIMD2(Double(i % 8) * 40, Double(i / 8) * 40)) }
        let rings = [UUID(), UUID()]
        let selected = spots[17].id
        let one = DiffractionMarkLabels.labelled(rings: [], spots: spots, selection: selected, pointer: nil)
        XCTAssertEqual(one, [selected])
        XCTAssertTrue(DiffractionMarkLabels.labelled(rings: [], spots: spots, selection: nil, pointer: nil).isEmpty)

        let hovered = DiffractionMarkLabels.labelled(rings: [], spots: spots, selection: selected, pointer: spots[3].point + SIMD2(3, -2))
        XCTAssertEqual(hovered, [selected, spots[3].id])
        let away = DiffractionMarkLabels.labelled(rings: [], spots: spots, selection: selected, pointer: SIMD2(20, 20))
        XCTAssertEqual(away, [selected], "no spot within reach of the pointer")

        let withRings = DiffractionMarkLabels.labelled(rings: rings, spots: spots, selection: nil, pointer: nil)
        XCTAssertEqual(withRings, Set(rings))
    }

    // MARK: Legend

    /// Mutation: a chip with the overlay off, no phase name, "unexplained" with the same mark as "found", no "unexplained" row
    /// after an Index that left a spot unexplained (#1063) - red.
    func testTheLegendsEntries() {
        XCTAssertTrue(DiffractionLegend.entries(overlayShown: false, phase: "Si", hasFound: true, hasUnexplained: true).isEmpty,
                      "no chip while no overlay is shown")

        let simulatedOnly = DiffractionLegend.entries(overlayShown: true, phase: "Si", hasFound: false, hasUnexplained: false)
        XCTAssertEqual(simulatedOnly, [.init(mark: .simulated(.ring), text: "Si")])

        let indexed = DiffractionLegend.entries(overlayShown: true, phase: "Si", hasFound: true, hasUnexplained: true)
        XCTAssertEqual(indexed, [.init(mark: .simulated(.ring), text: "Si"), .init(mark: .found, text: "found"),
                                 .init(mark: .unexplained, text: "unexplained")],
                       "an unexplained spot has a mark of its own, the dashed cross, and the chip names it")
        XCTAssertEqual(DiffractionLegend.entries(overlayShown: true, phase: "Si", hasFound: true, hasUnexplained: false).count, 2,
                       "no row while every found spot is explained")
        XCTAssertFalse(DiffractionLegend.unexplainedDash.isEmpty, "the mark differs from a found spot's")

        // The unexplained marks are the found spots whose Index row has no hkl.
        let explained = UUID(), unexplained = UUID()
        func row(_ id: UUID, _ hkl: MillerIndex?) -> PatternIndexing.SpotRow {
            PatternIndexing.SpotRow(id: id, number: 1, hkl: hkl, radiusPx: 30, q: 0.3, d: 3.1, dExpected: nil, deltaPercent: nil, phase: "Si")
        }
        XCTAssertEqual(DiffractionLegend.unexplained(in: [row(explained, MillerIndex(1, 1, 1)), row(unexplained, nil)]), [unexplained])
    }

    // MARK: The room draws them

    /// The room's overlays read the policies, not the 60-strongest rule or every row's label. Mutation: `ZoneAxisOverlay.labelled`
    /// back in the room's overlay; a found spot labelled without `shown` - red.
    func testTheRoomDrawsThePolicies() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let room = try String(contentsOf: root.appendingPathComponent("EMStudio/UI/DiffractionRoom.swift"), encoding: .utf8)
        XCTAssertTrue(room.contains("HKLLabelPlacement.place("))
        XCTAssertFalse(room.contains("ZoneAxisOverlay.labelled("))
        XCTAssertTrue(room.contains("if shown.contains(spot.id), let text = labels[spot.id]"))
        XCTAssertTrue(room.contains("DiffractionLegendChip(entries: legend)"))
        XCTAssertTrue(room.contains("dash: unexplained.contains(spot.id) ? DiffractionLegend.unexplainedDash : []"),
                      "the pattern draws an unexplained spot's cross dashed, as the chip does")
        XCTAssertTrue(room.contains("layer.addFilter(.shadow("), "labels keep a dark halo")
    }
}
