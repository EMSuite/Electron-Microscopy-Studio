//
//  HRTEMImageTests.swift
//  A Simulation document's HRTEM image (#894, plan row MA2): the exit waves of Si [1 1 0] are stored at every whole period, and the
//  image at a defocus is the kit's `waves.applying(ctf).intensity()` tiled, drawn x down the rows and y along the columns (the simulated
//  pattern's lab frame) and calibrated in nm. The kit
//  itself is pinned to abTEM 1.0.10 (SimulatoKit's `hrtem-si110` pins); this file pins the app's use of it: the grid from the kit's
//  sampling rule, the period planes, the pixel mapping, the calibration, the design's Uncorrected defaults, Scherzer and the method
//  line. Red before:
//  there was no HRTEM image.
//
//  Si a = 5.4309 Å along [1 1 0]: the box is a × a√2 (5.4309 × 7.6805 Å), a period a√2. At a 40 mrad aperture and 200 kV the
//  sampling with no aperture is the rule's finest, 0.05 Å (as min(0.05, λ / 3β) for any aperture up to 160 mrad), so at least 109 and 154 points; the
//  square grid is 125 × 176 (pixels 0.04345 and 0.04364 Å, 0.44 % apart; no pair of factors 2, 3, 5 up to twice is within 0.5 %, #1006). 2 nm is 2.6 periods:
//  3. A 4 nm view takes ⌈40 / 5.4309⌉ = 8 units across and ⌈40 / 7.6805⌉ = 6 up.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import SimulatoCore
import SimulatoMultislice
import SimulatoProbe
import ImagoCore
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class HRTEMImageTests: XCTestCase {

    private func silicon(nm: Double = 2) throws -> SimulationSpecimen.Built {
        try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: nm).get()
    }

    /// Mutation: each length raised on its own (120 × 160, #1006), the sampling not the kit's, the planes not at whole periods.
    func testTheExitWavesAreStoredAtEveryPeriodOnTheKitsGrid() throws {
        let exit = try HRTEMImage.exitWaves(try silicon(), optics: HRTEMOptics(), specimen: "Si [1 1 0]")
        XCTAssertEqual(exit.waves.count, 3)
        XCTAssertEqual(exit.planePeriods, [1, 2, 3])
        XCTAssertEqual(exit.waves[0].grid.nx, 125)
        XCTAssertEqual(exit.waves[0].grid.ny, 176)
        XCTAssertEqual(exit.periodNM, 5.4309 * 2.0.squareRoot() / 10, accuracy: 1e-12)
        XCTAssertEqual(exit.thicknessNM(at: 2), 3 * exit.periodNM, accuracy: 1e-12)
        XCTAssertNotEqual(exit.waves[0].field, exit.waves[2].field, "the planes are at different depths")
    }

    /// The pixels are square (#1006): the grid's lengths follow the box's sides, both at the sampling or finer. Si [1 1 0] (a × a√2)
    /// and Mg [0 0 0 1] (a × a√3, hexagonal) within 0.5 %, the frozen-phonon supercell too; Si [0 0 1] (a × a) keeps 120 × 120.
    /// Red before: each length was raised to factors 2, 3, 5 on its own, so Si [1 1 0] took 120 × 160 (0.0453 by 0.0480 Å, 6 %) and
    /// Mg 72 × 120 (3.8 %). Mutation: the tolerance dropped, a length below the sampling's count, the longer side taken for both.
    func testThePixelsAreSquareWithinHalfAPercent() throws {
        let optics = HRTEMOptics()
        let specimens: [(String, SimulationSpecimen.Built)] = [
            ("Si [1 1 0]", try silicon()),
            ("Mg [0 0 0 1]", try SimulationSpecimen.build(CrystalPresets.magnesium, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 2,
                                                          maximumStrain: 0.01).get()),
            ("Si [0 0 1]", try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 2).get()),
        ]
        for (name, built) in specimens {
            for (box, grid) in [(built.box, try HRTEMImage.grid(built, optics: optics)),
                                (built.slabBox, try HRTEMImage.thermalGrid(built, optics: optics))] {
                let px = box.x / Double(grid.nx), py = box.y / Double(grid.ny)
                XCTAssertLessThanOrEqual(abs(px - py) / max(px, py), 0.005, "\(name): \(grid.nx) × \(grid.ny) over \(box.x) × \(box.y) Å")
                XCTAssertLessThanOrEqual(max(px, py), HRTEMImage.finestSampling + 1e-12, "\(name): no axis coarser than the sampling")
            }
        }
        let si001 = try HRTEMImage.grid(specimens[2].1, optics: optics)
        XCTAssertEqual(si001.nx, 120, "equal sides keep factors 2, 3, 5 at the least length")
        XCTAssertEqual(si001.ny, 120)
        let si110 = try HRTEMImage.grid(specimens[0].1, optics: optics)
        XCTAssertEqual(si110.nx, 125)
        XCTAssertEqual(si110.ny, 176)
        let aperture = HRTEMImage.squareGrid(extent: SIMD2(3.2094, 3.2094 * 3.0.squareRoot()), sampling: 0.11)
        let ratio = (3.2094 / Double(aperture.nx)) / (3.2094 * 3.0.squareRoot() / Double(aperture.ny))
        XCTAssertEqual(ratio, 1, accuracy: 0.005, "a coarse sampling searches past twice the least length: \(aperture)")
    }

    /// The image is the kit's image of that wave at that defocus, tiled, in the simulated pattern's lab frame: x down the rows, y along
    /// the columns, no flip (#931), in nm. Mutation: rows flipped, x and y swapped, the defocus in Å passed as nm, the calibration in Å.
    func testTheImageIsTheKitsImageDrawnInThePatternsLabFrame() throws {
        let optics = HRTEMOptics()
        let exit = try HRTEMImage.exitWaves(try silicon(), optics: optics, specimen: "Si [1 1 0]")
        let image = try HRTEMImage.image(exit, thicknessIndex: 1, defocusNM: 30, optics: optics, name: "HRTEM of Simulation 1")
        let truth = try exit.waves[1].applying(optics.transferFunction(defocusNM: 30)).intensity()
            .tiled(repetitionsX: 8, repetitionsY: 6)
        XCTAssertEqual(image.height, truth.nx)
        XCTAssertEqual(image.width, truth.ny)
        XCTAssertEqual(image.height, 8 * 125)
        XCTAssertEqual(image.width, 6 * 176)
        let pixels = image.pixels
        for (ix, iy) in [(0, 0), (17, 3), (119, 159), (500, 700), (959, 959)] {
            XCTAssertEqual(pixels[ix * image.width + iy], Float(truth[ix, iy]), accuracy: 1e-6 * Float(truth.values.max()!))
        }
        XCTAssertEqual(try XCTUnwrap(image.y).scale, 5.4309 / 125 / 10, accuracy: 1e-15, "rows are lab x")
        XCTAssertEqual(try XCTUnwrap(image.y).unit, "nm")
        XCTAssertEqual(try XCTUnwrap(image.x).scale, 5.4309 * 2.0.squareRoot() / 176 / 10, accuracy: 1e-15, "columns are lab y")
        XCTAssertEqual(image.voltage, 200_000)
        XCTAssertEqual(image.notes.first, "simulated image, no measured data")
    }

    /// The image's lattice fringes run where the simulated pattern of the same document puts its spots (#931): the strongest
    /// reflection of Si [1 1 0] at the slab's orientation, (qx, qy) with qx down the rows and qy along the columns as
    /// `ZoneAxisOverlay` draws it, is a whole Fourier frequency of the image read at its own calibration (whole units, 5.43 Å down
    /// the rows by 7.68 Å along the columns), and the image's strongest among the pattern's spots. Mutation: the image drawn x
    /// across and y up (turned 90° against the pattern: the 111 fringe then falls between frequencies), rows and columns swapped.
    func testTheImagesFringesLineUpWithTheSimulatedPattern() throws {
        let optics = HRTEMOptics()
        let built = try silicon()
        let exit = try HRTEMImage.exitWaves(built, optics: optics, specimen: "Si [1 1 0]")
        let image = try HRTEMImage.image(exit, thicknessIndex: 2, defocusNM: 30, optics: optics, name: "f")
        let orientation = try CrystalOrientation(zoneAxis: SIMD3(1, 1, 0), inPlaneAngle: built.inPlaneAngle,
                                                 cell: CrystalPresets.silicon.cell)
        let spots = try SpotPatternSimulator(structure: CrystalPresets.silicon, kMax: 0.6)
            .pattern(orientation: orientation, volts: optics.volts).spots
        let g = try XCTUnwrap(spots.max { $0.intensity < $1.intensity }).position
        let rowStep = try XCTUnwrap(image.y).scale * 10, columnStep = try XCTUnwrap(image.x).scale * 10
        let bin = g * SIMD2(Double(image.height) * rowStep, Double(image.width) * columnStep)
        XCTAssertEqual(bin.x, bin.x.rounded(), accuracy: 1e-6, "the pattern's \(g) is a whole frequency down the rows")
        XCTAssertEqual(bin.y, bin.y.rounded(), accuracy: 1e-6, "and along the columns")
        let pixels = image.pixels.map(Double.init)
        let mean = pixels.reduce(0, +) / Double(pixels.count)
        func amplitude(_ q: SIMD2<Double>) -> Double {
            var re = 0.0, im = 0.0
            for r in 0 ..< image.height {
                for c in 0 ..< image.width {
                    let phase = -2 * Double.pi * (q.x * Double(r) * rowStep + q.y * Double(c) * columnStep)
                    let v = pixels[r * image.width + c] - mean
                    re += v * cos(phase); im += v * sin(phase)
                }
            }
            return (re * re + im * im).squareRoot() / Double(pixels.count)
        }
        let strongest = spots.map { amplitude($0.position) }.max() ?? 0
        XCTAssertGreaterThan(amplitude(g), 0.1 * strongest, "the image has fringes along the pattern's strongest spot")
    }

    /// The defaults are the design's Uncorrected preset (Cs 1.0 mm, focal spread 5 nm, no aperture, no angular spread); Scherzer is the
    /// kit's √(3/2 Cs λ), 61.33 nm at 200 kV, and the default defocus; the method line names every setting. Mutation: Cs in the wrong
    /// unit, the default not Scherzer, a setting missing from the line.
    @MainActor func testScherzerIsTheDefaultAndTheMethodLineNamesEverySetting() throws {
        let model = SimulationModel()
        XCTAssertEqual(model.optics.csMM, 1.0)
        XCTAssertEqual(model.optics.focalSpreadNM, 5.0)
        XCTAssertNil(model.optics.apertureMrad)
        XCTAssertNil(model.defocusNM)
        XCTAssertEqual(model.effectiveDefocusNM, try ContrastTransferFunction.scherzerDefocus(Cs: 1e7, energy: 200_000) / 10)
        XCTAssertEqual(model.effectiveDefocusNM, 61.33, accuracy: 0.01, "the design's 61 nm")
        model.setDefocus(nm: 20)
        XCTAssertEqual(model.effectiveDefocusNM, 20)
        model.useScherzerDefocus()
        XCTAssertNil(model.defocusNM)

        let exit = try HRTEMImage.exitWaves(try silicon(), optics: model.optics, specimen: "Si [1 1 0]")
        let line = HRTEMImage.methodLine(exit, thicknessIndex: 2, defocusNM: 61.33, optics: model.optics)
        XCTAssertEqual(line, "HRTEM · Si [1 1 0] · 200 kV · 2.3 nm · defocus 61.33 nm · Cs 1 mm · focal spread 5 nm · angular spread 0 mrad · "
                       + "no aperture · Lobato, infinite projection, 1 Å slices · static lattice · exact (float64)")
    }

    /// The model runs the multislice once for a specimen and optics, and Defocus and Thickness re-image the stored waves; a new
    /// thickness or voltage makes them stale. Mutation: the waves recomputed on a defocus move, kept for another thickness, the
    /// thickness index not clamped.
    @MainActor func testTheModelRunsOnceAndReimagesOnDefocusAndThickness() async throws {
        let model = SimulationModel()
        model.setThickness(nm: 2)
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let axis = SIMD3(1, 1, 0)
        XCTAssertFalse(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis))
        await model.updateExitWaves(crystal: si, zoneAxis: axis)
        XCTAssertTrue(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis))
        let waves = try XCTUnwrap(model.exitWaves)
        XCTAssertEqual(waves.waves.count, 3)
        let scherzer = try XCTUnwrap(model.hrtemImage(name: "x")).get()
        model.setDefocus(nm: -20)
        let other = try XCTUnwrap(model.hrtemImage(name: "x")).get()
        XCTAssertNotEqual(scherzer.pixels, other.pixels)
        XCTAssertEqual(model.exitWaves, waves, "a defocus move keeps the stored waves")
        model.setThicknessIndex(0)
        XCTAssertTrue(try XCTUnwrap(model.hrtemImage(name: "x")).get().notes[1].contains(" · 0.768 nm · "))
        model.setThicknessIndex(99)
        XCTAssertTrue(try XCTUnwrap(model.hrtemImage(name: "x")).get().notes[1].contains(" · 2.3 nm · "), "kept in range")

        model.setThickness(nm: 5)
        XCTAssertFalse(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis))
        var optics = model.optics
        optics.csMM = 1.2
        model.setThickness(nm: 2)
        model.setOptics(optics)
        XCTAssertTrue(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis), "Cs re-images only")
        optics.volts = 300_000
        model.setOptics(optics)
        XCTAssertFalse(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis), "the voltage runs again")
    }

    /// Show HRTEM Image opens "HRTEM of Simulation N" in the Image room and runs the multislice itself, with no inspector on screen,
    /// and the item's pixels become the model's image. Mutation: the item not opened, the room not selected, the run left to the
    /// inspector's task, the computed image not put into the item.
    @MainActor func testShowHRTEMImageOpensTheImageAndComputesIt() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let simulation = try XCTUnwrap(state.openItems.items.first { DemoDocuments.isSimulation($0.url) })
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        simulation.diffraction.simulation.zoneAxis = SIMD3(1, 1, 0)
        simulation.multislice.setThickness(nm: 2)
        await state.showHRTEMImage(of: simulation)?.value
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        let item = try XCTUnwrap(state.hrtemItem(of: simulation))
        XCTAssertEqual(item.url.lastPathComponent, "HRTEM of \(simulation.url.lastPathComponent)", "the launch numbers its simulations across tests")
        XCTAssertFalse(DemoDocuments.isSimulation(item.url), "the image is not a Simulation document")
        XCTAssertTrue(state.simulationDocument(ofHRTEM: item) === simulation)
        let expected = try XCTUnwrap(simulation.multislice.hrtemImage(name: item.url.lastPathComponent)).get()
        XCTAssertEqual(item.session.image?.pixels, expected.pixels, "computed without the inspector")
        XCTAssertEqual(item.session.image?.width, 6 * 176)
    }

    /// In a window that holds its Simulation document the image gets a tab of its own (one file per window): that tab lands in the
    /// Image room and draws from the document's model in the other window, both ways, and the Simulation window stays in its room.
    /// Mutation: the pair looked up in one window only (the tab says "Its Simulation document is closed"), the Simulation window
    /// switched to the Image room, the tab left on the placeholder.
    @MainActor func testTheImageTabDrawsFromItsDocumentInAnotherWindow() async throws {
        let windows = AppWindows()
        var made: [AppState] = []
        windows.openWindow = {
            let tab = AppState(launch: LaunchOptions(arguments: []))
            windows.enroll(tab)
            made.append(tab)
        }
        let first = AppState(launch: LaunchOptions(arguments: []))
        windows.enroll(first)
        await first.newSimulation()?.value
        let simulation = try XCTUnwrap(first.openItems.items.first { DemoDocuments.isSimulation($0.url) })
        simulation.diffraction.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        simulation.diffraction.simulation.zoneAxis = SIMD3(1, 1, 0)
        simulation.multislice.setThickness(nm: 2)
        await first.showHRTEMImage(of: simulation)?.value
        XCTAssertEqual(first.navigation.workspaceArea, .diffraction, "the Simulation window stays where it was")
        XCTAssertEqual(first.openItems.items.count, 1, "one file per window")

        // The window the app opened for the image takes its batch, as `ImageWindow` does when it appears.
        let tab = try XCTUnwrap(made.first)
        await tab.open(urls: try XCTUnwrap(windows.takeWaitingURLs()))?.value
        XCTAssertEqual(tab.navigation.workspaceArea, .image)
        let item = try XCTUnwrap(tab.openItems.items.first)
        XCTAssertTrue(tab.simulationDocument(ofHRTEM: item) === simulation)
        XCTAssertTrue(first.hrtemItem(of: simulation) === item)
        let scherzer = try XCTUnwrap(simulation.multislice.hrtemImage(name: item.url.lastPathComponent)).get()
        XCTAssertEqual(item.session.image?.pixels, scherzer.pixels, "drawn on landing from the waves the first window computed")

        simulation.multislice.setDefocus(nm: -20)
        await first.refreshHRTEMImage(of: simulation)?.value
        let moved = try XCTUnwrap(simulation.multislice.hrtemImage(name: item.url.lastPathComponent)).get()
        XCTAssertEqual(item.session.image?.pixels, moved.pixels, "a defocus move in one window redraws the tab")
        XCTAssertNotEqual(moved.pixels, scherzer.pixels)
    }

    /// The potential of one period repeated along the beam gives the exit waves of the whole slab built slice by slice. Mutation:
    /// period 0 taken with an atom of period 1, the slices of one period miscounted, the planes off by a slice.
    func testOnePeriodRepeatedEqualsTheWholeSlab() throws {
        let built = try silicon(nm: 3)
        let optics = HRTEMOptics()
        let exit = try HRTEMImage.exitWaves(built, optics: optics, specimen: "Si [1 1 0]")
        let slab = built.slab
        let (nx, ny) = try HRTEMImage.grid(built, optics: optics)
        let whole = try Potential(structure: slab.structure, nx: nx, ny: ny, sliceThicknesses: slab.sliceThicknesses)
        let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
        let truth = try Multislice.run(.planeWave(beam: try ElectronBeam(energy: optics.volts), grid: whole.grid), through: whole,
                                       exitPlanes: .afterSlices((1 ... slab.repeats.z).map { $0 * perPeriod - 1 }), backend: .cpu)
        XCTAssertEqual(exit.waves.count, truth.count)
        for (a, b) in zip(exit.waves, truth) {
            let scale = b.field.real.map(abs).max()! + b.field.imaginary.map(abs).max()!
            for i in Swift.stride(from: 0, to: a.field.real.count, by: 97) {
                XCTAssertEqual(a.field.real[i], b.field.real[i], accuracy: 1e-12 * scale)
                XCTAssertEqual(a.field.imaginary[i], b.field.imaginary[i], accuracy: 1e-12 * scale)
            }
        }
    }

    /// Every period is stored while the waves fit in the budget, else every n-th and always the last; a run over this Mac's budget is
    /// refused before it starts, in the room's words. Mutation: the last plane dropped, the stride rounded down, no check.
    func testStoredPlanesAreTieredAndAnOversizedRunIsRefused() throws {
        XCTAssertEqual(HRTEMImage.planePeriods(periods: 5, points: 100), [1, 2, 3, 4, 5])
        XCTAssertEqual(HRTEMImage.planePeriods(periods: 10, points: 100, budget: 100 * 16 * 4), [3, 6, 9, 10])
        XCTAssertEqual(HRTEMImage.planePeriods(periods: 3, points: 100, budget: 1), [3])
        let tiny = SimulationLimits(memoryBudget: 1 << 20, largestBuffer: 1 << 30)
        XCTAssertThrowsError(try HRTEMImage.exitWaves(try silicon(), optics: HRTEMOptics(), specimen: "Si", limits: tiny)) { error in
            guard case .overBudget? = error as? HRTEMImage.PlanRefusal else { return XCTFail("\(error)") }
            XCTAssertTrue(ErrorDetail.text(error).hasSuffix("this Mac allows a run: lower the thickness."), ErrorDetail.text(error))
        }
        XCTAssertNoThrow(try HRTEMImage.checkPlan(try silicon(), optics: HRTEMOptics()), "2 nm of Si fits any Mac")
    }

    /// The stored waves are keyed on the specimen as built: a thickness of the same whole periods keeps them, one more period runs
    /// again. Mutation: the waves keyed on the typed thickness.
    @MainActor func testAThicknessOfTheSamePeriodsKeepsTheWaves() async throws {
        let model = SimulationModel()
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        model.setThickness(nm: 2.0)
        await model.updateExitWaves(crystal: si, zoneAxis: SIMD3(1, 1, 0))
        model.setThickness(nm: 2.1)
        XCTAssertTrue(model.exitWavesAreCurrent(crystal: si, zoneAxis: SIMD3(1, 1, 0)), "2.1 nm is 3 periods too")
        model.setThickness(nm: 3.1)
        XCTAssertFalse(model.exitWavesAreCurrent(crystal: si, zoneAxis: SIMD3(1, 1, 0)), "3.1 nm is 4 periods")
    }

    /// Quick changes back and forth land only the newest run: a cancelled older run of the same specimen does not end the newer one,
    /// and going back to the stored waves' specimen cancels the run for another. Mutation: runs told apart by key, the stored waves'
    /// call returning without cancelling.
    @MainActor func testQuickChangesBackAndForthLandTheNewestRunOnly() async throws {
        let model = SimulationModel()
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let axis = SIMD3(1, 1, 0)
        model.setThickness(nm: 2)
        await model.updateExitWaves(crystal: si, zoneAxis: axis)
        let two = try XCTUnwrap(model.exitWaves)
        model.setThickness(nm: 5)
        let toFive = Task { await model.updateExitWaves(crystal: si, zoneAxis: axis) }
        await Task.yield()
        model.setThickness(nm: 2)
        await model.updateExitWaves(crystal: si, zoneAxis: axis)
        await toFive.value
        XCTAssertEqual(model.exitWaves, two, "the 5 nm run was cancelled and did not land")
        XCTAssertFalse(model.isComputing)

        model.setThickness(nm: 5)
        let first = Task { await model.updateExitWaves(crystal: si, zoneAxis: axis) }
        await Task.yield()
        model.setThickness(nm: 3)
        let second = Task { await model.updateExitWaves(crystal: si, zoneAxis: axis) }
        await Task.yield()
        model.setThickness(nm: 5)
        await model.updateExitWaves(crystal: si, zoneAxis: axis)
        await first.value
        await second.value
        XCTAssertTrue(model.exitWavesAreCurrent(crystal: si, zoneAxis: axis), "the newest 5 nm run landed")
        XCTAssertFalse(model.isComputing)
    }
}
