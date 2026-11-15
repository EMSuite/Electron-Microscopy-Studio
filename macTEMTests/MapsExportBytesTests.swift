//
//  MapsExportBytesTests.swift
//  The Maps room's figures are drawn off the main actor (#251): the room reads what the map figure draws on the main actor
//  (`MapsFigure.MapInput`, with the property layer's display) and `MapsRoomState.mapPNG` draws it in a nonisolated context.
//

import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class MapsExportBytesTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// The phase map figure, drawn from a nonisolated context, is the figure the main-actor call draws. Red under: the figure drawn only on
    /// the main actor (no `mapPNG`, or one isolated to it, does not compile here); the input dropping the legend's phases.
    func testTheMapFigureIsDrawnOffTheMainActorAsOnIt() async throws {
        let map = try ANGReader.read(url: Self.fixtures.appendingPathComponent("ebsd-tsl.ang")).map
        let raster = OrientationMaps.raster(.phase, of: map)
        let input = MapsFigure.MapInput(raster: raster, layer: .phase, map: map, keys: [], display: nil, fileName: "sdss.ang")
        let png = try await MapsRoomState.mapPNG(input)
        let expected = try await MainActor.run {
            try MapsFigure.png(raster: raster, layer: .phase, map: map, keys: [], presentation: ImagePresentation(), fileName: "sdss.ang")
        }
        XCTAssertEqual(png, expected)
        XCTAssertFalse(png.isEmpty)
    }
}
