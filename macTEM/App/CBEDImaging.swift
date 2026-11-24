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
