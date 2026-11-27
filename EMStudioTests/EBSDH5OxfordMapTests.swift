//
//  EBSDH5OxfordMapTests.swift
//  An Oxford .h5oina that holds an orientation map but no patterns (AZtec's map export, #513) opens in the Maps room, by double-click
//  and through any Open panel (both go through `FileRouting.inventory`), as a `.ctf` alone does. The planted fixtures
//  (tools/parity/sem-readers/make_h5oina_map_fixtures.py; every value exact in float32) read exactly as the H5OINA specification lays
//  the map out: Euler angles in radians as stored, phase 0 not indexed, the phases of `Header/Phases` with Oxford's Laue group ids,
//  lattice angles in degrees (90° and 120° exact), the `.ctf`'s column names with MAD in degrees and the `.ctf`'s error codes, the
//  header's cells and steps in µm.
//  The same points stored in another order with their X and Y, or without X and Y, read the same map (DREAM3D's EbsdLib, MTEX). A
//  file with no Euler angles is refused in words; the pattern files keep opening in the Patterns room.
//  The reader's own checks of the map moved to FormatoKit with it (FormatoEBSDTests/EBSDH5OxfordMapTests, #852).
//  Red before: the map-only file was routed to the Patterns room and refused with "the header has no 'Pattern Height' dataset.", and
//  the Maps room read only .ang and .ctf.
//

import Foundation
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class EBSDH5OxfordMapTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static func fixture(_ name: String) -> URL { fixtures.appendingPathComponent(name + ".h5oina") }
    private static let map = fixture("ebsd-oxford-map")

    // MARK: - Routing and the Maps room

    /// A map-only H5OINA is the Maps room's, the pattern files stay the Patterns room's, and the Patterns reader names the room
    /// instead of the 'Pattern Height' the map lacks.
    func testAMapOnlyH5OINARoutesToTheMapsRoomAndThePatternFilesDoNot() throws {
        for name in ["ebsd-oxford-map", "ebsd-oxford-map-shuffled", "ebsd-oxford-map-grid", "ebsd-oxford-map-no-euler"] {
            let url = Self.fixture(name)
            XCTAssertEqual(EBSDH5Reader.sniff(url: url), .oxfordH5OINA, name)
            XCTAssertEqual(EBSDH5Reader.content(url: url), .map(.oxford), name)
            XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(orientationMap: true), name)
        }
        for name in ["ebsd-oxford", "ebsd-oxford-6"] {
            let url = Self.fixture(name)
            XCTAssertEqual(EBSDH5Reader.content(url: url), .patterns(.oxfordH5OINA), name)
            XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(ebsdPatterns: true), name)
        }
        XCTAssertThrowsError(try EBSDH5Reader.read(url: Self.map)) { error in
            XCTAssertEqual((error as? EBSDReadError)?.reason, .holdsMapOnly)
            XCTAssertEqual((error as? EBSDReadError)?.inAppWords.text,
                           "ebsd-oxford-map.h5oina holds an orientation map but no EBSD patterns: it opens in the Maps room.")
        }
    }

    /// #522: a .ctf map's Format row names its writer in words, never the reader's code name ("oxford_or_bruker").
    /// Red before: ".ctf (oxford_or_bruker)", ".ctf (emsoft)", ".ctf (astar)", ".ctf (mtex)".
    func testACTFMapsFormatNamesItsWriterInWords() async throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/sem/oxford")
        let want = ["oxford": ".ctf (Oxford or Bruker)", "bruker": ".ctf (Oxford or Bruker)", "emsoft": ".ctf (EMsoft)",
                    "astar": ".ctf (NanoMegas ASTAR)", "mtex": ".ctf (MTEX)"]
        for (name, format) in want.sorted(by: { $0.key < $1.key }) {
            let document = try await OrientationMapSession.read(folder.appendingPathComponent("\(name).ctf"))
            XCTAssertEqual(document.format, format, name)
            XCTAssertFalse(document.format.contains("_"), name)
        }
    }

    /// The Maps room's reader makes the document of the map, named for Info; a file with neither patterns nor Euler angles is refused
    /// in words that name it.
    func testTheMapsRoomReadsTheMapAndRefusesAFileWithoutOrientations() async throws {
        let document = try await OrientationMapSession.read(Self.map)
        XCTAssertEqual(document.fileName, "ebsd-oxford-map.h5oina")
        XCTAssertEqual(document.source, .mapFile)
        XCTAssertEqual(document.format, ".h5oina (Oxford Instruments)")
        XCTAssertEqual(document.map, try EBSDH5Reader.readOxfordMap(url: Self.map).crystalMap())
        XCTAssertEqual([document.rows, document.columns, document.size, document.notIndexedCount], [3, 4, 12, 1])
        XCTAssertEqual(document.phaseCounts, [1: 6, 2: 5, PhaseList.notIndexedID: 1])

        do {
            let refused = try await OrientationMapSession.read(Self.fixture("ebsd-oxford-map-no-euler"))
            XCTFail("read as \(refused.format)")
        } catch let error as MapReadError {
            XCTAssertEqual(error.text,
                           "ebsd-oxford-map-no-euler.h5oina holds neither EBSD patterns nor orientations: its EBSD data has no Euler angles.")
        }
    }

    /// The app's Open: the map-only file lands in the Maps room with its map shown at IPF-Z.
    @MainActor func testOpeningAMapOnlyH5OINALandsInTheMapsRoom() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.open(urls: [Self.map])?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        try await waitUntil("state.maps.raster != nil", seconds: 20) { state.maps.raster != nil }
        XCTAssertEqual(state.maps.fileName, "ebsd-oxford-map.h5oina")
        XCTAssertEqual(state.maps.document?.source, .mapFile)
        XCTAssertEqual(state.maps.document?.format, ".h5oina (Oxford Instruments)")
        XCTAssertEqual(state.maps.layer, .ipf(.z))
        XCTAssertNil(state.ebsd.dataset, "nothing opened in the Patterns room")
        XCTAssertNil(state.roomUnavailableReason(.maps))
    }
}
