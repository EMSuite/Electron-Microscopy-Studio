//
//  DiffractionResultLineTests.swift
//  #1113: Index's result keeps its place in the pattern header, and Calibrate on Ring and Index write an Output line. The header's
//  right end (Index's verdict) is laid out before the readout slot: the scale's summary gives way whole, down to nothing, and the
//  verdict then drops its spot count whole, keeping the phase, the zone axis, the misfit and its warnings. Each calibration on a ring
//  and each Index answer that lands is told to the app (`DiffractionAnalysis.onEvent`, through `OpenItems.onDiffractionEvent`), which
//  writes it as the EBSD rooms write their runs. Red before: the readout's shortest summary was its last level ("300 kV · scale:
//  typed"), cut with the verdict at half the header ("GaAs · 1,1° from [1…"); the header had no shorter line; no event and no line.
//

import XCTest
import DiffractoCore
import DiffractoOrientation
import DiffractoScattering
import FormatoCore
import TEMCore
import TEMSession
@testable import macTEM

/// What the list's callback heard, kept on the main actor.
@MainActor private final class HeardLines {
    var lines: [String] = []
}

nonisolated final class DiffractionResultLineTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")

    private func outcome(_ verdict: PatternIndexing.Verdict) -> PatternIndexing.Outcome {
        PatternIndexing.Outcome(phase: "Al", verdict: verdict, spots: [], explained: 22, indexed: 24,
                                orientation: try? CrystalOrientation(zoneAxis: SIMD3(0, 0, 1), cell: CrystalPresets.aluminum.cell), alternatives: [],
                                zoneAxis: SIMD3(0, 0, 1), zoneAxisAngle: 2.1 * .pi / 180, scale: 1.0004, misfitPercent: 0.0712)
    }

    // MARK: The header

    /// The readout slot ends on nothing, so the scale's summary is dropped whole when the verdict takes the room, never cut.
    func testTheScaleSummaryGivesWayWholeDownToNothing() {
        let calibration = DiffractionCalibration(source: .typed, deltaQ: 0.032, ring: nil)
        let levels = DiffractionHeaderText.levels(width: 144, height: 144, volts: 300_000, voltsFromFile: true, calibration: calibration)
        let readout = DiffractionHeaderText.readoutLevels(width: 144, height: 144, volts: 300_000, voltsFromFile: true, calibration: calibration)
        XCTAssertEqual(readout.last, "", "the last level is nothing")
        XCTAssertEqual(Array(readout.dropLast()), levels, "every summary before it, longest first")
        XCTAssertEqual(levels.last, "300 kV · scale: typed")
    }

    /// The verdict's shorter line leaves out the spot count and keeps the result: the phase, the zone axis, the misfit, the verdict's words.
    func testTheVerdictsShorterLineKeepsTheResult() {
        XCTAssertEqual(PatternIndexing.header(outcome(.found), spotCount: false), "Al · 2.1° from [001] · misfit 0.07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.poor), locale: german, spotCount: false), "Al · 2,1° from [001] · found but poor · misfit 0,07 %")
        XCTAssertEqual(PatternIndexing.header(outcome(.found)), "Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 %",
                       "the whole line is as before")
    }

    // MARK: The Output lines

    func testCalibrateOnRingsLineNamesTheRingTheScaleAndTheFilesAxis() {
        let event = DiffractionEvent.calibrated(standard: "Au", family: "{111}", radius: 33.9612, deltaQ: 0.0125004, versusFilePercent: -1.0012)
        XCTAssertEqual(DiffractionEventLine.line(event, fileName: "au.dm4", locale: german),
                       "Calibrated au.dm4 on the Au {111} ring: R 33,96 px, Δq 0,01250 Å⁻¹/px, -1,00 % from the file's axis")
        let noAxis = DiffractionEvent.calibrated(standard: "Si", family: "{220}", radius: 51.5, deltaQ: 0.01, versusFilePercent: nil)
        XCTAssertEqual(DiffractionEventLine.line(noAxis, fileName: "si.tif", locale: UnitDisplay.point),
                       "Calibrated si.tif on the Si {220} ring: R 51.50 px, Δq 0.01000 Å⁻¹/px")
        XCTAssertEqual(DiffractionEventLine.line(.calibrationRefused("annulus holds no ring"), fileName: "si.tif"),
                       "Calibrate on Ring set no scale on si.tif: annulus holds no ring")
    }

    func testIndexsLineNamesThePhaseTheZoneAxisTheMisfitAndTheSpots() {
        XCTAssertEqual(DiffractionEventLine.line(.indexed(outcome(.found), solutions: 1), fileName: "al.dm4", locale: german),
                       "Index on al.dm4: Al · 2,1° from [001] · 22 of 24 spots explained · misfit 0,07 %")
        XCTAssertEqual(DiffractionEventLine.line(.indexed(outcome(.found), solutions: 2), fileName: "al.dm4", locale: UnitDisplay.point),
                       "Index on al.dm4: Al · 2.1° from [001] · 22 of 24 spots explained · misfit 0.07 % · 2 solutions")
    }

    /// A calibration on the Au demo pattern's {111} ring, on an item of the list: the list's callback hears it once, with the scale
    /// the ring set and the file's axis 1 % large. A plain Fit Ring says nothing.
    @MainActor func testACalibrationThatLandsIsToldToTheApp() async throws {
        let url = URL(fileURLWithPath: "/data/au.dm4")
        let items = OpenItems(identify: { FileIdentity(path: $0.path) }, reader: { request in
            let image = DemoDocuments.diffractionPattern()
            return OpenedImage(image: image, canvas: AppState.canvas(for: image), metadata: AcquisitionMetadata(), url: request.url,
                               thumbnail: nil, bookmark: nil)
        })
        let heard = HeardLines()
        items.onDiffractionEvent = { item, event in
            heard.lines.append(DiffractionEventLine.line(event, fileName: item.url.lastPathComponent, locale: UnitDisplay.point))
        }
        items.open(urls: [url])
        await items.settled()
        let item = try XCTUnwrap(items.items.first)
        let image = try XCTUnwrap(item.session.image)
        let analysis = item.diffraction
        analysis.bind(image)
        await analysis.fitRing(image: image, inner: 37, outer: 41.5)?.value
        XCTAssertEqual(heard.lines, [], "Fit Ring alone writes no line")
        let family = try XCTUnwrap(analysis.standardFamilies().first { $0.name == "{111}" })
        await analysis.fitRing(image: image, inner: 29, outer: 37, calibrateOn: family.family)?.value
        XCTAssertEqual(heard.lines.count, 1, "\(heard.lines)")
        let line = try XCTUnwrap(heard.lines.first)
        XCTAssertTrue(line.hasPrefix("Calibrated au.dm4 on the Au {111} ring: R 33."), line)
        XCTAssertTrue(line.contains("Δq 0.012"), line)
        XCTAssertTrue(line.hasSuffix(" % from the file's axis"), line)
    }
}
