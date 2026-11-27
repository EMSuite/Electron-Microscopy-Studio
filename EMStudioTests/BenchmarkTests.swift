//
//  BenchmarkTests.swift
//  The nightly CPU timings (tools/benchmarks/ci.sh, the Audit workflow's `benchmarks` job): opening an image, the FFT room's
//  spectrum, the EDS room's Quantify, the EELS room's Run (the maps) and Hough indexing of a pattern scan, each on generated data
//  of a fixed size, each the median of a few runs. The job compares every case with the previous night's and lists one that got
//  more than 25 % slower. Runner timings are noisy, so nothing here asserts a time: a case fails only when its work fails.
//
//  Skipped unless MACTEM_BENCHMARKS=1 (ci.sh passes it as TEST_RUNNER_MACTEM_BENCHMARKS), so the unit gate stays fast; listed in
//  tools/unit-skips.allow. Each case prints one line, `MACTEM_BENCH name=<case> dtype=<stored type> size=<size> ms=<median>`,
//  which ci.sh turns into the job's JSON.
//

import AppKit
import ShellEDXModel
import ShellLayout
import SwiftUI
import XCTest
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class BenchmarkTests: XCTestCase {

    /// One timed case's median, printed as ci.sh reads it.
    private static func report(_ name: String, dtype: String, size: String, _ runs: [Duration]) {
        let ms = runs.map { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }.sorted()
        let median = ms[ms.count / 2]
        print("MACTEM_BENCH name=\(name) dtype=\(dtype) size=\(size) ms=\(String(format: "%.3f", median)) runs=\(ms.count)")
    }

    private func scratchFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("benchmarks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// A window that draws `state`'s rooms, as RoomMemoryTests makes one; the caller closes it.
    @MainActor private func drawingWindow(_ state: AppState) -> (host: NSView, window: NSWindow) {
        let host = NSHostingView(rootView: ContentView().environment(state))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: LayoutPolicy.datasetWindowIdealSize),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    /// Opens `url` in a fresh window and enters each of `rooms`, drawn; returns the state and the window to close.
    @MainActor private func opened(_ url: URL, rooms: [WorkspaceArea]) async throws -> (state: AppState, window: NSWindow) {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        await state.open(urls: [url])?.value
        XCTAssertNil(state.errorMessage, "\(url.lastPathComponent) opened")
        for room in rooms {
            state.selectWorkspace(room)
            host.layoutSubtreeIfNeeded()
            host.display()
        }
        return (state, window)
    }

    @MainActor func testTheNightlyBenchmarks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACTEM_BENCHMARKS"] == "1",
                          "the nightly benchmarks run only where MACTEM_BENCHMARKS=1 is set (tools/benchmarks/ci.sh)")
        let dir = try scratchFolder()
        try await openAnImage(dir)
        try await theFFTSpectrum()
        try await quantifyASpectrumImage(dir)
        try await runTheEELSMaps(dir)
        try await indexAScanWithHough(dir)
    }

    /// Open: a 2048 × 2048 16-bit TIFF read and drawn (its canvas made), in a fresh window each run.
    @MainActor private func openAnImage(_ dir: URL) async throws {
        let side = 2048
        let url = dir.appendingPathComponent("open-\(side).tif")
        try DemoDocuments.writeStackTIFF(to: url, frames: 1, width: side, height: side) { _, x, y in UInt16((x * 7 + y * 13) % 4096) }
        var runs: [Duration] = []
        for run in 0..<6 {
            let state = AppState(launch: LaunchOptions(arguments: []))
            let clock = ContinuousClock(), start = clock.now
            await state.open(urls: [url])?.value
            try await waitUntil("the image's canvas", seconds: 60) { state.presentation.canvas != nil }
            if run > 0 { runs.append(clock.now - start) }     // the first run loads what every later one finds loaded
            XCTAssertNil(state.openItems.selected?.readFailure)
            while !state.openItems.items.isEmpty { state.openItems.closeSelected() }
            await state.openItems.settled()
        }
        Self.report("open TIFF", dtype: "uint16", size: "\(side)x\(side)", runs)
    }

    /// FFT: the room's spectrum of a whole 2048 × 2048 image (the power spectrum, its radial profile and the display levels).
    private func theFFTSpectrum() async throws {
        let side = 2048
        let image = FFTRoomMathPlanted(width: side, height: side).image()
        var runs: [Duration] = []
        for run in 0..<8 {
            let clock = ContinuousClock(), start = clock.now
            let product = try await FFTCompute.live.spectrum(image, FFTSpectrumKey(contentVersion: run + 1, crop: nil))
            if run > 0 { runs.append(clock.now - start) }
            XCTAssertEqual(product.width, side)
        }
        Self.report("FFT spectrum", dtype: "float32", size: "\(side)x\(side)", runs)
    }

    /// EDS quantify: Quantify on a 64 × 64 × 2048 spectrum image with Al and Si picked (the fit and the composition).
    @MainActor private func quantifyASpectrumImage(_ dir: URL) async throws {
        let url = try GeneratedFiles.spectrumImage(eels: false, nx: 64, ny: 64, channels: 2048, in: dir)
        let (state, window) = try await opened(url, rooms: [.edx])
        defer { window.contentView = nil; window.close() }
        try await waitUntil("the spectrum image to open", seconds: 120) { state.edx.hasImage && !state.edx.isBusy }
        for symbol in ["Al", "Si"] where !state.edx.picks.contains(where: { $0.symbol == symbol }) { state.edx.toggle(symbol) }
        await state.edx.settled()
        var runs: [Duration] = []
        for run in 0..<6 {
            let clock = ContinuousClock(), start = clock.now
            await state.edx.quantify()?.value
            await state.edx.settled()
            if run > 0 { runs.append(clock.now - start) }
            XCTAssertNotNil(state.edx.fit, state.edx.fitFailure ?? "no fit")
        }
        Self.report("EDS quantify", dtype: "int16", size: "64x64x2048", runs)
    }

    /// EELS map: Run on a 64 × 64 × 1024 low-loss spectrum image (Align, the t/λ map, deconvolution), in a fresh window each run,
    /// since a second Run finds every stage current.
    @MainActor private func runTheEELSMaps(_ dir: URL) async throws {
        let url = try GeneratedFiles.spectrumImage(eels: true, nx: 64, ny: 64, channels: 1024, in: dir)
        var runs: [Duration] = []
        for run in 0..<4 {
            let (state, window) = try await opened(url, rooms: [.eels])
            defer { window.contentView = nil; window.close() }
            try await waitUntil("the spectrum image to open", seconds: 120) { state.eels.hasImage && !state.eels.isBusy }
            let clock = ContinuousClock(), start = clock.now
            await state.eels.run().value
            await state.eels.settled()
            if run > 0 { runs.append(clock.now - start) }
            state.closeDocument(.eels(single: false))
            try await waitUntil("the spectrum image to close", seconds: 30) { !state.eels.hasImage && !state.eels.isBusy }
        }
        Self.report("EELS run", dtype: "int16", size: "64x64x1024", runs)
    }

    /// Hough indexing: a 24 × 32 scan of 100 × 100 uint16 patterns indexed with the first preset phase, in a fresh window each run.
    @MainActor private func indexAScanWithHough(_ dir: URL) async throws {
        let url = try GeneratedFiles.edaxScan(rows: 24, columns: 32, side: 100, ang: true, in: dir)
        var runs: [Duration] = []
        for run in 0..<4 {
            let (state, window) = try await opened(url, rooms: [.patterns, .indexing])
            defer { window.contentView = nil; window.close() }
            try await waitUntil("the scan's passes to end", seconds: 180) {
                state.ebsd.hasDataset && !state.ebsd.isOpening && !state.ebsd.isMapping && !state.ebsd.isComputingMean && !state.ebsd.isProcessing
            }
            if state.indexing.phases.isEmpty { state.indexing.addPhase(IndexingPhase.presets[0]) }
            XCTAssertNil(state.indexing.refusal)
            let clock = ContinuousClock(), start = clock.now
            await state.indexing.index().value
            if run > 0 { runs.append(clock.now - start) }
            XCTAssertNotNil(state.indexing.result, "the scan was indexed")
            state.closeDocument(.ebsdDataset)
            try await waitUntil("the scan to close", seconds: 30) { !state.ebsd.hasDataset && !state.indexing.isIndexing }
        }
        Self.report("Hough indexing", dtype: "uint16", size: "24x32x100x100", runs)
    }
}
