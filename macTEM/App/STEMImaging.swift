//
//  STEMImaging.swift
//  Role: a Simulation document's STEM image in the Image room (#913, plan row MA10). The image is an item of its own, "STEM of
//        Simulation 1" (`DemoDocuments.stemURL`), as the HRTEM image is (SimulationImaging.swift), so the Image, FFT and Profile tools
//        work on it. The document's `STEMModel` holds the run; every slice that lands, and every move of the band, redraws the item's
//        pixels (`OpenItems.showComputed`). Nothing here makes a number.
//

import FormatoCore
import Foundation
import ImagoCore
import TEMCore
import TEMSession

extension AppState {
    /// The Simulation document a STEM item belongs to, while it is open in any window.
    func simulationDocument(ofSTEM item: OpenItem) -> OpenItem? {
        guard DemoDocuments.isSTEM(item.url) else { return nil }
        return pairedItem(at: DemoDocuments.simulationURL(ofSTEM: item.url))?.item
    }

    /// The Simulation document whose STEM scan runs: the selected STEM image's (its document may sit in another window), else one of
    /// this window's. The Image room's busy line, its Stop and ⌘. read it (#1047).
    var scanningSTEMDocument: OpenItem? {
        if let item = openItems.selected, let document = simulationDocument(ofSTEM: item), document.stem.isRunning { return document }
        return openItems.items.first { $0.stem.isRunning }
    }

    /// Show STEM Image: opens (or brings forward) the image of `simulation` in the Image room, here or in a tab of its own. The run
    /// is the image's toolbar Simulate (#1047): a STEM scan takes minutes, so opening the image does not start one.
    func showSTEMImage(of simulation: OpenItem) {
        let url = DemoDocuments.stemURL(of: simulation.url)
        if let held = pairedItem(at: url) {
            held.state.openItems.select(held.item.id)
            held.state.selectWorkspace(.image)
            held.state.showWindow?()
            refreshSTEMImage(of: simulation)
        } else {
            _ = open(urls: [url])
        }
    }

    /// Why the probe wraps onto its own copies in `simulation`'s box (`STEMImage.wrapSentence`), for the run of the settings now.
    func stemWrapSentence(of simulation: OpenItem) -> String? {
        guard case .success(let run) = stemRun(of: simulation) else { return nil }
        let box = run.built.slabBox
        return STEMImage.wrapSentence(thicknessNM: box.z / 10, boxAngstrom: min(box.x, box.y),
                                      semiangleMrad: simulation.stem.settings.semiangleMrad, volts: run.key.volts)
    }

    /// The run's key for `simulation`'s specimen (the atom model when one is open, else the phase), optics and vibrations now, with
    /// the specimen built at least 20 Å across; or why there is none, in the room's words.
    func stemRun(of simulation: OpenItem) -> Result<(key: STEMModel.RunKey, built: SimulationSpecimen.Built, specimen: String), STEMRefusal> {
        let analysis = simulation.diffraction, model = simulation.multislice
        let crystal = analysis.simulatedPhase
        guard let source = model.sourceIdentity(crystal: crystal) else { return .failure(STEMRefusal(sentence: "Add a phase to simulate.")) }
        guard let kV = analysis.typedBeamKV else { return .failure(STEMRefusal(sentence: "Type the beam energy to simulate.")) }
        let zoneAxis = analysis.simulation.zoneAxis
        switch model.thermalSpecimen(crystal: crystal, zoneAxis: zoneAxis) {
        case .failure(let refusal): return .failure(STEMRefusal(sentence: refusal.sentence))
        case .success(let built):
            let key = simulation.stem.key(source: source, zoneAxis: model.sourceZoneAxis(zoneAxis), thicknessNM: model.thicknessNM,
                                          maximumStrain: model.maximumStrain(crystal: crystal, zoneAxis: zoneAxis), volts: kV * 1000,
                                          csMM: model.optics.csMM, thermal: model.thermal)
            return .success((key, built, model.sourceName(crystal: crystal, zoneAxis: zoneAxis) ?? source))
        }
    }

    /// Simulate (and Continue) for `simulation`'s STEM image, the image's toolbar verb, ⌘R and the door's run_stem (#1047): the run of the specimen, optics and vibrations now, the image redrawn
    /// as each slice lands. Returns when the run ends.
    func simulateSTEM(of simulation: OpenItem) async {
        guard case .success(let run) = stemRun(of: simulation) else { return }
        let model = simulation.stem
        let settings = model.settings, built = run.built, specimen = run.specimen
        let csMM = simulation.multislice.optics.csMM, thermal = simulation.multislice.thermal, volts = run.key.volts
        await model.simulate(run.key, prepare: {
            try STEMImage.prepare(built, settings: settings, csMM: csMM, volts: volts, thermal: thermal, specimen: specimen)
        }, landed: { [weak self] in self?.refreshSTEMImage(of: simulation) })
        refreshSTEMImage(of: simulation)
    }

    /// After an Open's items have landed: a STEM image among them is selected in the Image room and drawn from its document's run
    /// when there is one.
    func landSTEM(_ made: [(id: OpenItem.ID, url: URL)]) {
        guard let made = made.first(where: { DemoDocuments.isSTEM($0.url) }), let item = openItems.item(made.id) else { return }
        if openItems.selected?.id != item.id { openItems.select(item.id) }
        selectWorkspace(.image)
        if let simulation = simulationDocument(ofSTEM: item) { refreshSTEMImage(of: simulation) }
    }

    /// Puts the image of `simulation`'s run, for its band at the HRTEM field of view, into its STEM item, in whichever window holds
    /// it: the placeholder while a new run has no position yet, so the last run's image never stands for this one. Nothing while
    /// the band gives no image (the section says why: `STEMModel.bandRefusal`) or the item is closed.
    func refreshSTEMImage(of simulation: OpenItem) {
        let url = DemoDocuments.stemURL(of: simulation.url)
        guard let held = pairedItem(at: url) else { return }
        let image: CalibratedImage
        if simulation.stem.scan?.isEmpty == true {
            image = DemoDocuments.hrtemPlaceholder(name: url.lastPathComponent)
        } else if case .success(let drawn)? = simulation.stem.image(fieldOfViewNM: simulation.multislice.optics.fieldOfViewNM,
                                                                     name: url.lastPathComponent) {
            image = drawn
        } else {
            return
        }
        let canvas = Self.canvas(for: image)
        held.state.openItems.showComputed(held.item, OpenedImage(image: image, canvas: canvas, metadata: AcquisitionMetadata(), url: url,
                                                                 thumbnail: canvas.thumbnail(maxSide: Thumbnail.defaultMaxSide),
                                                                 bookmark: nil))
    }
}

/// Why a STEM run cannot start, in the room's words.
struct STEMRefusal: Error, Equatable {
    let sentence: String
}
