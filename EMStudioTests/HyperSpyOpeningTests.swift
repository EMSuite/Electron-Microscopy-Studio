//
//  HyperSpyOpeningTests.swift
//  Opening a HyperSpy file through FormatoKit's reader (#820, plan row X4; `HyperSpyOpening`): the files Export as HyperSpy File…
//  writes (#819) open again with equal counts, type and axes (an image in the Image room, a pattern in Å⁻¹, an EELS cube in the EELS
//  room, an EDS cube in the EDS room), and a file of several experiments sends each to its room, as a Velox file's image and streams
//  go. Fixture: tools/parity/sem-readers/make_hspy_two_experiments_fixture.py.
//  Red before: the app's own reader opened a file of one spectrum only and refused every other HyperSpy file.
//

import FormatoCore
import FormatoHSPY
import Foundation
import ImagoCore
import SpectroCore
import SpectroEELS
import TEMCore
import XCTest

nonisolated final class HyperSpyOpeningTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("hspy-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private static let options = HSPYWriteOptions(title: "written", software: "test", metadata: [HyperSpyExport.beamEnergyKey: .number(300)])

    /// An exported uint16 image reopens in the Image room with the same pixels, type and axes (x zero at pixel 1, 0.5 nm; y 0.25 nm),
    /// and the beam energy as the voltage. Mutation: the image widened to float32, an axis's zero or scale lost - red.
    func testAnExportedImageReopensWithItsPixelsAndAxes() async throws {
        let image = CalibratedImage(width: 3, height: 2, stored: .uint16([1, 2, 3, 400, 500, 65535]),
                                    x: AxisCalibration(scale: 0.5, unit: "nm", origin: 1), y: AxisCalibration(scale: 0.25, unit: "nm"),
                                    fileName: "scan.dm4", source: "ImageList.1", voltage: nil)
        let url = folder.appendingPathComponent("scan.hspy")
        try await HyperSpyExport.write(try HyperSpyExport.imageSignal(image), kind: .generic, options: Self.options, to: url)

        XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(image: true))
        let read = try ImageOpening.openNow(path: url.path)
        XCTAssertEqual(read.stored, image.stored)
        XCTAssertEqual(read.width, 3)
        XCTAssertEqual(read.height, 2)
        XCTAssertEqual(read.x, image.x)
        XCTAssertEqual(read.y?.scale, 0.25)
        XCTAssertEqual(read.y?.unit, "nm")
        XCTAssertEqual(read.y?.origin ?? .nan, 0, accuracy: 1e-12)
        XCTAssertEqual(read.voltage, 300_000)
        XCTAssertEqual(read.fileName, "scan.hspy")
    }

    /// An exported pattern reopens with its reciprocal axes in Å⁻¹ and the zero at the centre it was written with.
    /// Mutation: the zero read from the offset with the wrong sign - red.
    func testAnExportedPatternReopensCentredInReciprocalAngstroms() async throws {
        let image = CalibratedImage(width: 4, height: 4, pixels: (0..<16).map(Float.init), x: nil, y: nil, fileName: "p.dm4", source: "",
                                    voltage: nil)
        let url = folder.appendingPathComponent("pattern.hspy")
        let scale = HyperSpyExport.PatternScale(deltaQ: 0.0125, centreRow: 1.5, centreColumn: 2)
        try await HyperSpyExport.write(try HyperSpyExport.patternSignal(image, scale: scale), kind: .electronDiffraction, options: Self.options,
                                       to: url)
        let read = try ImageOpening.openNow(path: url.path)
        XCTAssertEqual(read.stored, image.stored)
        XCTAssertEqual(read.x?.unit, "Å⁻¹")
        XCTAssertEqual(read.x?.scale, 0.0125)
        XCTAssertEqual(read.x?.origin ?? .nan, 2, accuracy: 1e-9)
        XCTAssertEqual(read.y?.origin ?? .nan, 1.5, accuracy: 1e-9)
    }

    /// An exported EELS cube reopens in the EELS room with equal counts, its energy axis, its scan step and beam energy.
    /// Mutation: the cube's y and x swapped, the energy offset lost, or the EELS route not taken - red.
    func testAnExportedEELSCubeReopensInTheEELSRoom() async throws {
        let values: [Float] = (0..<24).map { Float($0) * 1.5 }
        let url = folder.appendingPathComponent("cube.hspy")
        let axes = HyperSpyExport.CubeAxes(scanStep: 2, scanUnit: "nm", energyOffsetEV: -5, energyScaleEV: 0.25)
        try await HyperSpyExport.writeCube(EELSCounts(values), nx: 3, ny: 2, channels: 4, axes: axes, options: Self.options, to: url) { _ in }

        XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(eelsSpectrumImage: true))
        let loaded = try EELSOpening.open(url: url)
        XCTAssertEqual(loaded.image.nx, 3)
        XCTAssertEqual(loaded.image.ny, 2)
        XCTAssertEqual(loaded.image.channels, 4)
        XCTAssertEqual(loaded.image.energyOffsetEV, -5)
        XCTAssertEqual(loaded.image.energyScaleEV, 0.25)
        XCTAssertEqual(loaded.image.storedCounts.doubles, values.map(Double.init))
        XCTAssertEqual(loaded.beamEnergyKeV, 300)
        XCTAssertEqual(loaded.scanPixelSize, 2)
        XCTAssertEqual(loaded.scanPixelUnit, "nm")
        XCTAssertNil(loaded.coreLoss)
    }

    /// An EDS spectrum image in HyperSpy's layout opens in the EDS room with its counts and its axis in keV.
    /// Mutation: the eV axis not converted to keV, or the cube not routed to the EDS room - red.
    func testAnEDSCubeOpensInTheEDSRoom() throws {
        let counts: [UInt16] = (0..<(2 * 3 * 8)).map { UInt16($0 * 7) }
        let data = try FormatoArray(dataType: .uint16, shape: [2, 3, 8], bytes: counts.withUnsafeBytes { Data($0) })
        let axes = [FormatoAxis(name: "y", size: 2, scale: 1, offset: 0, units: "µm", navigate: true),
                    FormatoAxis(name: "x", size: 3, scale: 1, offset: 0, units: "µm", navigate: true),
                    FormatoAxis(name: "Energy", size: 8, scale: 10, offset: -100, units: "eV", navigate: false)]
        let signal = FormatoSignal(title: "map", signalType: "EDS_TEM", axes: axes, metadata: FormatoMetadata(), data: data)
        let url = folder.appendingPathComponent("map.hspy")
        try HSPYWriter.write(signal, kind: .edsTEM, options: Self.options, to: url)

        let inventory = FileRouting.inventory(path: url.path)
        XCTAssertEqual(inventory, FileInventory(edsSpectrumImage: true))
        XCTAssertTrue(EDXOpening.isSpectrumImage(at: url))
        let loaded = try EDXOpening.open(url: url)
        XCTAssertEqual(loaded.nx, 3)
        XCTAssertEqual(loaded.ny, 2)
        XCTAssertEqual(loaded.channels, 8)
        let sums = (0..<8).map { c in stride(from: c, to: counts.count, by: 8).reduce(UInt64(0)) { $0 + UInt64(counts[$1]) } }
        XCTAssertEqual(loaded.image.sum(mask: nil), sums)
        XCTAssertEqual(loaded.energyAxis.offset, -0.1, accuracy: 1e-12)
        XCTAssertEqual(loaded.energyAxis.scale, 0.01, accuracy: 1e-12)
        XCTAssertEqual(loaded.metadata.scanPixelUnit, "µm")
        XCTAssertEqual(loaded.metadata.beamEnergyKeV, 300)
    }

    /// A file of a survey image and an EELS spectrum image sends each to its room: the image to the Image room, the cube to the EELS
    /// room, as a Velox file's image and EELS stream go. Mutation: only the first experiment taken, or a file of several refused - red.
    func testAFileOfSeveralExperimentsOpensEachInItsRoom() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/hspy/hyperspy-image-and-eels.hspy")
        XCTAssertEqual(FileRouting.inventory(path: url.path), FileInventory(image: true, eelsSpectrumImage: true))
        let image = try ImageOpening.openNow(path: url.path)
        XCTAssertEqual(image.stored, .uint16((0..<12).map(UInt16.init)))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.x?.scale, 0.5)
        let eels = try EELSOpening.open(url: url)
        XCTAssertEqual(eels.image.nx, 2)
        XCTAssertEqual(eels.image.channels, 5)
        XCTAssertEqual(eels.image.energyOffsetEV, -1)
        XCTAssertEqual(eels.image.storedCounts.doubles, (0..<20).map { 0.5 * Double($0) })
        XCTAssertEqual(eels.beamEnergyKeV, 200)
    }
}
