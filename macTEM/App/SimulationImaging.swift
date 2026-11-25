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
//        Place Beside (#898) draws the pair into the same item: the measured image, open in any window, beside the simulation or with
//        it inset, at the measured nanometres per pixel (`HRTEMBeside`), so the item exports as one figure with one scale bar.
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
    func pairedItem(at url: URL) -> (state: AppState, item: OpenItem)? {
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

    /// The Simulation document of this window whose frozen-phonon run is going (one at a time on this Mac): the Image room's busy
    /// work, which ⌘. stops and quitting asks about.
    var simulatingDocument: OpenItem? { openItems.items.first { $0.multislice.isSimulating } }

    /// Simulate (and Continue, ⌘R in the Image room, and the door): runs the frozen-phonon configurations of `simulation` not yet
    /// stored, redrawing its HRTEM image as each one lands. Returns when the run ends (#896).
    func simulateHRTEM(of simulation: OpenItem) async {
        let analysis = simulation.diffraction
        simulation.multislice.adoptVoltage(kV: analysis.typedBeamKV)
        await simulation.multislice.simulate(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis,
                                             current: { [weak analysis] in (analysis?.simulatedPhase, analysis?.simulation.zoneAxis ?? .zero) }) {
            [weak self] in self?.refreshHRTEMImage(of: simulation)
        }
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

    /// The measured image Place Beside names, while it is open in any window, with the settings and one unit cell of the
    /// simulated image (nm, across its columns and down its rows: the lab frame's y and x); nil when Place Beside is off.
    func besideSnapshot(of simulation: OpenItem)
        -> (settings: HRTEMBeside, measured: CalibratedImage, cellNM: SIMD2<Double>, key: String?)? {
        let model = simulation.multislice, analysis = simulation.diffraction
        guard let settings = model.beside, let item = besideMeasuredItem(of: simulation), let measured = item.session.image,
              case .success(let built) = model.specimen(crystal: analysis.simulatedPhase, zoneAxis: analysis.simulation.zoneAxis)
        else { return nil }
        return (settings, measured, SIMD2(built.box.y / 10, built.box.x / 10), item.openedIdentity?.pixelSHA256)
    }

    /// What the pair reads of the measured image: its item, pixels and calibration. The section redraws when it changes (the file
    /// opened, closed, or read again).
    func besideKey(of simulation: OpenItem) -> String? {
        guard let item = besideMeasuredItem(of: simulation), let image = item.session.image else { return nil }
        return "\(item.id) \(item.openedIdentity?.pixelSHA256 ?? "") \(image.x?.scale ?? 0) \(image.x?.unit ?? "") \(image.y?.scale ?? 0) \(image.y?.unit ?? "")"
    }

    /// The open item Place Beside names for `simulation`, in any window.
    func besideMeasuredItem(of simulation: OpenItem) -> OpenItem? {
        simulation.multislice.beside.flatMap { pairedItem(at: $0.measured)?.item }
    }

    /// What Place Beside shows now, in the section's words: off, the measured image closed (and where its file is), its file not
    /// connected or different (#824), without a calibration, or the scale both are shown at (and whether the measured pixels are
    /// coarser than the simulation's). One source for the section and the door.
    enum BesideStatus: Equatable {
        case off
        /// Closed; the file, when its link found it, can be opened again.
        case closed(String, file: URL?)
        /// The link's line (not connected, on a server, or a different file found); `different` offers Link Anyway.
        case unlinked(String, different: Bool)
        case uncalibrated
        case shown(scale: String, coarser: Bool)

        /// The sentences the section shows.
        var lines: [String] {
            switch self {
            case .off: []
            case .closed(let name, _): ["\(name) is closed: the simulation shows alone."]
            case .unlinked(let line, _): [line]
            case .uncalibrated: [HRTEMBeside.uncalibrated]
            case let .shown(scale, coarser): [scale] + (coarser ? [HRTEMBeside.coarser] : []) + [HRTEMBeside.pairNote]
            }
        }
    }

    func besideStatus(of simulation: OpenItem) -> BesideStatus {
        guard let beside = simulation.multislice.beside else { return .off }
        guard let measured = besideMeasuredItem(of: simulation)?.session.image else {
            if let link = beside.link, let state = simulation.multislice.besideLinkState {
                if case .connected(let url) = state { return .closed(link.name, file: url) }
                if let line = state.line(for: link) {
                    if case .different = state { return .unlinked(line, different: true) }
                    return .unlinked(line, different: false)
                }
            }
            return .closed(beside.link?.name ?? beside.measured.lastPathComponent, file: nil)
        }
        guard let scale = HRTEMBeside.sameScaleLine(measured) else { return .uncalibrated }
        let coarser = simulation.multislice.exitWaves?.nanometresPerPixel.map { HRTEMBeside.isCoarser(measured, than: $0) } ?? false
        return .shown(scale: scale, coarser: coarser)
    }

    /// Place Beside names `item`: its URL while it is open, and the link a document keeps (name, size, fingerprint; never a path)
    /// with the app's bookmark for it (#824). The link is kept while the same file stays named. The section's and the door's one path.
    func besideNaming(_ item: OpenItem, in beside: HRTEMBeside?) -> HRTEMBeside {
        var new = beside ?? HRTEMBeside(measured: item.url)
        if beside?.measured != item.url || new.link == nil { new.link = LinkedFileGrants.link(to: item.url) }
        new.measured = item.url
        return new
    }

    /// Resolves Place Beside's link while its measured image is not open: through the app's bookmark, off the main actor, without
    /// interface or mounting, given `LinkedFiles.resolveSeconds`; a stale bookmark is kept renewed. The section then says what was
    /// found. Nothing while the image is open or the link is unknown.
    /// `system` and `defaults` are the app's; a test passes its own.
    func resolveBesideLink(of simulation: OpenItem, system: LinkedFileSystem = .securityScoped,
                           defaults: UserDefaults = .standard) async {
        guard let link = simulation.multislice.beside?.link, besideMeasuredItem(of: simulation) == nil else { return }
        let resolution = await LinkedFiles.resolve(link, bookmark: LinkedFileGrants.bookmark(for: link, defaults: defaults), system: system,
                                                   within: LinkedFiles.resolveSeconds)
        if let renewed = resolution.renewedBookmark { LinkedFileGrants.store(renewed, for: link, defaults: defaults) }
        simulation.multislice.setBesideLinkState(resolution.state, for: link)
    }

    /// Locate…: the person picks the measured image's file. The same contents link it again (a new bookmark) and open it beside
    /// the simulation; other contents are named as different and linked only with Link Anyway.
    func locateBesideLink(of simulation: OpenItem) async {
        guard let link = simulation.multislice.beside?.link, let picked = await LinkedFilePanels.locate(link, appState: self) else { return }
        let found = LinkedFiles.locate(link, picked: picked)
        if case .connected(let url) = found.state {
            LinkedFileGrants.store(found.bookmark, for: link)
            simulation.multislice.setBesideLinkState(found.state, for: link)
            await openBeside(of: simulation, at: url)
        } else {
            simulation.multislice.setBesideLinkState(found.state, for: link)
        }
    }

    /// Link Anyway: the different file found or picked becomes the measured image's file (the link takes its name, size and
    /// fingerprint, and a new bookmark), and opens beside the simulation.
    func linkBesideAnyway(of simulation: OpenItem) async {
        guard var beside = simulation.multislice.beside, let link = beside.link,
              case .different(let url) = simulation.multislice.besideLinkState,
              let relinked = LinkedFiles.relinked(link, to: url) else { return }
        LinkedFileGrants.store(relinked.bookmark, for: relinked.link)
        beside.link = relinked.link
        simulation.multislice.setBeside(beside)
        await openBeside(of: simulation, at: url)
    }

    /// Opens the measured image's file at `url` and names it as Place Beside's while it is open.
    func openBeside(of simulation: OpenItem, at url: URL) async {
        await open(urls: [url])?.value
        let path = url.standardizedFileURL.path
        let states = [self] + (windows?.onScreen.filter { $0 !== self } ?? [])
        guard var beside = simulation.multislice.beside,
              let item = states.flatMap(\.openItems.items).first(where: { $0.url.standardizedFileURL.path == path }) else { return }
        beside.measured = item.url
        if simulation.multislice.setBeside(beside) { refreshHRTEMImage(of: simulation) }
    }

    /// The images Place Beside can pick: every open image in the windows on screen that is not a simulation's and not a pattern
    /// (an image calibrated in a reciprocal length).
    func measuredImages() -> [OpenItem] {
        let states = [self] + (windows?.onScreen.filter { $0 !== self } ?? [])
        return states.flatMap(\.openItems.items).filter { item in
            guard !DemoDocuments.isSimulation(item.url), !DemoDocuments.isHRTEM(item.url), !DemoDocuments.isSTEM(item.url),
                  !DemoDocuments.isCBED(item.url), let image = item.session.image else { return false }
            return UnitDisplay.reciprocalAngstromsPerPixel(image.x) == nil
        }
    }

    /// Puts the image of `simulation`'s stored exit waves, at its defocus and thickness, into its HRTEM item, in whichever window
    /// holds it. The image, its canvas and its thumbnail are made off the main actor and moves coalesce (`SimulationModel.render`), so a dragged slider stays live
    /// at any field of view. Nothing while either is missing or before the first run. Returns the task that ends when the image is in.
    @discardableResult
    func refreshHRTEMImage(of simulation: OpenItem) -> Task<Void, Never>? {
        let url = DemoDocuments.hrtemURL(of: simulation.url)
        guard pairedItem(at: url) != nil else { return nil }
        let beside = besideSnapshot(of: simulation)
        return simulation.multislice.render(name: url.lastPathComponent, prepare: { simulated in
            // Place Beside: the pair as one picture; the simulation alone when the measured image is closed or has no calibration
            // (the section says which).
            let image = beside.flatMap {
                try? $0.settings.composite(simulated: simulated, measured: $0.measured, cellNM: $0.cellNM, measuredKey: $0.key)
            } ?? simulated
            let canvas = AppState.canvas(for: image)
            return OpenedImage(image: image, canvas: canvas, metadata: AcquisitionMetadata(), url: url,
                               thumbnail: canvas.thumbnail(maxSide: Thumbnail.defaultMaxSide), bookmark: nil)
        }, deliver: { [weak self] opened in
            guard let self, let held = self.pairedItem(at: url) else { return }
            held.state.openItems.showComputed(held.item, opened)
        })
    }
}
