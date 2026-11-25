//
//  DemoData.swift
//  Role: Help > Open Demo Data and the welcome canvas's Try Demo Data. The generated demo documents (TEMSession's DemoDocuments) and
//        the shipped ones (`DemoDocuments.Shipped`, real licensed files in the bundle) opened from the menu, so anyone without a
//        microscope file, App Review first, can try every room (macTEM#105). The generated SEM image is written to the temporary
//        folder and opened as a file, so the Image room's SEM header and databar crop can be tried too. The launch options for the
//        UI tests open the same documents through `openDemo`, so the menu and the tests cannot drift apart.
//

import DiffractoCore
import Foundation
import TEMSession
import ShellEDXModel
import ShellSpectroscopy

nonisolated enum DemoDocument: String, CaseIterable, Identifiable, Sendable {
    case lattice, diffraction, edx, eels
    /// The generated SEM image (`DemoDocuments.semImageFile`: a Thermo-style TIFF with its header and a databar), written to the
    /// temporary folder and opened through the app's own Open like a file from disk, into the Image room.
    case semImage
    /// The shipped SEM-EDS spectrum (`DemoDocuments.Shipped.semEDSSpectrum`), opened through the app's own Open like a file from disk.
    case semSpectrum
    /// The shipped nickel EBSD scan (`DemoDocuments.Shipped.nickelEBSD`), opened through the app's own Open into the Patterns room.
    case ebsd
    /// The shipped two-phase orientation map (`DemoDocuments.Shipped.duplexSteelMap`), opened through the app's own Open into the Maps room.
    case orientationMap
    /// The shipped recorded spot pattern (`DemoDocuments.Shipped.nanowirePattern`, #804), opened through the app's own Open and shown in
    /// the Diffraction room.
    case spotPattern
    /// File > New Simulation with the shipped silicon CIF as its crystal (`DemoDocuments.Shipped.siliconCIF`, #804): simulated spots of
    /// silicon, with no measured pattern, in the Diffraction room.
    case siliconSimulation

    var id: String { rawValue }

    /// The menu title: what the document is, then the room it opens in.
    var title: String {
        switch self {
        case .lattice: "Lattice Image"
        case .diffraction: "Au Diffraction Pattern"
        case .edx: "EDX Spectrum Image"
        case .eels: "EELS Spectrum Image"
        case .semImage: "SEM Image (generated)"
        case .semSpectrum: DemoDocuments.Shipped.semEDSSpectrum.title
        case .ebsd: DemoDocuments.Shipped.nickelEBSD.title
        case .orientationMap: DemoDocuments.Shipped.duplexSteelMap.title
        case .spotPattern: DemoDocuments.Shipped.nanowirePattern.title
        case .siliconSimulation: DemoDocuments.Shipped.siliconCIF.title
        }
    }

    /// The room the document is shown in once open.
    var room: WorkspaceArea {
        switch self {
        case .lattice, .semImage: .image
        case .diffraction, .spotPattern, .siliconSimulation: .diffraction
        case .edx, .semSpectrum: .edx
        case .eels: .eels
        case .ebsd: .patterns
        case .orientationMap: .maps
        }
    }
}

extension AppState {
    /// Opens one demo document and shows its room. `regions` draws the UI tests' two rectangles and line on a
    /// spectrum image (`--demo-regions`); the menu never does. Returns the open's task (the images and the shipped files
    /// load like a file); the generated spectrum images bind at once.
    @discardableResult
    func openDemo(_ demo: DemoDocument, regions: Bool = false) -> Task<Void, Never>? {
        var task: Task<Void, Never>?
        switch demo {
        case .lattice:
            task = open(urls: [DemoDocuments.latticeURL])
        case .diffraction:
            task = open(urls: [DemoDocuments.patternURL])
        case .edx:
            edx.bind(DemoDocuments.edx())
            if regions { DemoDocuments.drawRegions(on: edx) }
        case .eels:
            guard let loaded = try? DemoDocuments.eels() else { return nil }
            eels.bind(loaded)
            if regions { DemoDocuments.drawRegions(on: eels) }
        case .semImage:
            // The file just written, through the Open route (`FileRouting`: a TIFF lands in the Image room, its SEM header read).
            guard let url = try? DemoDocuments.semImageFile() else { return nil }
            task = open(urls: [url])
        case .semSpectrum:
            // The file in the bundle, through the Open route (`FileRouting`: a `.hspy` of one spectrum lands in the EDS room).
            guard let url = DemoDocuments.Shipped.semEDSSpectrum.url else { return nil }
            task = open(urls: [url])
        case .ebsd:
            // The file in the bundle, through the Open route (`FileRouting`: an h5ebsd file lands in the Patterns room).
            guard let url = DemoDocuments.Shipped.nickelEBSD.url else { return nil }
            task = open(urls: [url])
        case .orientationMap:
            // The file in the bundle, through the Open route (`FileRouting`: an `.ang` without patterns lands in the Maps room).
            guard let url = DemoDocuments.Shipped.duplexSteelMap.url else { return nil }
            task = open(urls: [url])
        case .spotPattern:
            // The file in the bundle, through the Open route (`FileRouting`: a `.hspy` of one 2D signal is an image, which the
            // Diffraction room shows).
            guard let url = DemoDocuments.Shipped.nanowirePattern.url else { return nil }
            task = open(urls: [url])
        case .siliconSimulation:
            // New Simulation's own call, then the shipped CIF as the room's crystal, as Open CIF… would set it.
            guard let url = DemoDocuments.Shipped.siliconCIF.url, let bytes = try? Data(contentsOf: url),
                  let silicon = try? CrystalLoading.load(bytes: bytes, fileName: url.lastPathComponent) else { return nil }
            let opening = newSimulation()
            task = Task {
                await opening?.value
                if let item = openItems.selected, DemoDocuments.isSimulation(item.url) { item.diffraction.setCrystal(.cif(silicon)) }
            }
        }
        navigation.workspaceArea = demo.room
        return task
    }
}

extension AppState {
    /// The Au {111} annulus of the generated demo pattern, px: about R = sqrt(3) / (a Δq) = 33.98 (`DemoDocuments.Truth`) and short of
    /// {200} at 39.24, the annulus the app's own calibration tests fit on (DiffractionAnalysisTests and the others: 29 to 37).
    static let demoPatternAnnulus = (inner: 29.0, outer: 37.0)

    /// The Au demo pattern lands in the Diffraction room, ready for Calibrate on Ring (#1025): selected, its annulus on Au {111}
    /// (the room's standard and ring at their defaults, Au and {111}), the room in front. Called by the Open itself, as
    /// `landSimulation` is, so the pattern lands there in this window and in a tab of its own (a window that holds a document opens
    /// the demo in a new tab, whose room started in Image).
    func landDemoPattern(_ made: [(id: OpenItem.ID, url: URL)]) {
        guard let pattern = made.first(where: { $0.url == DemoDocuments.patternURL }), let item = openItems.item(pattern.id) else { return }
        if openItems.selected?.id != item.id { openItems.select(item.id) }
        if item.diffraction.rings.isEmpty {
            item.diffractionView.setAnnulus(inner: Self.demoPatternAnnulus.inner, outer: Self.demoPatternAnnulus.outer)
        }
        selectWorkspace(.diffraction)
    }
}
