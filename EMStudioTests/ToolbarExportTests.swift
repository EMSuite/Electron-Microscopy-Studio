//
//  ToolbarExportTests.swift
//  The toolbar's second button is Export (#1048): a click runs the room's main export (⇧⌘E's in the Image and Diffraction rooms,
//  else the first item the room's File menu lists), the chevron lists the room's exports through the File menu's own view
//  (`RoomExportItems`), so the two lists cannot drift, and it is off with its reason while the room holds no document. Red before:
//  the slot was the Image menu (`toolbar.datasetMenu`) repeating File > Open and Close, titled "Image" in every room.
//

import XCTest
@testable import EMStudio

nonisolated final class ToolbarExportTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// The click's export per room. Mutation: the Image room's click running the profile; a room with no main export.
    func testThePrimaryExportPerRoom() {
        let expected: [WorkspaceArea: String] = [
            .image: "Export Figure…", .diffraction: "Export Figure…", .fft: "Export Transform…", .results: "Export Results…",
            .edx: "Export Spectrum CSV…", .eels: "Export Spectrum CSV…", .patterns: "Export Map PNG…", .indexing: "Export Map PNG…",
            .maps: "Export Map PNG…",
        ]
        for area in WorkspaceArea.allCases {
            XCTAssertEqual(ToolbarExport.primary(in: area).menuTitle, expected[area], "\(area)")
        }
        XCTAssertEqual(ToolbarExport.primary(in: .image), .imageFigure)
        XCTAssertEqual(ToolbarExport.primary(in: .diffraction), .diffractionFigure)
    }

    /// The click runs the File menu's item: ⇧⌘E's Export Figure… where a room has it, and in a room whose items are its kinds, the
    /// first kind the menu lists. Mutation: a click that runs an item the menu does not list first.
    func testThePrimaryIsTheMenusMainItem() throws {
        let commands = squeezed(try source("EMStudio/App/ExportCommands.swift"))
        XCTAssertTrue(commands.contains("Button(\"Export Figure…\") { guard let appState else { return } if inDiffraction { ExportPanels.exportDiffractionFigure(appState: appState) } else { ExportPanels.exportImage(appState: appState) } } .keyboardShortcut(\"e\", modifiers: [.command, .shift])"),
                      "⇧⌘E is Export Figure…, the Image and Diffraction rooms' click")
        XCTAssertTrue(commands.contains("Button(\"Export Transform…\")"))
        XCTAssertTrue(commands.contains("Divider() Button(\"Export Spectrum CSV…\") { RoomExports.eds(.spectrum, appState: appState) }"),
                      "the EDS room's first item")
        XCTAssertEqual(EELSExportAvailability.menuKinds.first, .spectrum)
        XCTAssertEqual(PatternsExportKind.allCases.first, .mapPNG)
        XCTAssertEqual(IndexingExportKind.allCases.first, .mapPNG)
        XCTAssertEqual(MapsExportKind.allCases.first, .map)
        let run = squeezed(try source("EMStudio/App/ToolbarExport.swift"))
        for call in ["case .imageFigure: ExportPanels.exportImage(appState: appState)",
                     "case .diffractionFigure: ExportPanels.exportDiffractionFigure(appState: appState)",
                     "case .transform: ExportPanels.exportTransform(appState: appState)",
                     "case .results: ExportPanels.exportResults(appState: appState)",
                     "case .edsSpectrum: RoomExports.eds(.spectrum, appState: appState)",
                     "case .eelsSpectrum: RoomExports.eels(.spectrum, appState: appState)",
                     "case .patternsMap: RoomExports.patterns(.mapPNG, appState: appState)",
                     "case .indexingMap: RoomExports.indexing(.mapPNG, appState: appState)",
                     "case .mapsMap: RoomExports.maps(.map, appState: appState)"] {
            XCTAssertTrue(run.contains(call), call)
        }
    }

    /// One list: the File menu's export group and the toolbar's menu are the same view. Mutation: the toolbar listing its own items.
    func testTheToolbarListsTheFileMenusExports() throws {
        let commands = squeezed(try source("EMStudio/App/ExportCommands.swift"))
        XCTAssertTrue(commands.contains("CommandGroup(after: .saveItem) { // The room's exports: the same view the toolbar's Export menu lists (#1048), so the two cannot drift. RoomExportItems(appState: appState) }"))
        let view = squeezed(try source("EMStudio/UI/ContentView.swift"))
        XCTAssertTrue(view.contains("Menu { RoomExportItems(appState: appState, dividesFromAbove: false) } label: { Label(ToolbarExport.title, systemImage: ToolbarExport.systemImage) } primaryAction: { ToolbarExport.run(primary, appState: appState) }"))
        XCTAssertTrue(view.contains("documentMenu: { ToolbarExportMenu() }"))
        XCTAssertEqual(ToolbarExport.title, "Export")
        XCTAssertEqual(ToolbarExport.systemImage, "square.and.arrow.up")
        XCTAssertEqual(ToolbarExport.help, "Export from this room")
    }

    /// `toolbar.export` replaces `toolbar.datasetMenu`, in the view and in the door's coverage; File > Open… keeps its row.
    func testTheIdentifierIsExport() throws {
        let view = try source("EMStudio/UI/ContentView.swift")
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"toolbar.export\")"))
        XCTAssertFalse(view.contains("toolbar.datasetMenu"))
        XCTAssertFalse(view.contains("struct ImageMenu"), "the menu that repeated Open and Close is gone")
        XCTAssertEqual(AgentDoorCoverage.controls["toolbar.export"], .personOnly(AgentDoorCoverage.exportReason))
        XCTAssertNil(AgentDoorCoverage.controls["toolbar.datasetMenu"])
        XCTAssertEqual(AgentDoorCoverage.menuItems["Open…"], .tool("open_file"))
    }

    /// Off with its reason while the room holds no document. Mutation: on in an empty window.
    func testOffWithItsReasonWithNothingToExport() {
        XCTAssertEqual(ToolbarExport.blocker(hasDocument: false), ToolbarExport.nothingSentence)
        XCTAssertNil(ToolbarExport.blocker(hasDocument: true))
    }

    @MainActor func testAnEmptyWindowHasNothingToExport() {
        let state = AppState()
        XCTAssertEqual(ToolbarExport.blocker(state), ToolbarExport.nothingSentence)
        XCTAssertFalse(ToolbarExport.isEnabled(ToolbarExport.primary(in: state.navigation.workspaceArea), appState: state))
    }
}
