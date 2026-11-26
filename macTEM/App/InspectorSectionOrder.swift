//
//  InspectorSectionOrder.swift
//  Role: which inspector sections a document's room shows, in which order (#1043, control placement §2: image rooms read
//        `Calibration · Display · <the room's job, one section per stage> · Export`). Pure, so a test pins the list per document kind;
//        `ImageRoomSettings` and `DiffractionRoomSettings` draw their sections from it.
//
//        A computed document has no camera and no measured centre: a Simulation document's pattern and the CBED pattern derived from
//        it show one read-only Calibration section (the scale and where it comes from), never Centre, a standard, a ring fit, a camera
//        or a pixel pitch, and their Tools offer Spot and Tilt, not the Ring fit. A simulated HRTEM or STEM image puts Display second,
//        as a measured image does, then its job in the order the numbers depend on each other: Microscope (voltage, optics) before
//        HRTEM (defocus, thickness), then Thermal Vibrations, then Beside Measured.
//

import Foundation
import TEMSession

/// The Image room's sections per document.
nonisolated enum ImageSections {
    enum Kind: Sendable { case measured, hrtem, stem }

    enum Section: String, CaseIterable, Sendable {
        case calibration, stack, display, microscope, hrtem, thermalVibrations, besideMeasured, stem, particles, measure, lineage
    }

    /// The kind of the document at `url`: a Simulation document's HRTEM or STEM image, or any other image.
    static func kind(of url: URL?) -> Kind {
        guard let url else { return .measured }
        if DemoDocuments.isHRTEM(url) { return .hrtem }
        if DemoDocuments.isSTEM(url) { return .stem }
        return .measured
    }

    /// The sections in their order. The frame of an image stack sits with what is looked at, before Display.
    static func order(_ kind: Kind) -> [Section] {
        let job: [Section] = switch kind {
        case .measured: []
        case .hrtem: [.microscope, .hrtem, .thermalVibrations, .besideMeasured]
        case .stem: [.stem]
        }
        return [.calibration, .stack, .display] + job + [.particles, .measure, .lineage]
    }
}

/// The Diffraction room's sections per document, Export last (drawn after them).
nonisolated enum DiffractionSections {
    enum Kind: Sendable { case measured, simulation, cbed }

    enum Section: String, CaseIterable, Sendable {
        case centre, calibration, simulatedCalibration, display, tools, microscope, phases, index, orientation, holder, simulation,
             specimen, crystalView, precipitate, powder, rings, thickness
    }

    /// The kind of the document at `url`: a Simulation document, the CBED pattern derived from one, or a measured pattern.
    static func kind(of url: URL) -> Kind {
        if DemoDocuments.isSimulation(url) { return .simulation }
        if DemoDocuments.isCBED(url) { return .cbed }
        return .measured
    }

    /// A computed pattern: its scale is the simulation's, exact, and no camera recorded it.
    static func isComputed(_ kind: Kind) -> Bool { kind != .measured }

    /// The sections in their order. A measured pattern's Centre feeds its Calibration, so it comes first; a Simulation document's
    /// Microscope (voltage, camera length) leads its job and its Orientation stands where Index does.
    static func order(_ kind: Kind) -> [Section] {
        switch kind {
        case .measured:
            [.centre, .calibration, .display, .tools, .phases, .index, .holder, .simulation, .crystalView, .precipitate, .powder, .rings,
             .thickness]
        case .simulation:
            [.simulatedCalibration, .display, .tools, .microscope, .phases, .orientation, .holder, .simulation, .specimen, .crystalView,
             .precipitate, .powder, .rings, .thickness]
        case .cbed:
            [.simulatedCalibration, .display, .tools, .phases, .index, .holder, .simulation, .crystalView, .precipitate, .powder, .rings,
             .thickness]
        }
    }

    /// Whether the pattern's rings are fitted (the Ring tool, the annulus, Fit Ring): a computed pattern's scale is the simulation's,
    /// exact, so it has no ring to fit.
    static func fitsRings(_ kind: Kind) -> Bool { !isComputed(kind) }

    /// The tools a pointer has on the pattern: a computed pattern has no ring to fit.
    static func tools(_ kind: Kind) -> [DiffractionViewState.Tool] {
        fitsRings(kind) ? [.ring, .spot, .tilt] : [.spot, .tilt]
    }
}
