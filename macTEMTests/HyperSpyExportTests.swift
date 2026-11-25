//
//  HyperSpyExportTests.swift
//  Export HyperSpy File… (#819, plan row X3; `HyperSpyExport`, `HyperSpyExportPanel`): an image and a pattern written as .hspy
//  and read back with FormatoKit's own reader (the kit's pins H2 and H4 hold it to HyperSpy 2.5.0's): the pixels at their stored
//  type, the axes with their calibration (a pattern's in Å⁻¹ with the zero at the centre), HyperSpy's signal type for the class,
//  and the methods record and the beam energy in the metadata tree. Too little free space is refused before anything is written.
//  Red before: the export did not exist.
//

import FormatoCore
import FormatoHSPY
import Foundation
import ImagoCore
import ShellExport
import SpectroEELS
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class HyperSpyExportTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("hspy-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A 3 × 2 uint16 image, 0.5 nm a pixel in x and 0.25 nm in y, the x zero at pixel 1.
    private func image() -> CalibratedImage {
        CalibratedImage(width: 3, height: 2, stored: .uint16([1, 2, 3, 400, 500, 65535]),
                        x: AxisCalibration(scale: 0.5, unit: "nm", origin: 1), y: AxisCalibration(scale: 0.25, unit: "nm"),
                        fileName: "scan.dm4", source: "ImageList.1", voltage: 200_000)
    }

    private static let record = MethodsRecord(
        app: MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.4.0 (1)"), room: "image", exportKind: "image-hspy",
        kits: [], sources: [MethodsRecord.Source(fileName: "scan.dm4", byteCount: 12, fingerprint: String(repeating: "ab", count: 32),
                                                 kind: "image", shape: [3, 2])],
        steps: [], drawn: [])

    /// Mutation: the pixels widened to float32, the axes swapped or their zero lost, or the record left out of the tree - red.
    func testAnImageKeepsItsTypeItsAxesAndItsRecord() async throws {
        let url = folder.appendingPathComponent("scan.hspy")
        let options = try HyperSpyExport.options(title: "scan", software: "Electron Microscopy Studio 2.4.0 (1)", record: Self.record,
                                                 beamEnergyKeV: 200)
        try await HyperSpyExport.write(try HyperSpyExport.imageSignal(image()), kind: .generic, options: options, to: url)

        let read = try HSPYReader.readStored(url: url)
        XCTAssertEqual(read.title, "scan")
        XCTAssertEqual(read.signalType, "")
        XCTAssertEqual(read.data.dataType, .uint16)
        XCTAssertEqual(read.data.shape, [2, 3])
        XCTAssertEqual(read.data.bytes, [UInt16]([1, 2, 3, 400, 500, 65535]).withUnsafeBytes { Data($0) })
        XCTAssertEqual(read.axes.map(\.name), ["y", "x"])
        XCTAssertEqual(read.axes.map(\.scale), [0.25, 0.5])
        XCTAssertEqual(read.axes.map(\.offset), [0, -0.5])
        XCTAssertEqual(read.axes.map(\.units), ["nm", "nm"])
        XCTAssertEqual(read.axes.map(\.navigate), [false, false])
        guard case .text(let json)? = read.metadata[HyperSpyExport.recordKey]?.value else {
            return XCTFail("no record in \(read.metadata.entries.map(\.key))")
        }
        XCTAssertEqual(try MethodsRecord.decode(json), Self.record)
        XCTAssertEqual(read.metadata[HyperSpyExport.beamEnergyKey]?.value, .number(200))
    }

    /// A pattern with the room's scale is pyxem's ElectronDiffraction2D in Å⁻¹, centred; without one it keeps the file's axes.
    /// Mutation: the signal type not electron_diffraction, or the zero not at the centre - red.
    func testAPatternIsElectronDiffractionCentredInReciprocalAngstroms() async throws {
        let url = folder.appendingPathComponent("pattern.hspy")
        let scale = HyperSpyExport.PatternScale(deltaQ: 0.0125, centreRow: 1, centreColumn: 1.5)
        let options = try HyperSpyExport.options(title: "pattern", software: "test", record: nil, beamEnergyKeV: nil)
        try await HyperSpyExport.write(try HyperSpyExport.patternSignal(image(), scale: scale), kind: .electronDiffraction, options: options,
                                       to: url)
        let read = try HSPYReader.readStored(url: url)
        XCTAssertEqual(read.signalType, "electron_diffraction")
        XCTAssertEqual(read.axes.map(\.name), ["ky", "kx"])
        XCTAssertEqual(read.axes.map(\.units), ["Å⁻¹", "Å⁻¹"])
        XCTAssertEqual(read.axes.map(\.scale), [0.0125, 0.0125])
        XCTAssertEqual(read.axes.map(\.offset), [-1 * 0.0125, -1.5 * 0.0125])
        XCTAssertNil(read.metadata[HyperSpyExport.recordKey], "no record was given")

        let plain = try HyperSpyExport.patternSignal(image(), scale: nil)
        XCTAssertEqual(plain.axes.map(\.units), ["nm", "nm"], "the file's calibration")
    }

    /// Mutation: the space not checked, or checked after the write began - red.
    func testTooLittleFreeSpaceIsRefusedInWords() throws {
        let url = folder.appendingPathComponent("big.hspy")
        XCTAssertThrowsError(try HyperSpyExport.checkSpace(for: 2_000_000, at: url, free: 1_000_000)) { error in
            XCTAssertEqual(error as? HyperSpyExport.Refusal, .notEnoughSpace(needed: 2_000_000, free: 1_000_000))
            XCTAssertTrue(error.localizedDescription.contains("free"), error.localizedDescription)
        }
        XCTAssertNoThrow(try HyperSpyExport.checkSpace(for: 1_000, at: url, free: 1_000_000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The Diffraction room's item writes the pattern on screen as electron diffraction, the Image room's the image as a plain
    /// signal; the file names are left out of the title when asked. Mutation: the room not choosing the class, or the title
    /// keeping the name - red.
    @MainActor func testTheRoomChoosesTheClassAndTheTitle() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.diffraction)?.value
        try await waitUntil("the demo pattern to open", seconds: 60) { state.openItems.selected?.session.image != nil }
        state.navigation.workspaceArea = .diffraction
        XCTAssertTrue(HyperSpyExportPanel.isAvailable(in: state))
        let pattern = try XCTUnwrap(HyperSpyExportPanel.snapshot(of: state))
        XCTAssertEqual(pattern.kind, .electronDiffraction)
        state.navigation.workspaceArea = .image
        let image = try XCTUnwrap(HyperSpyExportPanel.snapshot(of: state))
        XCTAssertEqual(image.kind, .generic)
        state.navigation.workspaceArea = .fft
        XCTAssertFalse(HyperSpyExportPanel.isAvailable(in: state))

        let url = folder.appendingPathComponent("anonymous.hspy")
        try await HyperSpyExportPanel.write(pattern, to: url, leaveOutFileNames: true, software: "test")
        XCTAssertEqual(try HSPYReader.readStored(url: url).title, ExportMethods.anonymousName(0))
    }

    /// A float32 EELS cube is exspy's EELSSpectrum: y and x navigate, the energy loss in eV is the signal axis, the counts stay
    /// float32 and the fraction written reaches 1. Mutation: the cube widened to float64, the navigation flags lost, or the
    /// progress not reported - red.
    func testAnEELSCubeIsWrittenAsEELSSpectrumWithProgress() async throws {
        let values: [Float] = (0..<24).map { Float($0) * 1.5 }
        let url = folder.appendingPathComponent("cube.hspy")
        let axes = HyperSpyExport.CubeAxes(scanStep: 2, scanUnit: "nm", energyOffsetEV: -5, energyScaleEV: 0.25)
        let options = try HyperSpyExport.options(title: "cube", software: "test", record: Self.record, beamEnergyKeV: 300)
        let seen = Fractions()
        try await HyperSpyExport.writeCube(EELSCounts(values), nx: 3, ny: 2, channels: 4, axes: axes, options: options, to: url) {
            seen.add($0)
        }
        let read = try HSPYReader.readStored(url: url)
        XCTAssertEqual(read.signalType, "EELS")
        XCTAssertEqual(read.data.dataType, .float32)
        XCTAssertEqual(read.data.shape, [2, 3, 4])
        XCTAssertEqual(read.data.bytes, values.withUnsafeBytes { Data($0) })
        XCTAssertEqual(read.axes.map(\.navigate), [true, true, false])
        XCTAssertEqual(read.axes.map(\.units), ["nm", "nm", "eV"])
        XCTAssertEqual(read.axes[2].offset, -5)
        XCTAssertEqual(read.axes[2].scale, 0.25)
        XCTAssertEqual(read.metadata[HyperSpyExport.beamEnergyKey]?.value, .number(300))
        XCTAssertEqual(seen.values.last, 1)
    }

    /// Stop: a cancelled write throws FormatoCancelled and leaves no file. Mutation: the cancellation not reaching the writer - red.
    func testAStoppedCubeLeavesNoFile() async throws {
        let url = folder.appendingPathComponent("stopped.hspy")
        let axes = HyperSpyExport.CubeAxes(scanStep: nil, scanUnit: nil, energyOffsetEV: 0, energyScaleEV: 1)
        let options = try HyperSpyExport.options(title: "stopped", software: "test", record: nil, beamEnergyKeV: nil)
        let task = Task { () async throws in
            withUnsafeCurrentTask { $0?.cancel() }
            try await HyperSpyExport.writeCube(EELSCounts([Double](repeating: 1, count: 8)), nx: 2, ny: 2, channels: 2, axes: axes,
                                               options: options, to: url) { _ in }
        }
        let result = await task.result
        guard case .failure(let error) = result else { return XCTFail("the write went through") }
        XCTAssertTrue(error is FormatoCancelled, "\(error)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The EELS room's item writes the demo spectrum image as EELSSpectrum with its record. Mutation: the room not offering it, or
    /// the record not made for the cube - red.
    @MainActor func testTheEELSRoomWritesItsSpectrumImage() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        _ = state.openDemo(.eels)
        state.navigation.workspaceArea = .eels
        XCTAssertTrue(HyperSpyExportPanel.isAvailable(in: state))
        XCTAssertTrue(HyperSpyExportPanel.isAvailable(in: state, coreLoss: true), "the demo has a core loss (#1088)")
        let snapshot = try XCTUnwrap(HyperSpyExportPanel.snapshot(of: state))
        XCTAssertEqual(snapshot.kind, .eels)
        let url = folder.appendingPathComponent("eels.hspy")
        try await HyperSpyExportPanel.write(snapshot, to: url, leaveOutFileNames: false, software: "test")
        let read = try HSPYReader.readStored(url: url)
        XCTAssertEqual(read.signalType, "EELS")
        guard case .text(let json)? = read.metadata[HyperSpyExport.recordKey]?.value else { return XCTFail("no record") }
        XCTAssertEqual(try MethodsRecord.decode(json).room, "eels")
    }

    /// A cube's write is the EELS room's running work: the toolbar names it with its fraction, ⌘. stops it, and the File menu has no
    /// Stop item of its own. Mutation: the write left out of the room's busy state, or ⌘. not cancelling it - red.
    @MainActor func testACubesWriteIsTheEELSRoomsRunningWork() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        state.navigation.workspaceArea = .eels
        XCTAssertFalse(RoomPrimaryAction.canStop(room: .eels, appState: state))
        let task = Task<Void, any Error> { try await Task.sleep(for: .seconds(60)) }
        state.hyperSpyWrite = HyperSpyCubeWrite(task: task, fileName: "cube.hspy", fraction: 0.4)
        XCTAssertTrue(state.isEELSRoomBusy)
        XCTAssertTrue(RoomPrimaryAction.canStop(room: .eels, appState: state))
        XCTAssertEqual(BusyOperation.name(room: .eels, appState: state), "Exporting cube.hspy…")
        XCTAssertEqual(BusyOperation.toolbarOperation(room: .eels, appState: state), "Exporting cube.hspy…")
        XCTAssertEqual(try XCTUnwrap(RoomProgress.fraction(room: .eels, appState: state)), 0.4, accuracy: 1e-12)
        RoomPrimaryAction.stopActive(state)
        XCTAssertTrue(task.isCancelled)
        _ = await task.result
    }
}

/// The fractions a write reported, from whichever thread it reported them on.
nonisolated private final class Fractions: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] { lock.withLock { stored } }
    func add(_ value: Double) { lock.withLock { stored.append(value) } }
}
