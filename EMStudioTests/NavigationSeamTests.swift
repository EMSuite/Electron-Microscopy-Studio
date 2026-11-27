// The layout tests (window minimum, widest sidebar at the floor, the process area's drag extremes and toggle restore,
// WindowFillingLayout). The numbers are ShellLayout's (suite task 8, MacEMUI); the class is nonisolated and each test @MainActor.
import ShellLayout
import SwiftUI
import XCTest
@testable import EMStudio

nonisolated final class NavigationSeamTests: XCTestCase {

    @MainActor func testInfobarDragReachesBothExtremesWithoutMovingTheFixedBarHeight() {
        let available: CGFloat = 600
        let hidden = ProcessAreaLayout.heights(fraction: 0, available: available)
        XCTAssertEqual(hidden.canvas, available)
        XCTAssertEqual(hidden.process, 0)

        let full = ProcessAreaLayout.heights(fraction: 1, available: available)
        XCTAssertEqual(full.canvas, 0)
        XCTAssertEqual(full.process, available)

        let draggedUp = ProcessAreaLayout.fraction(afterDrag: -300, available: available, from: 0.25)
        XCTAssertEqual(draggedUp, 0.75, accuracy: 0.001)
        let draggedDown = ProcessAreaLayout.fraction(afterDrag: 300, available: available, from: 0.25)
        XCTAssertEqual(draggedDown, 0, accuracy: 0.001)
    }

    /// The Output log is shut in a fresh window and stays shut in every room until the person opens it (#1097): entering a room
    /// with a document opens nothing, and no app source opens the area or picks Output but the View menu's toggle. A room's
    /// table is offered in the area when the person asks for it (`offer`), which is not the log. Red under: a room that sets
    /// `showProcessArea = true` or selects `.output` on entry.
    @MainActor func testTheOutputLogIsShutUntilThePersonOpensIt() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        XCTAssertFalse(state.navigation.panels.showProcessArea, "a fresh window's Output is shut")
        await state.openDemo(.diffraction)?.value
        for area in WorkspaceArea.allCases {
            state.selectWorkspace(area)
            XCTAssertFalse(state.navigation.panels.showProcessArea, "entering \(area) opened the Output log")
        }
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        for folder in ["EMStudio", "Sources"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                for opener in ["showProcessArea = true", "selectProcessPane(.output)", "insert(.output)", "processFraction = "] {
                    XCTAssertFalse(text.contains(opener), "\(url.lastPathComponent) opens the Output log on its own (\(opener))")
                }
            }
        }
    }

    /// `PanelNavigation.showProcessArea` (the shell's, held as `panels`) is `processFraction > 0` with a setter that restores `lastProcessFraction`.
    @MainActor func testProcessAreaToggleRestoresTheLastDraggedFraction() {
        let navigation = WorkspaceNavigation()
        navigation.panels.processFraction = 0.6
        navigation.panels.showProcessArea = false
        XCTAssertEqual(navigation.panels.processFraction, 0)
        XCTAssertEqual(navigation.panels.lastProcessFraction, 0.6)
        navigation.panels.showProcessArea = true
        XCTAssertEqual(navigation.panels.processFraction, 0.6)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0.6, last: 0.6), 0)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0, last: 0.6), 0.6)
    }

    /// The window's own minimum width covers the ideal columns plus both science panes at their floor, so nothing
    /// collapses a panel to make room. Pins the derivation, the 915 it gives, and that it stays above 900.
    @MainActor func testDatasetWindowMinimumWidthCoversTheIdealColumnsAndBothSciencePanes() {
        let required = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, required)
        XCTAssertEqual(LayoutPolicy.datasetWindowMinimumSize.width, 915)
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, 900)
    }

    /// The sidebar dragged to its maximum must still leave the inspector and both science panes their floor at the
    /// window's minimum. A saved sidebar wider than that crashed every launch in the constraint loop at 915 pt
    /// .
    @MainActor func testTheWidestSidebarStillFitsTheMinimumWindow() {
        let required = LayoutPolicy.sidebarWidth.max + LayoutPolicy.inspectorWidth.min
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertLessThanOrEqual(required, LayoutPolicy.datasetWindowMinimumSize.width)
    }

    /// The window-width probe answers a finite proposal with itself, whatever the child needs. Red under the old
    /// shape (the split measured directly: 1190 in a 915-pt window) and under `max(proposal, child)`.
    @MainActor func testWindowFillingLayoutReportsTheOfferedSizeNotTheRigidChild() {
        let rigid = CGSize(width: 1190, height: 700)
        let reported = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: 915, height: 600), child: rigid)
        XCTAssertEqual(reported.width, 915)
        XCTAssertEqual(reported.height, 600)
        // The sidebar's step-aside line reads that width: 915 < 1095.
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: reported.width, inspectorVisible: true))
    }

    /// An ideal or unbounded query still goes to the child, so the window's ideal and maximum sizes are unchanged.
    /// Red if the layout answered 0 or infinity for those.
    @MainActor func testWindowFillingLayoutDefersIdealAndUnboundedQueriesToTheChild() {
        let child = CGSize(width: 1280, height: 800)
        let ideal = WindowFillingLayout.reportedSize(proposal: .unspecified, child: child)
        XCTAssertEqual(ideal, child)
        let unbounded = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: .infinity, height: 500), child: child)
        XCTAssertEqual(unbounded.width, 1280)
        XCTAssertEqual(unbounded.height, 500)
    }
}
