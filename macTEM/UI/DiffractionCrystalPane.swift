//
//  DiffractionCrystalPane.swift
//  Role: the crystal pane beside the Diffraction room's pattern (#790, plan row R7): the phase in 3D, seen down the beam the way the
//        simulated spots beside it are drawn (EMSuiteUI's `CrystalView`). Empty until the simulated spots are shown; then it follows
//        their orientation (Index's, a solution, a typed zone axis, the Tilt tool, Flip), and turning the crystal turns the spots:
//        one orientation, `DiffractionAnalysis.simulation`, drives both (`turnByHand`). The scene is the full cell VESTA draws, with the
//        kit's bonds (`CrystalPaneModel`). In a Simulation document whose specimen builds, the pane shows the slab the multislice
//        runs on instead (#897, plan row MA5): its atoms in the crystal's frame and its box, capped at the drawn-atom limit with
//        the count named under it (`SlabDrawing`), so the columns in the pane are the ones marked on the HRTEM image.
//

import ShellCrystal
import ShellLayout
import SwiftUI
import DiffractoCore
import TEMCore
import TEMSession

struct DiffractionCrystalPane: View {
    let analysis: DiffractionAnalysis
    /// The Crystal section's Unit cell toggle (#789); for a slab, its box.
    var showsUnitCell = true
    /// A Simulation document's slab (#897); nil draws the phase's unit cell.
    var slab: SlabDrawing.Drawn?

    var body: some View {
        Group {
            if let orientation = DiffractionCrystalScenes.shown(analysis) {
                let label = CrystalPaneModel.label(phase: analysis.crystal.name, orientation: orientation, cell: analysis.crystal.structure.cell)
                CrystalView(slab.map(DiffractionCrystalScenes.scene(for:)) ?? DiffractionCrystalScenes.scene(for: analysis.crystal),
                            orientation: CrystalPaneModel.view(orientation),
                            showsUnitCell: showsUnitCell,
                            accessibilityLabel: slab.map { "\(label). \($0.caption)" } ?? label,
                            onOrientationChange: { change in
                                // The crystal turned by hand: the simulated spots turn with it.
                                if let turned = CrystalPaneModel.orientation(view: change.orientation) { analysis.turnByHand(to: turned) }
                            })
                .overlay(alignment: .bottom) {
                    if let slab {
                        Text(slab.caption)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: .rect(cornerRadius: 6))
                            .padding(8)
                            .accessibilityHidden(true)   // said in the view's label
                            .allowsHitTesting(false)
                    }
                }
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

    private static var slabCache: (slab: SlabDrawing.Drawn, scene: CrystalScene)?

    /// A Simulation document's slab, its box drawn as the cell (no bonds: a slab is many cells, and its columns are what it shows).
    static func scene(for slab: SlabDrawing.Drawn) -> CrystalScene {
        if let slabCache, slabCache.slab == slab { return slabCache.scene }
        let scene = CrystalScene(atoms: slab.atoms.map { CrystalAtom(position: $0.position, atomicNumber: $0.atomicNumber) }, cell: slab.cell)
        slabCache = (slab, scene)
        return scene
    }
}
