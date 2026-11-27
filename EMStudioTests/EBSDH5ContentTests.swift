//
//  EBSDH5ContentTests.swift
//  #514: every EBSD HDF5 file goes to the room that opens what it holds, or is refused in a sentence that names it and says what it
//  holds, in words a user reads (no HDF5 path, no quoted dataset name).
//  - The patterns go to the Patterns room: an H5OINA whose scan holds only unprocessed patterns reads those (kikuchipy refuses it
//    unless asked for them), and an H5OINA's map comes with its patterns (kikuchipy 0.13.1 leaves it empty), while a map that does not
//    read never keeps the patterns from opening.
//  - A map without patterns goes to the Maps room: AZtec's H5OINA map export (#513) and orix's own HDF5 file, read as orix 0.15.0
//    reads it (ebsd-orix-map.truth.json, tools/parity/sem-readers/make_orix_map_fixtures.py): the points `is_in_data` keeps, and of a
//    map with several rotations a point the first, the one orix shows. So do a Bruker or EDAX file saved without patterns and EMsoft's
//    dictionary indexing file (EBSDH5VendorMapTests).
//  - An EDS-only H5OINA is refused in its sentence.
//  The readers' own checks of these files moved to FormatoKit with them (FormatoEBSDTests/EBSDH5ContentTests, #852).
//  Fixtures: tools/parity/sem-readers/make_h5oina_map_fixtures.py, make_orix_map_fixtures.py, make_h5ebsd_without_patterns.py.
//  Red before: the EDS-only file and the files without patterns were refused as "neither a Velox file nor an EBSD scan … open it in
//  mac4DSTEM" or with "could not find patterns in the expected dataset 'EBSD/Data/RawPatterns'."; the unprocessed-only scan with the
//  missing 'Processed Patterns'; orix's map file as an HDF5 file macEM does not open; the reader's refusals named no file.
//

import Foundation
import FormatoCore
import FormatoHDF5
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class EBSDH5ContentTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static func fixture(_ name: String) -> URL { fixtures.appendingPathComponent(name) }

    /// A sentence a user reads: it names the file and quotes nothing (no 'EBSD/Data/…', no HDF5 call).
    private static func assertPlain(_ sentence: String, names file: String, file path: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sentence.contains(file), "does not name \(file): \(sentence)", file: path, line: line)
        let rest = sentence.replacingOccurrences(of: file, with: "<file>")
        for leak in ["'", "/EBSD", "HDF5 failed", "H5D", "H5F", "dataset", "Error Domain"] {
            XCTAssertFalse(rest.contains(leak), "carries \(leak): \(sentence)", file: path, line: line)
        }
    }

    // MARK: - Which room

    func testEachEBSDFileGoesToTheRoomOfWhatItHoldsOrIsRefusedInWords() throws {
        let patterns: [(String, EBSDFileFormat)] = [
            ("ebsd-oxford.h5oina", .oxfordH5OINA), ("ebsd-oxford-map-patterns.h5oina", .oxfordH5OINA),
            ("ebsd-oxford-map-unprocessed.h5oina", .oxfordH5OINA), ("ebsd-bruker-h5ebsd.h5", .brukerH5EBSD),
            ("ebsd-edax-h5ebsd.h5", .edaxH5EBSD), ("ebsd-kikuchipy-h5ebsd.h5", .kikuchipyH5EBSD),
        ]
        for (name, format) in patterns {
            XCTAssertEqual(EBSDH5Reader.content(url: Self.fixture(name)), .patterns(format), name)
            XCTAssertEqual(FileRouting.inventory(path: Self.fixture(name).path), FileInventory(ebsdPatterns: true), name)
        }
        let maps: [(String, EBSDH5Reader.MapLayout)] = [
            ("ebsd-oxford-map.h5oina", .oxford), ("ebsd-orix-map.h5", .orix), ("ebsd-orix-map-best2.h5", .orix), ("ebsd-orix-map-crop.h5", .orix),
            ("ebsd-bruker-map.h5", .bruker), ("ebsd-bruker-nopatterns-h5ebsd.h5", .bruker), ("ebsd-edax-map.h5", .edax),
            ("ebsd-edax-nopatterns-h5ebsd.h5", .edax), ("ebsd-emsoft-map.h5", .emsoft),
        ]
        for (name, layout) in maps {
            XCTAssertEqual(EBSDH5Reader.content(url: Self.fixture(name)), .map(layout), name)
            XCTAssertEqual(FileRouting.inventory(path: Self.fixture(name).path), FileInventory(orientationMap: true), name)
        }
        let refused = [
            "ebsd-oxford-eds.h5oina": "ebsd-oxford-eds.h5oina holds EDS data from AZtec but no EBSD data. Electron Microscopy Studio does not read EDS from an "
                + ".h5oina file yet; a spectrum AZtec exports as .msa opens in the EDS room.",
        ]
        for (name, sentence) in refused {
            // FormatoKit's typed refusal; the app adds where the spectrum opens instead (`EBSDReadError.inAppWords`).
            guard case .refused(let refusal)? = EBSDH5Reader.content(url: Self.fixture(name)) else { return XCTFail(name) }
            XCTAssertEqual(refusal.reason, .edsOnly, name)
            XCTAssertEqual(refusal.inAppWords.text, sentence, name)
            XCTAssertEqual(FileRouting.inventory(path: Self.fixture(name).path), FileInventory(refusal: sentence), name)
            Self.assertPlain(sentence, names: name)
        }
        XCTAssertNil(EBSDH5Reader.content(url: Self.fixture("velox-haadf-last.emd")), "not an EBSD file: the Velox route decides")
    }

    /// The app's Open: the EDS-only file is refused in its sentence and nothing opens; orix's map lands in the Maps room.
    @MainActor func testOpeningRefusesTheEDSOnlyFileAndLandsOrixsMapInTheMapsRoom() async throws {
        let eds = AppState(launch: LaunchOptions(arguments: []))
        await eds.open(urls: [Self.fixture("ebsd-oxford-eds.h5oina")])?.value
        let message = try XCTUnwrap(eds.errorMessage)
        XCTAssertTrue(message.hasPrefix("ebsd-oxford-eds.h5oina holds EDS data from AZtec but no EBSD data."), message)
        XCTAssertNil(eds.ebsd.dataset)
        XCTAssertNil(eds.maps.document)

        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.open(urls: [Self.fixture("ebsd-orix-map.h5")])?.value
        XCTAssertEqual(state.navigation.workspaceArea, .maps)
        try await waitUntil("state.maps.raster != nil", seconds: 20) { state.maps.raster != nil }
        XCTAssertEqual(state.maps.fileName, "ebsd-orix-map.h5")
        XCTAssertEqual(state.maps.document?.format, ".h5 (orix)")
        XCTAssertNil(state.errorMessage)
    }

    // MARK: - orix's map file

    /// The Maps room reads orix's file and names its format for Info.
    func testTheMapsRoomReadsOrixsMapFile() async throws {
        let document = try await OrientationMapSession.read(Self.fixture("ebsd-orix-map-crop.h5"))
        XCTAssertEqual(document.source, .mapFile)
        XCTAssertEqual(document.format, ".h5 (orix)")
        XCTAssertEqual(document.map, try EBSDH5Reader.readOrixMap(url: Self.fixture("ebsd-orix-map-crop.h5")).crystalMap())
        XCTAssertEqual(document.size, 6)
    }

}
