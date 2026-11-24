//
//  AgentFolder.swift
//  Role: The one folder an agent may work in (Settings > Agents > Agent folder, #739; mac4DSTEM's `AgentFolder`, issue #191 there,
//        copied unchanged but for this header). The person chooses it; the app keeps a security-scoped bookmark
//        (`MacTEMAgentDoor.folderKey`) and holds the folder open while it is chosen. Every path
//        an agent names is resolved inside it, symbolic links followed, and refused when it leads outside. Nothing here deletes,
//        moves or overwrites a file.
//

import Foundation
import TEMCore

@MainActor
final class AgentFolder {
    /// The chosen folder, standardized with its links resolved; nil while none is chosen or its bookmark no longer resolves.
    private(set) var url: URL?
    /// Whether `url` holds a security scope this object started (and stops when the folder changes).
    private var scoped = false

    /// No folder.
    init() {}

    /// Why a chosen folder is not open (its bookmark no longer resolves, or macOS refused its access); nil while it is, or none
    /// is chosen.
    private(set) var unavailableReason: String?

    /// The folder a bookmark names, opened for this app until it changes; none when the bookmark is nil or no longer resolves
    /// (`unavailableReason` says so). A bookmark that resolves but is stale (the folder moved or was renamed) is made again
    /// and answered, for the caller to keep in place of the old one, as `CompanionFolderAccess` does (#310).
    @discardableResult
    func use(bookmark: Data?) -> Data? {
        if scoped { url?.stopAccessingSecurityScopedResource() }
        scoped = false
        url = nil
        unavailableReason = nil
        guard let bookmark else { return nil }
        var stale = false
        let resolved: URL
        do {
            resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            unavailableReason = "The Agent folder chosen in Settings > Agents can no longer be found (\(error.localizedDescription)). "
                + "Ask the person to choose it again."
            return nil
        }
        scoped = resolved.startAccessingSecurityScopedResource()
        // Outside the sandbox (tests, tools) there is no scope to start; what matters is that the folder can be reached.
        guard scoped || (try? resolved.checkResourceIsReachable()) == true else {
            unavailableReason = "macOS no longer lets \(AppName.display) open the Agent folder \(resolved.lastPathComponent). Ask the person "
                + "to choose it again in Settings > Agents."
            return nil
        }
        url = Self.canonical(resolved)
        guard stale else { return nil }
        // try? OK: without a fresh bookmark the stale one still resolves this launch; Settings asks again once it stops.
        return try? resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// A folder already open to the app, without a bookmark (tests).
    func use(folder: URL?) {
        if scoped { url?.stopAccessingSecurityScopedResource() }
        scoped = false
        unavailableReason = nil
        url = folder.map(Self.canonical)
    }

    /// The bookmark to keep for a folder the person just chose (in an open panel, so the app may read it now).
    static func bookmark(for folder: URL) -> Data? {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        return try? folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Where a bookmark points, for Settings to show; nil when it does not resolve.
    static func displayPath(bookmark: Data?) -> String? {
        guard let bookmark else { return nil }
        var stale = false
        let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        return resolved.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    static let noFolder = "No Agent folder is chosen. Ask the person to choose one in \(AppName.display)'s Settings > Agents > Agent folder."

    /// What a tool answers while no folder is open: none chosen, or the reason the chosen one is not open.
    var missingMessage: String { unavailableReason ?? Self.noFolder }

    /// `path`, relative to the folder, as a URL inside it; or the sentence that says why not.
    func resolve(_ path: String) -> Result<URL, AgentFolderRefusal> {
        guard let url else { return .failure(AgentFolderRefusal(missingMessage)) }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
            return .failure(AgentFolderRefusal("Name the file relative to the Agent folder, as list_agent_folder shows it."))
        }
        let candidate = Self.canonical(url.appendingPathComponent(trimmed))
        guard contains(candidate) else {
            return .failure(AgentFolderRefusal("\(trimmed) is outside the Agent folder; only files inside it can be used."))
        }
        return .success(candidate)
    }

    /// Whether `candidate` (canonical) is the folder or inside it.
    func contains(_ candidate: URL) -> Bool {
        guard let url else { return false }
        let root = url.path.hasSuffix("/") ? url.path : url.path + "/"
        return candidate.path == url.path || candidate.path.hasPrefix(root)
    }

    /// The most entries (files and folders) one listing visits, so a huge tree cannot hold the main actor for long (#926).
    static let visitLimit = 50_000

    /// The files in the folder and its subfolders (hidden ones and packages' insides left out), the first `limit` by path:
    /// relative path, size in bytes and modification date (ISO 8601). `truncated` says files were left out: more than `limit`,
    /// or a tree of more than `visitLimit` entries, of which only the ones visited are sorted.
    func listing(limit: Int = 2000, visitLimit: Int = AgentFolder.visitLimit) -> (files: [[String: Any]], truncated: Bool)? {
        guard let url else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let keySet = Set(keys)
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let root = url.path.hasSuffix("/") ? url.path : url.path + "/"
        var found: [(path: String, bytes: Int, modified: Date?)] = []
        var visited = 0
        var truncated = false
        for case let file as URL in walk {
            visited += 1
            guard visited <= visitLimit else { truncated = true; break }
            // A symbolic link is not a regular file, and the walk does not follow one, so nothing listed leads out of the folder.
            guard let values = try? file.resourceValues(forKeys: keySet), values.isRegularFile == true else { continue }
            let path: String
            if file.path.hasPrefix(root) {
                path = String(file.path.dropFirst(root.count))
            } else {
                // The walk spelled the folder another way (/private/var for /var): the slow, link-resolving way, as before #926.
                let inside = Self.canonical(file)
                guard contains(inside) else { continue }
                path = relativePath(of: inside)
            }
            found.append((path, values.fileSize ?? 0, values.contentModificationDate))
        }
        found.sort { $0.path < $1.path }
        if found.count > limit { truncated = true }
        let dates = ISO8601DateFormatter()
        let files = found.prefix(limit).map { file -> [String: Any] in
            var entry: [String: Any] = ["path": file.path, "bytes": file.bytes]
            if let date = file.modified { entry["modified"] = dates.string(from: date) }
            return entry
        }
        return (files, truncated)
    }

    /// `file`'s path below the folder.
    func relativePath(of file: URL) -> String {
        guard let url else { return file.lastPathComponent }
        let root = url.path.hasSuffix("/") ? url.path : url.path + "/"
        return file.path.hasPrefix(root) ? String(file.path.dropFirst(root.count)) : file.lastPathComponent
    }

    /// Standardized, with symbolic links resolved, so `..` and links cannot lead out unseen.
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

/// Why a path cannot be used, in a sentence for the agent.
struct AgentFolderRefusal: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
