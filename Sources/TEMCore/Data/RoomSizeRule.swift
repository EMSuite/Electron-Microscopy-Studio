// The size rule (#905, plan row X13; suite docs/design/files-exports.md, "The size table and the refusal"): before a file is read, a
// room that holds its data whole in memory says whether this Mac can hold it, and refuses it in words when it cannot. The rule is one
// line: refused when the room's peak factor times the file's stored bytes is more than this Mac's memory minus 4 GB. The sentence names
// the file, what the room needs, what this Mac has and what works instead. No "Open Anyway": a refusal in words is cheaper than a swap
// storm, and an out-of-core engine is HyperSpy's job.
//
// The factors are the size table's (docs/performance.md, #904), measured once per feature release; a room's factor here is never below
// its measured peak (pin Z1, `RoomSizeRuleTests`). Until a room is measured it carries quality bar 3's target, 3 times the stored bytes
// at the peak. The Patterns, Indexing and Maps rooms stream their scans a block at a time, so the rule does not refuse their files; a
// TIFF stack is read a frame at a time, so its frame counts, not the file. The Image room is held to the file only for the formats it
// reads whole (`wholeImageExtensions`): a Velox file, a HyperSpy file or a TIA series is read an image or a frame at a time.
//
// The rule counts stored bytes: a compressed HyperSpy cube or a sparse Velox EDS stream holds more once read; the size table's rows
// are what to trust for those.
import Foundation

package nonisolated enum RoomSizeRule {
    /// A room that reads a file whole.
    package enum Room: String, CaseIterable, Sendable {
        case image = "Image", eds = "EDS", eels = "EELS"

        /// What the file holds for this room, in words.
        var holding: String { self == .image ? "image" : "spectrum image" }

        /// What works instead of the whole file.
        var instead: String { self == .image ? "Open a binned or cropped copy" : "Open a binned copy" }
    }

    /// Peak footprint over stored bytes, above the empty app's footprint (the size table's peak factor).
    package static func peakFactor(_ room: Room) -> Double {
        switch room {
        case .image, .eds, .eels: 3
        }
    }

    /// What the rule leaves to the system and the other apps.
    package static let margin: UInt64 = 4 << 30

    /// Memory sizes Macs are sold with, in GB: the smallest that holds a file is the one the sentence names.
    static let macMemories: [UInt64] = [8, 16, 24, 32, 36, 48, 64, 96, 128, 192, 256, 512]

    /// The sentence that refuses `fileName` for `room` on a Mac of `memory` bytes, or nil when the Mac holds it.
    package static func refusal(fileName: String, storedBytes: UInt64, room: Room, memory: UInt64) -> String? {
        let need = peakFactor(room) * Double(storedBytes)
        guard need > Double(memory) - Double(margin) else { return nil }
        let bigger = macMemories.first { Double($0 << 30) - Double(margin) >= need }
        let elsewhere = bigger.map { ", or open it on a Mac with \($0) GB." } ?? "; no Mac holds it whole."
        return "\(fileName) holds a \(gigabytes(Double(storedBytes))) \(room.holding). The \(room.rawValue) room needs about "
            + "\(gigabytes(need)) to open it and this Mac has \(gigabytes(Double(memory))). \(room.instead)\(elsewhere)"
    }

    /// The image formats the Image room reads whole: one image a file, its bytes all read at the open.
    package static let wholeImageExtensions: Set<String> = ["tif", "tiff", "mrc", "dm3", "dm4", "png", "jpg", "jpeg"]

    /// The first room of `inventory` the file would pass, with its sentence; nil when every room that reads it whole holds it.
    /// `storedBytes` is what the room reads (a TIFF stack's one frame, `readBytes`).
    package static func refusal(fileName: String, inventory: FileInventory, storedBytes: UInt64, memory: UInt64) -> String? {
        var rooms: [Room] = []
        if inventory.edsSpectrumImage { rooms.append(.eds) }
        if inventory.eelsSpectrumImage { rooms.append(.eels) }
        if inventory.image, wholeImageExtensions.contains((fileName as NSString).pathExtension.lowercased()) { rooms.append(.image) }
        return rooms.lazy.compactMap { refusal(fileName: fileName, storedBytes: storedBytes, room: $0, memory: memory) }.first
    }

    /// The bytes an Open reads whole from the file at `path`: the file's size, a TIFF stack's size over its frames (read one at a
    /// time). From the file system and the TIFF's directory only; no pixel is read.
    package static func readBytes(path: String) -> UInt64 {
        let size = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.uint64Value ?? 0
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "tif" || ext == "tiff", let stack = try? ImageStackSource.open(path: path) else { return size }
        return size / UInt64(max(stack.frameCount, 1))
    }

    /// "512 MB" under 1 GB, "9.6 GB" under 10 GB, "19 GB" from there, in units of 2^30 and 2^20 bytes (how a Mac's memory is sold).
    static func gigabytes(_ bytes: Double) -> String {
        let gb = bytes / Double(1 << 30)
        if gb < 1 { return "\(max(1, Int((bytes / Double(1 << 20)).rounded()))) MB" }
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        let tenths = (gb * 10).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths)) GB" : String(format: "%.1f GB", tenths)
    }
}
