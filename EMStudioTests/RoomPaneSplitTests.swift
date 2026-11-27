//
//  RoomPaneSplitTests.swift
//  Role: every room's pane boundary is the shared split the person drags (#1094): the FFT room's two panes, the Diffraction
//        room's side pane and pattern, the Results room's image table over the SEM session's. Read from the source, as the
//        layout is the code's shape; the drag itself is for the release walk (unverified on screen).
//

import XCTest
@testable import EMStudio

nonisolated final class RoomPaneSplitTests: XCTestCase {

    /// The room's body: from `var body: some View {` in the room's struct to the struct's close, white space squeezed.
    private func body(of room: String, in file: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("EMStudio/UI/\(file)"), encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "struct \(room): View {"), "\(room) is not in \(file)")
        let end = try XCTUnwrap(text.range(of: "\n}\n", range: start.upperBound..<text.endIndex), "\(room) is not closed")
        let declaration = text[start.lowerBound..<end.upperBound]
        let body = try XCTUnwrap(declaration.range(of: "var body: some View {"), "\(room) has no body")
        return declaration[body.lowerBound...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The FFT room's image and transform meet at the shell's centre, not at a fixed `Divider` in an `HStack`. Red under: the
    /// room back to `HStack { source; Divider(); spectrum }`.
    func testTheFFTRoomsPanesMeetAtTheSharedSplit() throws {
        let room = try body(of: "FFTRoom", in: "FFTRoom.swift")
        XCTAssertTrue(room.contains("WorkspaceCentre(storageKey: FFTRoomLayout.centreKey"), "the FFT panes are not the shell's centre")
        XCTAssertFalse(room.contains("Divider()"), "the FFT room draws a fixed divider")
    }

    /// The Diffraction room's centre is the shell's, and its tables are no strip of fixed height under it (they are tabs of the
    /// bottom area the person drags, #1112). Red under: `.frame(height: LayoutPolicy.diffractionReadoutHeight)` on a strip.
    func testTheDiffractionRoomsCentreIsTheSharedSplitWithNoFixedStrip() throws {
        let room = try body(of: "DiffractionRoom", in: "DiffractionRoom.swift")
        XCTAssertTrue(room.contains("WorkspaceCentre(storageKey: DiffractionCrystalSplit.storageKey"), "the Diffraction centre is not the shell's")
        XCTAssertFalse(room.contains("diffractionReadoutHeight"), "a Diffraction strip has a fixed height")
        XCTAssertFalse(room.contains("Divider()"), "the Diffraction room draws a fixed divider")
    }

    /// The Results room's image table and the SEM session's meet at the shared vertical split, remembered under its own key;
    /// the one fixed divider left is the header's rule. Red under: the session pane stacked under a `Divider()` again.
    func testTheResultsRoomsSectionsMeetAtTheSharedSplit() throws {
        let room = try body(of: "ResultsRoom", in: "ResultsRoom.swift")
        XCTAssertTrue(room.contains("VerticalPaneSplit(storageKey: ResultsRoomLayout.sessionSplitKey"), "the Results sections do not split")
        let split = try XCTUnwrap(room.range(of: "VerticalPaneSplit("))
        XCTAssertTrue(room[split.upperBound...].contains("} bottom: { ResultsSessionPane("), "the session's table is not the split's lower pane")
        XCTAssertEqual(room.components(separatedBy: "Divider()").count - 1, 1, "the Results room draws a fixed divider between its sections")
        XCTAssertEqual(ResultsRoomLayout.sessionSplitKey, "results.sessionSplit")
    }
}
