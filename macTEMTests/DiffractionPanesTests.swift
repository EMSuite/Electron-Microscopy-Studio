//
//  DiffractionPanesTests.swift
//  Charts, maps and result tables leave the inspector for panes of the room (#921, control placement §1): the pane beside the Diffraction
//  room's pattern shows the crystal, the zone-axis map or the powder pattern, picked from View or its header; the powder peaks are a
//  table under the pattern with ⌘C; the HRTEM transfer function is a strip under its image. The Holder, Powder and HRTEM sections hold
//  rows and buttons only. Red before: the map, the chart, the peak list and the transfer chart were drawn in their sections, and the
//  room had one pane beside the pattern, the crystal.
//

import XCTest
import DiffractoCore
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionPanesTests: XCTestCase {

    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// One pane beside the pattern, three views: a View item shows the pane with its view, or hides it while that view is shown.
    @MainActor func testTheSidePaneShowsOneOfThreeViews() {
        let view = DiffractionViewState()
        XCTAssertEqual(view.sidePane, .crystal, "the crystal, as before")
        XCTAssertTrue(view.isShowing(.crystal) && view.showsCrystal)
        view.toggle(.zoneAxisMap)
        XCTAssertTrue(view.isShowing(.zoneAxisMap))
        XCTAssertFalse(view.showsCrystal, "one view at a time")
        view.toggle(.zoneAxisMap)
        XCTAssertFalse(view.showsSidePane, "the same item hides it")
        view.toggle(.powder)
        XCTAssertTrue(view.isShowing(.powder))
        view.showsCrystal = true
        XCTAssertTrue(view.isShowing(.crystal))
        view.showsCrystal = false
        XCTAssertFalse(view.showsSidePane)

        let analysis = DiffractionAnalysis()
        analysis.simulation.isShown = false
        view.toggle(.zoneAxisMap)
        XCTAssertTrue(DiffractionSidePaneView.isShown(view: view, analysis: analysis), "the map's pane needs no simulated spots")
    }

    /// The View menu's items name the pane and say Hide only while it is shown (never "Hide Crystal" outside the room).
    @MainActor func testTheMenuTitlesNameThePane() {
        XCTAssertEqual(DiffractionPaneWords.menuTitle(.crystal, shown: false), "Show Crystal")
        XCTAssertEqual(DiffractionPaneWords.menuTitle(.zoneAxisMap, shown: true), "Hide Zone-axis Map")
        XCTAssertEqual(DiffractionPaneWords.menuTitle(.powder, shown: false), "Show Powder Pattern")
        XCTAssertEqual(DiffractionViewState.SidePane.allCases.map(DiffractionPaneWords.title), ["Crystal", "Zone-axis Map", "Powder Pattern"])
    }

    /// The table strip offers the peaks while the Powder Pattern pane is shown, and falls back to the readout when the chosen table goes.
    @MainActor func testThePeaksTableComesWithThePowderPane() {
        let view = DiffractionViewState()
        XCTAssertEqual(view.lowerTables(hasSpots: false), [.readout])
        XCTAssertEqual(view.shownLowerTable(hasSpots: false), .readout, "Spots chosen, none yet: the readout")
        XCTAssertEqual(view.shownLowerTable(hasSpots: true), .spots)
        view.toggle(.powder)
        XCTAssertEqual(view.lowerTables(hasSpots: true), [.readout, .spots, .peaks])
        view.lowerTable = .peaks
        XCTAssertEqual(view.shownLowerTable(hasSpots: false), .peaks)
        view.toggle(.powder)
        XCTAssertEqual(view.shownLowerTable(hasSpots: true), .readout, "the pane hidden, its table goes with it")
    }

    /// The peaks copy as the other tables do: the titles, then a row a line, tab-separated, strongest first.
    @MainActor func testThePeaksCopyAsTheTableShowsThem() {
        let powder = DiffractionPowder()
        let al = StandardCrystals.all.first { $0.name == "Al" }!
        let table = powder.table(phases: powder.phases(crystal: .preset(al), others: []), volts: nil)
        let rows = DiffractionPowderPeakFormat.ordered(table)
        XCTAssertEqual(rows.first?.hkl, "111", "strongest first")
        let en = Locale(identifier: "en_US")
        let text = DiffractionPowderPeakFormat.copyText(Array(rows.prefix(1)), table: table, locale: en)
        XCTAssertEqual(text, "Phase\thkl\td (Å)\t2θ (°)\tI\tMarks\nAl\t111\t2.338\t38.51\t100\t◆ diagnostic")
        XCTAssertEqual(DiffractionPowderPeakFormat.copyText([], table: table), "", "nothing selected copies nothing")
    }

    /// The sections hold rows and buttons; the results are drawn in the panes. Identifiers kept for the door.
    func testTheSectionsHoldRowsAndThePanesTheResults() throws {
        let holder = try ui("DiffractionHolderSection.swift")
        XCTAssertFalse(holder.contains("DiffractionZoneAxisMap("), "the map is a pane")
        XCTAssertFalse(holder.contains("InspectorNote(plan."), "the calibration's and the tilt's sentences are the pane's words")
        let powder = try XCTUnwrap(try ui("DiffractionPowderSection.swift").components(separatedBy: "struct DiffractionPowderChart").first)
        XCTAssertFalse(powder.contains("DiffractionPowderChart(") || powder.contains("PeakList(") || powder.contains("table.headline("),
                       "the chart, the peaks and the headlines are the pane's and the table's")
        let pane = try ui("DiffractionSidePane.swift")
        for id in ["diffraction.sidePane", "diffraction.powder.pane", "diffraction.powder.peaks", "diffraction.holder.sentence"] {
            XCTAssertTrue(pane.contains(".accessibilityIdentifier(\"\(id)\")"), id)
        }
        XCTAssertTrue(pane.contains("DiffractionZoneAxisMap(plan: plan, selected:"), "the map, with its click, in the pane")
        XCTAssertTrue(pane.contains(".onCopyCommand(perform: selection.isEmpty ? nil :"), "⌘C copies the peaks")
        XCTAssertTrue(try ui("DiffractionZoneAxisMap.swift").contains(".accessibilityIdentifier(\"diffraction.holder.map\")"))
    }

    /// The HRTEM transfer function is a strip under its image, not an inspector section (#921, mockup 5).
    func testTheTransferFunctionIsAStripUnderTheImage() throws {
        let hrtem = try ui("SimulationHRTEMSection.swift")
        XCTAssertFalse(hrtem.contains("InspectorSection(\"Transfer Function\")") || hrtem.contains("SimulationTransfer"))
        XCTAssertTrue(try ui("ImagePane.swift").contains("HRTEMTransferStrip(item: item)"), "the strip is under the image")
        let strip = try ui("SimulationHRTEMOptics.swift")
        XCTAssertTrue(strip.contains("if DemoDocuments.isHRTEM(item.url), let simulation = appState.simulationDocument(ofHRTEM: item) {"))
        XCTAssertTrue(strip.contains(".accessibilityIdentifier(\"simulation.hrtem.transfer\")"), "the door's id kept")
    }
}
