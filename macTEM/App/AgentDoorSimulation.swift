//
//  AgentDoorSimulation.swift
//  Role: the agent door's tools for the Simulation document and the crystal pane (#846, plan row R8b). `new_simulation` is File >
//        New Simulation (`AppState.newSimulation`, the menu's own call); `get_crystal_view` reads the crystal pane beside the
//        Diffraction room's pattern: its words (the phase, the zone axis and the tilt off it, the pane's label), the orientation as the
//        3 by 3 matrix the simulated spots are drawn with (`CrystalOrientation.matrix`, row by row), EMSuiteUI's `CrystalSummary` of
//        the scene, and with picture true the pane's picture (`CrystalSnapshot.image`, the same scene and view matrix the pane draws),
//        so a check can see that crystal and pattern turn together.
//
//        The picture is drawn off the main actor (RealityKit's renderer is asynchronous) and the door's tools answer at once: the
//        first ask for a view starts the drawing and answers 409 "ask again"; the next ask for the same view answers the PNG
//        (`CrystalViewPicture`). One drawing is kept: the last view asked for.
//

import CoreGraphics
import DiffractoCore
import Foundation
import ShellAgentDoor
import ShellCrystal
import TEMCore
import TEMSession

extension MacTEMAgentDoor {
    static let simulationTools: [AgentTool] = [
        said(AgentTool(name: "new_simulation", title: "New Simulation",
                       summary: "File > New Simulation: a simulated diffraction pattern with no measured one under it, in the "
                           + "Diffraction room with the simulated spots on ([0 0 1], 200 kV typed, 0.0125 Å⁻¹/px) and no phase yet "
                           + "(add_phase gives it one; until then get_crystal_view answers that the pane is empty). A window that "
                           + "holds a file gives it a tab of its own, which list_windows then names. set_diffraction (crystal, "
                           + "beam_kv) and set_zone_axis set it; get_diffraction_picture and get_crystal_view show it. Answers at once "
                           + "with opens_in_new_window; get_window says the simulation is open once it is.",
                       input: .window, acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            let elsewhere = appState.isTaken && appState.windows?.canOpenTabs == true
            appState.newSimulation()
            return .json(["opens_in_new_window": elsewhere])
        }),
        AgentTool(name: "get_crystal_view", title: "Crystal view",
                  summary: "The crystal pane beside the Diffraction room's pattern: shown (false when hidden), the phase, place "
                      + "(the zone axis nearest the drawn orientation and the tilt off it, as the pane's label reads), orientation "
                      + "(the 3 by 3 matrix the simulated spots are drawn with, row by row: its columns are the lab x, y and z axes "
                      + "in the crystal frame), shows_unit_cell, and crystal (the scene: atoms and bonds by element, the cell "
                      + "lengths, the view's rotation rows and direction). With picture true, the pane's picture as a PNG: the first "
                      + "ask for a view starts drawing it and answers 409; ask again. Answers in words while the simulated spots "
                      + "are off (the pane is then empty).",
                  input: .window,
                  parameters: [AgentParameter("picture", .boolean, summary: "The pane's picture instead.")]) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            switch diffractionItem(appState) {
            case .refused(let refusal): return refusal
            case .item(let item): return crystalView(item, picture: call.arguments["picture"] == "true")
            }
        },
    ]

    static func crystalView(_ item: OpenItem, picture: Bool) -> AgentToolOutput {
        let analysis = item.diffraction, view = item.diffractionView
        guard let orientation = DiffractionCrystalScenes.shown(analysis) else {
            if analysis.awaitsPhase {
                return .refusal(status: 404, message: "The crystal pane is empty: this Simulation document has no phase yet; add one "
                    + "(add_phase) first.")
            }
            return .refusal(status: 404, message: "The crystal pane is empty: show the simulated spots (simulate_pattern overlay true) "
                + "or Index first.")
        }
        let scene = DiffractionCrystalScenes.scene(for: analysis.crystal)
        if picture {
            return CrystalViewPicture.png(scene: scene, orientation: orientation, showsUnitCell: view.showsUnitCell, pixels: pictureSide)
        }
        let cell = analysis.crystal.structure.cell
        let summary = CrystalSummary(scene: scene, orientation: CrystalPaneModel.view(orientation), showsUnitCell: view.showsUnitCell)
        let crystal = AgentJSON.encoded(summary).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        return .json([
            "shown": view.showsCrystal,
            "phase": analysis.crystal.name,
            "place": CrystalPaneModel.label(phase: analysis.crystal.name, orientation: orientation, cell: cell),
            "orientation": CrystalPaneModel.rows(orientation),
            "shows_unit_cell": view.showsUnitCell,
            "crystal": crystal,
        ])
    }
}

/// The crystal pane's picture for the door: one drawing kept, the last view asked for, by everything that changes it.
@MainActor enum CrystalViewPicture {
    private struct Key: Equatable {
        var scene: CrystalScene
        var orientation: [[Double]]
        var showsUnitCell: Bool
        var pixels: Int

        // Written out (not synthesized) so the unused-code scan sees each field read.
        static func == (a: Key, b: Key) -> Bool {
            a.scene == b.scene && a.orientation == b.orientation && a.showsUnitCell == b.showsUnitCell && a.pixels == b.pixels
        }
    }

    private static var drawn: (key: Key, png: Data?)?
    private static var drawing: Key?

    static func png(scene: CrystalScene, orientation: CrystalOrientation, showsUnitCell: Bool, pixels: Int) -> AgentToolOutput {
        let key = Key(scene: scene, orientation: CrystalPaneModel.rows(orientation), showsUnitCell: showsUnitCell, pixels: pixels)
        if let drawn, drawn.key == key {
            guard let png = drawn.png else {
                return .refusal(status: 503, message: "The crystal could not be drawn: this Mac offers no Metal device.")
            }
            return .png(png)
        }
        if drawing != key {
            drawing = key
            Task {
                let image = await CrystalSnapshot.image(scene, orientation: CrystalPaneModel.view(orientation), showsUnitCell: showsUnitCell,
                                                        pixels: pixels)
                if drawing == key {
                    drawn = (key, image.flatMap(AgentJSON.png))
                    drawing = nil
                }
            }
        }
        return .refusal(status: 409, message: "The crystal is being drawn; ask get_crystal_view with picture true again.")
    }
}
