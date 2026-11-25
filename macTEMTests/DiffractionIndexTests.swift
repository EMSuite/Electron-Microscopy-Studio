//
//  DiffractionIndexTests.swift
//  Index in the Diffraction room (#783, plan row R2): the toolbar verb finds the spots and the crystal's full orientation off the
//  main actor (`DiffractionAnalysis.index`, `PatternIndexing`), Stop drops the answer, the verdict is said in words, and a found
//  orientation becomes the simulated spots' at its fitted scale. Red before: the room had no Index.
//  #784 (plan row R2b): the found spots are ordinary marks Index reads again, and clicked spots give the zone axis only. Red before:
//  Index searched afresh every time and never read a mark.
//
//  The pattern is planted with the kit's own `SpotPatternSimulator`: aluminium at [0 1 1] turned 0.4 rad and tilted (0.8°, −0.5°),
//  200 kV, each spot a Gaussian (σ 1.5 px) of its kinematical intensity on a 512 × 512 image, Δq 0.008 Å⁻¹/px, centre (256, 256).
//  The kit's own bounds on such patterns are in its parity (DiffractoKit P45: medians about 0.1°); the room is held to 0.5° here,
//  the best or a flagged alternative, as the kit's tests hold it.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation
import ShellLayout
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionIndexTests: XCTestCase {

    private static let deltaQ = 0.008
    private static let side = 512

    /// The planted pattern of `truth` and its image (no axis; the scale is typed).
    @MainActor private func planted(_ truth: CrystalOrientation, crystal: StandardCrystal) throws -> CalibratedImage {
        let pattern = try SpotPatternSimulator(structure: crystal.structure, kMax: 2.5).pattern(orientation: truth, volts: 200_000)
        let n = Self.side, c = Double(n / 2)
        var px = [Float](repeating: 5, count: n * n)
        let strongest = pattern.spots.map(\.intensity).max() ?? 1
        func add(row: Double, column: Double, amplitude: Double, sigma: Double) {
            let r0 = max(0, Int(row - 6 * sigma)), r1 = min(n - 1, Int(row + 6 * sigma))
            let c0 = max(0, Int(column - 6 * sigma)), c1 = min(n - 1, Int(column + 6 * sigma))
            guard r0 <= r1, c0 <= c1 else { return }
            for y in r0...r1 {
                for x in c0...c1 {
                    let d2 = (Double(y) - row) * (Double(y) - row) + (Double(x) - column) * (Double(x) - column)
                    px[y * n + x] += Float(amplitude * exp(-d2 / (2 * sigma * sigma)))
                }
            }
        }
        add(row: c, column: c, amplitude: 5000, sigma: 3)
        for s in pattern.spots {
            add(row: c + s.position.x / Self.deltaQ, column: c + s.position.y / Self.deltaQ, amplitude: 1000 * s.intensity / strongest, sigma: 1.5)
        }
        return CalibratedImage(width: n, height: n, pixels: px, x: nil, y: nil, fileName: "planted Al", source: "test", voltage: 200_000)
    }

    @MainActor private func analysis(for image: CalibratedImage, crystal: StandardCrystal) -> DiffractionAnalysis {
        let a = DiffractionAnalysis()
        a.bind(image)
        a.typedDeltaQ = Self.deltaQ
        a.setCrystal(.preset(crystal))
        return a
    }

    // MARK: Index on a planted pattern

    @MainActor func testIndexFindsTheFullOrientationOfAPlantedPattern() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 1, 1), inPlaneAngle: 0.4, cell: al.structure.cell)
            .tilted(by: SIMD2(0.8, -0.5) * .pi / 180)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        XCTAssertNil(a.indexBlocker(image: image))

        let task = try XCTUnwrap(a.index(image: image), "Index starts")
        XCTAssertTrue(a.isIndexing, "Index runs off the main actor")
        await task.value
        XCTAssertFalse(a.isIndexing)
        let o = try XCTUnwrap(a.indexOutcome)
        let best = try XCTUnwrap(o.orientation, PatternIndexing.header(o))

        let indexer = try PatternIndexerCache.shared.indexer(key: "Al||200000.0") {
            try PatternOrientation(structure: al.structure, volts: 200_000, kMax: PatternIndexing.reach)
        }
        let off = ([best] + o.alternatives).map { indexer.solver.angle(between: $0, and: truth, includingHalfTurn: false) }
        XCTAssertLessThan(off.min() ?? .infinity, 0.5 * .pi / 180, "\(PatternIndexing.header(o)); off \(off.map { $0 * 180 / .pi })°")
        if off[0] > 0.5 * .pi / 180 { XCTAssertNotEqual(o.verdict, .found, "a best answer off the truth is flagged") }
        XCTAssertEqual(o.zoneAxis.map { [abs($0.x), abs($0.y), abs($0.z)].sorted() }, [0, 1, 1], "the nearest zone axis is ⟨011⟩")
        XCTAssertEqual(try XCTUnwrap(o.zoneAxisAngle) * 180 / .pi, 0.94, accuracy: 0.3, "tilted (0.8°, −0.5°): 0.94° off the axis")
        XCTAssertGreaterThanOrEqual(o.explained, o.indexed - 2, "the planted spots are explained")
        XCTAssertGreaterThanOrEqual(o.indexed, 8)
        XCTAssertEqual(try XCTUnwrap(o.scale), 1, accuracy: 0.003, "the typed scale is the planted one")
        XCTAssertLessThan(try XCTUnwrap(o.misfitPercent), 0.3)
        // Every explained spot carries its hkl and listed d; its measured d is within 1 % of it (the solver's tolerance).
        for s in o.spots where s.hkl != nil {
            XCTAssertLessThan(abs(try XCTUnwrap(s.deltaPercent)), 1, "\(String(describing: s.hkl))")
        }

        // The found spots are the room's spot marks now (#784), each with the kit's intensity.
        XCTAssertEqual(a.spots.count, o.spots.count)
        XCTAssertTrue(a.spots.allSatisfy { $0.intensity != nil })
        XCTAssertFalse(o.zoneAxisOnly)
        XCTAssertFalse(a.indexSpotsChanged)

        // The found orientation is the simulated spots' now, at its fitted scale, and the zone axis field shows its zone axis.
        XCTAssertEqual(a.simulation.indexed, best)
        XCTAssertEqual(a.simulation.scale, o.scale)
        XCTAssertEqual(a.simulation.zoneAxis, o.zoneAxis)
        XCTAssertTrue(a.simulation.isShown)
        let drawn = try XCTUnwrap(a.simulatedSpots(image: image)).get()
        // The strongest simulated spots sit on found spots (within 1.5 px).
        for s in drawn.prefix(6) {
            let nearest = o.spots.map { hypot($0.row - s.row, $0.column - s.column) }.min() ?? .infinity
            XCTAssertLessThan(nearest, 1.5, "\(s.label) at (\(s.row), \(s.column))")
        }
        // A new scale makes the answer stale: the header says so and the overlay draws the orientation at |g| (its fitted
        // |q| over |g| was the old scale's).
        XCTAssertFalse(a.indexIsStale)
        a.typedDeltaQ = Self.deltaQ * 1.02
        XCTAssertTrue(a.indexIsStale)
        let strongest = try XCTUnwrap(try XCTUnwrap(a.simulatedSpots(image: image)).get().first)
        let g = try XCTUnwrap(SpotPatternSimulator(structure: al.structure, kMax: 2.5).pattern(orientation: best, volts: 200_000).spots
            .first { $0.hkl == strongest.hkl })
        XCTAssertEqual(hypot(strongest.row - 256, strongest.column - 256), hypot(g.position.x, g.position.y) / (Self.deltaQ * 1.02), accuracy: 1e-9)
        a.typedDeltaQ = Self.deltaQ
        XCTAssertFalse(a.indexIsStale, "the scale Index ran under again")

        // Typing a zone axis takes the drawn spots off Index's orientation.
        a.setZoneAxis(SIMD3(0, 0, 1))
        XCTAssertNil(a.simulation.indexed)
        XCTAssertEqual(a.simulation.scale, 1)
    }

    /// Fit scale off (#787): Index holds the room's scale, |q| over |g| at 1, and a held scale is never "at its limit". Red before:
    /// the indexer always fitted within ±3 %, and a shut window read as a scale at its limit.
    @MainActor func testFitScaleOffHoldsTheRoomsScale() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 1, 1), inPlaneAngle: 0.4, cell: al.structure.cell)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        a.fitScale = false
        await a.index(image: image)?.value
        let o = try XCTUnwrap(a.indexOutcome)
        XCTAssertNotNil(o.orientation, PatternIndexing.header(o))
        XCTAssertEqual(try XCTUnwrap(o.scale), 1, accuracy: 1e-9, "the scale is held")
        XCTAssertNotEqual(o.verdict, .scaleAtLimit)
        XCTAssertEqual(a.solutionIndex, 0)
        XCTAssertEqual(a.solutions.first, o.orientation)
        XCTAssertFalse(a.isTurnedByHand)
    }

    @MainActor func testStopAndANewCrystalDropTheAnswer() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), inPlaneAngle: 0.2, cell: al.structure.cell)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        let stopped = try XCTUnwrap(a.index(image: image))
        a.stop()
        XCTAssertFalse(a.isIndexing, "Stop ends Index at once")
        await stopped.value
        XCTAssertNil(a.indexOutcome, "a stopped Index lands nothing")

        await a.index(image: image)?.value
        XCTAssertNotNil(a.indexOutcome?.orientation)
        a.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named("Si"))))
        XCTAssertNil(a.indexOutcome, "the answer was the old crystal's")
        XCTAssertNil(a.simulation.indexed)
    }

    // MARK: Found spots are marks (#784)

    /// A found spot removed is a spot Index no longer reads: the header says the spots changed, and Index again reads the marks
    /// left (no new search). Remove Spots empties the marks, and Index finds them again.
    @MainActor func testFoundSpotsAreMarksIndexReadsAgain() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), inPlaneAngle: 0.2, cell: al.structure.cell)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        await a.index(image: image)?.value
        let found = a.spots
        XCTAssertGreaterThanOrEqual(found.count, 8)
        XCTAssertNotNil(a.indexOutcome?.orientation, a.indexLine ?? "")

        // The weakest found spot removed.
        let weakest = try XCTUnwrap(found.min { ($0.intensity ?? 0) < ($1.intensity ?? 0) })
        a.remove(weakest.id)
        XCTAssertTrue(a.indexSpotsChanged)
        XCTAssertTrue(try XCTUnwrap(a.indexLine).hasSuffix(" · the spots changed since: Index again"))
        await a.index(image: image)?.value
        XCTAssertFalse(a.indexSpotsChanged)
        XCTAssertEqual(a.spots, found.filter { $0.id != weakest.id }, "Index read the marks left and searched no new ones")
        XCTAssertEqual(try XCTUnwrap(a.indexOutcome).spots.count, found.count - 1)
        XCTAssertNotNil(a.indexOutcome?.orientation)

        a.removeSpots()
        XCTAssertTrue(a.spots.isEmpty)
        await a.index(image: image)?.value
        XCTAssertEqual(a.spots.count, found.count, "with no spot marked, Index finds them again")
        XCTAssertEqual(a.spots.map(\.row), found.map(\.row))
    }

    /// Clicked spots carry no intensities: Index gives their zone axis and turn only, and the header and the Index section say the
    /// tilt needs found spots.
    @MainActor func testClickedSpotsGiveTheZoneAxisOnly() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), inPlaneAngle: 0.2, cell: al.structure.cell)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        let pattern = try SpotPatternSimulator(structure: al.structure, kMax: 2.5).pattern(orientation: truth, volts: 200_000)
        let picked = [MillerIndex(2, 0, 0), MillerIndex(0, 2, 0), MillerIndex(2, 2, 0), MillerIndex(2, -2, 0), MillerIndex(-2, 0, 0)]
        for hkl in picked {
            let s = try XCTUnwrap(pattern.spots.first { $0.hkl == hkl }, "\(hkl)")
            a.addSpot(image: image, row: 256 + s.position.x / Self.deltaQ + 0.6, column: 256 + s.position.y / Self.deltaQ - 0.4)
        }
        XCTAssertEqual(a.spots.count, picked.count)
        XCTAssertTrue(a.spots.allSatisfy { $0.intensity == nil && $0.row != nil }, "clicked spots carry no intensity")

        await a.index(image: image)?.value
        XCTAssertEqual(a.spots.count, picked.count, "Index read the clicked spots and found none")
        let o = try XCTUnwrap(a.indexOutcome)
        XCTAssertTrue(o.zoneAxisOnly)
        XCTAssertNotNil(o.orientation, PatternIndexing.header(o))
        XCTAssertEqual(o.zoneAxis.map { [abs($0.x), abs($0.y), abs($0.z)].sorted() }, [0, 0, 1])
        XCTAssertEqual(try XCTUnwrap(o.zoneAxisAngle), 0, accuracy: 1e-6, "on the zone axis: a click measures no tilt")
        XCTAssertEqual(o.explained, picked.count)
        XCTAssertTrue(PatternIndexing.header(o).hasSuffix(PatternIndexing.zoneAxisOnlyNote), PatternIndexing.header(o))
        XCTAssertTrue(DiffractionIndexText.note(spots: a.spots, outcome: o, indexed: true).contains("the tilt needs Index on found spots"))
        XCTAssertEqual(a.simulation.indexed, o.orientation)
        XCTAssertTrue(a.simulation.isShown)
    }

    func testTheIndexSectionSaysWhatIndexWillRead() {
        XCTAssertTrue(DiffractionIndexText.note(spots: [], outcome: nil, indexed: false).hasPrefix("Index (⌘R) finds the spots, marks them"))
        let clicked = MeasuredSpot(clickRow: 1, clickColumn: 2, row: 1, column: 2, radius: nil, refusal: nil)
        XCTAssertTrue(DiffractionIndexText.note(spots: [clicked], outcome: nil, indexed: false).hasPrefix("Index (⌘R) reads the marked spots"))
    }

    // MARK: The Spots table and its CSV (#785)

    /// A spot Index leaves unexplained that sits on a spot double diffraction adds is named in the Spots table (#786): silicon down
    /// [1 1 0] forbids 002, 1̄11 + 11̄1 lands there; a measured spot at 1.01 times its q (Index's fitted scale 1.01) reads 002, d expected
    /// a/2 = 2.71545 Å, phase "Si · double diffraction". Off the added spot, or with no added spots, it stays unexplained. Red before:
    /// the table named no spot of double diffraction.
    func testTheSpotsTableNamesASpotOfDoubleDiffraction() throws {
        let si = try XCTUnwrap(StandardCrystals.named("Si"))
        let o = try CrystalOrientation(zoneAxis: SIMD3(1, 1, 0), cell: si.structure.cell)
        let added = try PatternIndexing.addedSpots(structure: si.structure, orientation: o, volts: 200_000, sigma: 0.02)
        let s002 = try XCTUnwrap(added.first { $0.hkl == MillerIndex(0, 0, 2) }, "\(added.map(\.hkl))")
        let on = PatternIndexing.Spot(id: UUID(), row: 0, column: 0, intensity: 1, radiusPx: 40, q: 1.01 * s002.q, hkl: nil, dListed: nil)
        let off = PatternIndexing.Spot(id: UUID(), row: 0, column: 0, intensity: 1, radiusPx: 40, q: 1.2 * s002.q, hkl: nil, dListed: nil)
        let outcome = PatternIndexing.Outcome(phase: "Si", verdict: .found, spots: [on, off], explained: 0, indexed: 2, orientation: o,
                                              alternatives: [], zoneAxis: SIMD3(1, 1, 0), zoneAxisAngle: 0, scale: 1.01, misfitPercent: nil)
        let numbers = [on.id: 1, off.id: 2]
        let rows = PatternIndexing.rows(outcome, numbers: numbers, added: added, cell: si.structure.cell)
        XCTAssertEqual(rows[0].hkl, MillerIndex(0, 0, 2))
        XCTAssertEqual(rows[0].phase, "Si · double diffraction")
        XCTAssertEqual(try XCTUnwrap(rows[0].dExpected), 5.4309 / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(rows[0].deltaPercent), 100 * (on.d - 5.4309 / 2) / (5.4309 / 2), accuracy: 1e-9)
        XCTAssertNil(rows[1].hkl, "20 % off: not the added spot")
        XCTAssertEqual(rows[1].phase, "")
        XCTAssertNil(PatternIndexing.rows(outcome, numbers: numbers).first?.hkl, "no added spots: unexplained")
    }

    /// The Spots table lists Index's spots still marked, numbered as the readout numbers them, each with its hkl, R, q, d, the
    /// expected d of its hkl, Δd/d and its phase; a row's id is its mark's (selecting it selects the spot); the CSV has the same
    /// columns. Red before: the room had no Spots table and no Spots CSV.
    @MainActor func testTheSpotsTableListsIndexsSpotsAndItsCSVHasItsColumns() async throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let truth = try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), inPlaneAngle: 0.2, cell: al.structure.cell)
        let image = try planted(truth, crystal: al)
        let a = analysis(for: image, crystal: al)
        XCTAssertEqual(a.indexSpotRows, [], "no rows before an answer")
        await a.index(image: image)?.value
        let rows = a.indexSpotRows
        XCTAssertEqual(rows.count, a.spots.count)
        XCTAssertEqual(rows.map(\.number), Array(1...a.spots.count))
        XCTAssertEqual(rows.map(\.id), a.spots.map(\.id), "a row is its mark: selecting it selects the spot")
        let explained = rows.filter { $0.hkl != nil }
        XCTAssertGreaterThanOrEqual(explained.count, 8)
        for (row, mark) in zip(rows, a.spots) {
            let r = try XCTUnwrap(mark.row), c = try XCTUnwrap(mark.column)
            XCTAssertEqual(row.radiusPx, hypot(r - 256, c - 256), accuracy: 1e-9)
            XCTAssertEqual(row.q, row.radiusPx * Self.deltaQ, accuracy: 1e-9, "q is R times the typed Δq")
            XCTAssertEqual(row.d, 1 / row.q, accuracy: 1e-12)
            guard let hkl = row.hkl else { XCTAssertEqual(row.phase, ""); continue }
            XCTAssertEqual(row.phase, "Al")
            XCTAssertEqual(row.hklText, ZoneAxisText.label(hkl))
            XCTAssertEqual(try XCTUnwrap(row.dExpected), al.structure.cell.d(hkl), accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(row.deltaPercent), 100 * (row.d - al.structure.cell.d(hkl)) / al.structure.cell.d(hkl), accuracy: 1e-9)
            XCTAssertEqual(hkl.l, 0, "every explained spot of [0 0 1] is in its zero layer")
        }

        // Sorted by a column, rows that tie keep the order of their numbers (all explained rows share the phase).
        let byPhase = DiffractionSpotFormat.sorted(explained, by: [KeyPathComparator(\PatternIndexing.SpotRow.phase)])
        XCTAssertEqual(byPhase.map(\.number), explained.map(\.number))
        let byMisfit = DiffractionSpotFormat.sorted(rows, by: [KeyPathComparator(\PatternIndexing.SpotRow.deltaKey, order: .reverse)])
        XCTAssertEqual(byMisfit.count, rows.count)
        XCTAssertTrue(zip(byMisfit, byMisfit.dropFirst()).allSatisfy { $0.deltaKey >= $1.deltaKey })

        // The CSV: Index's line above the table's columns, one line per row.
        let csv = a.spotsExportText(image: image).split(separator: "\n").map(String.init)
        XCTAssertEqual(csv[0], "# \(AppName.writer) diffraction spots")
        XCTAssertEqual(csv[1], "# file: planted Al")
        XCTAssertEqual(csv[2], "# index: \(try XCTUnwrap(a.indexLine))")
        XCTAssertEqual(csv[3], "spot,hkl,R_px,R_mm,q_per_A,d_A,d_expected_A,delta_percent,phase")
        XCTAssertEqual(csv.count, 4 + rows.count)
        let first = try XCTUnwrap(explained.first)
        let line = csv[3 + first.number].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(line.count, 9)
        XCTAssertEqual(line[0], "\(first.number)")
        let hkl = try XCTUnwrap(first.hkl)
        XCTAssertEqual(line[1], "\(hkl.h) \(hkl.k) \(hkl.l)")
        XCTAssertEqual(line[3], "", "no pixel pitch, no R in mm")
        XCTAssertEqual(try XCTUnwrap(Double(line[5])), first.d, accuracy: 1e-8 * first.d)
        XCTAssertEqual(line[8], "Al")

        // With the camera's pixel pitch, R in mm is R px times it (#907); without, none.
        XCTAssertTrue(rows.allSatisfy { $0.radiusMM == nil })
        a.pitchMM = 0.015
        for row in a.indexSpotRows { XCTAssertEqual(try XCTUnwrap(row.radiusMM), row.radiusPx * 0.015, accuracy: 1e-12) }
        a.pitchMM = nil

        // A spot removed leaves the table; the rest are numbered again as the readout numbers them.
        a.remove(rows[0].id)
        XCTAssertEqual(a.indexSpotRows.map(\.number), Array(1...a.spots.count))
        XCTAssertEqual(a.indexSpotRows.map(\.id), a.spots.map(\.id))
    }

    func testTheSpotsTableCellsAndWords() {
        let row = PatternIndexing.SpotRow(id: UUID(), number: 3, hkl: MillerIndex(1, -1, 1), radiusPx: 42.4709, q: 0.4247, d: 2.354567,
                                          dExpected: 2.338, deltaPercent: 0.7086, phase: "Au")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(DiffractionSpotFormat.Column.allCases.map { DiffractionSpotFormat.cell($0, row, locale: en) },
                       ["3", "11\u{0304}1", "42.47", UnitDisplay.noValue, "0.42470", "2.3546", "2.3380", "+0.71", "Au", UnitDisplay.noValue])
        XCTAssertEqual(DiffractionSpotFormat.Column.allCases.map(\.title),
                       ["Spot", "hkl", "R (px)", "R (mm)", "q (Å⁻¹)", "d (Å)", "d Expected", "Δd/d (%)", "Phase", "I dyn (%)"])
        XCTAssertEqual(DiffractionSpotFormat.spokenHKL(row), "1, minus 1, 1")
        let unexplained = PatternIndexing.SpotRow(id: UUID(), number: 4, hkl: nil, radiusPx: 80, q: 0.8, d: 1.25, dExpected: nil,
                                                  deltaPercent: nil, phase: "")
        XCTAssertEqual(DiffractionSpotFormat.cell(.hkl, unexplained), UnitDisplay.noValue)
        XCTAssertEqual(DiffractionSpotFormat.cell(.phase, unexplained), UnitDisplay.noValue)
        XCTAssertEqual(DiffractionSpotFormat.spokenHKL(unexplained), "not explained")
        XCTAssertEqual(DiffractionIndexText.spoken(nil, rows: 0), "")
        XCTAssertEqual(DiffractionIndexText.spoken("Al [001]", rows: 12), ", Index: Al [001]; 12 spots in the Spots table")
    }

    @MainActor func testIndexNamesWhatItNeeds() throws {
        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let image = try planted(try CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: al.structure.cell), crystal: al)
        let a = DiffractionAnalysis()
        a.bind(image)
        XCTAssertEqual(a.indexBlocker(image: image), "Index needs a scale: calibrate on a standard's ring, or type Δq")
        XCTAssertNil(a.index(image: image), "Index does not start without a scale")
        a.typedDeltaQ = Self.deltaQ
        XCTAssertNil(a.indexBlocker(image: image))
        let unpowered = CalibratedImage(width: 8, height: 8, pixels: [Float](repeating: 1, count: 64), x: nil, y: nil, fileName: "u",
                                        source: "test", voltage: nil)
        let b = DiffractionAnalysis()
        b.bind(unpowered)
        b.typedDeltaQ = 0.01
        XCTAssertEqual(b.indexBlocker(image: unpowered), "Index needs the beam energy: type it under Calibration")
    }

    // MARK: The map and the words

    /// q of a pixel is the inverse of the overlay's map: a simulated spot's pixel reads back the kit's (qx, qy).
    func testThePixelToQMapIsTheOverlaysInverse() {
        let centre = DiffractionCentre(row: 120, column: 130, source: .typed)
        let calibration = DiffractionCalibration(source: .typed, deltaQ: 0.01, ring: nil)
        let q = PatternIndexing.q(row: 120 + 30, column: 130 - 40, centre: centre, calibration: calibration)
        XCTAssertEqual(q?.x ?? .nan, 0.30, accuracy: 1e-12, "qx runs down the rows")
        XCTAssertEqual(q?.y ?? .nan, -0.40, accuracy: 1e-12, "qy runs along the columns")
        XCTAssertNil(PatternIndexing.q(row: 120, column: 130, centre: centre, calibration: calibration), "the centre has no direction")
        XCTAssertEqual(ZoneAxisOverlay.radius(q: 0.5, calibration: calibration), 50, accuracy: 1e-12)
    }

    func testTheHeaderSaysEveryVerdictInWords() {
        func outcome(_ verdict: PatternIndexing.Verdict, angle: Double?, found: Bool = true, scale: Double = 1.0004) -> PatternIndexing.Outcome {
            PatternIndexing.Outcome(phase: "Al", verdict: verdict, spots: [], explained: found ? 22 : 0, indexed: 24,
                                    orientation: found ? CrystalOrientation.identityForTests : nil, alternatives: [],
                                    zoneAxis: found ? SIMD3(0, 0, 1) : nil, zoneAxisAngle: angle.map { $0 * .pi / 180 },
                                    scale: found ? scale : nil, misfitPercent: found ? 0.0712 : nil)
        }
        XCTAssertEqual(PatternIndexing.header(outcome(.found, angle: 2.1)), "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.found, angle: 0.3)), "Al [001] · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.poor, angle: 2.1)),
                       "Al · 2.1° from [001] · found but poor · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.tied(count: 2), angle: 0.3)),
                       "Al [001] · tied: 2 orientations explain the pattern equally · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.scaleAtLimit, angle: 0.3, scale: 1.03)),
                       "Al [001] · scale at its limit (+3.0 %): check the calibration · 22 of 24 spots explained · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.oneRow, angle: nil, found: false)),
                       "Al · one row: the spots lie on one row through the beam, which fixes no zone axis")
        XCTAssertEqual(PatternIndexing.header(outcome(.notFound("No pair matches."), angle: nil, found: false)), "Al · not found: No pair matches.")
        XCTAssertEqual(PatternIndexing.Verdict.poor.word, "found but poor")
        XCTAssertEqual(PatternIndexing.zoneText(SIMD3(-1, 1, 0)), "[1\u{0304}10]")
    }

    /// The toolbar's verb in the Diffraction room: Index, on while the pattern has a scale and a beam energy, Stop while it runs.
    @MainActor func testTheToolbarVerbIsIndex() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.diffraction)?.value
        state.navigation.workspaceArea = .diffraction
        let analysis = try XCTUnwrap(state.openItems.selected?.diffraction)
        let image = try XCTUnwrap(state.openItems.selected?.session.image)
        analysis.bind(image)   // the room's view binds it on screen
        let action = try XCTUnwrap(RoomPrimaryAction.current(state))
        XCTAssertEqual(action.title, "Index")
        XCTAssertEqual(RoomPrimaryAction.runTitle(state), "Index")
        XCTAssertTrue(action.isEnabled, action.help)
        XCTAssertFalse(action.isRunning)

        let task = try XCTUnwrap(analysis.index(image: image))
        XCTAssertTrue(try XCTUnwrap(RoomPrimaryAction.current(state)).isRunning)
        XCTAssertTrue(RoomPrimaryAction.canStop(state), "⌘. reaches Index")
        XCTAssertEqual(BusyOperation.name(room: .diffraction, appState: state), "Indexing the pattern…")
        RoomPrimaryAction.stopActive(state)
        XCTAssertFalse(analysis.isIndexing)
        await task.value
        XCTAssertNil(analysis.indexOutcome)
    }
}

private extension CrystalOrientation {
    nonisolated static var identityForTests: CrystalOrientation {
        // swiftlint:disable:next force_try
        try! CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: StandardCrystals.named("Al")!.structure.cell)
    }
}
