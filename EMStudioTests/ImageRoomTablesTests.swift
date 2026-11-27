//
//  ImageRoomTablesTests.swift
//  The Image room has one Export section and its results sit under the image (#864): the selected line's profile chart and the found
//  objects (counts and table) are tabs of the shell's bottom area beside Output, as the Diffraction and Maps rooms' tables are, and
//  Figure…, Profile CSV… and Particles CSV… are one closed Export section, last (control placement §2, §4). Red before: Export
//  Profile… under the chart in Measure, Export CSV… and the counts in Particles, no Image tab in the bottom area, no Export section.
//

import ShellLayout
import XCTest
@testable import EMStudio

nonisolated final class ImageRoomTablesTests: XCTestCase {
    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// Each result has a tab of its own, never Output's, with a name for the area's header and a symbol.
    @MainActor func testEachResultHasItsOwnTab() {
        let ids = ImageTable.allCases.map(\.paneID)
        XCTAssertEqual(Set(ids).count, ImageTable.allCases.count)
        XCTAssertFalse(ids.contains(.output))
        XCTAssertEqual(ids.map(\.rawValue), ["image.profile", "image.objects"])
        XCTAssertEqual(ImageTable.allCases.map(\.title), ["Profile", "Objects"])
        XCTAssertTrue(ImageTable.allCases.allSatisfy { !$0.systemImage.isEmpty })
        XCTAssertTrue(Set(ids).isDisjoint(with: DiffractionTable.allCases.map(\.paneID) + MapsTable.allCases.map(\.paneID)))
    }

    /// The window selects a tab the first time it has something to show and opens the area; after that the person's choice wins.
    /// Mutation: `offer` selecting every time, never, or leaving a shut area shut.
    @MainActor func testATabIsSelectedOnceAndThePersonsChoiceWins() {
        let tools = ImageRoomTools()
        let panels = PanelNavigation()
        XCTAssertFalse(panels.showProcessArea)
        tools.offer(nil, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, .output)

        tools.offer(.profile, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, ImageTable.profile.paneID)
        XCTAssertTrue(panels.showProcessArea, "the area opens with it")
        panels.selectProcessPane(.output)
        tools.offer(.profile, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, .output, "the person chose Output: a second offer leaves it")

        panels.showProcessArea = false
        tools.offer(.objects, in: panels)
        XCTAssertEqual(panels.selectedProcessPane, ImageTable.objects.paneID, "objects found: the Objects tab is selected once")
        panels.showProcessArea = false
        tools.offer(.objects, in: panels)
        XCTAssertFalse(panels.showProcessArea, "the area the person shut stays shut")
        XCTAssertEqual(tools.offeredTables, [.profile, .objects])
    }

    /// The bottom area holds the Image room's tabs in that room only, and the room's pane offers them; the profile's chart and the
    /// objects' counts are drawn there, not in the inspector. Mutation: the chart back in Measure, the counts back in Particles.
    func testTheChartAndTheCountsSitUnderTheImage() throws {
        let workspace = try ui("WorkspaceView.swift")
        XCTAssertTrue(workspace.contains("+ imageTabs + diffractionTabs + mapsTabs,"))
        XCTAssertTrue(workspace.contains("guard appState.navigation.workspaceArea == .image, appState.openItems.selected?.session.image != nil else { return [] }"))
        XCTAssertTrue(workspace.contains("ImagePane(item: item) .modifier(ImageTableOffers(item: item))"))
        let tables = try ui("ImageRoomTables.swift")
        XCTAssertTrue(tables.contains("MeasureProfileChart(profile: profile, x: image.x, y: image.y)"))
        XCTAssertTrue(tables.contains("ParticleTableSheet(analysis: item.particles, report: report, scale: ParticleCompute.scale(of: image), embedded: true)"))
        XCTAssertTrue(tables.contains(".accessibilityIdentifier(\"particles.counts\") .accessibilityValue(String(report.summary.counted))"))
        XCTAssertTrue(tables.contains("guard appState.navigation.workspaceArea == .image else { return }"), "offers only in the Image room")
        XCTAssertFalse(try ui("ImageRoomMeasure.swift").contains("MeasureProfileChart(profile:"), "no chart in Measure")
        let particles = try ui("ImageRoomParticles.swift")
        let section = try XCTUnwrap(particles.components(separatedBy: "// MARK: - The table").first)
        XCTAssertFalse(section.contains("ParticleFormat.counts("), "no counts in the Particles section")
        XCTAssertTrue(particles.contains("if embedded { ImageObjectsSummary(report: report, scale: scale) }"))
    }

    /// One Export section, last and closed, with the three plain buttons and their identifiers; none left in Measure or Particles.
    /// Mutation: an export button back in a job section, the section open, or not last.
    func testTheRoomHasOneExportSectionLast() throws {
        let tables = try ui("ImageRoomTables.swift")
        XCTAssertTrue(tables.contains("InspectorSection(\"Export\", startsExpanded: false) {"))
        for (title, id) in [("Figure…", "image.export.figure"), ("Profile CSV…", "export.profileButton"), ("Particles CSV…", "particles.export")] {
            XCTAssertTrue(tables.contains("Button(\"\(title)\")"), title)
            XCTAssertTrue(tables.contains(".accessibilityIdentifier(\"\(id)\")"), id)
        }
        XCTAssertFalse(try ui("ImageRoomMeasure.swift").contains("Button(\"Export"), "no export in Measure")
        XCTAssertFalse(try ui("ImageRoomParticles.swift").contains("Button(\"Export"), "no export in Particles")
        XCTAssertTrue(try ui("ImageRoomInspector.swift").contains("case .export: // What the room takes home, last and closed (control placement §4, #864). if let item { ImageRoomExportSection(item: item) }"))
        for kind in [ImageSections.Kind.measured, .hrtem, .stem] { XCTAssertEqual(ImageSections.order(kind).last, .export) }
    }
}
