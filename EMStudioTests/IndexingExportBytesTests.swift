//
//  IndexingExportBytesTests.swift
//  The Indexing room's export bytes are made off the main actor (#251): the room reads what an export needs from the session on the
//  main actor (`IndexingRoomState.input`), as values, and `IndexingRoomState.bytes` makes the file from them in a nonisolated
//  context. Run on the generated demo scan (30 × 40), so the run is short.
//

import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class IndexingExportBytesTests: XCTestCase {

    /// The demo scan indexed, and what its .ang export reads, with the text the writer makes of the run's crystal map on the main actor.
    @MainActor private static func demoAng() async throws -> (input: IndexingRoomState.Input, expected: String) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        state.navigation.workspaceArea = .indexing
        await state.ebsd.bind(try DemoDocuments.ebsd()).value
        let ebsd = state.ebsd
        try await waitUntil("the demo scan's passes to end", seconds: 30) { !ebsd.isMapping && !ebsd.isComputingMean && !ebsd.isProcessing }
        await state.indexing.index().value
        let indexing = state.indexing
        let document = try XCTUnwrap(indexing.patterns.document)
        let result = try XCTUnwrap(indexing.result)
        let input = try IndexingRoomState.input(.ang, from: indexing, document: document, result: result)
        guard case .ang(_, let options) = input else { throw XCTSkip("the .ang export reads another input") }
        let map = try XCTUnwrap(try indexing.crystalMap())
        return (input, try ANGWriter.text(of: map, options: options))
    }

    /// The .ang bytes, awaited from a nonisolated context, are the writer's text of the run. Red under: the bytes made only on the main
    /// actor (no `bytes`, or one isolated to it, does not compile here); the recipe building another map than `crystalMap()`.
    func testTheAngBytesAreMadeOffTheMainActorAndAreTheWritersText() async throws {
        let (input, expected) = try await Self.demoAng()
        let data = try await IndexingRoomState.bytes(input)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
        XCTAssertFalse(expected.isEmpty)
    }
}
