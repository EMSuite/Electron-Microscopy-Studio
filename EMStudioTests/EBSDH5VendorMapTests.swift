//
//  EBSDH5VendorMapTests.swift
//  #514: the EBSD maps of h5ebsd files saved without patterns open in the Maps room, read as their references read them:
//  - Bruker Esprit, as orix 0.15.0's bruker_h5ebsd.py reads it: the points put back in map order by the SEM IY and IX, X SAMPLE
//    reversed as orix reverses it, Phase 0 not indexed, the phases by IT, the thirteen columns orix keeps.
//  - EDAX OIM Analysis, as orix 0.15.0 reads the .ang OIM writes for the same scan (no Python reader reads the .h5 map).
//  - EMsoft's dictionary indexing file, as orix 0.15.0's emsoft_h5ebsd.py reads it: the best match of each point from the dictionary,
//    y from the rows and Step Y, the properties' first column.
//  Truth: Fixtures/ebsd-h5ebsd-map.truth.json (tools/parity/sem-readers/make_h5ebsd_map_fixtures.py). Departure checked here: the
//  Bruker phases take distinct Tableau colours (orix leaves them all tab:blue, so a two-phase map showed one colour).
//  Red before: each of the three files was refused ("macEM does not read its orientation map yet") or not routed at all (EMsoft writes
//  no version, so it was no EBSD file).
//

import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class EBSDH5VendorMapTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static func fixture(_ name: String) -> URL { fixtures.appendingPathComponent(name) }

    private struct Truth: Decodable {
        struct Phase: Decodable { var id: Int; var name: String; var spaceGroup: Int?; var pointGroup: String?; var color: String; var lattice: [String] }
        struct File: Decodable {
            var reference: String; var size: Int; var shape: [Int]; var rotationsPerPoint: Int
            var phaseIDs: [Int]; var x: [String]; var y: [String]; var euler: [String]
            var properties: [String: [String]]; var scanUnit: String; var dx: String; var dy: String; var phases: [Phase]
        }
        var orix: String
        var files: [String: File]
    }

    private static func numbers(_ values: [String]) -> [Double] { values.map { Double($0) ?? .nan } }

    private static let layouts: [String: EBSDH5Reader.MapLayout] = [
        "ebsd-bruker-map.h5": .bruker, "ebsd-edax-map.h5": .edax, "ebsd-emsoft-map.h5": .emsoft,
    ]

    /// Each map reads as its reference reads it, exactly: phases of the points, x and y, the Euler angles orix builds its rotations
    /// from, every property orix keeps, the phases (lattice to the float64 rounding of diffpy's recomputed cell) and the unit.
    /// Red under: the Bruker points left in the order stored (the phases of row 1 shuffled), X SAMPLE not reversed, the degrees taken as
    /// radians or converted in float64 (one ulp off orix), Phase 0 kept as a phase; the EDAX ci -1 points kept indexed, its names not
    /// taken from the formulas; EMsoft's second match shown, its Y Position used, the match index taken as 0-based.
    func testEachMapReadsAsItsReferenceReadsIt() throws {
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: Self.fixture("ebsd-h5ebsd-map.truth.json")))
        XCTAssertEqual(truth.orix, "0.15.0")
        XCTAssertEqual(Set(truth.files.keys), Set(Self.layouts.keys))
        for (name, expected) in truth.files.sorted(by: { $0.key < $1.key }) {
            let layout = try XCTUnwrap(Self.layouts[name])
            XCTAssertEqual(EBSDH5Reader.content(url: Self.fixture(name)), .map(layout), name)
            let found = try EBSDH5Reader.readMap(url: Self.fixture(name))
            XCTAssertEqual(found.layout, layout, name)
            let map = found.map
            XCTAssertEqual(map.size, expected.size, name)
            XCTAssertEqual(map.shape, expected.shape, name)
            XCTAssertEqual(map.phaseIDs, expected.phaseIDs, name)
            XCTAssertEqual(map.x, Self.numbers(expected.x), name)
            XCTAssertEqual(map.y, Self.numbers(expected.y), name)
            XCTAssertEqual([map.dx, map.dy], Self.numbers([expected.dx, expected.dy]), name)
            let euler = Self.numbers(expected.euler)
            XCTAssertEqual(map.eulerInData, (0..<expected.size).map { SIMD3(euler[3 * $0], euler[3 * $0 + 1], euler[3 * $0 + 2]) }, name)
            XCTAssertEqual(map.propertyNames, expected.properties.keys.sorted(), name)
            for (property, values) in expected.properties { XCTAssertEqual(map.property(property), Self.numbers(values), "\(name) \(property)") }
            XCTAssertEqual(map.scanUnit, expected.scanUnit, name)
            XCTAssertEqual(map.phases.ids, expected.phases.map(\.id), name)
            for phase in expected.phases {
                let read = try XCTUnwrap(map.phases[id: phase.id], "\(name) phase \(phase.id)")
                XCTAssertEqual(read.name, phase.name, "\(name) phase \(phase.id)")
                if layout != .bruker { XCTAssertEqual(read.color, phase.color, "\(name) phase \(phase.id)") }
                guard phase.id != PhaseList.notIndexedID else { continue }
                XCTAssertEqual(read.spaceGroup, phase.spaceGroup, "\(name) phase \(phase.id)")
                XCTAssertEqual(read.pointGroupName, phase.pointGroup, "\(name) phase \(phase.id)")
                let lattice = try XCTUnwrap(read.lattice, "\(name) phase \(phase.id)")
                XCTAssertEqual(lattice.count, 6)
                for (got, want) in zip(lattice, Self.numbers(phase.lattice)) { XCTAssertEqual(got, want, accuracy: 1e-12 * max(1, abs(want))) }
            }
        }
    }

    /// The departure: each Bruker phase its own colour, in id order, where orix paints them all tab:blue.
    func testBrukerPhasesTakeTheirOwnColours() throws {
        let map = try EBSDH5Reader.readVendorMap(url: Self.fixture("ebsd-bruker-map.h5"), layout: .bruker)
        XCTAssertEqual(map.phases.ids, [-1, 1, 2])
        XCTAssertEqual(map.phases.colors, ["white", "tab:blue", "tab:orange"])
    }

    /// The EDAX .h5 map and the .ang of the same scan are one map, phase list and all.
    func testTheEDAXMapIsItsAngMap() throws {
        let h5 = try EBSDH5Reader.readVendorMap(url: Self.fixture("ebsd-edax-map.h5"), layout: .edax)
        let ang = try ANGReader.read(url: Self.fixture("ebsd-edax-map.ang")).map
        XCTAssertEqual(h5, ang)
    }

    /// A file saved without patterns has the map its patterned twin carries beside its patterns (the kikuchipy-made EDAX file); a
    /// Bruker file whose points all sit at one X and Y SAMPLE (kikuchipy's) lays out no map and is refused in words.
    func testFilesSavedWithoutPatternsReadTheMapTheirPatternedTwinCarries() throws {
        let edax = try EBSDH5Reader.readMap(url: Self.fixture("ebsd-edax-nopatterns-h5ebsd.h5"))
        XCTAssertEqual(edax.layout, .edax)
        XCTAssertEqual(edax.map, try XCTUnwrap(EBSDH5Reader.read(url: Self.fixture("ebsd-edax-h5ebsd.h5")).crystalMap))
        XCTAssertEqual(edax.map.shape, [3, 3])

        XCTAssertThrowsError(try EBSDH5Reader.readMap(url: Self.fixture("ebsd-bruker-nopatterns-h5ebsd.h5"))) { error in
            XCTAssertEqual((error as? EBSDReadError)?.text,
                           "ebsd-bruker-nopatterns-h5ebsd.h5: the positions of its 9 points do not lay them out on a map (they span 1 grid cell).")
        }
    }

    /// The Maps room reads each and names its format for Info.
    func testTheMapsRoomReadsEachAndNamesItsFormat() async throws {
        for (name, format) in [("ebsd-bruker-map.h5", ".h5 (Bruker Esprit)"), ("ebsd-edax-map.h5", ".h5 (EDAX OIM)"),
                               ("ebsd-emsoft-map.h5", ".h5 (EMsoft)")] {
            let document = try await OrientationMapSession.read(Self.fixture(name))
            XCTAssertEqual(document.source, .mapFile, name)
            XCTAssertEqual(document.format, format, name)
            XCTAssertEqual([document.rows, document.columns], [3, 4], name)
            XCTAssertEqual(FileRouting.inventory(path: Self.fixture(name).path), FileInventory(orientationMap: true), name)
        }
    }

    /// The app's Open lands an EMsoft file (no version in it) in the Maps room.
    @MainActor func testOpeningLandsAnEMsoftFileInTheMapsRoom() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.open(urls: [Self.fixture("ebsd-emsoft-map.h5")])?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        try await waitUntil("state.maps.raster != nil", seconds: 20) { state.maps.raster != nil }
        XCTAssertEqual(state.maps.document?.format, ".h5 (EMsoft)")
        XCTAssertNil(state.errorMessage)
    }

    /// orix's regular expressions for EMsoft's phase: the first `[A-z0-9]` run of the name, the bracketed point group (the class holds
    /// `]` itself, so the match backs off to the last `]`).
    func testEMsoftPhaseTextsReadAsOrixsRegularExpressions() {
        XCTAssertEqual(EBSDH5Reader.firstRun(in: "fe4al13/fe4al13", allowed: { ($0 >= 65 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }), "fe4al13")
        XCTAssertEqual(EBSDH5Reader.bracketedPointGroup("Monoclinic b (C2h) [2/m]"), "2/m")
        XCTAssertEqual(EBSDH5Reader.bracketedPointGroup("Cubic (Oh) [m3m]"), "m3m")
        XCTAssertEqual(EBSDH5Reader.bracketedPointGroup("Hexagonal [6/mmm] x"), "6/mmm")
        XCTAssertNil(EBSDH5Reader.bracketedPointGroup("Cubic []"))
        XCTAssertNil(EBSDH5Reader.bracketedPointGroup("Cubic"))
    }
}
