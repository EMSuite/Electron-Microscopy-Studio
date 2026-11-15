//
//  PatternsExportBytesTests.swift
//  The Patterns room's export pictures are encoded off the main actor (#251): the room reads the canvas and its display from the session
//  on the main actor and `PatternsRoomState.png` encodes them in a nonisolated context. Run on the generated demo scan.
//

import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class PatternsExportBytesTests: XCTestCase {

    /// The demo scan's mean map as a picture to encode, with the PNG the room's exporter makes of it on the main actor.
    @MainActor private static func demoMap() async throws -> (picture: PatternsRoomState.Picture, expected: Data) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.ebsd.bind(try DemoDocuments.ebsd()).value
        let ebsd = state.ebsd
        try await waitUntil("the demo scan's map to land", seconds: 30) { !ebsd.isMapping && ebsd.mapPresentation.canvas != nil }
        let document = try XCTUnwrap(ebsd.document)
        let canvas = try XCTUnwrap(ebsd.mapPresentation.canvas)
        let presentation = ebsd.mapPresentation
        let picture = PatternsRoomState.Picture.map(canvas: canvas, display: ExportSnapshot.display(canvas: canvas, presentation: presentation),
                                                    scaleBar: presentation.showsScaleBar, dataset: document.dataset, fileName: document.fileName,
                                                    map: "mean")
        let expected = try PatternsRoomState.mapPNG(canvas: canvas, presentation: presentation, dataset: document.dataset,
                                                    fileName: document.fileName, map: "mean")
        return (picture, expected)
    }

    /// The map PNG, awaited from a nonisolated context, is the bytes the exporter makes on the main actor. Red under: the picture
    /// encoded only on the main actor (no `png`, or one isolated to it, does not compile here); the display or scale bar dropped.
    func testTheMapPictureIsEncodedOffTheMainActorAsTheExporterMakesIt() async throws {
        let (picture, expected) = try await Self.demoMap()
        let png = try await PatternsRoomState.png(picture)
        XCTAssertEqual(png, expected)
        XCTAssertFalse(expected.isEmpty)
    }
}
