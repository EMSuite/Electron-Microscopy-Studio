//
//  LinkedFileGrants.swift
//  Role: the app's permission for a document's links to other files (#824; the suite's files-exports design, rule 3): a
//        security-scoped bookmark made when the person picks the file, kept in the app's own defaults under the link's id, never in
//        the document. The document names the file (`LinkedFile`: name, size, fingerprint); this store reaches it. On another Mac, or
//        after the store is cleared, a link has no bookmark and says it is not connected, with Locate….
//
//        The scope is never held for a link's life: `LinkedFiles.resolve` holds it for one read.
//

import Foundation
import TEMCore
import TEMSession

nonisolated enum LinkedFileGrants {
    private static let keyPrefix = "linkedFile.grant."

    /// The key of `link`'s bookmark: its id, never a path.
    static func key(for link: LinkedFile) -> String { keyPrefix + link.id }

    static func bookmark(for link: LinkedFile, defaults: UserDefaults = .standard) -> Data? {
        defaults.data(forKey: key(for: link))
    }

    /// Stores `bookmark` for `link`, or drops it when nil.
    static func store(_ bookmark: Data?, for link: LinkedFile, defaults: UserDefaults = .standard) {
        if let bookmark { defaults.set(bookmark, forKey: key(for: link)) } else { defaults.removeObject(forKey: key(for: link)) }
    }

    /// A new link to the file at `url` (read for its fingerprint), with its bookmark stored; nil when the file cannot be read (an
    /// image made in memory has no file). `system` makes the bookmark and reads the file.
    static func link(to url: URL, system: LinkedFileSystem = .securityScoped, defaults: UserDefaults = .standard) -> LinkedFile? {
        guard url.isFileURL, let print = try? system.fingerprint(url) else { return nil }
        let link = LinkedFile(name: url.lastPathComponent, byteCount: print.byteCount, fingerprint: print.fingerprint)
        store(try? system.makeBookmark(url), for: link, defaults: defaults)
        return link
    }
}
