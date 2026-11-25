//
//  DiffractionCrystalPaneTests.swift
//  The crystal pane beside the Diffraction room's pattern (#790, plan row R7): empty until the simulated spots are shown, then the
//  crystal at their orientation (a typed zone axis, Index's, Flip's), as one cell VESTA draws, and a turn of the crystal turns the
//  spots. Red before: the room had no crystal pane (`DiffractionCrystalScenes`, `CrystalPaneModel` did not exist).
//
//  The cells are the room's standards: silicon draws 18 atoms and 16 bonds (8 corners, 6 faces, 4 inside, each inside atom bonded to
//  four), aluminium 14 atoms and no bond (VESTA's table has no Al-Al pair).
//

import XCTest
import DiffractoCore
import ShellCrystal
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionCrystalPaneTests: XCTestCase {

    @MainActor private func analysis(_ crystal: String) throws -> (DiffractionAnalysis, CalibratedImage) {
        let image = CalibratedImage(width: 256, height: 256, pixels: [Float](repeating: 1, count: 256 * 256), x: nil, y: nil,
                                    fileName: "blank", source: "test", voltage: 200_000)
        let a = DiffractionAnalysis()
        a.bind(image)
        a.typedDeltaQ = 0.01
        a.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named(crystal))))
        return (a, image)
    }

    @MainActor func testTheCellIsDrawnAsVESTADrawsIt() throws {
        let si = try XCTUnwrap(StandardCrystals.named("Si"))
        let silicon = DiffractionCrystalScenes.scene(for: .preset(si))
        XCTAssertEqual(silicon.atoms.count, 18)
        XCTAssertEqual(silicon.bonds.count, 16)
        XCTAssertTrue(silicon.atoms.allSatisfy { $0.atomicNumber == 14 })
        XCTAssertNotNil(silicon.cell)
        XCTAssertEqual(CrystalPaneModel.sites(si.structure).count, 8)
        XCTAssertEqual(CrystalPaneModel.bonds(si.structure).count, si.structure.bonds.count / 2, "each bond once")

        let al = try XCTUnwrap(StandardCrystals.named("Al"))
        let aluminium = DiffractionCrystalScenes.scene(for: .preset(al))
        XCTAssertEqual(aluminium.atoms.count, 14)
        XCTAssertEqual(aluminium.bonds.count, 0)
    }

    @MainActor func testThePaneFollowsTheSimulatedSpotsAndTurnsThem() throws {
        let (a, image) = try analysis("Au")
        XCTAssertNil(DiffractionCrystalScenes.shown(a), "empty until the simulated spots are shown")

        a.simulation.isShown = true
        a.setZoneAxis(SIMD3(0, 0, 1))
        let typed = try XCTUnwrap(DiffractionCrystalScenes.shown(a))
        XCTAssertEqual(typed, a.drawnOrientation)
        XCTAssertEqual(CrystalPaneModel.label(phase: "Au", orientation: typed, cell: a.crystal.structure.cell), "Au, zone axis [001]")

        // Flip turns the crystal too.
        a.flip()
        let flipped = try XCTUnwrap(DiffractionCrystalScenes.shown(a))
        XCTAssertEqual(flipped, typed.rotatedInPlane(by: .pi))

        // The view's frame and back is the same orientation, exactly; a crystal turned in the pane turns the spots.
        XCTAssertEqual(CrystalPaneModel.orientation(view: CrystalPaneModel.view(flipped)), flipped)
        let tilted = typed.tilted(by: SIMD2(0, 2 * Double.pi / 180))
        a.turnByHand(to: try XCTUnwrap(CrystalPaneModel.orientation(view: CrystalPaneModel.view(tilted))))
        XCTAssertEqual(a.drawnOrientation, tilted)
        XCTAssertEqual(CrystalPaneModel.label(phase: "Au", orientation: tilted, cell: a.crystal.structure.cell), "Au, zone axis [001], tilted 2.0°")
        XCTAssertNotNil(try? a.simulatedSpots(image: image)?.get(), "the spots are drawn at the crystal's orientation")

        a.simulation.isShown = false
        XCTAssertNil(DiffractionCrystalScenes.shown(a))
    }
}
