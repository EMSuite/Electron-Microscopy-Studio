//
//  DiffractionPartTests.swift
//  The Diffraction workspace's parts in the sidebar (#1044): Calibrate, Index, Simulate, Tilt Plan, Powder, Thickness, each showing a
//  few of the room's sections; a part the document has nothing for listed, dimmed, with its reason; the part a document opens on; the
//  sidebar route round trip; Show Next Room through the parts; the toolbar naming the part; the door reaching each row. Read as data
//  from `DiffractionPart` and on a window's state. Red before: no `DiffractionPart`; the inspector stacked up to fifteen sections and
//  the sidebar listed Diffraction as one room.
//

import Foundation
import ShellAgentDoor
import TEMSession
import XCTest
@testable import macTEM

nonisolated final class DiffractionPartTests: XCTestCase {
    private typealias Facts = DiffractionPart.Facts

    // MARK: Sections

    /// Mutation: a section in the wrong part, Display not closed in Index, Export in Thickness - red.
    func testEachPartListsItsSections() {
        XCTAssertEqual(DiffractionPart.allCases.map(\.title), ["Calibrate", "Index", "Simulate", "Tilt Plan", "Powder", "Thickness"])
        XCTAssertEqual(DiffractionPart.sections(.calibrate, kind: .measured), [.centre, .calibration, .display, .tools, .rings])
        XCTAssertEqual(DiffractionPart.sections(.index, kind: .measured),
                       [.phases, .index, .simulation, .crystalView, .precipitate, .tools, .display])
        XCTAssertEqual(DiffractionPart.sections(.simulate, kind: .simulation).prefix(6),
                       [.simulatedCalibration, .microscope, .phases, .orientation, .simulation, .specimen])
        XCTAssertEqual(DiffractionPart.sections(.tiltPlan, kind: .measured), [.holder])
        XCTAssertEqual(DiffractionPart.sections(.powder, kind: .measured), [.phases, .powder])
        XCTAssertEqual(DiffractionPart.sections(.thickness, kind: .cbed), [.thickness, .display])
        XCTAssertTrue(DiffractionPart.sections(.calibrate, kind: .simulation).isEmpty)
        XCTAssertTrue(DiffractionPart.sections(.simulate, kind: .measured).isEmpty)

        XCTAssertFalse(DiffractionPart.showsExport(.thickness))
        for part in DiffractionPart.allCases where part != .thickness { XCTAssertTrue(DiffractionPart.showsExport(part), part.title) }
        XCTAssertFalse(DiffractionPart.startsClosed(.display, in: .calibrate))
        for part in [DiffractionPart.index, .simulate, .thickness] { XCTAssertTrue(DiffractionPart.startsClosed(.display, in: part)) }

        XCTAssertEqual(DiffractionPart.tableStrip(.calibrate), .readout)
        XCTAssertEqual(DiffractionPart.tableStrip(.index), .spots)
        XCTAssertEqual(DiffractionPart.tableStrip(.thickness), DiffractionPart.TableStrip.none)
        XCTAssertEqual(DiffractionPart.allCases.filter(DiffractionPart.showsCrystalPane), [.index, .simulate])
    }

    /// Regrouping only: every section a document had before (#1043's list) is in one of the parts it can enter. Mutation: a section
    /// dropped from every part - red.
    func testNoSectionIsLost() {
        let facts: [Facts] = [Facts(kind: .measured, isIndexed: true), Facts(kind: .simulation), Facts(kind: .cbed)]
        for fact in facts {
            let reachable = Set(DiffractionPart.allCases.filter { DiffractionPart.unavailableReason($0, facts: fact) == nil }
                .flatMap { DiffractionPart.sections($0, kind: fact.kind) })
            XCTAssertEqual(Set(DiffractionSections.order(fact.kind)).subtracting(reachable), [], "\(fact.kind)")
        }
    }

    // MARK: Availability, opening part, status

    /// Mutation: Calibrate offered for a computed pattern, Simulate for a measured one, Tilt Plan without an orientation, Powder for an
    /// atom model, a reason missing - red.
    func testAvailabilityAndItsReasonsPerDocument() {
        func available(_ facts: Facts) -> [DiffractionPart] {
            DiffractionPart.allCases.filter { DiffractionPart.unavailableReason($0, facts: facts) == nil }
        }
        XCTAssertEqual(available(Facts(kind: .measured)), [.calibrate, .index, .powder, .thickness])
        XCTAssertEqual(available(Facts(kind: .measured, isIndexed: true)), [.calibrate, .index, .tiltPlan, .powder, .thickness])
        XCTAssertEqual(available(Facts(kind: .simulation)), [.simulate, .tiltPlan, .powder, .thickness])
        XCTAssertEqual(available(Facts(kind: .cbed)), [.simulate, .tiltPlan, .powder, .thickness])
        XCTAssertEqual(available(Facts(kind: .simulation, hasPhase: false)), [.simulate, .tiltPlan, .thickness])

        XCTAssertEqual(DiffractionPart.unavailableReason(.calibrate, facts: Facts(kind: .simulation)), DiffractionPart.measuredOnlySentence)
        XCTAssertEqual(DiffractionPart.unavailableReason(.simulate, facts: Facts(kind: .measured)), DiffractionPart.simulationOnlySentence)
        XCTAssertEqual(DiffractionPart.unavailableReason(.tiltPlan, facts: Facts(kind: .measured)), DiffractionPart.noOrientationSentence)
        XCTAssertEqual(DiffractionPart.unavailableReason(.powder, facts: Facts(kind: .cbed, hasPhase: false)), DiffractionPart.noPhaseSentence)
    }

    /// Mutation: a measured pattern opening on Index without a scale, a Simulation document on Calibrate, a CBED pattern on Simulate,
    /// a chosen part kept where it cannot be entered - red.
    func testTheOpeningPartPerDocument() {
        XCTAssertEqual(DiffractionPart.opening(Facts(kind: .measured)), .calibrate)
        XCTAssertEqual(DiffractionPart.opening(Facts(kind: .measured, hasScale: true)), .index)
        XCTAssertEqual(DiffractionPart.opening(Facts(kind: .simulation, hasScale: true)), .simulate)
        XCTAssertEqual(DiffractionPart.opening(Facts(kind: .cbed, hasScale: true)), .thickness)
        XCTAssertEqual(DiffractionPart.shown(chosen: .powder, facts: Facts(kind: .measured)), .powder)
        XCTAssertEqual(DiffractionPart.shown(chosen: .calibrate, facts: Facts(kind: .simulation)), .simulate)
        XCTAssertEqual(DiffractionPart.shown(chosen: nil, facts: Facts(kind: .cbed)), .thickness)
    }

    /// Mutation: a mark with no spoken value, a mark before the fact - red.
    func testTheStatusMarks() {
        XCTAssertNil(DiffractionPart.status(.calibrate, facts: Facts(kind: .measured)))
        XCTAssertEqual(DiffractionPart.status(.calibrate, facts: Facts(kind: .measured, hasScale: true))?.spoken, "Scale known")
        XCTAssertNil(DiffractionPart.status(.index, facts: Facts(kind: .measured, hasScale: true)))
        XCTAssertEqual(DiffractionPart.status(.index, facts: Facts(kind: .measured, isIndexed: true))?.spoken, "Indexed")
        XCTAssertNil(DiffractionPart.status(.powder, facts: Facts(kind: .measured, hasScale: true, isIndexed: true)))
    }

    /// Show Next Room and Show Previous Room step through the parts that can be entered, round from the last to the first.
    func testNextAndPreviousStepThroughTheParts() {
        let measured = Facts(kind: .measured)
        XCTAssertEqual(DiffractionPart.calibrate.neighbour(forward: true, facts: measured), .index)
        XCTAssertEqual(DiffractionPart.index.neighbour(forward: true, facts: measured), .powder, "Simulate and Tilt Plan skipped")
        XCTAssertEqual(DiffractionPart.thickness.neighbour(forward: true, facts: measured), .calibrate)
        XCTAssertEqual(DiffractionPart.calibrate.neighbour(forward: false, facts: measured), .thickness)
        XCTAssertEqual(DiffractionPart.toolbarRoom(.index), "Diffraction · Index")
    }

    // MARK: On a window's state

    /// The sidebar's selection is the part shown; selecting a row shows its part; a part that cannot be entered is not; the menu's
    /// Show Next Room steps to the next part. Mutation: the route not reading the part, a refused part entered - red.
    @MainActor func testTheSidebarRouteRoundTrip() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.openDemo(.lattice)?.value
        try await waitUntil("the image to open", seconds: 30) { state.openItems.selected != nil }
        state.navigation.workspaceArea = .diffraction
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        state.settleDiffractionPart(restored: nil)
        let facts = try XCTUnwrap(state.diffractionPartFacts)
        XCTAssertEqual(facts.kind, .measured)
        XCTAssertEqual(state.diffractionPart, DiffractionPart.opening(facts))
        XCTAssertEqual(state.sidebarRoute.wrappedValue, .diffractionPart(state.diffractionPart))

        state.sidebarRoute.wrappedValue = .diffractionPart(.powder)
        XCTAssertEqual(state.diffractionPart, .powder)
        XCTAssertEqual(state.sidebarRoute.wrappedValue, .diffractionPart(.powder))
        state.sidebarRoute.wrappedValue = .diffractionPart(.simulate)
        XCTAssertEqual(state.diffractionPart, .powder, "a measured pattern has no Simulate")

        XCTAssertTrue(state.canShowNeighbour(forward: true))
        state.showNeighbour(forward: true)
        XCTAssertEqual(state.diffractionPart, .thickness)
        XCTAssertEqual(state.navigation.workspaceArea, .diffraction)
        // A restored part is taken only when none is chosen yet.
        state.settleDiffractionPart(restored: .calibrate)
        XCTAssertEqual(state.diffractionPart, .thickness)
    }

    /// The source draws the parts from the data: the sidebar's rows, the inspector's sections, the toolbar's name.
    func testTheViewsDrawTheParts() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        XCTAssertTrue(try source("macTEM/UI/WorkspaceSidebar.swift").contains("ForEach(DiffractionPart.allCases) { part in"))
        XCTAssertTrue(try source("macTEM/UI/DiffractionRoomInspector.swift").contains("DiffractionPart.sections(part, kind: kind)"))
        XCTAssertTrue(try source("macTEM/UI/ToolbarDisplay.swift").contains("DiffractionPart.toolbarRoom(appState.diffractionPart)"))
    }

    // MARK: The door

    /// Each of the six sidebar rows names a registered tool; get_window says the part. Mutation: a row without a tool - red.
    @MainActor func testTheDoorReachesEachPart() {
        let names = Set(MacTEMAgentDoor.allTools.map(\.name))
        XCTAssertTrue(names.contains("set_diffraction_part"))
        XCTAssertEqual(Set(AgentDoorCoverage.diffractionParts.keys), Set(DiffractionPart.allCases.map(\.identifier)))
        for (row, reach) in AgentDoorCoverage.diffractionParts {
            guard case .tool(let name) = reach else { XCTFail("\(row): reached by a tool"); continue }
            XCTAssertTrue(names.contains(name), "\(row) names \(name)")
        }
        let tool = MacTEMAgentDoor.allTools.first { $0.name == "set_diffraction_part" }
        XCTAssertEqual(tool?.parameters.map(\.name), ["part"])
        XCTAssertEqual(tool?.acts, true)
    }
}
