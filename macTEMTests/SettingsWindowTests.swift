//
//  SettingsWindowTests.swift
//  The Settings window (#626, control-placement §10): a sidebar of sections, Images first, built as mac4DSTEM's; the SEM databar's choice
//  lives there and nowhere in a room, read by every window from the one key, so a change in Settings shows in each open window at once.
//  Red before: Settings was the agent switch alone and the databar a Hide · Show switch in the Image room's Display section, kept on
//  each window's `AppState`.
//

import ShellPhaseLibrary
import XCTest
@testable import macTEM

nonisolated final class SettingsWindowTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    func testTheSectionsAreImagesThenAgents() {
        XCTAssertEqual(Array(SettingsSection.allCases.prefix(2)), [.images, .agents])
        XCTAssertEqual(SettingsSection.images.title, "Images")
        XCTAssertEqual(Set(SettingsSection.allCases.map(\.id)).count, SettingsSection.allCases.count, "one id each")
    }

    /// Settings > Materials Project is EMSuiteUI's pane (#778): its sections on the app's one key store and client, which are
    /// EMSuiteUI's keychain store, the same item in both builds. Red before: no section.
    @MainActor func testMaterialsProjectIsASectionOnTheSharedKeyStore() throws {
        XCTAssertTrue(SettingsSection.allCases.contains(.materialsProject))
        XCTAssertEqual(SettingsSection.materialsProject.title, "Materials Project")
        let window = squeezed(try source("macTEM/UI/SettingsWindow.swift"))
        XCTAssertTrue(window.contains("case .materialsProject: MaterialsProjectSettingsSections(model: materialsProject)"))
        XCTAssertTrue(window.contains("MaterialsProjectSettingsModel(keyStore: PhaseServices.keyStore, client: PhaseServices.client)"))
        XCTAssertTrue(PhaseServices.keyStore is KeychainAPIKeyStore, "the key lives in the login keychain")
        let services = try source("macTEM/App/PhaseServices.swift")
        XCTAssertFalse(services.contains("#if"), "one key store for the store build and the download")
    }

    /// The scene shows the window; the Images section holds the databar's toggle on the one key.
    func testTheSceneShowsTheWindowAndImagesHoldsTheDatabar() throws {
        let app = squeezed(try source("macTEM/App/macTEMApp.swift"))
        XCTAssertTrue(app.contains("Settings { SettingsWindow()"), "the Settings scene is the sectioned window")
        let window = squeezed(try source("macTEM/UI/SettingsWindow.swift"))
        XCTAssertTrue(window.contains("NavigationSplitView {"))
        XCTAssertTrue(window.contains("@AppStorage(SEMImageSettings.cropDatabarKey) private var cropsDatabar = SEMImageSettings.cropDatabarDefault"))
        XCTAssertTrue(window.contains("Toggle(\"Hide the SEM databar\", isOn: $cropsDatabar)"))
    }

    /// VoiceOver reads the databar switch by its row's words (#1023; the agent switches are EMSuiteUI's, labelled there). Red before:
    /// a bare switch in the accessibility tree.
    func testTheDatabarSwitchIsLabelled() throws {
        let window = squeezed(try source("macTEM/UI/SettingsWindow.swift"))
        XCTAssertTrue(window.contains("Toggle(\"Hide the SEM databar\", isOn: $cropsDatabar) .accessibilityLabel(\"Hide the SEM databar\")"))
    }

    /// Images holds the scroll wheel's Zoom · Pan, the shared row (control-placement §6), above the databar. Red before: no row.
    func testImagesHoldsTheScrollWheelChoice() throws {
        let window = squeezed(try source("macTEM/UI/SettingsWindow.swift"))
        let wheel = try XCTUnwrap(window.range(of: "ScrollWheelSettingRow()"), "Settings > Images offers Zoom · Pan")
        let databar = try XCTUnwrap(window.range(of: "Toggle(\"Hide the SEM databar\""))
        XCTAssertLessThan(wheel.lowerBound, databar.lowerBound)
    }

    /// No room holds the switch and no window keeps its own copy: the pane reads the key, the Display section only says which.
    func testNoRoomHoldsTheDatabarSwitch() throws {
        XCTAssertFalse(try source("macTEM/App/AppState.swift").contains("cropsDatabar"), "a window's own copy would not follow Settings")
        let sem = try source("macTEM/UI/ImageRoomSEM.swift")
        XCTAssertFalse(sem.contains("SegmentedPicker(label: \"Databar\""), "the Display section holds no databar switch")
        XCTAssertTrue(try source("macTEM/UI/ImagePane.swift").contains("@AppStorage(SEMImageSettings.cropDatabarKey)"))
    }

    /// The Display section's note says which, and where to change it.
    func testTheDisplayNoteNamesSettings() {
        XCTAssertEqual(SEMDatabarNote.note(rows: 29, hidden: true),
                       "Databar hidden: the 29 rows under the scan are cut; lengths and exports are of the scan. Settings > Images shows it.")
        XCTAssertTrue(SEMDatabarNote.note(rows: 29, hidden: false).hasSuffix("Settings > Images hides it."))
    }
}
