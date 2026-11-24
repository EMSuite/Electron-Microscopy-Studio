//
//  SimulationImaging.swift
//  Role: a Simulation document's HRTEM image in the Image room (#894, plan row MA2). The image is an item of its own,
//        "HRTEM of Simulation 1" (`DemoDocuments.hrtemURL`), so FFT, Profile and the scale bar work on it as on any image; the
//        document's `SimulationModel` holds the exit waves, and every move of Defocus or Thickness replaces the item's pixels with
//        the image made from them (`OpenItems.showComputed`). Nothing here makes a number.
//
//        One file per window: the image opens through the app's own Open, so a window that holds its Simulation document gives the
//        image a tab of its own (`AppWindows.openInTabs`). The pair is found across the windows on screen (`pairedItem`), both ways,
//        so the image tab draws from the document's model wherever each one is; the tab that receives the image lands on it in the
//        Image room (`landHRTEM`). Show HRTEM Image runs the multislice itself, so the image computes with the inspector hidden.
//
//        Departure from the design's "images appear in Imaging from the same document": one item is one picture in this app (its
//        pixels, marks and FFT), so the image is a second item, in the tab the app already makes, that names its document.
//

import FormatoCore
import Foundation
import ImagoCore
import TEMCore
import TEMSession

extension AppState {
    /// The open item at `url` in this window or in another window on screen, with the window's state.
    private func pairedItem(at url: URL) -> (state: AppState, item: OpenItem)? {
        let states = [self] + (windows?.onScreen.filter { $0 !== self } ?? [])
        for state in states {
            if let item = state.openItems.items.first(where: { $0.url == url }) { return (state, item) }
        }
        return nil
    }

    /// The Simulation document an HRTEM item belongs to, while it is open in any window.
    func simulationDocument(ofHRTEM item: OpenItem) -> OpenItem? {
        guard DemoDocuments.isHRTEM(item.url) else { return nil }
        return pairedItem(at: DemoDocuments.simulationURL(ofHRTEM: item.url))?.item
    }

    /// The HRTEM item of a Simulation document, while it is open in any window.
    func hrtemItem(of simulation: OpenItem) -> OpenItem? {
        pairedItem(at: DemoDocuments.hrtemURL(of: simulation.url))?.item
    }

    /// Show HRTEM Image: opens (or brings forward) the image of `simulation`, here or in a tab of its own, and runs the multislice
    /// for it; its pixels land when the exit waves are computed. Returns the task that ends when both are done.
    @discardableResult
    func showHRTEMImage(of simulation: OpenItem) -> Task<Void, Never>? {
        let url = DemoDocuments.hrtemURL(of: simulation.url)
        let opening: Task<Void, Never>?
        if let held = pairedItem(at: url) {
            held.state.openItems.select(held.item.id)
            held.state.selectWorkspace(.image)
            held.state.showWindow?()
            opening = nil
        } else {
            opening = open(urls: [url])
        }
        return Task {
            await opening?.value
            await computeHRTEMImage(of: simulation)
        }
    }

    /// Runs the multislice for `simulation`'s specimen and optics at the document's beam energy, then draws the image into its item.
    func computeHRTEMImage(of simulation: OpenItem) async {
        let analysis = simulation.diffraction
        simulation.multislice.adoptVoltage(kV: analysis.typedBeamKV)
        await simulation.multislice.updateExitWaves(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis)
        await refreshHRTEMImage(of: simulation)?.value
    }

    /// After an Open's items have landed: an HRTEM image among them is selected in the Image room and drawn from its document's
    /// stored exit waves when they exist. Nothing for an Open with no HRTEM image.
    @discardableResult
    func landHRTEM(_ made: [(id: OpenItem.ID, url: URL)]) -> Task<Void, Never>? {
        guard let made = made.first(where: { DemoDocuments.isHRTEM($0.url) }), let item = openItems.item(made.id) else { return nil }
        if openItems.selected?.id != item.id { openItems.select(item.id) }
        selectWorkspace(.image)
        return simulationDocument(ofHRTEM: item).flatMap { refreshHRTEMImage(of: $0) }
    }

    /// Puts the image of `simulation`'s stored exit waves, at its defocus and thickness, into its HRTEM item, in whichever window
    /// holds it. The image, its canvas and its thumbnail are made off the main actor and moves coalesce (`SimulationModel.render`), so a dragged slider stays live
    /// at any field of view. Nothing while either is missing or before the first run. Returns the task that ends when the image is in.
    @discardableResult
    func refreshHRTEMImage(of simulation: OpenItem) -> Task<Void, Never>? {
        let url = DemoDocuments.hrtemURL(of: simulation.url)
        guard pairedItem(at: url) != nil else { return nil }
        return simulation.multislice.render(name: url.lastPathComponent, prepare: { image in
            let canvas = AppState.canvas(for: image)
            return OpenedImage(image: image, canvas: canvas, metadata: AcquisitionMetadata(), url: url,
                               thumbnail: canvas.thumbnail(maxSide: Thumbnail.defaultMaxSide), bookmark: nil)
        }, deliver: { [weak self] opened in
            guard let self, let held = self.pairedItem(at: url) else { return }
            held.state.openItems.showComputed(held.item, opened)
        })
    }
}
