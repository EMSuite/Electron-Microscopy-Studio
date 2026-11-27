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
//  The readers' own checks of these maps moved to FormatoKit with them (FormatoEBSDTests/EBSDH5VendorMapTests, #852); the colours are
//  DiffractoKit's, from the map's columns (`EBSDMapColumns.crystalMap`).
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

    /// The departure: each Bruker phase its own colour, in id order, where orix paints them all tab:blue.
    func testBrukerPhasesTakeTheirOwnColours() throws {
        let map = try EBSDH5Reader.readVendorMap(url: Self.fixture("ebsd-bruker-map.h5"), layout: .bruker).crystalMap()
        XCTAssertEqual(map.phases.ids, [-1, 1, 2])
        XCTAssertEqual(map.phases.colors, ["white", "tab:blue", "tab:orange"])
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

}
