//
//  HRTEMControlsTests.swift
//  The HRTEM image's controls (#895, plan row MA3): the Optics presets of the mockup brief, the transfer function strip (the kit's
//  `profiles`, in 1/nm, with its point resolution and the aperture edge), the defocus and thickness table (its columns centred on the
//  current defocus, its rows from the first thickness step, every cell the HRTEM section's image), the field of view and the
//  phase's strongest spacings. The kit itself is pinned to abTEM 1.0.10; this file pins the app's use of it. Red before: there were
//  no presets, no strip and no table.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoProbe
import ImagoCore
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class HRTEMControlsTests: XCTestCase {

    private func siliconWaves(optics: HRTEMOptics = HRTEMOptics()) throws -> HRTEMExitWaves {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 4).get()
        return try HRTEMImage.exitWaves(built, optics: optics, specimen: "Si [1 1 0]")
    }

    /// Uncorrected is Cs 1.0 mm and 5 nm focal spread, Cs Corrected −0.010 mm and 3 nm; any other pair is Custom, and Custom keeps
    /// the fields. Mutation: the corrected Cs positive or in µm, a preset that does not round-trip, Custom overwriting.
    func testThePresetsAreTheBriefsAndRoundTrip() {
        let defaults = HRTEMOptics()
        XCTAssertEqual(HRTEMPreset.of(defaults), .uncorrected, "the default is Uncorrected")
        let corrected = HRTEMPreset.csCorrected.applied(to: defaults)
        XCTAssertEqual(corrected.csMM, -0.010)
        XCTAssertEqual(corrected.focalSpreadNM, 3.0)
        XCTAssertEqual(corrected.volts, defaults.volts, "a preset leaves the voltage")
        XCTAssertEqual(HRTEMPreset.of(corrected), .csCorrected)
        var custom = defaults
        custom.csMM = 1.2
        XCTAssertEqual(HRTEMPreset.of(custom), .custom)
        XCTAssertEqual(HRTEMPreset.custom.applied(to: custom), custom)
        XCTAssertEqual(HRTEMPreset.uncorrected.applied(to: corrected), defaults)
    }

    /// The strip is the kit's profiles with frequencies in 1/nm, the envelope the product of the two envelopes, the point
    /// resolution the kit's, and the aperture edge at α / λ. Mutation: frequencies left in 1/Å, the envelope one factor only, the
    /// edge in 1/Å.
    func testTheTransferStripIsTheKitsProfilesInPerNanometre() throws {
        var optics = HRTEMOptics()
        optics.angularSpreadMrad = 0.2
        optics.apertureMrad = 20
        let curve = try HRTEMTransferCurve.of(optics, defocusNM: 61.33, points: 200)
        let ctf = try optics.transferFunction(defocusNM: 61.33)
        let truth = try ctf.profiles(energy: 200_000, points: 200)
        XCTAssertEqual(curve.frequencies, truth.spatialFrequencies.map { $0 * 10 })
        XCTAssertEqual(curve.transfer, truth.transfer)
        let envelope = try XCTUnwrap(curve.envelope)
        let t = try XCTUnwrap(truth.temporalEnvelope), s = try XCTUnwrap(truth.spatialEnvelope)
        for i in [0, 50, 199] { XCTAssertEqual(envelope[i], t[i] * s[i], accuracy: 1e-15) }
        XCTAssertEqual(try XCTUnwrap(curve.pointResolutionAngstrom), try ctf.pointResolution(energy: 200_000), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(curve.apertureFrequency), 20e-3 / truth.wavelength * 10, accuracy: 1e-9)

        var bare = HRTEMOptics()
        bare.focalSpreadNM = 0
        bare.csMM = 0
        let plain = try HRTEMTransferCurve.of(bare, defocusNM: 10, points: 50)
        XCTAssertNil(plain.envelope, "no spread, no envelope")
        XCTAssertNil(plain.pointResolutionAngstrom, "no Cs, no point resolution")
        XCTAssertNil(plain.apertureFrequency)
    }

    /// Five columns 10 nm apart centred on the current defocus; counts held to 3…9. Mutation: the centre at an edge, the count not
    /// clamped.
    func testTheDefocusColumnsAreCentredOnTheCurrentDefocus() {
        let columns = HRTEMImage.defocusColumns(centreNM: 61.33, stepNM: 10, count: 5)
        XCTAssertEqual(columns.count, 5)
        for (got, want) in zip(columns, [41.33, 51.33, 61.33, 71.33, 81.33]) { XCTAssertEqual(got, want, accuracy: 1e-12) }
        XCTAssertEqual(columns[2], 61.33, "the middle column is the current defocus")
        XCTAssertEqual(HRTEMImage.defocusColumns(centreNM: 0, stepNM: 10, count: 4), [-15, -5, 5, 15])
        XCTAssertEqual(HRTEMImage.defocusColumns(centreNM: 0, stepNM: 1, count: 1).count, 3)
        XCTAssertEqual(HRTEMImage.defocusColumns(centreNM: 0, stepNM: 1, count: 20).count, 9)
    }

    /// Rows at the stored periods nearest 2, 4, 6 … nm, each used once and in range. Si [1 1 0] has a 0.768 nm period, so 2 nm is
    /// period 3 (index 2), 4 nm period 5 (index 4); a 4 nm specimen is the 5 whole periods nearest it (SimulatoKit 0.7.0), so the
    /// rows stop at index 4. Mutation: rows from 0, repeated rows, an index past the waves.
    func testTheThicknessRowsStepFromTheFirstStep() throws {
        let exit = try siliconWaves()
        XCTAssertEqual(exit.waves.count, 5)
        XCTAssertEqual(HRTEMImage.thicknessRows(exit, stepNM: 2, count: 5), [2, 4])
        XCTAssertEqual(HRTEMImage.thicknessRows(exit, stepNM: 0.768, count: 5), [0, 1, 2, 3, 4])
        XCTAssertEqual(HRTEMImage.thicknessRows(exit, stepNM: 0, count: 5), [])
    }

    /// Every cell is the image the HRTEM section shows at that defocus and thickness. Mutation: rows and columns swapped, a cell at
    /// the current settings instead of its own.
    func testEveryCellIsTheSectionsImage() throws {
        var optics = HRTEMOptics()
        optics.fieldOfViewNM = 1
        let exit = try siliconWaves(optics: optics)
        let table = try HRTEMImage.table(exit, defocusNM: [20, 60, 100], thicknessIndices: [0, 3], optics: optics, name: "t")
        XCTAssertEqual(table.cells.count, 2)
        XCTAssertEqual(table.cells[0].count, 3)
        XCTAssertEqual(table.thicknessNM[1], exit.thicknessNM(at: 3), accuracy: 1e-12)
        let truth = try HRTEMImage.image(exit, thicknessIndex: 3, defocusNM: 100, optics: optics, name: "t")
        XCTAssertEqual(table.cells[1][2], truth)
        XCTAssertNotEqual(table.cells[1][0], truth)
    }

    /// The field of view sets how many units are tiled: 4 nm is 8 by 6 units of Si [1 1 0], 1 nm is 2 by 2. Mutation: the view
    /// ignored, Å taken for nm.
    func testTheFieldOfViewSetsTheTiles() throws {
        var optics = HRTEMOptics()
        let exit = try siliconWaves(optics: optics)
        XCTAssertEqual(try HRTEMImage.image(exit, thicknessIndex: 0, defocusNM: 0, optics: optics, name: "f").height, 8 * 125)
        optics.fieldOfViewNM = 1
        let small = try HRTEMImage.image(exit, thicknessIndex: 0, defocusNM: 0, optics: optics, name: "f")
        XCTAssertEqual(small.height, 2 * 125, "rows are lab x")
        XCTAssertEqual(small.width, 2 * 176)
    }

    /// The strip marks the phase's strongest families, strongest first: for silicon {1 1 1} leads. Mutation: weakest first, the
    /// calibration standard's families instead of the phase's.
    @MainActor func testTheStripMarksThePhasesStrongestSpacings() throws {
        let analysis = DiffractionAnalysis()
        XCTAssertEqual(analysis.strongestSpacings().count, 0, "no phase, no marks")
        analysis.setCrystal(.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon)))
        let spacings = analysis.strongestSpacings()
        XCTAssertEqual(spacings.count, 3)
        XCTAssertEqual(spacings[0].d, 5.4309 / 3.0.squareRoot(), accuracy: 1e-9, "{1 1 1} is silicon's strongest")
    }

    /// Every control edits the optics through one validated path: an invalid value is refused whole, a valid one kept. Mutation: a
    /// negative spread, a zero aperture or a field past the cap kept.
    @MainActor func testInvalidOpticsAreRefusedWhole() {
        let model = SimulationModel()
        let before = model.optics
        XCTAssertFalse(model.changeOptics { $0.focalSpreadNM = -1 })
        XCTAssertFalse(model.changeOptics { $0.apertureMrad = 0 })
        XCTAssertFalse(model.changeOptics { $0.volts = .nan })
        XCTAssertFalse(model.changeOptics { $0.fieldOfViewNM = SimulationModel.largestFieldOfViewNM + 1 })
        XCTAssertEqual(model.optics, before)
        XCTAssertTrue(model.changeOptics { $0.csMM = -0.01; $0.apertureMrad = 20 })
        XCTAssertEqual(model.optics.apertureMrad, 20)
    }

    /// Images asked for while one is being made coalesce: one more is made, at the latest settings, for the last caller. Mutation:
    /// every call queued, the stale image delivered last.
    @MainActor func testImagesAskedForWhileOneIsMadeCoalesce() async throws {
        let model = SimulationModel()
        model.setThickness(nm: 2)
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        await model.updateExitWaves(crystal: si, zoneAxis: SIMD3(1, 1, 0))
        var delivered: [CalibratedImage] = []
        for d in [0.0, 10, 20, 30, 40] {
            model.setDefocus(nm: d)
            model.render(name: "x", prepare: { $0 }, deliver: { delivered.append($0) })
        }
        await model.render(name: "x", prepare: { $0 }, deliver: { delivered.append($0) })?.value
        XCTAssertLessThanOrEqual(delivered.count, 2, "the first image and one coalesced one")
        XCTAssertEqual(delivered.last?.pixels, try XCTUnwrap(model.hrtemImage(name: "x")).get().pixels, "the latest settings")
    }

    /// A cell with a non-finite pixel draws it black instead of trapping, and spans its finite range. Mutation: no guard (a trap).
    func testAGreyCellSurvivesANonFinitePixel() {
        let axis = AxisCalibration(scale: 1, unit: "nm")
        let image = CalibratedImage(width: 2, height: 2, pixels: [0, 1, .nan, 2], x: axis, y: axis, fileName: "c", source: "c",
                                    voltage: nil, notes: [])
        XCTAssertEqual(GreyCell(image).bytes, [0, 128, 0, 255])
    }

    /// The exported table names its columns, rows, cell width and the method line. Mutation: a list missing, Å for nm.
    func testTheTablesDescriptionNamesEverySetting() throws {
        var optics = HRTEMOptics()
        optics.fieldOfViewNM = HRTEMImage.tableCellFieldNM
        let exit = try siliconWaves(optics: optics)
        let table = try HRTEMImage.table(exit, defocusNM: [50, 60], thicknessIndices: [0, 2], optics: optics, name: "t")
        let text = HRTEMImage.tableDescription(table, exit: exit, optics: optics)
        XCTAssertTrue(text.hasPrefix("HRTEM defocus by thickness table · columns: defocus 50, 60 nm · rows: thickness 0.768, 2.304 nm · each cell 2 nm wide · HRTEM · Si [1 1 0] · "), text)
    }
}
