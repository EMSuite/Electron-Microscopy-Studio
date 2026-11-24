//
//  AgentFolderPanel.swift (in App/, beside ExportPanels: AppKit stays out of UI/, docs/architecture.md)
//  Settings > Agents > Agent folder > Choose… (#739, as mac4DSTEM's, mac4DSTEM#457 there). AppKit's open panel, because SwiftUI's `.fileImporter` on a Section of
//  the Settings scene's Form never presented: the button did nothing, so the agent folder could not be set.
//

import AppKit

@MainActor
enum AgentFolderPanel {
    /// The panel the button opens: one folder, nothing else.
    static func make() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "The one folder an agent may list and open files from. It never changes a file there."
        return panel
    }

    /// The bookmark of the folder the person chose, or nil when they cancelled.
    static func choose() async -> Data? {
        let panel = make()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let folder = panel.url else { return nil }
        return AgentFolder.bookmark(for: folder)
    }
}
