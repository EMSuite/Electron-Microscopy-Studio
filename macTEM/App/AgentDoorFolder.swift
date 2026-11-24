//
//  AgentDoorFolder.swift
//  Role: the agent door's folder tools (#739): an agent works through the files of the one Agent folder the person chose in
//        Settings > Agents (`AgentFolder`): it lists them and opens one in the window as File > Open does (`AppState.open(urls:)`),
//        so a release recipe can open its reference file and replay a room's action. As mac4DSTEM's `AgentDoorFolder.swift`.
//
//  Listing only looks. Opening acts, so it needs "Let agents run analyses" (`acts: true`). Nothing outside the folder is listed or
//  opened, and nothing is written there.
//

import Foundation
import ShellAgentDoor
import TEMCore

extension MacTEMAgentDoor {
    /// The Agent folder the tools work in.
    static let folder = AgentFolder()

    /// The preference behind Settings > Agents > Agent folder: the folder's security-scoped bookmark; absent while none is chosen.
    static let folderKey = "prefs.agentFolderBookmark"

    /// The bookmark `folder` was last opened from, so a window that appears does not open it again.
    private static var folderBookmark: Data?

    /// Opens the folder a bookmark names (nil: none). Answers a fresh bookmark when the stored one was stale, for the caller to keep.
    @discardableResult
    static func setFolder(bookmark: Data?) -> Data? {
        guard folderBookmark != bookmark || (bookmark != nil && folder.url == nil) else { return nil }
        folderBookmark = bookmark
        let refreshed = folder.use(bookmark: bookmark)
        if let refreshed { folderBookmark = refreshed }
        return refreshed
    }

    /// What a file tool answers when its path names no file; an empty path is the folder itself.
    static func noFileMessage(_ url: URL) -> String {
        guard let root = folder.url, url.standardizedFileURL.path != root.standardizedFileURL.path else {
            return "Give a path: a file of the Agent folder, as list_agent_folder shows it."
        }
        return "There is no file \(folder.relativePath(of: url)) in the Agent folder."
    }

    static let folderTools: [AgentTool] = [
        AgentTool(name: "list_agent_folder", title: "Agent folder files",
                  summary: "The files in the Agent folder the person chose in Settings > Agents (and its subfolders): path relative to "
                      + "the folder, size in bytes, modification date. open_file opens one.",
                  input: .noWindow) { _ in
            guard let listed = folder.listing() else { return .refusal(status: 404, message: folder.missingMessage) }
            return .json(["folder": folder.url?.lastPathComponent ?? "", "files": listed.files, "truncated": listed.truncated])
        },
        AgentTool(name: "open_file", title: "Open file",
                  summary: "Opens a file of the Agent folder as File > Open does: into every room that has data in it, landing in the "
                      + "richest. A window that already holds a file opens the new one in a tab of its own (list_windows then names it). "
                      + "It starts the open and answers at once; get_window shows the file once it is in, and get_log says if it failed.",
                  input: .window,
                  parameters: [AgentParameter("path", .text, summary: "The file, relative to the Agent folder, as list_agent_folder "
                                                  + "names it.", required: true)],
                  acts: true) { call in
            guard let appState = call.window?.state as? AppState else { return notAWindowRefusal }
            guard appState.opensInFlight == 0 else {
                return .refusal(status: 409, message: "An open is still running in this window; wait until get_window shows it.")
            }
            let file: URL
            switch folder.resolve(call.arguments["path"] ?? "") {
            case .success(let url): file = url
            case .failure(let refusal): return .refusal(status: 404, message: refusal.message)
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
                return .refusal(status: 404, message: noFileMessage(file))
            }
            appState.statusText = "An agent opened \(file.lastPathComponent)."
            appState.open(urls: [file])
            return .json(["opening": folder.relativePath(of: file)])
        },
    ]
}
