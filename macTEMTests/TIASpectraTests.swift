//
//  TIASpectraTests.swift
//  TIA spectra open in their rooms (#906): the `.emi` says EDS (`<ShapingTime>`) or EELS (`<GainCorrection>`, `<BiasCorrection>`),
//  and a series without one asks once which room, an answer kept per file; the EDS room gets whole counts laid out rows, columns,
//  channels on a keV axis with E₀ from the `.emi`, the EELS room the counts on an eV axis; a picked `.emi` stands for each of its
//  series, each a file of its own; the agent door's open_file takes the room. The files are planted here (TIA's layout, as
//  `TIAImageReaderTests` plants it): a 2 x 3 spectrum image of 4 channels, 50 eV + 10 eV a channel, 2 nm a scan pixel, element k
//  holding 10k to 10k + 3, checked when written against RosettaSciIO 0.15's `tia.file_reader`: shape (2, 3, 4), data[1, 2] =
//  50, 51, 52, 53, data[0, 1] = 10, 11, 12, 13, axes y and x 2 nm, Energy offset 50 eV scale 10 eV. Red before: a series of spectra
//  was refused in words, and an `.emi` opened its first image series only.
//

import Foundation
import FormatoCore
import ShellAgentDoor
import ShellEDXModel
import ShellLayout
import SpectroCore
import SpectroEELS
import TEMCore
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class TIASpectraTests: XCTestCase {

    // MARK: Planting

    private struct Bytes {
        var data = Data()
        mutating func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        mutating func f32(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        mutating func text(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
    }

    /// A `.ser` of spectra (SeriesVersion 528, a time tag each), float32: one element per scan position of `dims` (each a size and
    /// its scale in metres), `channels` values each from `values`, 50 eV + 10 eV a channel.
    /// An acquisition stopped early holds `valid` elements of them; the other offsets are 0.
    private static func ser(dims: [(size: Int, metres: Double)], channels: Int, values: [Float], valid: Int? = nil) -> Data {
        var d = Bytes()
        for dim in dims {
            d.u32(dim.size); d.f64(0); d.f64(dim.metres); d.u32(0); d.u32(4); d.text("Scan"); d.u32(6); d.text("meters")
        }
        let n = dims.reduce(1) { $0 * $1.size }
        let filled = valid ?? n
        let offsetsAt = 30 + d.data.count
        var elements = Bytes(), dataAt: [Int] = [], tagAt: [Int] = []
        var position = offsetsAt + 8 * n
        for k in 0 ..< filled {
            var element = Bytes()
            element.f64(50); element.f64(10); element.u32(0); element.u16(7); element.u32(channels)
            for v in values[k * channels ..< (k + 1) * channels] { element.f32(v) }
            dataAt.append(position); position += element.data.count
            tagAt.append(position); position += 8
            elements.data.append(element.data)
            elements.u16(0x4152); elements.u16(0); elements.u32(0)
        }
        var file = Bytes()
        file.u16(0x4949); file.u16(0x0197); file.u16(528)
        file.u32(0x4120); file.u32(0x4152); file.u32(n); file.u32(filled); file.u32(offsetsAt); file.u32(dims.count)
        file.data.append(d.data)
        for at in dataAt + Array(repeating: 0, count: n - filled) { file.u32(at) }
        for at in tagAt + Array(repeating: 0, count: n - filled) { file.u32(at) }
        file.data.append(elements.data)
        return file.data
    }

    /// An `.emi` whose first document records 200 kV and whose second records the detector by `tags` (none: no detector document).
    private static func emi(detector tags: [String]) -> Data {
        var file = Bytes()
        file.data.append(contentsOf: [0x4A, 0x4B, 0x00, 0x02])
        file.text("<ObjectInfo><ExperimentalDescription><Root>"
            + "<Data><Label>High tension</Label><Value>200</Value><Unit>kV</Unit></Data>"
            + "</Root></ExperimentalDescription></ObjectInfo>")
        if !tags.isEmpty {
            file.text("<ObjectInfo><AcquireInfo>" + tags.map { "<\($0)>1</\($0)>" }.joined() + "</AcquireInfo></ObjectInfo>")
        }
        return file.data
    }

    private static let cube = TIASpectraTests.ser(dims: [(2, 2e-9), (3, 2e-9)], channels: 4,
                                                  values: (0 ..< 6).flatMap { k in (0 ..< 4).map { Float(10 * k + $0) } })

    /// A folder of its own with `files` in it.
    private func folder(_ files: [String: Data]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tia-spectra-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: dir.appendingPathComponent(name)) }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: Which room

    /// Mutation: the tags swapped, either alone not enough, or both taken as one room.
    func testTheEMISaysTheRoomByItsDetectorOrNothing() {
        XCTAssertEqual(TIASpectra.room(emi: Self.emi(detector: ["ShapingTime"])), .eds)
        XCTAssertEqual(TIASpectra.room(emi: Self.emi(detector: ["GainCorrection", "BiasCorrection"])), .eels)
        XCTAssertEqual(TIASpectra.room(emi: Self.emi(detector: ["BiasCorrection"])), .eels)
        XCTAssertNil(TIASpectra.room(emi: Self.emi(detector: ["ShapingTime", "GainCorrection"])), "both: ask")
        XCTAssertNil(TIASpectra.room(emi: Self.emi(detector: [])), "neither: ask")
    }

    /// The routing sends the series to the room its `.emi` says, and a series alone asks; the answer kept for the file routes it.
    /// Mutation: spectra still refused, the `.emi` not read, the kept answer not applied.
    func testTheRoutingSendsSpectraToTheirRoomOrAsks() throws {
        let eds = try folder(["si.emi": Self.emi(detector: ["ShapingTime"]), "si_1.ser": Self.cube])
        XCTAssertEqual(FileRouting.inventory(path: eds.appendingPathComponent("si_1.ser").path), FileInventory(edsSpectrumImage: true))
        let eels = try folder(["si.emi": Self.emi(detector: ["GainCorrection"]), "si_1.ser": Self.cube])
        XCTAssertEqual(FileRouting.inventory(path: eels.appendingPathComponent("si_1.ser").path), FileInventory(eelsSpectrumImage: true))

        let alone = try folder(["si_1.ser": Self.cube]).appendingPathComponent("si_1.ser")
        let asks = FileRouting.inventory(path: alone.path)
        XCTAssertTrue(asks.asksForSpectraRoom)
        XCTAssertNil(asks.refusal)
        XCTAssertNil(asks.landing, "nothing opens until the question is answered")
        XCTAssertEqual(TIASpectraRooms.routed(asks, url: alone), asks, "no answer yet")
        TIASpectraRooms.remember(.eels, for: alone)
        XCTAssertEqual(TIASpectraRooms.routed(asks, url: alone), FileInventory(eelsSpectrumImage: true))
        XCTAssertEqual(TIASpectra.askTitle(names: ["si_1.ser"]), "Which room opens the TIA spectra of si_1.ser?")
        XCTAssertEqual(TIASpectra.askTitle(names: ["a_1.ser", "b_1.ser"]), "Which room opens the TIA spectra of 2 files?")
    }

    // MARK: The rooms

    /// The EDS room's spectrum image: 2 rows, 3 columns, 4 channels, element k at (k / 3, k % 3), 0.05 keV + 0.01 keV a channel,
    /// 200 kV from the `.emi`, 2 nm a scan pixel. Mutation: rows and columns swapped, the axis left in eV, E₀ not read.
    func testTheEDSRoomGetsTheCubeOnAKeVAxis() throws {
        let dir = try folder(["si.emi": Self.emi(detector: ["ShapingTime"]), "si_1.ser": Self.cube])
        let loaded = try EDXOpening.open(url: dir.appendingPathComponent("si_1.ser"))
        XCTAssertEqual(loaded.image.ny, 2)
        XCTAssertEqual(loaded.image.nx, 3)
        XCTAssertEqual(loaded.image.channels, 4)
        func pixel(x: Int, y: Int) -> [UInt64] {
            var mask = PixelMask(repeating: false, count: loaded.image.ny * loaded.image.nx)
            mask[y * loaded.image.nx + x] = true
            return loaded.image.sum(mask: mask)
        }
        XCTAssertEqual(pixel(x: 2, y: 1), [50, 51, 52, 53])
        XCTAssertEqual(pixel(x: 1, y: 0), [10, 11, 12, 13])
        XCTAssertEqual(loaded.energyAxis.offset, 0.05, accuracy: 1e-12)
        XCTAssertEqual(loaded.energyAxis.scale, 0.01, accuracy: 1e-12)
        XCTAssertEqual(loaded.metadata.beamEnergyKeV, 200)
        XCTAssertEqual(try XCTUnwrap(loaded.metadata.scanPixelSize), 2, accuracy: 1e-12)
        XCTAssertEqual(loaded.metadata.scanPixelUnit, "nm")
        XCTAssertTrue(EDXOpening.isSpectrumImage(at: dir.appendingPathComponent("si_1.ser")))
    }

    /// A negative count is no count spectrum. Mutation: the values clamped to 0 instead.
    func testTheEDSRoomRefusesNegativeCounts() throws {
        let dir = try folder(["neg_1.ser": Self.ser(dims: [(2, 2e-9)], channels: 2, values: [1, -1, 2, 3])])
        XCTAssertThrowsError(try EDXOpening.open(url: dir.appendingPathComponent("neg_1.ser")))
    }

    /// The EELS room's cube: the same layout on its eV axis, E₀ from the `.emi`. Mutation: the `.ser` not an EELS extension, the
    /// axis taken in keV, rows and columns swapped.
    func testTheEELSRoomGetsTheCubeOnAnEVAxis() throws {
        let dir = try folder(["si.emi": Self.emi(detector: ["GainCorrection"]), "si_1.ser": Self.cube])
        XCTAssertTrue(EELSOpening.readableExtensions.contains("ser"))
        let loaded = try EELSOpening.open(url: dir.appendingPathComponent("si_1.ser"))
        XCTAssertEqual(loaded.image.nx, 3)
        XCTAssertEqual(loaded.image.ny, 2)
        XCTAssertEqual(loaded.image.channels, 4)
        XCTAssertEqual(loaded.image.energyOffsetEV, 50, accuracy: 1e-12)
        XCTAssertEqual(loaded.image.energyScaleEV, 10, accuracy: 1e-12)
        XCTAssertEqual(loaded.beamEnergyKeV, 200)
        XCTAssertEqual(loaded.scanPixelUnit, "nm")
        XCTAssertEqual(loaded.origin, "TIA series si_1.ser (EELS)")
    }

    /// A 2 x 2 spectrum image stopped after 3 positions (RosettaSciIO 0.15 reads it as [[[0, 1], [2, 3]], [[4, 5], [nan, nan]]]):
    /// the fourth is an empty spectrum in both rooms, and the EELS room's origin says so. Mutation: the NaN kept, and the
    /// file refused as "not a count spectrum".
    func testASpectrumImageStoppedEarlyOpensWithItsUnfilledPositionsEmpty() throws {
        let stopped = Self.ser(dims: [(2, 2e-9), (2, 2e-9)], channels: 2, values: (0 ..< 6).map(Float.init), valid: 3)
        let dir = try folder(["stop_1.ser": stopped])
        let eds = try EDXOpening.open(url: dir.appendingPathComponent("stop_1.ser"))
        func pixel(x: Int, y: Int) -> [UInt64] {
            var mask = PixelMask(repeating: false, count: 4)
            mask[y * 2 + x] = true
            return eds.image.sum(mask: mask)
        }
        XCTAssertEqual(pixel(x: 0, y: 1), [4, 5])
        XCTAssertEqual(pixel(x: 1, y: 1), [0, 0])
        let eels = try EELSOpening.open(url: dir.appendingPathComponent("stop_1.ser"))
        XCTAssertEqual(eels.origin, "TIA series stop_1.ser (EELS), stopped early: 3 of 4 positions acquired, the others empty")
    }

    // MARK: The series of an .emi

    /// An `.emi` stands for each `.ser` of it that opens, in order, each routed on its own. Mutation: the first image series only,
    /// the digits out of order, the `.emi` itself left in the batch.
    func testAPickedEMIOpensEachOfItsSeries() async throws {
        let dir = try folder(["run.emi": Self.emi(detector: ["ShapingTime"]), "run_2.ser": Self.cube, "run_1.ser": Self.cube])
        let emi = dir.appendingPathComponent("run.emi")
        XCTAssertEqual(TIASpectra.seriesFiles(of: emi).map(\.lastPathComponent), ["run_1.ser", "run_2.ser"])
        XCTAssertEqual(TIASpectra.seriesFiles(of: dir.appendingPathComponent("run_1.ser")), [], "a .ser stands for itself")
        let routed = await AppState.inventories([emi], memory: ProcessInfo.processInfo.physicalMemory)
        XCTAssertEqual(routed.map { $0.url.lastPathComponent }, ["run_1.ser", "run_2.ser"])
        XCTAssertEqual(routed.map { $0.inventory }, [FileInventory(edsSpectrumImage: true), FileInventory(edsSpectrumImage: true)])
        // Picked with one of its own series, the .emi opens it once.
        let both = [emi, dir.appendingPathComponent("run_1.ser")]
        XCTAssertEqual(TIASpectra.withoutSeriesOfPickedEMI(both), [emi])
        let routedBoth = await AppState.inventories(both, memory: ProcessInfo.processInfo.physicalMemory)
        XCTAssertEqual(routedBoth.map { $0.url.lastPathComponent }, ["run_1.ser", "run_2.ser"])
    }

    // MARK: The agent door

    /// open_file refuses spectra no `.emi` places without `room`, and with it opens them in that room. Mutation: the alert raised
    /// for an agent, the room argument not kept for the Open.
    @MainActor func testOpenFileTakesTheRoomOfSpectraNoEMIPlaces() async throws {
        let suite = "tia-spectra-door-\(UUID().uuidString)"
        let door = AgentDoor(appName: "macEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        door.register(MacTEMAgentDoor.allTools)
        door.runsAllowed = true
        door.setEnabled(true)
        let root = try folder(["point_1.ser": Self.ser(dims: [(1, 1e-9)], channels: 4, values: [5, 6, 7, 8])])
        MacTEMAgentDoor.folder.use(folder: root)
        defer {
            door.setEnabled(false)
            MacTEMAgentDoor.folder.use(folder: nil)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        try await waitUntil("the door to open", seconds: 5) { if case .listening = door.status { return true } else { return false } }
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        let state = AppState(launch: LaunchOptions(arguments: []))
        door.enroll(state) { [weak state] in state.map { MacTEMAgentDoor.summary(of: $0) } ?? [:] }

        func call(_ arguments: [String: Any]) async throws -> (refused: Bool, text: String) {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
            request.httpMethod = "POST"
            request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "open_file", "arguments": arguments],
            ])
            let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
            let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try XCTUnwrap(answer["result"] as? [String: Any], String(decoding: data, as: UTF8.self))
            return (result["isError"] as? Bool ?? false, ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "")
        }

        let refused = try await call(["path": "point_1.ser"])
        XCTAssertTrue(refused.refused, refused.text)
        XCTAssertTrue(refused.text.contains("give room eds or eels"), refused.text)
        XCTAssertNil(state.lastOpen, "nothing opened, no question raised")

        let opened = try await call(["path": "point_1.ser", "room": "eds"])
        XCTAssertFalse(opened.refused, opened.text)
        await state.lastOpen?.value
        XCTAssertEqual(state.navigation.workspaceArea, .edx)
        XCTAssertEqual(state.edx.source?.metadata.fileName, "point_1.ser")
    }
}
