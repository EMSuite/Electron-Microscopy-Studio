//
//  AgentSettingsView.swift
//  Role: Settings > Agents (`SettingsWindow`): the agent door's switches (`MacTEMAgentDoor`). The section itself is MacEMUI's
//        (`AgentDoorSettingsSection`), the same in both apps; this view keeps the preference and opens or closes the door when it changes.
//

import ShellAgentDoor
import SwiftUI

struct AgentSettingsView: View {
    @AppStorage(MacTEMAgentDoor.enabledKey) private var enabled = false
    @AppStorage(MacTEMAgentDoor.runsKey) private var runs = false
    @AppStorage(MacTEMAgentDoor.folderKey) private var folderBookmark: Data?

    var body: some View {
        AgentDoorSettingsSection(door: MacTEMAgentDoor.shared, isOn: $enabled,
                                 canSee: "the open files, the image as Export Image draws it, the results and the Output lines",
                                 runs: $runs,
                                 canRun: "open the files of the Agent folder, move a window to another room, pick elements and the "
                                     + "region in the EDS room, and press Auto ID, Quantify and Stop there")
        .onChange(of: enabled) { _, now in MacTEMAgentDoor.shared.setEnabled(now) }
        .onChange(of: runs) { _, now in MacTEMAgentDoor.shared.runsAllowed = now }
        .accessibilityIdentifier("settings.agents")
        // The one folder an agent may work in (`App/AgentFolder.swift`, #739), as mac4DSTEM's Settings > Agents.
        Section("Agent folder") {
            LabeledContent("Folder") {
                HStack {
                    Text(AgentFolder.displayPath(bookmark: folderBookmark) ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        Task { if let bookmark = await AgentFolderPanel.choose() { folderBookmark = bookmark } }
                    }
                    .accessibilityIdentifier("settings.agents.folder.choose")
                    if folderBookmark != nil {
                        Button("Remove") { folderBookmark = nil }
                            .accessibilityIdentifier("settings.agents.folder.remove")
                    }
                }
            }
            Text("An agent can list the files in this folder and its subfolders, and, with \"Let agents run analyses\" on, open "
                + "them. It never changes, replaces or deletes a file. Nothing outside the folder is reached.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: folderBookmark) { _, bookmark in
            if let refreshed = MacTEMAgentDoor.setFolder(bookmark: bookmark) { folderBookmark = refreshed }
        }
    }
}
