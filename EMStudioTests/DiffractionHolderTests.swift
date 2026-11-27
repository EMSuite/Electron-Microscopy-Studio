//
//  DiffractionHolderTests.swift
//  The Diffraction room's double-tilt holder for one open pattern (#815): the file's stage tilts are read once and only as a pair
//  (a record without the pair does not use up the read),
//  a typed tilt marks the source typed, limits outside (0, 90] are refused, a typed axis is folded into [0, 360) and Forget clears it,
//  the β sense set by hand forgets only a calibrated axis it clashes with (#932),
//  and there is no tilt plan before Index found an orientation. Red before: the holder did not exist.
//

import XCTest
import DiffractoGeometry
import FormatoCore
import TEMCore
import TEMSession

nonisolated final class DiffractionHolderTests: XCTestCase {

    @MainActor func testTheFileStageTiltsAreReadOnceAndOnlyAsAPair() {
        var onlyAlpha = AcquisitionMetadata()
        onlyAlpha.stageTiltAlphaDeg = MetadataReading(12)
        let holder = DiffractionHolder()
        holder.bindStage(onlyAlpha)
        XCTAssertEqual(holder.settings.source, .typed, "α without β is not a stage readout")
        XCTAssertEqual(holder.settings.alphaDeg, 0)
        var both0 = AcquisitionMetadata()
        both0.stageTiltAlphaDeg = MetadataReading(7)
        both0.stageTiltBetaDeg = MetadataReading(3)
        holder.bindStage(both0)
        XCTAssertEqual(holder.settings.source, .file, "a record that stated no pair did not use up the read")
        XCTAssertEqual(holder.settings.alphaDeg, 7)

        var both = AcquisitionMetadata()
        both.stageTiltAlphaDeg = MetadataReading(12)
        both.stageTiltBetaDeg = MetadataReading(-4)
        let fresh = DiffractionHolder()
        fresh.bindStage(both)
        XCTAssertEqual(fresh.settings.source, .file)
        XCTAssertEqual(fresh.settings.alphaDeg, 12)
        XCTAssertEqual(fresh.settings.betaDeg, -4)

        fresh.setTilts(alphaDeg: 5, betaDeg: -4)
        fresh.bindStage(both)
        XCTAssertEqual(fresh.settings.alphaDeg, 5, "a second appearance does not overwrite the typed tilt")
        XCTAssertEqual(fresh.settings.source, .typed)
    }

    @MainActor func testLimitsAndTheAxisAreChecked() {
        let holder = DiffractionHolder()
        holder.setLimits(alphaDeg: 0, betaDeg: 20)
        holder.setLimits(alphaDeg: 95, betaDeg: 20)
        XCTAssertEqual(holder.settings.alphaLimitDeg, 30, "a limit of 0° or past 90° is refused")
        holder.setLimits(alphaDeg: 40, betaDeg: 20)
        XCTAssertEqual(holder.settings.alphaLimitDeg, 40)
        XCTAssertEqual(holder.settings.betaLimitDeg, 20)

        holder.setAxis(degrees: -30)
        XCTAssertEqual(try XCTUnwrap(holder.settings.axisAngleDeg), 330, accuracy: 1e-12)
        holder.forgetAxis()
        XCTAssertNil(holder.settings.axisAngleDeg)
    }

    @MainActor func testThereIsNoPlanBeforeIndex() {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        XCTAssertNil(DiffractionHolder().plan(analysis: analysis, image: image))
    }

    /// The β sense set by hand: a typed axis stays (only a calibrated axis was fitted with a sense); back to found, β is taken
    /// positive until a calibration finds it.
    @MainActor func testSettingTheBetaSense() {
        let holder = DiffractionHolder()
        holder.setAxis(degrees: 20)
        holder.setBetaSense(.negative)
        XCTAssertEqual(holder.settings.axisAngleDeg, 20, "a typed axis has no sense to clash with")
        XCTAssertEqual(holder.settings.betaSense, .negative)
        XCTAssertEqual(holder.settings.betaSenseSource, .hand)
        holder.setBetaSense(nil)
        XCTAssertEqual(holder.settings.betaSense, .positive)
        XCTAssertEqual(holder.settings.betaSenseSource, .assumed)
    }
}
