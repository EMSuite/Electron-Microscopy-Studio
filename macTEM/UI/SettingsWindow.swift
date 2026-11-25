//
//  SettingsWindow.swift
//  Role: the Settings scene (⌘,), built as mac4DSTEM's `SettingsWindow` is (control-placement §10): a `NavigationSplitView` with a
//        sidebar of sections and a grouped `Form` beside it. A choice lives here, not in a room, when it changes no number in an open
//        document and outlives the document: the scroll wheel and the SEM databar (Images, #626), the agent door (Agents), the
//        Materials Project key (#778, EMSuiteUI's pane, kept in the login keychain) and, in the website download, Software Update. Every value is a UserDefaults key read through `@AppStorage`, so each open window follows a change at once;
//        this scene has no window's `AppState`.
//
//  `NavigationSplitView`, never `HSplitView`/`NSSplitView`, as the workspace split.
//

import ShellControls
import ShellLayout
import ShellPhaseLibrary
import ShellPhaseViews
import SwiftUI

nonisolated enum SettingsSection: String, CaseIterable, Identifiable {
    case images, agents, materialsProject
    #if SPARKLE
    case softwareUpdate
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: "Images"
        case .agents: "Agents"
        case .materialsProject: "Materials Project"
        #if SPARKLE
        case .softwareUpdate: "Software Update"
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .images: "photo"
        case .agents: "door.left.hand.open"
        case .materialsProject: "atom"
        #if SPARKLE
        case .softwareUpdate: "arrow.down.circle"
        #endif
        }
    }
}

struct SettingsWindow: View {
    @State private var selection: SettingsSection? = .images
    @State private var materialsProject = MaterialsProjectSettingsModel(keyStore: PhaseServices.keyStore,
                                                                         client: PhaseServices.client)

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: LayoutPolicy.sidebarWidth.min, ideal: LayoutPolicy.sidebarWidth.ideal,
                                            max: LayoutPolicy.sidebarWidth.max)
        } detail: {
            Form {
                switch selection ?? .images {
                case .images: ImageSettingsSection()
                case .agents: AgentSettingsView()
                case .materialsProject: MaterialsProjectSettingsSections(model: materialsProject)
                #if SPARKLE
                case .softwareUpdate: SoftwareUpdateSettingsSection()   // the website download only (#583)
                #endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle((selection ?? .images).title)
        }
        // The category list stands; there is nothing to toggle in a settings window (System Settings' own shape).
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: LayoutPolicy.settingsWindow.min.width, idealWidth: LayoutPolicy.settingsWindow.ideal.width,
               minHeight: LayoutPolicy.settingsWindow.min.height, idealHeight: LayoutPolicy.settingsWindow.ideal.height)
    }
}

/// Settings > Images: whether the databar a Thermo or Tescan SEM TIFF's vendor drew under the scan is hidden (the default) or shown as a
/// strip under the picture. The picture, every length and every export are of the scan either way (`SEMImageSettings`).
struct ImageSettingsSection: View {
    @AppStorage(SEMImageSettings.cropDatabarKey) private var cropsDatabar = SEMImageSettings.cropDatabarDefault

    var body: some View {
        // Control-placement §6: what the wheel does on every zoomable picture, the shared row both apps' Settings show (MacEMUI).
        Section {
            ScrollWheelSettingRow()
        } footer: {
            Text("Zoom about the pointer, as Velox, GMS and ImageJ do, or pan, the Mac's way. Hold ⌥ for the other.")
        }
        Section {
            Toggle("Hide the SEM databar", isOn: $cropsDatabar)
                .accessibilityIdentifier("settings.images.cropDatabar")
        } footer: {
            Text("The bar a Thermo or Tescan microscope draws under the scan. Shown, it is a strip under the picture; lengths and exports "
                 + "are of the scan either way.")
        }
    }
}
