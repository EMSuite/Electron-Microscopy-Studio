//
//  DemoDocumentsTests.swift
//  The generated demo documents the UI journeys open (`DemoDocuments`, TEMSession) and the launch arguments that open them
//  (`LaunchOptions`, App): their planted truth is pinned here, so a changed constant is a deliberate fixture move.
//

import XCTest
import ImagoCore
import SpectroCore
import SpectroEELS
import SpectroEDX
import TEMCore
import TEMSession
@testable import macTEM
import ShellEDXModel

nonisolated final class DemoDocumentsTests: XCTestCase {

    /// The lattice: 512 x 512 at 0.0123 nm/px, deterministic (two calls equal), named, flagged as generated, and its brightest column
    /// pattern repeats at the planted period. Red under: a different size, calibration or seed; the period moved.
    func testTheLatticeIsDeterministicAndHasThePlantedPeriod() throws {
        let a = DemoDocuments.lattice(), b = DemoDocuments.lattice()
        XCTAssertEqual(a, b, "a fixed seed: the same pixels every time")
        XCTAssertEqual(a.width, 512); XCTAssertEqual(a.height, 512)
        XCTAssertEqual(a.fileName, "Demo lattice")
        XCTAssertEqual(a.x, AxisCalibration(scale: 0.0123, unit: "nm")); XCTAssertEqual(a.y, a.x)
        XCTAssertTrue(a.notes.contains { $0.contains("not data") })
        // The mean of each column over the rows free of the discs: its autocorrelation peaks at the planted period (19.1 px).
        var column = [Double](repeating: 0, count: 512)
        for x in 0..<512 { for y in 200..<300 { column[x] += Double(a.pixels[y * 512 + x]) } }
        let mean = column.reduce(0, +) / 512
        let centred = column.map { $0 - mean }
        func r(_ lag: Int) -> Double { (0..<(512 - lag)).reduce(0) { $0 + centred[$1] * centred[$1 + lag] } }
        let best = (15...24).max { r($0) < r($1) }
        XCTAssertEqual(best, 19, "0.235 nm / 0.0123 nm per pixel = 19.1 px")
    }

    /// The EDX demo is 16 x 16 x 2048 at 10 eV with the beam stated, deterministic, and Auto ID through the room finds the planted
    /// Mg and Si besides the Al; quantifying lists them. Red under: the line areas or the continuum changed so that a planted element is lost.
    @MainActor func testTheEDXDemoIsFoundByAutoID() async throws {
        let demo = DemoDocuments.edx()
        XCTAssertEqual(demo.metadata.scanWidth, 16); XCTAssertEqual(demo.metadata.channelCount, 2048)
        XCTAssertEqual(demo.metadata.beamEnergyKeV, 200)
        XCTAssertEqual(demo.energyAxis.scale, 0.01, accuracy: 1e-12)
        XCTAssertEqual(DemoDocuments.edx().image.sum(mask: nil), demo.image.sum(mask: nil), "deterministic")
        let session = EDXSession(host: .macTEM)
        await session.bind(demo).value
        await session.settled()
        let picked = Set(session.picks.map(\.symbol))
        XCTAssertTrue(picked.isSuperset(of: ["Al", "Mg", "Si"]), "Auto ID picked \(picked)")
        await session.quantify()?.value
        await session.settled()
        let fit = try XCTUnwrap(session.fit, session.fitFailure ?? "no fit")
        for e in ["Al", "Mg", "Si"] { XCTAssertNotNil(fit.rows.first { $0.element == e }?.weightPercent, e) }
        // Al is the matrix: far above Mg and Si over the whole map, as planted (about 120 : 40 : 47 counts per pixel on average).
        let wt = Dictionary(uniqueKeysWithValues: fit.rows.compactMap { r in r.weightPercent.map { (r.element, $0) } })
        XCTAssertGreaterThan(try XCTUnwrap(wt["Al"]), try XCTUnwrap(wt["Si"]))
        XCTAssertGreaterThan(try XCTUnwrap(wt["Si"]), try XCTUnwrap(wt["Mg"]))
    }

    /// The EELS demo recovers the planted t/λ at every pixel through the room with a fixed threshold, 0.5 above the interface across the
    /// middle and 0.8 below it, so the t/λ map shows two halves; and through the default (estimated) rule within the kit's stated bias.
    /// Red under: the plasmon or the zero-loss area moved; a map flat over the scan (the uniform demo before, a plain grey map).
    @MainActor func testTheEELSDemoRecoversThePlantedThickness() async throws {
        let session = EELSSession()
        await session.bind(try DemoDocuments.eels()).value
        session.setThreshold(.fixed(DemoDocuments.Truth.eelsThresholdEV))
        await session.settled()
        let map = try XCTUnwrap(session.map, session.failure ?? "no map")
        XCTAssertEqual(map.pixels.count, 256)
        let side = DemoDocuments.Truth.eelsSide
        for (k, p) in map.pixels.enumerated() {
            XCTAssertEqual(try XCTUnwrap(p.tOverLambda), DemoDocuments.Truth.eelsTOverLambda(x: k % side, y: k / side), accuracy: 2e-3,
                           "pixel \(k): the fixed 4 eV threshold leaves a plasmon tail of about 1e-4 in I_0")
        }
        XCTAssertEqual(DemoDocuments.Truth.eelsTOverLambda(x: 3, y: 2), 0.5)
        XCTAssertEqual(DemoDocuments.Truth.eelsTOverLambda(x: 3, y: 12), 0.8)
        let above = try XCTUnwrap(map.pixels[2 * side + 3].tOverLambda), below = try XCTUnwrap(map.pixels[12 * side + 3].tOverLambda)
        XCTAssertGreaterThan(below - above, 0.25, "the map is not flat: the lower half is thicker")
        session.setThreshold(.estimated)
        await session.settled()
        let estimated = try XCTUnwrap(session.map?.pixels.first?.tOverLambda, session.failure ?? "no estimated map")
        XCTAssertEqual(estimated, 0.5, accuracy: 0.01, "the estimated rule on the noise-free demo, at the first pixel (the thinner half)")
    }

    /// The EDX demo has structure: a Mg- and Si-rich particle at the centre of an Al matrix, so the element maps differ and the colour mix
    /// shows the particle. The counts in each K alpha window, summed over the particle's middle pixels and over a matrix corner of the same
    /// size, follow the planted areas (`Truth.edxAreas`): Mg and Si far higher in the particle, Al far higher in the matrix. Red under: a
    /// uniform demo (every pixel alike: the colour mix plain white).
    func testTheEDXDemoHasAParticleInAMatrix() throws {
        let demo = DemoDocuments.edx()
        let n = DemoDocuments.Truth.edxSide
        XCTAssertEqual(DemoDocuments.Truth.edxParticleShare(x: 7, y: 7), 1)
        XCTAssertEqual(DemoDocuments.Truth.edxParticleShare(x: 0, y: 0), 0)
        let middle = [(7, 7), (8, 7), (7, 8), (8, 8)], corner = [(0, 0), (1, 0), (0, 1), (1, 1)]
        for (x, y) in middle { XCTAssertEqual(DemoDocuments.Truth.edxAreas(x: x, y: y).map { $0.area }, [30, 130, 113]) }
        for (x, y) in corner { XCTAssertEqual(DemoDocuments.Truth.edxAreas(x: x, y: y).map { $0.area }, [150, 10, 25]) }
        // The counts of a K alpha window (±100 eV about the line, 10 eV channels from 0) summed over the pixels.
        func window(_ keV: Double, _ pixels: [(Int, Int)]) -> Double {
            var mask = PixelMask(repeating: false, count: n * n)
            for (x, y) in pixels { mask[y * n + x] = true }
            let summed = demo.image.sum(mask: mask)
            let lo = Int(((keV - 0.1) / 0.01).rounded()), hi = Int(((keV + 0.1) / 0.01).rounded())
            return (lo...hi).reduce(0) { $0 + Double(summed[$1]) }
        }
        let al = 1.4865, mg = 1.2536, si = 1.7398   // K alpha, keV
        XCTAssertGreaterThan(window(mg, middle), 3 * window(mg, corner), "Mg is the particle's")
        XCTAssertGreaterThan(window(si, middle), 2 * window(si, corner), "Si is mostly the particle's")
        XCTAssertGreaterThan(window(al, corner), 2 * window(al, middle), "Al is the matrix's")
    }

    /// The five planted discs are found and counted by the Particles defaults (a threshold at half the range, no smoothing, minimum 4 px): five
    /// objects, none on the edge, whose areas match the planted diameters within the rasterisation. Red under: a disc moved to the edge; a
    /// lattice peak counted as an object.
    func testTheDemoLatticeHasFivePlantedDiscs() throws {
        let image = DemoDocuments.lattice()
        let report = try ParticleCompute.analyse(pixels: image.pixels, width: image.width, height: image.height, settings: ParticleSettings())
        XCTAssertEqual(report.summary.counted, 5, "objects: \(report.objects.map(\.moments.area))")
        XCTAssertEqual(report.summary.total, 5)
        let areas = report.objects.map(\.moments.area).sorted()
        for (area, d) in zip(areas, DemoDocuments.Truth.discDiametersPx) {
            let planted = Double.pi * Double(d * d) / 4
            XCTAssertEqual(Double(area), planted, accuracy: 0.05 * planted, "a disc of \(d) px")
        }
    }

    // MARK: Launch arguments

    @MainActor func testTheLaunchArgumentsAreRead() {
        XCTAssertEqual(LaunchOptions(arguments: ["macEM"]), LaunchOptions(arguments: []))
        let all = LaunchOptions(arguments: ["macEM", "--ui-testing", "--demo-fixture", "--demo-spectrum-fixture", "--demo-eels-fixture", "--demo-sem-eds", "--demo-ebsd-fixture", "--export-dir", "/tmp/out"])
        XCTAssertTrue(all.isUITesting && all.demoImage && all.demoSpectrum && all.demoEELS && all.demoSEMSpectrum && all.demoEBSD)
        XCTAssertEqual(all.exportDirectory, URL(fileURLWithPath: "/tmp/out", isDirectory: true))
        XCTAssertNil(LaunchOptions(arguments: ["--export-dir"]).exportDirectory, "no path after the flag")
        let relative = AppState(launch: LaunchOptions(arguments: ["--export-dir", "ui-export"]))
        XCTAssertEqual(relative.exportDirectory, FileManager.default.temporaryDirectory.appendingPathComponent("ui-export", isDirectory: true), "a relative folder is inside the temporary folder")
        let absolute = AppState(launch: LaunchOptions(arguments: ["--export-dir", "/tmp/out"]))
        XCTAssertEqual(absolute.exportDirectory, URL(fileURLWithPath: "/tmp/out", isDirectory: true))
        XCTAssertNil(AppState(launch: LaunchOptions(arguments: [])).exportDirectory, "a person gets the panel")
        XCTAssertFalse(LaunchOptions(arguments: ["--demo-fixture"]).isUITesting)
    }

    /// A UI-testing launch removes the saved application state (a saved "window closed" hid the window at launch), the saved window frames, and keeps no
    /// windows on quit; other defaults and other apps' saved states stay.
    @MainActor func testTheUITestingResetRemovesTheSavedState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let states = home.appendingPathComponent("Library/Saved Application State")
        let mine = states.appendingPathComponent("org.example.macTEM.savedState"), other = states.appendingPathComponent("org.example.other.savedState")
        for folder in [mine, other] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let suite = "macTEM-reset-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("0 0 800 600", forKey: "NSWindow Frame image")
        defaults.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        defaults.set("kept", forKey: "edx.resultsSplit")

        LaunchOptions.resetSavedState(defaults: defaults, home: home.path, bundleIdentifier: "org.example.macTEM")

        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path), "the app's saved state is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "another app's stays")
        XCTAssertNil(defaults.object(forKey: "NSWindow Frame image"))
        XCTAssertEqual(defaults.object(forKey: "NSQuitAlwaysKeepsWindows") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "edx.resultsSplit"), "kept")
    }

    @MainActor func testOpenArgumentsParseInOrderAndRefuseARelativePath() {
        let two = LaunchOptions(arguments: ["macEM", "--open", "/data/b.emd", "--ui-testing", "--open", "/data/a.emd"])
        XCTAssertEqual(two.openFiles, [URL(fileURLWithPath: "/data/b.emd"), URL(fileURLWithPath: "/data/a.emd")], "the order given")
        XCTAssertTrue(LaunchOptions(arguments: ["--open", "data/relative.emd"]).openFiles.isEmpty, "a relative path is refused")
        XCTAssertTrue(LaunchOptions(arguments: ["--open"]).openFiles.isEmpty, "no path after the flag")
        XCTAssertTrue(LaunchOptions(arguments: []).openFiles.isEmpty)
    }

    /// The demo opens through the app's own open path: an item named for it, resident, with the image in its session.
    /// Red under: the reader not answering the demo URL; the item stuck reading.
    @MainActor func testTheDemoImageOpensThroughTheAppsOpenPath() async throws {
        let state = AppState(launch: LaunchOptions(arguments: ["--demo-fixture"]))
        await state.lastOpen?.value
        XCTAssertEqual(state.openItems.items.count, 1)
        let item = try XCTUnwrap(state.openItems.selected)
        XCTAssertEqual(item.session.image?.fileName, "Demo lattice")
        XCTAssertEqual(item.residency, .resident)
        XCTAssertTrue(DemoDocuments.isDemo(DemoDocuments.latticeURL))
        XCTAssertFalse(DemoDocuments.isDemo(URL(fileURLWithPath: "/Users/x/a.dm4")))
    }

    /// A STEM image opened before Simulate (an Open of the image by itself starts no run; Show STEM Image starts one) says so, never "computing" (#1022);
    /// the placeholder says "computing" only while a run goes. Red before: the STEM item held the HRTEM placeholder's "computing".
    @MainActor func testAStemImageBeforeSimulateSaysItIsNotComputedYet() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.open(urls: [DemoDocuments.stemURL(of: DemoDocuments.simulationURL(1))])?.value
        let image = try XCTUnwrap(state.openItems.selected?.session.image)
        XCTAssertEqual(image.notes, ["simulated image, no measured data", "not computed yet: press Simulate"])
        XCTAssertFalse(image.notes.contains("computing"))
        XCTAssertEqual(DemoDocuments.stemPlaceholder(name: "STEM of Simulation 1", computing: true).notes.last, "computing")
    }

    @MainActor func testTheSpectrumFixturesOpenTheirRooms() async throws {
        let state = AppState(launch: LaunchOptions(arguments: ["--demo-spectrum-fixture", "--demo-eels-fixture"]))
        await state.edx.settled()
        await state.eels.settled()
        XCTAssertEqual(state.edx.fileName, "Demo EDX")
        XCTAssertEqual(state.eels.fileName, "Demo EELS")
        XCTAssertFalse(state.hasImage, "no image fixture: no image open")
        XCTAssertEqual(state.navigation.workspaceArea, .edx, "a launch with only spectrum documents starts in a room that can show one, not in Prepare")
    }
}
