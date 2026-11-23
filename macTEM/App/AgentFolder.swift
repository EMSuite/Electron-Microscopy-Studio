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

    /// A folder given directly (tests, or a folder already open to the app).
    init(folder: URL) {
        url = Self.canonical(folder)
    }

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

    /// The files in the folder and its subfolders (hidden ones and packages' insides left out), at most `limit`, sorted by path:
    /// relative path, size in bytes and modification date (ISO 8601).
    func listing(limit: Int = 2000) -> (files: [[String: Any]], truncated: Bool)? {
        guard let url else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let dates = ISO8601DateFormatter()
        var files: [[String: Any]] = []
        var truncated = false
        for case let file as URL in walk {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let inside = Self.canonical(file)
            guard contains(inside) else { continue }   // a link that leads out is not listed
            guard files.count < limit else { truncated = true; break }
            var entry: [String: Any] = ["path": relativePath(of: inside), "bytes": values.fileSize ?? 0]
            if let date = values.contentModificationDate { entry["modified"] = dates.string(from: date) }
            files.append(entry)
        }
        files.sort { ($0["path"] as? String ?? "") < ($1["path"] as? String ?? "") }
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
