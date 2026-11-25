//
//  LinkedFiles.swift
//  Role: the sandbox rule for a document's links to other files (#824, plan row X8; the suite's files-exports design, rules 3 to 5),
//        as one pure decision over the system's answers. The document holds a `LinkedFile` (name, size, fingerprint); the app holds a
//        bookmark for it. Resolving a link reads the bookmark without interface and without mounting a volume, holds the file's scope
//        for the one read of its fingerprint, and says what the link is now:
//
//          - connected: the bookmark found a file with the link's fingerprint, wherever it now is (moved, renamed); a stale bookmark
//            is made again, so the next open finds it at once;
//          - not connected: no bookmark (another Mac, a cleared store), or the file is gone (deleted, emptied from the Trash);
//          - on a server that is not connected: the bookmark's volume is not mounted, so nothing is mounted to look;
//          - different: a file was found, or picked with Locate…, whose contents are not the link's; it is linked only when the
//            person says so (`relinked`).
//
//        The system's calls are `LinkedFileSystem`, injected, so the six cases are tests with real files and the one the test Mac
//        cannot make (an unmounted volume) is the system's answer stood in for. `resolve(within:)` bounds the wait: a bookmark to a
//        server that does not answer must not hold a document's opening (rule 4, 5 seconds).
//

import Foundation
import TEMCore

/// What a link is now.
package nonisolated enum LinkedFileState: Equatable, Sendable {
    /// The file with the link's fingerprint, at this URL.
    case connected(URL)
    /// No bookmark, or the file is not there.
    case notConnected
    /// The file is on a volume that is not mounted: its name.
    case serverNotConnected(volume: String)
    /// A file was found or picked whose contents are not the link's.
    case different(URL)

    /// The line the document shows for `link` in this state; nil when connected.
    package func line(for link: LinkedFile) -> String? {
        switch self {
        case .connected: nil
        case .notConnected: link.notConnectedLine
        case .serverNotConnected: link.serverLine
        case .different(let url): link.differentLine(found: url.lastPathComponent)
        }
    }
}

/// The system's calls the rule makes, injected: the app's are `securityScoped`.
package nonisolated struct LinkedFileSystem: Sendable {
    /// Resolves a bookmark to a URL and whether it is stale; throws when it does not resolve.
    package var resolve: @Sendable (Data) throws -> (url: URL, isStale: Bool)
    /// Makes a bookmark for a URL.
    package var makeBookmark: @Sendable (URL) throws -> Data
    /// The volume a bookmark names and whether it is mounted now; nil when the bookmark does not say.
    package var volume: @Sendable (Data) -> (name: String, isMounted: Bool)?
    /// Reads a file for its fingerprint, with whatever access the URL needs held for the read.
    package var fingerprint: @Sendable (URL) throws -> (fingerprint: String, byteCount: Int)

    package init(resolve: @escaping @Sendable (Data) throws -> (url: URL, isStale: Bool),
                 makeBookmark: @escaping @Sendable (URL) throws -> Data,
                 volume: @escaping @Sendable (Data) -> (name: String, isMounted: Bool)?,
                 fingerprint: @escaping @Sendable (URL) throws -> (fingerprint: String, byteCount: Int)) {
        self.resolve = resolve
        self.makeBookmark = makeBookmark
        self.volume = volume
        self.fingerprint = fingerprint
    }

    /// The volume a bookmark names, read from the bookmark itself (nothing is resolved or mounted), and whether it is mounted.
    package static func bookmarkVolume(_ data: Data) -> (name: String, isMounted: Bool)? {
        let values = URL.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey], fromBookmarkData: data)
        guard let volume = values?.volume else { return nil }
        let name = values?.volumeName ?? volume.lastPathComponent
        return (name, (try? volume.checkResourceIsReachable()) == true)
    }

    /// The app's: security-scoped bookmarks (read-write first, read-only as the fallback), resolved without interface and without
    /// mounting, the scope held for the one read.
    package static let securityScoped = LinkedFileSystem(
        resolve: { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        },
        makeBookmark: { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try SecurityScopedBookmark.make(for: url)
        },
        volume: { LinkedFileSystem.bookmarkVolume($0) },
        fingerprint: { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try LinkedFile.fingerprint(ofFileAt: url)
        })
}

package nonisolated enum LinkedFiles {
    /// What resolving a link found, and the bookmark to keep in place of the old one when it was stale.
    package struct Resolution: Equatable, Sendable {
        package var state: LinkedFileState
        package var renewedBookmark: Data?

        package init(state: LinkedFileState, renewedBookmark: Data? = nil) {
            self.state = state
            self.renewedBookmark = renewedBookmark
        }
    }

    /// How long opening waits for a bookmark (rule 4).
    package static let resolveSeconds = 5.0

    /// Resolves `link` through `bookmark` (nil: the app holds none for it). Blocks for the bookmark and the read: call it off the
    /// main actor, or through `resolve(_:bookmark:system:within:)`.
    package static func resolve(_ link: LinkedFile, bookmark: Data?, system: LinkedFileSystem = .securityScoped) -> Resolution {
        guard let bookmark else { return Resolution(state: .notConnected) }
        let found: (url: URL, isStale: Bool)
        do {
            found = try system.resolve(bookmark)
        } catch {
            if let volume = system.volume(bookmark), !volume.isMounted { return Resolution(state: .serverNotConnected(volume: volume.name)) }
            return Resolution(state: .notConnected)
        }
        guard let print = try? system.fingerprint(found.url) else { return Resolution(state: .notConnected) }
        guard link.matches(print) else { return Resolution(state: .different(found.url)) }
        return Resolution(state: .connected(found.url), renewedBookmark: found.isStale ? try? system.makeBookmark(found.url) : nil)
    }

    /// `resolve` off the caller's actor, given at most `seconds`: a bookmark that has not answered by then is not connected (the
    /// read goes on and its answer is dropped).
    package static func resolve(_ link: LinkedFile, bookmark: Data?, system: LinkedFileSystem = .securityScoped,
                                within seconds: Double) async -> Resolution {
        await withCheckedContinuation { (continuation: CheckedContinuation<Resolution, Never>) in
            let once = Once(continuation)
            DispatchQueue.global(qos: .userInitiated).async { once.finish(resolve(link, bookmark: bookmark, system: system)) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { once.finish(Resolution(state: .notConnected)) }
        }
    }

    /// Locate…: the file the person picked for `link`. The same contents connect it, with a new bookmark; other contents are
    /// `different` and nothing is linked until `relinked`. A file that cannot be read is not connected.
    package static func locate(_ link: LinkedFile, picked url: URL, system: LinkedFileSystem = .securityScoped)
        -> (state: LinkedFileState, bookmark: Data?) {
        guard let print = try? system.fingerprint(url) else { return (.notConnected, nil) }
        guard link.matches(print) else { return (.different(url), nil) }
        return (.connected(url), try? system.makeBookmark(url))
    }

    /// Link Anyway: `link` names the file at `url` from now on (its name, size and fingerprint, the same id), with a new bookmark.
    package static func relinked(_ link: LinkedFile, to url: URL, system: LinkedFileSystem = .securityScoped)
        -> (link: LinkedFile, bookmark: Data?)? {
        guard let print = try? system.fingerprint(url) else { return nil }
        return (LinkedFile(id: link.id, name: url.lastPathComponent, byteCount: print.byteCount, fingerprint: print.fingerprint),
                try? system.makeBookmark(url))
    }

    /// Resumes a continuation once, from whichever of the read and the clock comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Resolution, Never>?

        init(_ continuation: CheckedContinuation<Resolution, Never>) { self.continuation = continuation }

        func finish(_ resolution: Resolution) {
            lock.lock()
            let held = continuation
            continuation = nil
            lock.unlock()
            held?.resume(returning: resolution)
        }
    }
}
