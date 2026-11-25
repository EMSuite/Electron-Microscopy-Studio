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

    /// Why Use in Simulation does nothing for a measurement on `item`: its Simulation document simulates an atom model, whose
    /// thickness is the model's own slab (#953). The section and the door read this one.
    func useInSimulationRefusal(of item: OpenItem) -> String? {
        thicknessSimulation(of: item)?.multislice.atomModel != nil ? SimulationModel.modelThicknessSentence : nil
    }

    /// A CBED run of `simulation` as its settings stand: the key, the specimen with its name, and the zone's shortest reflection the
    /// edge must hold (none for an atom model); or why there is none, in the order a person fixes them: no phase or model, a refused
    /// specimen, no beam energy, no semiangle. The section, Show CBED Pattern and the door read this one.
    func cbedRun(of simulation: OpenItem) -> Result<CBEDRunInputs, CBEDRefusal> {
        let analysis = simulation.diffraction, model = simulation.multislice
        let crystal = analysis.simulatedPhase, zoneAxis = analysis.simulation.zoneAxis
        guard let source = model.sourceIdentity(crystal: crystal) else { return .failure(CBEDRefusal(sentence: "Add a phase to simulate.")) }
        let built: SimulationSpecimen.Built
        switch model.specimen(crystal: crystal, zoneAxis: zoneAxis) {
        case .failure(let refusal): return .failure(CBEDRefusal(sentence: refusal.sentence))
        case .success(let specimen): built = specimen
        }
        guard let volts = analysis.typedBeamKV.map({ $0 * 1000 }) else { return .failure(CBEDRefusal(sentence: "Type the beam energy to simulate.")) }
        let shortestG = cbedShortestG(of: simulation)
        guard let semiangle = simulation.cbed.semiangle(shortestG: shortestG, volts: volts) else {
            return .failure(CBEDRefusal(sentence: model.atomModel != nil ? SimulationModel.modelFitDiscsSentence
                                            : "Type the convergence semiangle: this zone has no reflection for Fit Discs."))
        }
        let key = simulation.cbed.key(source: source, zoneAxis: model.sourceZoneAxis(zoneAxis),
                                      maximumStrain: model.maximumStrain(crystal: crystal, zoneAxis: zoneAxis), volts: volts,
                                      semiangleMrad: semiangle)
        return .success(CBEDRunInputs(key: key, built: built, specimen: model.sourceName(crystal: crystal, zoneAxis: zoneAxis) ?? source,
                                      shortestG: shortestG))
    }

    /// The zero-order zone's shortest reflection, 1/Å, that Fit Discs keeps apart (`DiffractionAnalysis.shortestZeroOrderG`); nil
    /// while an atom model is the source: it has no reflection list, so Fit Discs refuses and the semiangle is the typed one (#953).
    func cbedShortestG(of simulation: OpenItem) -> Double? {
        guard simulation.multislice.atomModel == nil else { return nil }
        return simulation.diffraction.shortestZeroOrderG(image: simulation.session.imageOrBlank)
    }

    /// Why Show CBED Pattern cannot run for `simulation`: `cbedRun`'s refusal, an edge that cuts the discs off, another document's
    /// run. The section and the door read this one.
    func cbedBlocker(of simulation: OpenItem) -> String? {
        switch cbedRun(of: simulation) {
        case .failure(let refusal): return refusal.sentence
        case .success(let run):
            if let sentence = CBEDRun.edgeSentence(edgeMrad: simulation.cbed.settings.edgeMrad, semiangleMrad: run.key.semiangleMrad,
                                                   shortestG: run.shortestG, volts: run.key.volts) { return sentence }
            return simulation.cbed.blocker
        }
    }

    /// The plan of a run of `simulation`'s CBED settings before it runs (the box the angular step needs); nil while there is no
    /// specimen or beam energy.
    func cbedPlan(of simulation: OpenItem) -> CBEDRun.Plan? {
        let analysis = simulation.diffraction
        guard let volts = analysis.typedBeamKV.map({ $0 * 1000 }),
              case .success(let built) = simulation.multislice.specimen(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis)
        else { return nil }
        return try? CBEDRun.plan(built, settings: simulation.cbed.settings, volts: volts)
    }

    /// Runs the probe for `simulation`'s specimen (the atom model, else the phase down its axis) and settings at the document's beam
    /// energy, then draws the pattern into its item.
    func computeCBEDPattern(of simulation: OpenItem) async {
        // The section disables Show CBED Pattern and says why for each refusal (`cbedBlocker`).
        guard case .success(let run) = cbedRun(of: simulation) else { return }
        await simulation.cbed.update(run.key, built: run.built, specimen: run.specimen, shortestG: run.shortestG)
        refreshCBEDPattern(of: simulation, inPlaneDegrees: run.built.inPlaneAngle * 180 / .pi)
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
    /// axis, beam and the slab's turn on the item's overlay. An atom model's pattern has no overlay: its spots and hkl labels would be
    /// the phase's (`SimulationModel.modelLabelsSentence`, #953). Nothing while either is missing or before the first run.
    func refreshCBEDPattern(of simulation: OpenItem, inPlaneDegrees: Double? = nil) {
        let url = DemoDocuments.cbedURL(of: simulation.url)
        guard let held = pairedItem(at: url), let image = simulation.cbed.image(name: url.lastPathComponent) else { return }
        let source = simulation.diffraction, target = held.item.diffraction
        target.typedBeamKV = source.typedBeamKV
        if simulation.multislice.atomModel != nil {
            target.simulation.isShown = false
        } else {
            if target.crystal != source.crystal { target.setCrystal(source.crystal) }
            if target.simulation.zoneAxis != source.simulation.zoneAxis { target.setZoneAxis(source.simulation.zoneAxis) }
            if let inPlaneDegrees { target.setTurn(degrees: inPlaneDegrees) }
            target.simulation.isShown = true
        }
        let canvas = Self.canvas(for: image)
        held.state.openItems.showComputed(held.item, OpenedImage(image: image, canvas: canvas, metadata: AcquisitionMetadata(),
                                                                 url: held.item.url,
                                                                 thumbnail: canvas.thumbnail(maxSide: Thumbnail.defaultMaxSide),
                                                                 bookmark: nil))
    }
}

/// What a CBED run is made of (`AppState.cbedRun`).
struct CBEDRunInputs {
    let key: CBEDModel.RunKey
    let built: SimulationSpecimen.Built
    /// The name the pattern carries: the phase down its axis, or the model along its beam axis.
    let specimen: String
    /// The zone's shortest reflection, 1/Å, the edge must hold; nil for an atom model.
    let shortestG: Double?
}

/// Why a CBED run cannot start, in the room's words.
struct CBEDRefusal: Error, Equatable {
    let sentence: String
}
