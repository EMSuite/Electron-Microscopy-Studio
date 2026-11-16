//
//  AgentSettingsView.swift
//  Role: macTEM's Settings window (⌘,): Agents, the agent door's switch (`MacTEMAgentDoor`), and in the website download Software
//        Update (`SoftwareUpdateSettingsSection`, #583). The agent section itself is MacEMUI's (`AgentDoorSettingsSection`), the
//        same in both apps; this view keeps the preference and opens or closes the door when it changes.
//

import ShellAgentDoor
import SwiftUI

struct AgentSettingsView: View {
    @AppStorage(MacTEMAgentDoor.enabledKey) private var enabled = false
    @AppStorage(MacTEMAgentDoor.runsKey) private var runs = false

    var body: some View {
        Form {
            AgentDoorSettingsSection(door: MacTEMAgentDoor.shared, isOn: $enabled,
                                     canSee: "the open files, the image as Export Image draws it, the results and the Output lines",
                                     runs: $runs,
                                     canRun: "move a window to another room, pick elements and the region in the EDS room, and press Auto ID, "
                                         + "Quantify and Stop there")
            #if SPARKLE
            SoftwareUpdateSettingsSection()   // the website download only (#583)
            #endif
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, now in MacTEMAgentDoor.shared.setEnabled(now) }
        .onChange(of: runs) { _, now in MacTEMAgentDoor.shared.runsAllowed = now }
        .accessibilityIdentifier("settings.agents")
    }
}
