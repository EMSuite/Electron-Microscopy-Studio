//
//  CrystalMapParityTests.swift
//  The functions are DiffractoKit's since DiffractoKit#180, which holds their own parity tests; what stays here reads its maps with
//  the app's readers (ANG, CTF) or draws the room's rasters.
//  The crystal map model (DiffractoKit's `CrystalMap`, `PhaseList`, `NeighbourMisorientation`,
//  `AngleHistogram`) against orix 0.15.0 through the bundles `m3/ti-neighbour-misorientations` (a committed 3 x 507 Ti map),
//  `m3/ti-neighbour-misorientations-full` (figure F7: orix-data's whole 381 x 507 Ti map, a downloaded dataset) and
//  `m3/crystal-map-sdss` (orix-data's two-phase .ang map, committed as Fixtures/ebsd-sdss-ferrite-austenite.ang).
//  Tolerances are the bundles' (docs/parity.md): counts, edges, shapes, ids, rows, columns and map data exact; misorientations
//  and angles atol 1e-7. Red before the port: none of these types exists. Red after a swapped neighbour order, a pair taken
//  across a row end, a histogram bin closed on the wrong side or a slice that loses its place in the grid.
//

import DiffractoOrientation
import TEMCore
import XCTest

nonisolated final class CrystalMapParityTests: XCTestCase {

    private func flat(_ a: [SIMD4<Double>]) -> [Double] { a.flatMap { [$0[0], $0[1], $0[2], $0[3]] } }

    private func rows3(_ a: SEMParityReference.LoadedArray) -> [SIMD3<Double>] {
        stride(from: 0, to: a.values.count, by: 3).map { SIMD3(a.values[$0], a.values[$0 + 1], a.values[$0 + 2]) }
    }

    private static let ti = CrystalPhase(name: "Ti", spaceGroup: 194, pointGroup: "622", lattice: [2.95, 2.95, 4.68, 90, 90, 120])

    // MARK: - F7 on the committed map

    /// Figure F7: the neighbour disorientation angle histogram of orix-data's whole Ti map, counts and edges exact. The 29 MB
    /// file comes through tools/parity/sem/fetch-data.sh (References/sem-data/orix/Ti_orientations.ctf); without it the test
    /// skips and the committed 3 x 507 map above holds the port.
    func testFigureF7NeighbourMisorientationHistogramOfTheTiMap() throws {
        let ref = try SEMParityReference.load("m3/ti-neighbour-misorientations-full")
        let url = try XCTUnwrap(ref.inputURL())
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "fetch-data.sh has not fetched \(url.lastPathComponent)")
        let map = try Self.tiMap(url: url)
        XCTAssertEqual(map.shape, [381, 507])
        let (h, v) = try NeighbourMisorientation.misorientations(of: map)
        XCTAssertEqual(h.quaternions.count, 192_786)
        XCTAssertEqual(v.quaternions.count, 192_660)
        let radians = h.angles + v.angles
        let sample = try ref.array("sample_index").values.map { radians[Int($0)] }
        SEMAssertParity(sample, try ref.array("sample_angles"))
        let histogram = AngleHistogram(values: radians.map { $0 * 180 / .pi }, edges: NeighbourMisorientation.f7Edges)
        SEMAssertParity(histogram.edges, try ref.array("edges_degrees"))
        SEMAssertParity(histogram.counts.map(Double.init), try ref.array("counts"))
        Self.writeFigureF7(histogram)
    }

    /// orix-data's Ti table read by `CTFReader` (the orientation-table form), 622 attached as `orix.data.ti_orientations` does.
    static func tiMap(url: URL) throws -> CrystalMap {
        var map = try CTFReader.read(path: url.path).map.crystalMap()
        map.phases = PhaseList([(1, ti)])
        return map
    }

    /// The figure's numbers as text beside the reference figure (`$TMPDIR/macTEM-F7-ours.txt`): edge, count per bin.
    static func writeFigureF7(_ histogram: AngleHistogram) {
        let lines = zip(histogram.edges, histogram.counts).map { "\($0.0)\t\($0.1)" }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: NSTemporaryDirectory() + "macTEM-F7-ours.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - The two-phase map

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    private func sdssMap() throws -> CrystalMap {
        try ANGReader.read(url: Self.fixtures.appendingPathComponent("ebsd-sdss-ferrite-austenite.ang")).map.crystalMap()
    }

    /// The reader's map is the model's map: the head of orix-data's Ti table read by `CTFReader` into a `CrystalMap`, its first
    /// three rows kept by a mask, 622 attached, gives the committed F7 numbers.
    func testTheCTFReaderHandsTheF7MapThrough() throws {
        let ref = try SEMParityReference.load("m3/ti-neighbour-misorientations")
        var map = try CTFReader.read(path: Self.fixtures.appendingPathComponent("sem/oxford/ti_orientations_head.ctf").path).map.crystalMap()
        XCTAssertEqual(map.pointCount, 2000)
        map.phases = PhaseList([(1, Self.ti)])
        let head = map.masked((0..<map.size).map { $0 < 3 * 507 })
        XCTAssertEqual(head.shape, [3, 507])
        XCTAssertEqual(head.ids, Array(0..<(3 * 507)))
        let (h, v) = try NeighbourMisorientation.misorientations(of: head)
        SEMAssertParity(h.angles, try ref.array("horizontal_angles"))
        SEMAssertParity(v.angles, try ref.array("vertical_angles"))
        let histogram = AngleHistogram(values: try NeighbourMisorientation.anglesDegrees(of: head), edges: NeighbourMisorientation.f7Edges)
        SEMAssertParity(histogram.counts.map(Double.init), try ref.array("counts"))
    }

    func testTheTwoPhaseMapSlicesAsOrix() throws {
        let ref = try SEMParityReference.load("m3/crystal-map-sdss")
        let map = try sdssMap()
        XCTAssertEqual(map.shape, ref.values["shape"] as? [Int])
        XCTAssertEqual(map.size, ref.values["size"] as? Int)
        XCTAssertEqual(map.dx, ref.values["dx"] as? Double)
        XCTAssertEqual(map.dy, ref.values["dy"] as? Double)
        XCTAssertEqual(map.phases.ids, ref.values["phase_ids"] as? [Int])
        XCTAssertEqual(map.phases.names, ref.values["phase_names"] as? [String])
        XCTAssertEqual(map.phases.colors, ref.values["phase_colors"] as? [String])
        XCTAssertEqual(map.phases.pointGroupNames.compactMap { $0 }, ref.values["point_groups"] as? [String])
        XCTAssertEqual(map.allIndexed, ref.values["all_indexed"] as? Bool)
        XCTAssertEqual(map.isIndexed.filter { $0 }.count, ref.values["indexed_count"] as? Int)

        let slices = try XCTUnwrap(ref.values["phase_slices"] as? [String: [String: Any]])
        for (name, expected) in slices {
            let s = map[phase: name]
            XCTAssertEqual(s.size, expected["size"] as? Int, name)
            XCTAssertEqual(s.shape, expected["shape"] as? [Int], name)
            XCTAssertEqual(s.phasesInData.ids, expected["phases_in_data"] as? [Int], name)
        }

        let window = map.sliced(rows: 10..<20, columns: 5..<15)
        let w = try XCTUnwrap(ref.values["window"] as? [String: Any])
        XCTAssertEqual(window.size, w["size"] as? Int)
        XCTAssertEqual(window.shape, w["shape"] as? [Int])
        SEMAssertParity(window.row.map(Double.init), try ref.array("window_row"))
        SEMAssertParity(window.col.map(Double.init), try ref.array("window_col"))
        SEMAssertParity(window.ids.map(Double.init), try ref.array("window_id"))
        SEMAssertParity(try XCTUnwrap(window.mapData(named: "iq")), try ref.array("window_iq"))

        let ferrite = map[phase: try XCTUnwrap(ref.values["ferrite_name"] as? String)]
        SEMAssertParity(try XCTUnwrap(ferrite.mapData(named: "iq", fill: -1)), try ref.array("ferrite_iq_map"))
        SEMAssertParity(ferrite.row.map(Double.init), try ref.array("ferrite_row"))
        SEMAssertParity(ferrite.col.map(Double.init), try ref.array("ferrite_col"))
        SEMAssertParity(try XCTUnwrap(map.mapData(named: "phase_id")), try ref.array("phase_id_map"))

        let austenite = try map[phase: map.phases.names[0]].orientations()
        XCTAssertEqual(austenite.symmetry.name, ref.values["austenite_symmetry"] as? String)
        SEMAssertParity(flat(austenite.quaternions), try ref.array("austenite_quaternions"))
        XCTAssertThrowsError(try map.orientations()) { error in
            XCTAssertEqual(error as? CrystalMap.Refusal, .moreThanOnePhase(map.phases.names))
        }
    }

    // MARK: - orix's rules without a bundle

}
