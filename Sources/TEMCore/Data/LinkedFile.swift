//
//  LinkedFile.swift
//  Role: how a document names a file outside it (#824, plan row X8; the suite's files-exports design, "The sandbox rule for
//        documents that point at other files", rule 1): by its name, its size and a fingerprint, never by a path. A path does not
//        travel to another Mac, tells a reader the user's folders, and is not what decides whether a file is the same one: its
//        contents are. The permission to read the file is the app's own bookmark, kept outside the document under the link's id
//        (`LinkedFileGrants` in the app); this type holds nothing the sandbox needs.
//
//        The fingerprint is the SHA-256 of the size (8 bytes, little-endian), the first MiB and the last MiB of the file (the whole
//        file once when it is no larger than one MiB): a gigabyte scan is told apart from another in two reads, not a pass over the
//        file. Two files that share their size, their first and their last MiB are taken for the same file; the design accepts that.
//

import CryptoKit
import Foundation
import TEMBase
import TEMSEM

package nonisolated struct LinkedFile: Codable, Equatable, Hashable, Sendable {
    /// The link's own id: the key of the app's bookmark for it. A new id for each file linked.
    package var id: String
    /// The file's name, never its folders, under Unicode NFC.
    package var name: String
    /// The file's size in bytes.
    package var byteCount: Int
    /// 64 lowercase hexadecimal digits (`fingerprint(ofFileAt:)`).
    package var fingerprint: String

    package init(id: String = UUID().uuidString, name: String, byteCount: Int, fingerprint: String) {
        self.id = id
        self.name = name.precomposedStringWithCanonicalMapping
        self.byteCount = byteCount
        self.fingerprint = fingerprint
    }

    /// The link to the file at `url`, read for its fingerprint (two reads of at most one MiB). Throws when the file cannot be read.
    package init(describing url: URL, id: String = UUID().uuidString) throws {
        let print = try Self.fingerprint(ofFileAt: url)
        self.init(id: id, name: url.lastPathComponent, byteCount: print.byteCount, fingerprint: print.fingerprint)
    }

    /// The bytes read from each end of the file.
    package static let edgeBytes = 1 << 20

    /// The fingerprint of the file at `url` and its size: the SHA-256 of the size, the first MiB and the last MiB.
    package static func fingerprint(ofFileAt url: URL) throws -> (fingerprint: String, byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        var hasher = SHA256()
        withUnsafeBytes(of: UInt64(size).littleEndian) { hasher.update(bufferPointer: $0) }
        try handle.seek(toOffset: 0)
        if let head = try handle.read(upToCount: edgeBytes) { hasher.update(data: head) }
        if size > edgeBytes {
            try handle.seek(toOffset: UInt64(size - edgeBytes))
            if let tail = try handle.read(upToCount: edgeBytes) { hasher.update(data: tail) }
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }

    /// Whether a file read as `print` is this one: the same size and fingerprint.
    package func matches(_ print: (fingerprint: String, byteCount: Int)) -> Bool {
        print.byteCount == byteCount && print.fingerprint == fingerprint
    }

    /// "frame_012.dm4 is not connected." The design's header line (F4) for a link whose file is not there.
    package var notConnectedLine: String { "\(name) is not connected." }
    /// The line for a file on a volume that is not mounted (a server).
    package var serverLine: String { "\(name) is on a server that is not connected." }
    /// The line for a file picked or found that is not this one.
    package func differentLine(found: String) -> String {
        "\(found) is not \(name): its contents differ. Link it anyway only if it is the same data."
    }
}
