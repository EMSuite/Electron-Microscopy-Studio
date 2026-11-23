//
//  RoomMemoryTests.swift
//  Every room gives its memory back (#577): a large file opened in a window that draws (`ContentView` in an `NSHostingView`), used in
//  its rooms and closed, leaves the process's physical footprint where it was before the open. A view, `@State`, closure, binding or
//  preference that kept the file's data (#574, #576), or a room session that kept a cube, a canvas or a run after its close, would keep
//  it; `PixelOwnershipTests` reads the sources for the stored ones, this test catches what the scan cannot see (a closure's capture).
//
//  THE TRUTH, each written by the test (the spectrum images and scans by GeneratedFiles.swift):
//    * the image rooms (Image, FFT, Diffraction, Results): a 3072 × 3072 16-bit TIFF (18 MB as stored, 38 MB as Float32);
//    * EDS: a GMS DM4 EDS spectrum image, 128 × 128 × 2048 int16 counts (64 MB as stored, 128 MB as the room's UInt32 counts),
//      with two elements mapped;
//    * EELS: a GMS DM4 EELS spectrum image, 128 × 128 × 1024 int16 (32 MB as stored, 64 MB as the room's Float32), run (Align,
//      t/λ, deconvolution);
//    * Patterns and Indexing: an EDAX `.up2` scan of 48 × 64 patterns of 100 × 100 uint16 (61 MB) with its `.ang`, the patterns
//      processed and the scan indexed with Hough;
//    * Maps: a lone `.ang` of 500 × 500 points.
//  Each room is used once with a small file of the same kind first, so what the first use loads for good (the shaders, SwiftUI's
//  caches, a Hough library) is in the baseline. The measure is `ImageStackTests.footprint()`, taken with the window drawing and no
//  file open, before and after.
//

import AppKit
import Metal
import ShellLayout
import SwiftUI
import XCTest
import ShellEDXModel
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class RoomMemoryTests: XCTestCase {

    private static let side = 3072
    private static let rooms: [WorkspaceArea] = [.image, .fft, .diffraction, .results]

    private func scratchImage(side: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("room-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("large-\(side).tif")
        try DemoDocuments.writeStackTIFF(to: url, frames: 1, width: side, height: side) { _, x, y in UInt16((x * 7 + y * 13) % 4096) }
        return url
    }

    /// Opens `url` in `state`, shows it in each image room with the window drawing, and closes it; waits until the item, its session
    /// and its presentation are gone. Returns the footprint while the file was open (the largest seen).
    @MainActor private func openVisitClose(_ url: URL, state: AppState, host: NSView) async throws -> Int {
        final class Weak<T: AnyObject> { weak var value: T?; init(_ value: T) { self.value = value } }
        await state.open(urls: [url])?.value
        // No strong reference to the item outlives this block: the test must not be what keeps it.
        let (id, watched) = try { () throws -> (OpenItem.ID, (item: Weak<OpenItem>, session: Weak<ImageSession>, presentation: Weak<ImagePresentation>)) in
            let item = try XCTUnwrap(state.openItems.selected, "the image opened")
            XCTAssertNil(item.readFailure)
            return (item.id, (Weak(item), Weak(item.session), Weak(item.presentation)))
        }()
        var peak = 0
        for room in Self.rooms {
            state.selectWorkspace(room)
            XCTAssertEqual(state.navigation.workspaceArea, room, "\(room.title) can be entered")
            host.layoutSubtreeIfNeeded()
            host.display()
            // The room's own work (the FFT's spectrum, the histogram) runs off the main actor; let it land and draw.
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            host.display()
            peak = max(peak, ImageStackTests.footprint())
        }
        state.selectWorkspace(.image)
        state.openItems.close(id)
        await state.openItems.settled()
        host.layoutSubtreeIfNeeded()
        host.display()
        let released = try await conditionHolds(within: 10) {
            watched.item.value == nil && watched.session.value == nil && watched.presentation.value == nil
        }
        XCTAssertTrue(released, "after the close, still held: item \(watched.item.value != nil), session \(watched.session.value != nil), "
                      + "presentation \(watched.presentation.value != nil)")
        return peak
    }

    /// Red under: a room's view, closure or preference keeping the image or its canvas after the close (#574 kept a 375 MB TIFF's
    /// 1.5 GB in a hover closure); the session or presentation not released.
    @MainActor func testTheImageRoomsGiveAClosedImagesMemoryBack() async throws {
        let small = try scratchImage(side: 256)
        let large = try scratchImage(side: Self.side)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let host = NSHostingView(rootView: ContentView().environment(state))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: LayoutPolicy.datasetWindowIdealSize),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        _ = try await openVisitClose(small, state: state, host: host)
        let before = Self.settledFootprint()
        let regionsBefore = Self.settledRegions()
        let partsBefore = Self.parts()
        let open = try await openVisitClose(large, state: state, host: host)

        let stored = Self.side * Self.side * 2
        // An FFT stage already running when the file closed holds its copy until the stage ends (it stops between stages, #618): the
        // footprint is asked again for a few seconds, as the other rooms' check asks it (#713: one immediate read saw 9.5 to 12 MB).
        let back = try await conditionHolds(within: 5) { Self.settledRegions() - regionsBefore < stored / 2 }
        let after = Self.settledFootprint()
        let regionsAfter = Self.settledRegions()
        let held = Self.parts().minus(partsBefore)
        print("RoomMemoryTests image rooms: \(regionsAfter - regionsBefore) bytes of regions over the baseline after the close (allowed "
              + "\(stored / 2)); footprint \(after - before); \(held.words)")
        XCTAssertGreaterThan(open - before, stored, "the measure sees the open image (\(open - before) bytes over the baseline)")
        XCTAssertTrue(back, "after the close the regions hold \(regionsAfter - regionsBefore) bytes over the baseline (footprint \(after - before)); "
                      + "the image is \(stored) bytes as stored; of it over their baselines (bytes): \(held.words) (#713: names which one holds it)")
    }

    /// The footprint once malloc has handed its free pages back: a parse of many small values (an `.ang`'s 250 000 lines) leaves
    /// freed pages in malloc's regions, which it returns only under pressure (CI, 14 Nov: 12 MiB, a whole number of MiB, after the
    /// Maps room's close). Asked for at both ends of a check, so it is the same measure before and after.
    private static func settledFootprint() -> Int {
        _ = malloc_zone_pressure_relief(nil, 0)
        return ImageStackTests.footprint()
    }

    /// What the process's own memory holds once malloc has handed its free pages back: the dirty and compressed pages of every VM
    /// region (malloc's, Metal's, CoreGraphics', Accelerate's and the rest, by `mach_vm_region_recurse`) plus the graphics ledger
    /// (IOSurface and GPU memory charged to the task). The close checks gate on it, not on the footprint: on CI the footprint stayed
    /// 10 to 15 MB over its baseline after a close while no region's dirty and compressed pages grew by 1 MB and malloc in use grew
    /// by under 0.1 MB (#713, PR 742's run, 16 Nov), so that residue lies outside the process's regions. A buffer, texture, surface or
    /// malloc's kept free pages a room holds after its close are dirty pages in a region and show here.
    private static func settledRegions() -> Int {
        _ = malloc_zone_pressure_relief(nil, 0)
        return bytesByTag().values.reduce(0, +) + graphicsLedger()
    }

    private static func graphicsLedger() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? Int(info.ledger_tag_graphics_footprint) : 0
    }

    /// Where a footprint lies: malloc's bytes in use (every zone) and the Metal device's allocations (textures and buffers; on Apple
    /// silicon they count in the footprint too), then the kernel's own split of the footprint (`task_vm_info`): anonymous resident pages
    /// (`internal`), compressed pages, and the graphics ledger (IOSurface and GPU memory charged to the task). A failure that names the
    /// larger says whether a buffer, a texture, a surface or other anonymous VM is held (#713: malloc and Metal named only 0.2 MB of 11).
    private struct Parts {
        var malloc: Int
        var metal: Int
        /// The bytes malloc's zones hold from the system (`size_allocated`): over `malloc` by the free space in their regions. Grown
        /// while `malloc` is not, the held pages are malloc's free space that a few live values keep (fragmentation), not a leak.
        var reserved = 0
        var anonymous = 0
        var compressed = 0
        var graphics = 0
        /// Dirty and compressed bytes by the VM regions' tag (`mach_vm_region_recurse`): which allocator's regions hold the pages
        /// (malloc's tiny, small, medium or large ones, or another tag), where `task_vm_info` only says resident or compressed (#713).
        var byTag: [UInt32: Int] = [:]
        func minus(_ other: Parts) -> Parts {
            var tags = byTag
            for (tag, bytes) in other.byTag { tags[tag, default: 0] -= bytes }
            return Parts(malloc: malloc - other.malloc, metal: metal - other.metal, reserved: reserved - other.reserved,
                         anonymous: anonymous - other.anonymous, compressed: compressed - other.compressed, graphics: graphics - other.graphics,
                         byTag: tags)
        }
        var words: String {
            let tags = byTag.filter { abs($0.value) >= 1 << 20 }.sorted { abs($0.value) > abs($1.value) }.prefix(6)
                .map { "\(RoomMemoryTests.tagName($0.key)) \($0.value)" }.joined(separator: ", ")
            return "regions \(byTag.values.reduce(0, +)), malloc \(malloc) (zones reserve \(reserved)), Metal \(metal), VM internal \(anonymous), compressed \(compressed), graphics \(graphics)"
                + "; by VM tag (dirty + compressed, 1 MB or more): " + (tags.isEmpty ? "none" : tags)
        }
    }

    /// A VM tag's name (mach/vm_statistics.h), its number otherwise.
    nonisolated static func tagName(_ tag: UInt32) -> String {
        let names: [UInt32: String] = [1: "malloc", 2: "malloc small", 3: "malloc large", 4: "malloc huge", 7: "realloc", 8: "malloc tiny",
                                       9: "malloc large reusable", 10: "malloc large reused", 11: "malloc nano", 12: "malloc medium",
                                       13: "malloc proba guard", 30: "Swift runtime", 33: "IOKit", 35: "stack", 36: "guard", 70: "IOAccelerator",
                                       71: "CoreGraphics image", 89: "image IO", 98: "Accelerate"]
        return names[tag] ?? "tag \(tag)"
    }

    /// Dirty plus compressed bytes of every region of the task, summed by its tag.
    nonisolated static func bytesByTag() -> [UInt32: Int] {
        var out: [UInt32: Int] = [:]
        var address: mach_vm_address_t = 0
        var depth: natural_t = 0
        let page = Int(getpagesize())
        while true {
            var size: mach_vm_size_t = 0
            var info = vm_region_submap_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
                    mach_vm_region_recurse(mach_task_self_, &address, &size, &depth, $0, &count)
                }
            }
            guard kr == KERN_SUCCESS else { break }
            if info.is_submap != 0 { depth += 1; continue }
            out[info.user_tag, default: 0] += (Int(info.pages_dirtied) + Int(info.pages_swapped_out)) * page
            address += size
        }
        return out
    }

    private static func parts() -> Parts {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        var parts = Parts(malloc: Int(stats.size_in_use), metal: MTLCreateSystemDefaultDevice().map { Int($0.currentAllocatedSize) } ?? 0,
                          reserved: Int(stats.size_allocated))
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        if r == KERN_SUCCESS {
            parts.anonymous = Int(info.internal)
            parts.compressed = Int(info.compressed)
            parts.graphics = Int(info.ledger_tag_graphics_footprint)
        }
        parts.byTag = bytesByTag()
        return parts
    }

    /// The tag probe sees malloc: a 64 MB buffer touched shows under a malloc tag while it lives. Red under: a probe that reads nothing.
    func testTheTagProbeSeesALargeBuffer() {
        let before = Self.bytesByTag()
        let count = 64 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16384)
        defer { buffer.deallocate() }
        memset(buffer, 1, count)
        let after = Self.bytesByTag()
        let grown = after.reduce(0) { $0 + $1.value - (before[$1.key] ?? 0) }
        XCTAssertGreaterThan(grown, count / 2, "the probe sees the touched buffer: \(after.map { "\(Self.tagName($0.key))" })")
    }

    // MARK: - The spectrum and SEM rooms

    /// A window that draws `state`'s rooms, as the image test makes one; the caller closes it.
    @MainActor private func drawingWindow(_ state: AppState) -> (host: NSView, window: NSWindow) {
        let host = NSHostingView(rootView: ContentView().environment(state))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: LayoutPolicy.datasetWindowIdealSize),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    private func scratchFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("room-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// One room's cycle: `url` opened as the window opens a file, each of `rooms` shown and drawn, `use` run in them, the room's
    /// document closed as File > Close closes it (`closeDocument(target)`), and waited on until `closed` holds and the rooms' work has
    /// ended. Returns the largest footprint seen while the file was open.
    @MainActor private func cycle(_ url: URL, rooms: [WorkspaceArea], target: DocumentTarget, state: AppState, host: NSView,
                                  use: @MainActor (AppState) async throws -> Void, busy: @MainActor (AppState) -> Bool,
                                  closed: @MainActor (AppState) -> Bool) async throws -> Int {
        func draw() { host.layoutSubtreeIfNeeded(); host.display() }
        await state.open(urls: [url])?.value
        XCTAssertNil(state.errorMessage, "\(url.lastPathComponent) opened")
        XCTAssertFalse(closed(state), "\(url.lastPathComponent) is held by its room")
        var peak = ImageStackTests.footprint()
        for room in rooms {
            state.selectWorkspace(room)
            XCTAssertEqual(state.navigation.workspaceArea, room, "\(room.title) can be entered")
            draw()
            try await Task.sleep(for: .milliseconds(300))
            draw()
            peak = max(peak, ImageStackTests.footprint())
        }
        try await use(state)
        try await waitUntil("the rooms' work on \(url.lastPathComponent) to end", seconds: 120) { !busy(state) }
        draw()
        peak = max(peak, ImageStackTests.footprint())
        state.selectWorkspace(rooms[0])
        XCTAssertEqual(state.documentTarget, target, "File > Close acts on \(url.lastPathComponent)")
        state.closeDocument(target)
        try await waitUntil("\(url.lastPathComponent) to be closed", seconds: 10) { closed(state) }
        try await waitUntil("the rooms' work to end after the close", seconds: 30) { !busy(state) }
        draw()
        try await Task.sleep(for: .milliseconds(300))
        draw()
        return peak
    }

    /// Runs `cycle` with the small file, takes the baseline, runs it with the large one, and asserts the footprint came back to within
    /// `allowed` bytes of the baseline (the large file's size as the room holds it, halved). `seen`, when given, is what the open must
    /// at least add, so the measure is shown to see the file.
    @MainActor private func assertGivesBack(_ name: String, small: URL, large: URL, allowed: Int, seen: Int?, rooms: [WorkspaceArea],
                                            target: DocumentTarget, state: AppState, host: NSView,
                                            use: @MainActor (AppState) async throws -> Void, busy: @MainActor (AppState) -> Bool,
                                            closed: @MainActor (AppState) -> Bool) async throws {
        _ = try await cycle(small, rooms: rooms, target: target, state: state, host: host, use: use, busy: busy, closed: closed)
        let before = Self.settledFootprint()
        let regionsBefore = Self.settledRegions()
        let partsBefore = Self.parts()
        let open = try await cycle(large, rooms: rooms, target: target, state: state, host: host, use: use, busy: busy, closed: closed)
        // What is freed off the main actor (a pass's last buffer) lands a moment after the close: asked again for a few seconds.
        let back = try await conditionHolds(within: 5) { Self.settledRegions() - regionsBefore < allowed }
        let after = Self.settledFootprint()
        let regionsAfter = Self.settledRegions()
        if let seen {
            XCTAssertGreaterThan(open - before, seen, "\(name): the measure sees the open file (\(open - before) bytes over the baseline)")
        }
        let held = Self.parts().minus(partsBefore)
        // Logged on every run, so a green run shows the margin and the holders too (#713).
        print("RoomMemoryTests \(name): \(regionsAfter - regionsBefore) bytes of regions over the baseline after the close (allowed "
              + "\(allowed)); footprint \(after - before); \(held.words)")
        XCTAssertTrue(back, "\(name): after the close the regions hold \(regionsAfter - regionsBefore) bytes over the baseline (footprint "
                      + "\(after - before), \(open - before) while open); allowed \(allowed); of it over their baselines (bytes): \(held.words) (#713)")
    }

    /// Red under: the EDS room keeping the cube, its maps, the pooled spectra or the scan image after the close.
    @MainActor func testTheEDSRoomGivesAClosedSpectrumImagesMemoryBack() async throws {
        let dir = try scratchFolder()
        let small = try GeneratedFiles.spectrumImage(eels: false, nx: 8, ny: 8, channels: 2048, in: dir)
        let large = try GeneratedFiles.spectrumImage(eels: false, nx: 128, ny: 128, channels: 2048, in: dir)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        let held = 128 * 128 * 2048 * 4
        try await assertGivesBack("EDS", small: small, large: large, allowed: held / 2, seen: held / 2, rooms: [.edx],
                                  target: .eds(single: false), state: state, host: host,
                                  use: { state in
                                      for symbol in ["Al", "Si"] where !state.edx.picks.contains(where: { $0.symbol == symbol }) { state.edx.toggle(symbol) }
                                      await state.edx.settled()
                                  },
                                  busy: { $0.edx.isBusy }, closed: { !$0.edx.hasImage })
    }

    /// Red under: the EELS room keeping the low-loss cube, the aligned cube, the t/λ map or a pass's buffer after the close.
    @MainActor func testTheEELSRoomGivesAClosedSpectrumImagesMemoryBack() async throws {
        let dir = try scratchFolder()
        let small = try GeneratedFiles.spectrumImage(eels: true, nx: 8, ny: 8, channels: 1024, in: dir)
        let large = try GeneratedFiles.spectrumImage(eels: true, nx: 128, ny: 128, channels: 1024, in: dir)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        let held = 128 * 128 * 1024 * 4
        try await assertGivesBack("EELS", small: small, large: large, allowed: held / 2, seen: held / 2, rooms: [.eels],
                                  target: .eels(single: false), state: state, host: host,
                                  use: { state in
                                      await state.eels.run().value   // Align, t/λ, deconvolution and the fit, as Run does
                                      await state.eels.settled()
                                  },
                                  busy: { $0.eels.isBusy }, closed: { !$0.eels.hasImage })
    }

    /// Red under: the Patterns room keeping its processed patterns, mean map or pattern canvas, the Indexing room its run, map or
    /// band overlay, or the Maps room the dataset's own map, after the dataset is closed.
    @MainActor func testThePatternsAndIndexingRoomsGiveAClosedScansMemoryBack() async throws {
        let dir = try scratchFolder()
        let small = try GeneratedFiles.edaxScan(rows: 4, columns: 6, side: 100, ang: true, in: dir)
        let large = try GeneratedFiles.edaxScan(rows: 48, columns: 64, side: 100, ang: true, in: dir)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        let stored = 48 * 64 * 100 * 100 * 2
        try await assertGivesBack("Patterns and Indexing", small: small, large: large, allowed: stored / 2, seen: nil,
                                  rooms: [.patterns, .indexing], target: .ebsdDataset, state: state, host: host,
                                  use: { state in
                                      try await waitUntil("the scan's passes to end", seconds: 120) {
                                          !state.ebsd.isOpening && !state.ebsd.isMapping && !state.ebsd.isComputingMean && !state.ebsd.isProcessing
                                      }
                                      if state.indexing.phases.isEmpty { state.indexing.addPhase(IndexingPhase.presets[0]) }
                                      XCTAssertNil(state.indexing.refusal)
                                      await state.indexing.index().value
                                      XCTAssertNotNil(state.indexing.result, "the scan was indexed")
                                      state.selectWorkspace(.indexing)
                                  },
                                  busy: { $0.ebsd.isOpening || $0.ebsd.isMapping || $0.ebsd.isComputingMean || $0.ebsd.isProcessing || $0.indexing.isIndexing },
                                  closed: { !$0.ebsd.hasDataset })
    }

    /// Red under: the Maps room keeping a closed map's crystal map, its layer images or the colour key's canvas.
    @MainActor func testTheMapsRoomGivesAClosedMapsMemoryBack() async throws {
        let dir = try scratchFolder()
        let small = try GeneratedFiles.loneMap(rows: 10, columns: 12, in: dir)
        let large = try GeneratedFiles.loneMap(rows: 500, columns: 500, in: dir)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let (host, window) = drawingWindow(state)
        defer { window.contentView = nil; window.close() }
        // A point as a crystal map holds it: an orientation (four Doubles), a position and a phase id, and the ten properties.
        let held = 500 * 500 * 8 * 8
        try await assertGivesBack("Maps", small: small, large: large, allowed: held / 2, seen: nil, rooms: [.maps],
                                  target: .orientationMap, state: state, host: host,
                                  use: { _ in },
                                  busy: { $0.maps.isOpening || $0.maps.isDrawing }, closed: { !$0.maps.hasMap })
    }
}
