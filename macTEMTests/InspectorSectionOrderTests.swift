//
//  InspectorSectionOrderTests.swift
//  Each document's inspector sections, in control placement §2's order (#1043): Calibration · Display · <the job> · Export for every
//  image, a simulated HRTEM image's job in the order its numbers depend on each other (Microscope before HRTEM, then Thermal
//  Vibrations, then Beside Measured); a computed pattern (a Simulation document's, the CBED pattern derived from it) shows one
//  read-only Calibration and no Centre, and its Tools have no Ring; the HRTEM and STEM method lines are in the Info tab.
//  Red before: no `ImageSections` or `DiffractionSections`; "CBED of Simulation 1" fell through to the measured pattern's Centre and
//  Calibration (a gold standard, a ring fit, a camera); an HRTEM image read Calibration · HRTEM · Thermal Vibrations · Beside Measured ·
//  Microscope · Display, a STEM image Calibration · STEM · Display.
//

import XCTest
import TEMSession
@testable import macTEM

nonisolated final class InspectorSectionOrderTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private let simulation = URL(fileURLWithPath: "/macTEM-demo/Simulation 1")

    func testEachDocumentKnowsItsKind() {
        XCTAssertEqual(ImageSections.kind(of: DemoDocuments.hrtemURL(of: simulation)), .hrtem)
        XCTAssertEqual(ImageSections.kind(of: DemoDocuments.stemURL(of: simulation)), .stem)
        XCTAssertEqual(ImageSections.kind(of: URL(fileURLWithPath: "/data/lattice.dm4")), .measured)
        XCTAssertEqual(ImageSections.kind(of: nil), .measured)
        XCTAssertEqual(DiffractionSections.kind(of: simulation), .simulation)
        XCTAssertEqual(DiffractionSections.kind(of: DemoDocuments.cbedURL(of: simulation)), .cbed)
        XCTAssertEqual(DiffractionSections.kind(of: URL(fileURLWithPath: "/data/Au.dm4")), .measured)
    }

    func testEveryImagePutsDisplaySecondAndTheJobInDependencyOrder() {
        XCTAssertEqual(ImageSections.order(.measured), [.calibration, .stack, .display, .particles, .measure, .lineage])
        XCTAssertEqual(ImageSections.order(.hrtem),
                       [.calibration, .stack, .display, .microscope, .hrtem, .thermalVibrations, .besideMeasured, .particles, .measure, .lineage])
        XCTAssertEqual(ImageSections.order(.stem), [.calibration, .stack, .display, .stem, .particles, .measure, .lineage])
        for kind in [ImageSections.Kind.measured, .hrtem, .stem] {
            XCTAssertEqual(ImageSections.order(kind).first, .calibration)
            XCTAssertEqual(ImageSections.order(kind).filter { $0 != .stack }.dropFirst().first, .display, "Display second in \(kind)")
        }
    }

    func testAComputedPatternShowsNoMeasuredCalibration() {
        let measured = DiffractionSections.order(.measured)
        XCTAssertEqual(Array(measured.prefix(3)), [.centre, .calibration, .display])
        for kind in [DiffractionSections.Kind.simulation, .cbed] {
            let order = DiffractionSections.order(kind)
            XCTAssertEqual(Array(order.prefix(2)), [.simulatedCalibration, .display], "\(kind)")
            XCTAssertFalse(order.contains(.centre) || order.contains(.calibration), "\(kind): no Centre, standard, ring, camera or pitch")
            XCTAssertEqual(DiffractionSections.tools(kind), [.spot, .tilt], "\(kind): no Ring fit")
            XCTAssertTrue(order.contains(.thickness), "\(kind): the thickness measurement")
        }
        XCTAssertTrue(DiffractionSections.order(.simulation).contains(.orientation))
        XCTAssertTrue(DiffractionSections.order(.cbed).contains(.index))
        XCTAssertEqual(DiffractionSections.tools(.measured), [.ring, .spot, .tilt])
    }

    /// The method lines left the HRTEM and STEM sections for the Info tab's Simulation section, with Copy Methods Paragraph.
    func testTheMethodLineIsInTheInfoTab() throws {
        let hrtem = try source("macTEM/UI/SimulationHRTEMSection.swift")
        let stem = try source("macTEM/UI/SimulationSTEMSection.swift")
        XCTAssertFalse(hrtem.contains("HRTEMImage.methodLine("))
        XCTAssertFalse(stem.contains("scan.methodLine("))
        let record = try source("macTEM/UI/SimulationRecordSection.swift")
        XCTAssertTrue(record.contains("HRTEMImage.methodLine(") && record.contains("scan.methodLine("))
        XCTAssertTrue(record.contains("Button(\"Copy Methods Paragraph\")"))
        XCTAssertTrue(try source("macTEM/UI/ImageRoomInspector.swift").contains("SimulationRecordSection(item: item)"))
    }
}
