//
//  DiffractionCrystalSplitTests.swift
//  The pattern gets two thirds of the centre, the crystal pane a third (#1046): the default fraction as data, the stored place kept
//  (the key `PaneSplit` stored the crystal's share under, which the frame's centre `WorkspaceCentre` keeps since #1094, so a place
//  dragged in an earlier version reads back), and the pattern fitted to its panel with no margin of the room's own, at least 505 pt
//  across in a 1400 × 876 window with the sidebar, the inspector and the bottom area open (at least 510 pt with the bottom area shut).
//  Red before: the split was half and half and the pane kept an 8 pt margin, so the pattern was about 408 pt.
//

import ShellLayout
import ShellSpectroscopy
import SwiftUI
import XCTest
@testable import EMStudio

nonisolated final class DiffractionCrystalSplitTests: XCTestCase {
    private func squeezed(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Mutation: half and half again; another key (an earlier drag lost).
    func testTheCrystalTakesAThirdByDefaultUnderItsOldKey() throws {
        XCTAssertEqual(DiffractionCrystalSplit.defaultCrystalFraction, 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(DiffractionCrystalSplit.storageKey, "diffraction.crystalSplit", "the key PaneSplit stored the crystal's share under")
        let room = try squeezed("EMStudio/UI/DiffractionRoom.swift")
        XCTAssertTrue(room.contains("WorkspaceCentre(storageKey: DiffractionCrystalSplit.storageKey, defaultFraction: DiffractionCrystalSplit.defaultCrystalFraction, resizeLabel: \"Resize the side pane and the pattern\", leadingName: DiffractionPaneWords.title(pane)"),
                      "the side pane (the crystal in Index and Simulate) leads, as before, so the stored share keeps its meaning")
        XCTAssertFalse(room.contains("PaneSplit(storageKey: \"diffraction.crystalSplit\""))
        XCTAssertFalse(room.contains("WorkspaceCentre(storageKey: CentreSplitModel.storageKey(room:"), "the old key, not a new one")
    }

    /// A dragged place is the person's: the split's clamp leaves a stored share inside the panes' floors alone. Mutation: a clamp that
    /// pulls every stored value to the default.
    @MainActor func testAStoredPlaceIsKept() {
        let usable: CGFloat = 847
        let model = CentreSplitModel(arrangement: .split, defaultFraction: DiffractionCrystalSplit.defaultCrystalFraction,
                                     minimumLeading: LayoutPolicy.imagePaneMinimum, minimumTrailing: LayoutPolicy.imagePaneMinimum)
        for dragged in [0.25, 0.5, 0.6] {
            XCTAssertEqual(model.restored(dragged), dragged, "\(dragged): read back as stored")
            XCTAssertEqual(model.clamped(dragged, usable: usable), dragged, "\(dragged)")
        }
        // A wider crystal than the default makes a smaller pattern: the stored share is what the layout uses.
        let wide = DiffractionCrystalSplit.patternSide(width: 848, height: 900, crystalFraction: 0.5, minimumPane: LayoutPolicy.imagePaneMinimum)
        let third = DiffractionCrystalSplit.patternSide(width: 848, height: 900, crystalFraction: 1.0 / 3, minimumPane: LayoutPolicy.imagePaneMinimum)
        XCTAssertLessThan(wide, third)
    }

    /// The pattern's fitted side in a 1400 × 876 window, the sidebar and the inspector at their ideal widths: the centre is
    /// 1400 − 230 − 320 − 2 dividers wide; the column's height loses the toolbar (52 pt, macOS 26's unified title bar and toolbar)
    /// and the infobar, and the bottom area, which holds the tables since #1094, takes its ideal share of the rest; the pattern's
    /// panel takes its inset and its header (`patternSide`). The frame's panel insets cost about 10 pt against the room's own
    /// header row and fixed strip before (515 pt then). Mutation: a margin of the room's own back; half and half again (about 408 pt).
    @MainActor func testThePatternIsAtLeast505PointsInA1400By876Window() throws {
        let width: CGFloat = 1400 - LayoutPolicy.sidebarWidth.ideal - LayoutPolicy.inspectorWidth.ideal - 2
        let toolbar: CGFloat = 52
        let column: CGFloat = 876 - toolbar - LayoutPolicy.statusStripHeight
        let open = ProcessAreaLayout.heights(fraction: LayoutPolicy.processAreaIdealFraction, available: column).canvas
        let side = DiffractionCrystalSplit.patternSide(width: width, height: open,
                                                       crystalFraction: DiffractionCrystalSplit.defaultCrystalFraction,
                                                       minimumPane: LayoutPolicy.imagePaneMinimum)
        XCTAssertGreaterThanOrEqual(side.rounded(), 505, "the pattern's side with the bottom area open: \(side) pt")
        let shut = DiffractionCrystalSplit.patternSide(width: width, height: column,
                                                       crystalFraction: DiffractionCrystalSplit.defaultCrystalFraction,
                                                       minimumPane: LayoutPolicy.imagePaneMinimum)
        XCTAssertGreaterThanOrEqual(shut, 510, "the pattern's side with the bottom area shut: \(shut) pt")
        let halfAndHalf = DiffractionCrystalSplit.patternSide(width: width, height: column, crystalFraction: 0.5,
                                                              minimumPane: LayoutPolicy.imagePaneMinimum) - 16
        XCTAssertLessThan(halfAndHalf, 430, "before: half the centre less the 8 pt margin each side")
        XCTAssertFalse(try squeezed("EMStudio/UI/DiffractionRoom.swift").contains("} .padding(8) // The pattern's keyboard"), "no fixed margin")
    }
}
