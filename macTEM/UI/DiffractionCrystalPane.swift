//
//  DiffractionCrystalPane.swift
//  Role: the crystal pane beside the Diffraction room's pattern (#790, plan row R7): the phase in 3D, seen down the beam the way the
//        simulated spots beside it are drawn (EMSuiteUI's `CrystalView`). Empty until the simulated spots are shown; then it follows
//        their orientation (Index's, a solution, a typed zone axis, the Tilt tool, Flip), and turning the crystal turns the spots:
//        one orientation, `DiffractionAnalysis.simulation`, drives both (`turnByHand`). The scene is the full cell VESTA draws, with the
//        kit's bonds (`CrystalPaneModel`).
//

import ShellCrystal
import ShellLayout
import SwiftUI
import DiffractoCore
import TEMCore
import TEMSession

struct DiffractionCrystalPane: View {
    let analysis: DiffractionAnalysis

    var body: some View {
        Group {
            if let orientation = DiffractionCrystalScenes.shown(analysis) {
                CrystalView(DiffractionCrystalScenes.scene(for: analysis.crystal), orientation: CrystalPaneModel.view(orientation),
                            accessibilityLabel: CrystalPaneModel.label(phase: analysis.crystal.name, orientation: orientation,
                                                                       cell: analysis.crystal.structure.cell),
                            onOrientationChange: { change in
                                // The crystal turned by hand: the simulated spots turn with it.
                                if let turned = CrystalPaneModel.orientation(view: change.orientation) { analysis.turnByHand(to: turned) }
                            })
            } else {
                Text("Show the simulated spots, or Index, to see the crystal down the beam.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("diffraction.crystalPane")
    }
}

/// The crystal scenes built so far (the kit's bonds are the costly part), by crystal; and what the pane shows.
@MainActor enum DiffractionCrystalScenes {
    private static var cache: (structure: CrystalStructure, scene: CrystalScene)?

    /// The orientation the pane draws: the simulated spots', nil while they are off.
    static func shown(_ analysis: DiffractionAnalysis) -> CrystalOrientation? {
        analysis.simulation.isShown ? analysis.drawnOrientation : nil
    }

    /// One unit cell of the crystal as VESTA draws it, with its bonds.
    static func scene(for crystal: DiffractionCrystal) -> CrystalScene {
        // Keyed by the structure itself: two crystals of one name, or one phase after a lattice edit, are two scenes.
        let s = crystal.structure
        if let cache, cache.structure == s { return cache.scene }
        let scene = CrystalScene.unitCell(
            cell: CrystalPaneModel.cell(s),
            sites: CrystalPaneModel.sites(s).map { CrystalSite(fractional: $0.fractional, atomicNumber: $0.atomicNumber, occupancy: $0.occupancy) },
            bonds: CrystalPaneModel.bonds(s).map { CrystalBondInput(from: $0.from, to: $0.to, image: $0.image) })
        cache = (s, scene)
        return scene
    }
}
