//
//  NewSimulation.swift
//  Role: File > New Simulation (⇧⌘N, #788): a diffraction pattern simulated with no measured pattern, the thin slice of the 2.3
//        Simulation document. It opens through the app's own Open, as the demos do (`DemoDocuments.simulationURL`, answered from
//        memory by an empty canvas with a scale and a beam energy), so one file per window holds: a window that already holds a file
//        gives the simulation a tab of its own. Once the item has landed, the window shows the Diffraction room with the simulated
//        spots on (`landSimulation`) and the Add Phase sheet in front, and every tool there works on it as on a measured pattern: the
//        zone axis, the phase, the Spots table, Export Spots… and Export Image…. Until a phase is shown the pattern is an empty state
//        with the one button Add Phase… (`SimulationEmptyState`, #907).
//

import Foundation
import TEMCore
import TEMSession

extension AppState {
    /// The simulations made in this launch, across windows: each New Simulation takes the next number.
    private static var simulationsMade = 0

    /// File > New Simulation: opens the next simulation, here or in a tab of its own. Returns the open's task.
    @discardableResult
    func newSimulation() -> Task<Void, Never>? {
        open(urls: [Self.nextSimulationURL()])
    }

    /// The next simulation's document ("Simulation 1", "Simulation 2", …): New Simulation's, and a reopened session file's (#908).
    static func nextSimulationURL() -> URL {
        simulationsMade += 1
        return DemoDocuments.simulationURL(simulationsMade)
    }

    /// After an Open's items have landed: a simulation among them is selected, its beam energy typed, its simulated spots shown, and
    /// the window goes to the Diffraction room. Nothing for an Open with no simulation.
    func landSimulation(_ made: [(id: OpenItem.ID, url: URL)]) {
        guard let simulation = made.first(where: { DemoDocuments.isSimulation($0.url) }),
              let item = openItems.item(simulation.id) else { return }
        if openItems.selected?.id != item.id { openItems.select(item.id) }
        // A reopened session file (#908): its phase and settings first, so what follows keeps them.
        SimulationSessions.landReopened(item)
        // The beam energy is typed, not the file's, so the Calibration section changes it: 200 kV to start, the demo pattern's.
        if item.diffraction.typedBeamKV == nil { item.diffraction.typedBeamKV = DemoDocuments.Truth.patternVolts / 1000 }
        item.diffraction.simulation.isShown = true
        // The Add Phase sheet in front (#788): a simulation needs a phase. Cancel leaves the empty pattern with its one button
        // (`SimulationEmptyState`); a document that already holds a phase opens without it.
        if item.diffraction.simulatedPhase == nil { item.diffractionView.isAddingPhase = true }
        selectWorkspace(.diffraction)
    }
}
