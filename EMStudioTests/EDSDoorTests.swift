//
//  EDSDoorTests.swift
//  The shared EDS room's own Open goes through the app's Open (`AppState.open(urls:)`, handed to MacEMUI as `EDXRoomActions.open`), as File > Open
//  and the EELS, Patterns, Indexing and Maps rooms' buttons do (#318): the file is among the window's EDS files (so the Results room lists the
//  room's numbers under it), the EDS room is in front, and the session gets the file from the app's Open.
//
//  THE FILE: an EMSA/MSA spectrum of signal type EDS_TEM (256 channels of 0.01 keV, one peak), written by FormatoKit's MSA writer into a
//  temporary folder that tearDown removes.
//

import XCTest
import FormatoCore
import FormatoMSA
import TEMCore
import TEMSession
import ShellSpectroscopy
@testable import EMStudio

nonisolated final class EDSDoorTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for folder in scratch { try? FileManager.default.removeItem(at: folder) }
        scratch = []
        super.tearDown()
    }

    private func edsSpectrum(named name: String) throws -> URL {
        var counts = [Double](repeating: 5, count: 256)
        counts[148] = 200
        counts[149] = 900
        counts[150] = 200
        var bytes = Data(capacity: counts.count * 8)
        for c in counts { withUnsafeBytes(of: c.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        let beam = FormatoMetadataEntry(key: "Acquisition_instrument.TEM.beam_energy", value: .number(200), units: "kV",
                                        provenance: FormatoProvenance(file: "", source: "test", rule: "planted"))
        let signal = FormatoSignal(title: "planted", signalType: "EDS_TEM",
                                   axes: [FormatoAxis(name: "Energy", size: counts.count, scale: 0.01, offset: 0, units: "keV", navigate: false)],
                                   metadata: FormatoMetadata([beam]),
                                   data: try FormatoArray(dataType: .float64, shape: [counts.count], bytes: bytes))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("eds-door-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        scratch.append(folder)
        let url = folder.appendingPathComponent(name)
        try MSAWriter.encode(signal, creator: "test").write(to: url)
        return url
    }

    /// Red under: no `open` in the window's `EDXRoomActions` (the room opens its session itself: the file never among the EDS files, so no
    /// Results rows, and the window left in the room it was in).
    @MainActor func testTheRoomsOpenGoesThroughTheAppsOpen() async throws {
        let url = try edsSpectrum(named: "point.msa")
        XCTAssertTrue(FileRouting.inventory(path: url.path).opensInEDS, "the planted file is an EDS spectrum")
        let state = AppState(launch: LaunchOptions(arguments: []))
        let open = try XCTUnwrap(state.edxActions.open, "the window gives the EDS room no Open of its own")
        XCTAssertEqual(state.navigation.workspaceArea, .image)

        open(url)
        try await waitUntil("the file to be among the EDS files", seconds: 10) { state.spectrumFiles.edsFiles.contains(url) }
        XCTAssertEqual(state.navigation.workspaceArea, .edx, "the EDS room is in front")
        XCTAssertTrue(state.spectrumFiles.eelsFiles.isEmpty)
        XCTAssertNil(state.errorMessage)
    }
}
