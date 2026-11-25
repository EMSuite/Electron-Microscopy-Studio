//
//  SimulationSpotsTableTests.swift
//  A Simulation document's Microscope section and Spots table (#907): the camera length sets R in mm, R = λ L |g|, in the table and
//  its CSV at once, and a measured pattern's Index rows carry R px times the camera's pixel pitch. Au (2 0 0) down [0 0 1] on a new
//  simulation is |g| = 2 / 4.0782 Å⁻¹ (39.2330 px at 0.0125 Å⁻¹/px); at 200 kV (λ 0.0250793 Å) and the default 500 mm it is 6.149 mm
//  out, 12.30 mm at 1 000 mm. Red before: a simulation had no Spots table, no camera length and no R in mm.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class SimulationSpotsTableTests: XCTestCase {

    /// Mutation: L in m or µm, λ at another voltage, q from another scale, the camera length not read at once, double diffraction
    /// listed, the rows not strongest first, a nonsense camera length kept.
    @MainActor func testTheSimulatedSpotsCarryRInMillimetresFromTheCameraLength() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let item = try XCTUnwrap(state.openItems.selected)
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        analysis.simulation.doubleDiffraction = true
        XCTAssertEqual(analysis.cameraLengthMM, 500)

        let rows = analysis.simulatedSpotRows(image: image)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.map(\.number), Array(1...rows.count))
        guard case .success(let spots) = try XCTUnwrap(analysis.simulatedSpots(image: image)) else { return XCTFail("no spots") }
        XCTAssertEqual(rows.count, spots.filter { !$0.isDoubleDiffraction }.count, "double diffraction's spots have no intensity: not listed")
        let intensities = rows.compactMap { row in spots.first { $0.hkl == row.hkl }?.intensity }
        XCTAssertTrue(zip(intensities, intensities.dropFirst()).allSatisfy { $0 >= $1 }, "strongest first")

        let lambda = RingCalibration.wavelengthAngstroms(volts: 200_000)
        XCTAssertEqual(lambda, 0.0250793, accuracy: 1e-6)
        let g200 = 2 / 4.0782
        let row = try XCTUnwrap(rows.first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(row.radiusPx, g200 / 0.0125, accuracy: 1e-9)
        XCTAssertEqual(row.q, g200, accuracy: 1e-9)
        XCTAssertEqual(row.d, 4.0782 / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(row.radiusMM), lambda * 500 * g200, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(row.radiusMM), 6.149, accuracy: 0.001)
        XCTAssertNil(row.dExpected, "a simulated spot is its own reflection")
        XCTAssertEqual(row.phase, analysis.crystal.name)

        XCTAssertTrue(analysis.setCameraLength(mm: 1_000))
        let moved = try XCTUnwrap(analysis.simulatedSpotRows(image: image).first { $0.hkl == MillerIndex(2, 0, 0) })
        XCTAssertEqual(try XCTUnwrap(moved.radiusMM), lambda * 1_000 * g200, accuracy: 1e-9)
        XCTAssertEqual(moved.id, row.id, "the same reflection keeps its row")
        for bad in [0, -5, .nan, .infinity, 1e9] as [Double] {
            XCTAssertFalse(analysis.setCameraLength(mm: bad), "\(bad) mm")
        }
        XCTAssertFalse(analysis.setCameraLength(mm: nil))
        XCTAssertEqual(analysis.cameraLengthMM, 1_000)

        // The CSV: the settings line, the table's columns, R in mm in its column.
        let csv = analysis.simulatedSpotsExportText(image: image).split(separator: "\n").map(String.init)
        XCTAssertEqual(csv[0], "# \(AppName.writer) diffraction spots")
        XCTAssertTrue(csv[2].hasPrefix("# simulation: \(analysis.crystal.name) [0 0 1], turn 0°, 200 kV, L 1000 mm"), csv[2])
        XCTAssertEqual(csv[3], PatternIndexing.csvColumns)
        XCTAssertEqual(csv.count, 4 + rows.count)
        let line = try XCTUnwrap(csv.first { $0.hasPrefix("\(moved.number),2 0 0,") }).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(try XCTUnwrap(Double(line[3])), lambda * 1_000 * g200, accuracy: 1e-7)
    }

    /// The table writes R in mm to three decimals, a dash without it, and VoiceOver hears the unit (a measured pattern's rows read R px
    /// times the pixel pitch: `DiffractionIndexTests.testTheSpotsTableListsIndexsSpotsAndItsCSVHasItsColumns`). Mutation: the column's words lost, mm to
    /// two decimals.
    func testTheRInMillimetresColumn() throws {
        let row = PatternIndexing.SpotRow(id: UUID(), number: 1, hkl: MillerIndex(1, 1, 1), radiusPx: 120, radiusMM: 1.8, q: 0.5, d: 2,
                                          dExpected: nil, deltaPercent: nil, phase: "Au")
        XCTAssertEqual(DiffractionSpotFormat.cell(.radiusMM, row, locale: Locale(identifier: "en_US")), "1.800")
        XCTAssertEqual(DiffractionSpotFormat.cell(.radiusMM, row, locale: Locale(identifier: "de_DE")), "1,800")
        let none = PatternIndexing.SpotRow(id: UUID(), number: 2, hkl: nil, radiusPx: 80, q: 0.8, d: 1.25, dExpected: nil,
                                           deltaPercent: nil, phase: "")
        XCTAssertEqual(DiffractionSpotFormat.cell(.radiusMM, none), UnitDisplay.noValue)
        XCTAssertEqual(DiffractionSpotFormat.Column.radiusMM.spoken, "radius, millimetres")
        XCTAssertEqual(DiffractionSpotFormat.Column.radiusMM.title, "R mm")
    }
}
