//
//  DemoEELSCoreLossTests.swift
//  #1088: Help > Open Demo Data > EELS Spectrum Image held only a low loss, so the room's edge fit and its maps could not be shown
//  ("This file holds no core-loss spectrum image to fit"). The demo now carries a core loss with the C, N and O K edges planted
//  (`DemoDocuments.Truth.eelsAmounts`): carbon everywhere, oxygen in a central disc, nitrogen in the top half. Red before: no core loss.
//

import SpectroEELS
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class DemoEELSCoreLossTests: XCTestCase {
    @MainActor func testTheDemoFitsItsPlantedEdgesIntoMapsThatShowWhereEachIs() async throws {
        let demo = try DemoDocuments.eels()
        let core = try XCTUnwrap(demo.coreLoss, "the demo carries a core loss")
        XCTAssertEqual(core.channels, DemoDocuments.Truth.eelsCoreChannels)
        let session = EELSSession()
        await session.bind(demo).value
        await session.settled()
        session.setConvolveLowLoss(false)
        for edge in [CoreLossEdge.carbonK, .nitrogenK, .oxygenK] { session.toggleEdge(edge) }
        await session.fit()?.value
        await session.settled()
        XCTAssertNotNil(session.model, session.failure ?? session.fitRefusal ?? "no fit")

        let side = DemoDocuments.Truth.eelsSide
        func value(_ id: String, x: Int, y: Int) throws -> Double {
            try XCTUnwrap(session.modelTiles.first { $0.id == id }, "\(id) in \(session.modelTiles.map(\.id))").values[y * side + x]
        }
        XCTAssertGreaterThan(try value("edge-O-K1", x: 8, y: 8), 10 * max(try value("edge-O-K1", x: 0, y: 0), 1e-12), "oxygen in the central disc")
        XCTAssertGreaterThan(try value("edge-N-K1", x: 8, y: 2), 10 * max(try value("edge-N-K1", x: 8, y: 13), 1e-12), "nitrogen in the top half")
        let carbonCorner = try value("edge-C-K1", x: 0, y: 15), carbonCentre = try value("edge-C-K1", x: 8, y: 8)
        XCTAssertEqual(carbonCorner, carbonCentre, accuracy: 0.05 * carbonCentre, "carbon everywhere alike")
    }

    /// The energy axis never prints "-0": the first tick of a window just below zero is +0. Red before: -0.0, read "-0".
    func testTheEnergyAxisHasNoNegativeZero() {
        let ticks = EELSOneAxis.ticks(in: -2.5 ... 20)
        let zero = ticks.first { $0 == 0 }
        XCTAssertEqual(zero?.sign, .plus, "\(ticks)")
        XCTAssertFalse(ticks.map { EELSRoomFormat.sig($0, 5) }.contains("-0"))
    }
}
