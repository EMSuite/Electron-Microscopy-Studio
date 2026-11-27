//
//  DocumentMemoryBudgetTests.swift
//  What each kind of document costs while it is open, held to a budget (2.3 plan row Q2): a file opened in a window that draws,
//  shown in its room and settled, may grow the process's physical footprint by at most its kind's factor of the bytes the file
//  stores (plus a fixed allowance for the room's own first canvases), and an empty window may cost at most the idle budget. A
//  change that holds one more copy of the pixels than the kind needs (a second Float32 image, a canvas kept twice, a cube widened
//  twice) fails here by name, before a user's large file finds it.
//
//  THE KINDS, each written by the test (GeneratedFiles.swift): an 8-bit, a 16-bit and a 32-bit float 4096 × 4096 image, a stack of
//  16 frames of 1024 × 1024 16-bit, an EDS and an EELS spectrum image (GMS DM4, int16), an EDAX pattern scan with its `.ang`. Each
//  kind is opened small first, so what the first open of its kind loads for good (shaders, SwiftUI's caches) is in the baseline;
//  the measure is the footprint (`ImageStackTests.footprint()`) with the window drawing, before the open and at its largest while
//  open. RoomMemoryTests checks the other half: that the close gives it back.
//
//  The factors are what the room holds by design, with room for the runner's noise: an image is widened to Float32 once and drawn
//  from a display canvas, a cube is held as the room's 32-bit values. Each run prints every kind's cost and factor, so a green run
//  shows the margin; a factor is raised only with the reason in its line.
//

import AppKit
import ShellEDXModel
import ShellLayout
import SwiftUI
import XCTest
import TEMSession
@testable import EMStudio

nonisolated final class DocumentMemoryBudgetTests: XCTestCase {

    /// A fixed allowance over the factor: a room's first canvases, its histogram and its chart, which do not grow with the file.
    private static let allowance = 48 << 20

    /// The process's footprint once malloc has handed its free pages back.
    private static func footprint() -> Int {
        _ = malloc_zone_pressure_relief(nil, 0)
        return ImageStackTests.footprint()
    }

    private func scratchFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("memory-budget-\(UUID().uuidString)")
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

    /// One kind of document: how it is shown, when its room has settled, and how it is closed.
    private struct Kind {
        let name: String
        let rooms: [WorkspaceArea]
        /// The largest footprint growth allowed, as a multiple of the bytes the file stores (plus `allowance`).
        let factor: Double
        let ready: @MainActor (AppState) -> Bool
        let close: @MainActor (AppState) -> Void
        let closed: @MainActor (AppState) -> Bool
    }

    /// An image kind: shown in the Image room, settled once its canvas is drawn, closed as File > Close closes the open items.
    private static func kind(_ name: String, factor: Double) -> Kind {
        Kind(name: name, rooms: [.image], factor: factor, ready: { $0.presentation.canvas != nil && $0.openItems.selected != nil },
             close: { state in while !state.openItems.items.isEmpty { state.openItems.closeSelected() } },
             closed: { $0.openItems.items.isEmpty })
    }

    /// Opens `url`, shows each of the kind's rooms drawn, waits until it has settled, and returns the largest footprint seen; then
    /// closes it and waits until it is gone.
    @MainActor private func openShowClose(_ url: URL, _ kind: Kind, state: AppState, host: NSView) async throws -> Int {
        func draw() { host.layoutSubtreeIfNeeded(); host.display() }
        await state.open(urls: [url])?.value
        XCTAssertNil(state.errorMessage, "\(url.lastPathComponent) opened")
        var peak = Self.footprint()
        for room in kind.rooms {
            state.selectWorkspace(room)
            XCTAssertEqual(state.navigation.workspaceArea, room, "\(room.title) can be entered")
            draw()
            try await waitUntil("\(url.lastPathComponent) to settle in \(room.title)", seconds: 120) { kind.ready(state) }
            draw()
            try await Task.sleep(for: .milliseconds(300))
            draw()
            peak = max(peak, Self.footprint())
        }
        kind.close(state)
        try await waitUntil("\(url.lastPathComponent) to close", seconds: 30) { kind.closed(state) }
        await state.openItems.settled()
        draw()
        return peak
    }

    /// Opens `small` then `large` of one kind in one drawing window, and fails when the large file grows the footprint by more than
    /// `kind.factor` × `stored` + `allowance` bytes over the footprint after the small one's close.
    @MainActor private func assertBudget(_ kind: Kind, small: URL, large: URL, stored: Int) async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        _ = try await openShowClose(small, kind, state: state, host: host)
        let before = Self.footprint()
        let open = try await openShowClose(large, kind, state: state, host: host)
        let cost = open - before, budget = Int(kind.factor * Double(stored)) + Self.allowance
        // Logged on every run, so a green run shows the margin.
        print("DocumentMemoryBudgetTests \(kind.name): \(cost) bytes while open for \(stored) stored (x"
              + "\(String(format: "%.2f", Double(cost) / Double(stored)))); budget \(budget) (x\(kind.factor) + \(Self.allowance))")
        XCTAssertLessThanOrEqual(cost, budget, "\(kind.name): open, it grew the footprint by \(cost) bytes, "
                                 + "\(String(format: "%.2f", Double(cost) / Double(stored))) times the \(stored) bytes it stores; "
                                 + "the budget is \(kind.factor) times plus \(Self.allowance)")
    }

    // MARK: - Images

    /// An 8-bit image is widened to Float32 (4 bytes a pixel for 1 stored) and drawn from its display canvas.
    @MainActor func testAn8BitImageStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        try await assertBudget(Self.kind("8-bit image", factor: 12),
                               small: try GeneratedFiles.greyTIFF(.uint8, width: 256, height: 256, in: dir),
                               large: try GeneratedFiles.greyTIFF(.uint8, width: 4096, height: 4096, in: dir), stored: 4096 * 4096)
    }

    /// A 16-bit image: Float32 is twice the stored bytes.
    @MainActor func testA16BitImageStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        try await assertBudget(Self.kind("16-bit image", factor: 6),
                               small: try GeneratedFiles.greyTIFF(.uint16, width: 256, height: 256, in: dir),
                               large: try GeneratedFiles.greyTIFF(.uint16, width: 4096, height: 4096, in: dir), stored: 4096 * 4096 * 2)
    }

    /// A 32-bit float image: its pixels are already Float32. 3.5 rather than 3: the peak catches a transient copy partly freed or not
    /// depending on how the machine schedules the release (268 MB against 252 MB on the loaded Mac runner, once, #963). A copy
    /// held while open adds a whole 1× (67 MB) and still fails.
    @MainActor func testA32BitImageStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        try await assertBudget(Self.kind("32-bit image", factor: 3.5),
                               small: try GeneratedFiles.greyTIFF(.float32, width: 256, height: 256, in: dir),
                               large: try GeneratedFiles.greyTIFF(.float32, width: 4096, height: 4096, in: dir), stored: 4096 * 4096 * 4)
    }

    /// A stack of 16 frames of 1024 × 1024 16-bit: the frames are read as they are shown, so the stack costs a few frames, not all.
    @MainActor func testAStackStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        let small = dir.appendingPathComponent("stack-small.tif"), large = dir.appendingPathComponent("stack-large.tif")
        try DemoDocuments.writeStackTIFF(to: small, frames: 4, width: 128, height: 128) { f, x, y in UInt16((x * 7 + y * 13 + f * 101) % 4096) }
        try DemoDocuments.writeStackTIFF(to: large, frames: 16, width: 1024, height: 1024) { f, x, y in UInt16((x * 7 + y * 13 + f * 101) % 4096) }
        try await assertBudget(Self.kind("stack", factor: 3), small: small, large: large, stored: 16 * 1024 * 1024 * 2)
    }

    // MARK: - Spectrum images and scans

    /// An EDS spectrum image is held as the room's UInt32 counts, twice the stored int16.
    @MainActor func testAnEDSSpectrumImageStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        let kind = Kind(name: "EDS spectrum image", rooms: [.edx], factor: 4, ready: { $0.edx.hasImage && !$0.edx.isBusy },
                        close: { $0.closeDocument(.eds(single: false)) }, closed: { !$0.edx.hasImage && !$0.edx.isBusy })
        try await assertBudget(kind, small: try GeneratedFiles.spectrumImage(eels: false, nx: 8, ny: 8, channels: 2048, in: dir),
                               large: try GeneratedFiles.spectrumImage(eels: false, nx: 128, ny: 128, channels: 2048, in: dir),
                               stored: 128 * 128 * 2048 * 2)
    }

    /// An EELS spectrum image is held as the room's Float32, twice the stored int16.
    @MainActor func testAnEELSSpectrumImageStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        let kind = Kind(name: "EELS spectrum image", rooms: [.eels], factor: 4, ready: { $0.eels.hasImage && !$0.eels.isBusy },
                        close: { $0.closeDocument(.eels(single: false)) }, closed: { !$0.eels.hasImage && !$0.eels.isBusy })
        try await assertBudget(kind, small: try GeneratedFiles.spectrumImage(eels: true, nx: 8, ny: 8, channels: 1024, in: dir),
                               large: try GeneratedFiles.spectrumImage(eels: true, nx: 128, ny: 128, channels: 1024, in: dir),
                               stored: 128 * 128 * 1024 * 2)
    }

    /// An EBSD scan: its patterns, their processed copies and the mean map, shown in the Patterns room.
    @MainActor func testAnEBSDScanStaysInItsBudget() async throws {
        let dir = try scratchFolder()
        let passesDone: @MainActor (AppState) -> Bool = {
            $0.ebsd.hasDataset && !$0.ebsd.isOpening && !$0.ebsd.isMapping && !$0.ebsd.isComputingMean && !$0.ebsd.isProcessing
        }
        let kind = Kind(name: "EBSD scan", rooms: [.patterns], factor: 4, ready: passesDone,
                        close: { $0.closeDocument(.ebsdDataset) }, closed: { !$0.ebsd.hasDataset && !$0.ebsd.isOpening })
        try await assertBudget(kind, small: try GeneratedFiles.edaxScan(rows: 4, columns: 6, side: 100, ang: true, in: dir),
                               large: try GeneratedFiles.edaxScan(rows: 48, columns: 64, side: 100, ang: true, in: dir),
                               stored: 48 * 64 * 100 * 100 * 2)
    }

    // MARK: - Idle

    /// The empty window: AppState and every room's chrome drawn with no file open may cost at most 160 MB over the process before it.
    /// Red under: a room that allocates its working buffers before it has a file.
    @MainActor func testAnEmptyWindowStaysInTheIdleBudget() async throws {
        let budget = 160 << 20
        let before = Self.footprint()
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        for room in [WorkspaceArea.image, .fft, .edx, .eels, .diffraction, .patterns, .indexing, .maps, .results] {
            state.selectWorkspace(room)
            host.layoutSubtreeIfNeeded()
            host.display()
        }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        host.display()
        let cost = Self.footprint() - before
        print("DocumentMemoryBudgetTests idle: \(cost) bytes for an empty window in every room; budget \(budget)")
        XCTAssertLessThanOrEqual(cost, budget, "an empty window grew the footprint by \(cost) bytes; the idle budget is \(budget)")
    }
}
