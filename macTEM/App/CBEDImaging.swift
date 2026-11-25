//
//  CBEDImaging.swift
//  Role: a Simulation document's CBED pattern in the Diffraction room (#912, plan row MA9). The pattern is an item of its own,
//        "CBED of Simulation 1" (`DemoDocuments.cbedURL`), as the HRTEM image is (SimulationImaging.swift): the room's tools (Spot,
//        Ring, Index, Export) and its kinematic overlay work on the discs as on a measured pattern. The document's `CBEDModel` holds
//        the stored patterns; every move of the thickness replaces the item's pixels (`OpenItems.showComputed`). The item takes the
//        document's phase, zone axis and beam energy, and the overlay's turn is the slab's, so the hkl labels sit on the discs.
//        Nothing here makes a number.
//

import FormatoCore
import Foundation
import ImagoCore
import TEMCore
import TEMSession

extension AppState {
    /// The Simulation document a CBED item belongs to, while it is open in any window.
    func simulationDocument(ofCBED item: OpenItem) -> OpenItem? {
        guard DemoDocuments.isCBED(item.url) else { return nil }
        return pairedItem(at: DemoDocuments.simulationURL(ofCBED: item.url))?.item
    }

    /// Show CBED Pattern: opens (or brings forward) the pattern of `simulation`, here or in a tab of its own, and runs the probe for
    /// it; its pixels land when the patterns are computed. Returns the task that ends when both are done.
    @discardableResult
    func showCBEDPattern(of simulation: OpenItem) -> Task<Void, Never>? {
        let url = DemoDocuments.cbedURL(of: simulation.url)
        let opening: Task<Void, Never>?
        if let held = pairedItem(at: url) {
            held.state.openItems.select(held.item.id)
            held.state.selectWorkspace(.diffraction)
            held.state.showWindow?()
            opening = nil
        } else {
            opening = open(urls: [url])
        }
        return Task {
            await opening?.value
            await computeCBEDPattern(of: simulation)
        }
    }

    /// The Simulation document whose thickness Use in Simulation sets for a measurement on `item`: `item` itself, or the document
    /// its CBED pattern belongs to; nil for a measured file.
    func thicknessSimulation(of item: OpenItem) -> OpenItem? {
        DemoDocuments.isSimulation(item.url) ? item : simulationDocument(ofCBED: item)
    }

    /// Why Show CBED Pattern cannot run for `simulation`, in the order a person fixes them: no phase, a refused specimen, no beam
    /// energy, no semiangle, an edge that cuts the discs off, another document's run. The section and the door read this one.
    func cbedBlocker(of simulation: OpenItem) -> String? {
        let analysis = simulation.diffraction
        guard let phase = analysis.simulatedPhase else { return "Add a phase to simulate." }
        if case .failure(let refusal) = simulation.multislice.specimen(crystal: phase, zoneAxis: analysis.simulation.zoneAxis) { return refusal.sentence }
        guard let volts = analysis.typedBeamKV.map({ $0 * 1000 }) else { return "Type the beam energy to simulate." }
        let shortestG = analysis.shortestZeroOrderG(image: simulation.session.imageOrBlank)
        guard let semiangle = simulation.cbed.semiangle(shortestG: shortestG, volts: volts) else {
            return "Type the convergence semiangle: this zone has no reflection for Fit Discs."
        }
        if let sentence = CBEDRun.edgeSentence(edgeMrad: simulation.cbed.settings.edgeMrad, semiangleMrad: semiangle,
                                               shortestG: shortestG, volts: volts) { return sentence }
        return simulation.cbed.blocker
    }

    /// The plan of a run of `simulation`'s CBED settings before it runs (the box the angular step needs); nil while there is no
    /// specimen or beam energy.
    func cbedPlan(of simulation: OpenItem) -> CBEDRun.Plan? {
        let analysis = simulation.diffraction
        guard let volts = analysis.typedBeamKV.map({ $0 * 1000 }), let phase = analysis.simulatedPhase,
              case .success(let built) = simulation.multislice.specimen(crystal: phase, zoneAxis: analysis.simulation.zoneAxis) else { return nil }
        return try? CBEDRun.plan(built, settings: simulation.cbed.settings, volts: volts)
    }

    /// Runs the probe for `simulation`'s crystal, axis and settings at the document's beam energy, then draws the pattern into its item.
    func computeCBEDPattern(of simulation: OpenItem) async {
        let analysis = simulation.diffraction
        // The section disables Show CBED Pattern and says why for each of these (no phase, no beam energy, a refused specimen).
        let shortestG = analysis.shortestZeroOrderG(image: simulation.session.imageOrBlank)
        guard let crystal = analysis.simulatedPhase, let volts = analysis.typedBeamKV.map({ $0 * 1000 }),
              case .success(let built) = simulation.multislice.specimen(crystal: crystal, zoneAxis: analysis.simulation.zoneAxis),
              let semiangle = simulation.cbed.semiangle(shortestG: shortestG, volts: volts) else { return }
        let zoneAxis = analysis.simulation.zoneAxis
        let key = simulation.cbed.key(crystal: crystal, zoneAxis: zoneAxis,
                                      maximumStrain: simulation.multislice.maximumStrain(crystal: crystal, zoneAxis: zoneAxis),
                                      volts: volts, semiangleMrad: semiangle)
        await simulation.cbed.update(key, built: built, specimen: "\(crystal.name) \(ZoneAxisText.text(zoneAxis))", shortestG: shortestG)
        refreshCBEDPattern(of: simulation, inPlaneDegrees: built.inPlaneAngle * 180 / .pi)
    }

    /// After an Open's items have landed: a CBED item among them is selected in the Diffraction room with its document's phase,
    /// axis and beam, and drawn from the stored patterns when they exist. Nothing for an Open with no CBED item.
    @discardableResult
    func landCBED(_ made: [(id: OpenItem.ID, url: URL)]) -> Task<Void, Never>? {
        guard let made = made.first(where: { DemoDocuments.isCBED($0.url) }), let item = openItems.item(made.id) else { return nil }
        if openItems.selected?.id != item.id { openItems.select(item.id) }
        selectWorkspace(.diffraction)
        guard let simulation = simulationDocument(ofCBED: item) else { return nil }
        return Task { await computeCBEDPattern(of: simulation) }
    }

    /// Puts the shown stored pattern of `simulation` into its CBED item, in whichever window holds it, with the document's phase, zone
    /// axis, beam and the slab's turn on the item's overlay. Nothing while either is missing or before the first run.
    func refreshCBEDPattern(of simulation: OpenItem, inPlaneDegrees: Double? = nil) {
        let url = DemoDocuments.cbedURL(of: simulation.url)
        guard let held = pairedItem(at: url), let image = simulation.cbed.image(name: url.lastPathComponent) else { return }
        let source = simulation.diffraction, target = held.item.diffraction
        if target.crystal != source.crystal { target.setCrystal(source.crystal) }
        if target.simulation.zoneAxis != source.simulation.zoneAxis { target.setZoneAxis(source.simulation.zoneAxis) }
        if let inPlaneDegrees { target.setTurn(degrees: inPlaneDegrees) }
        target.typedBeamKV = source.typedBeamKV
        target.simulation.isShown = true
        let canvas = Self.canvas(for: image)
        held.state.openItems.showComputed(held.item, OpenedImage(image: image, canvas: canvas, metadata: AcquisitionMetadata(),
                                                                 url: held.item.url,
                                                                 thumbnail: canvas.thumbnail(maxSide: Thumbnail.defaultMaxSide),
                                                                 bookmark: nil))
    }
}
