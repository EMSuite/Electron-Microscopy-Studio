//
//  SimulationHRTEMOptics.swift
//  Role: the HRTEM image's Microscope section and its transfer function strip (#895, plan row MA3; the mockup brief's "Shared:
//        Microscope" rows and section 3). Voltage, the Optics preset (Uncorrected by default), Cs, focal spread and angular spread;
//        the strip plots the kit's transfer function and envelope against spatial frequency and marks the point resolution, the
//        aperture edge and the phase's strongest spacings. Presentation only; the numbers are SimulatoKit's.
//
//        The strip is a pane under the HRTEM image (#921, `ImagePane`), not an inspector section: a chart is a result (control
//        placement §1). It moves with Defocus.
//

import Charts
import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationMicroscopeSection: View {
    let model: SimulationModel
    /// The document's diffraction state: its typed beam energy is the voltage of both its pattern and its image.
    let analysis: DiffractionAnalysis
    /// Called after every change, so the image follows.
    let changed: () -> Void

    var body: some View {
        let optics = model.optics
        InspectorSection("Microscope") {
            InspectorRow("Voltage") {
                OptionalNumericField(title: "Voltage", value: optics.volts / 1000, format: wholeFormat, unit: "kV") { kV in
                    if set({ $0.volts = kV * 1000 }) { analysis.typedBeamKV = kV }
                }
                .help("The beam energy of the document, its pattern's and its image's; a new voltage computes the exit waves again")
                .accessibilityIdentifier("simulation.microscope.voltage")
            }
            InspectorRow("Optics") {
                let current = HRTEMPreset.of(optics)
                Picker("Optics", selection: Binding(get: { current },
                                                    set: { preset in set { $0 = preset.applied(to: $0) } })) {
                    // Custom is the state the fields put the optics in, never a choice: picking it would change nothing.
                    ForEach(HRTEMPreset.allCases.filter { $0 != .custom || current == .custom }, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset).disabled(preset == .custom)
                    }
                }
                .labelsHidden()
                .help("Uncorrected: Cs 1.0 mm, focal spread 5 nm. Cs Corrected: Cs −0.010 mm, focal spread 3 nm. Custom: the fields were changed")
                .accessibilityIdentifier("simulation.microscope.optics")
            }
            InspectorRow("Cₛ") {
                OptionalNumericField(title: "Spherical aberration", value: optics.csMM, format: fineFormat, unit: "mm") { cs in set { $0.csMM = cs } }
                    .help("Spherical aberration, Cₛ")
                    .accessibilityIdentifier("simulation.microscope.cs")
            }
            InspectorRow("Focal spread") {
                OptionalNumericField(title: "Focal spread", value: optics.focalSpreadNM, format: fineFormat, unit: "nm") { spread in
                    set { $0.focalSpreadNM = spread }
                }
                .help("The 1/e half-width of the focal spread (temporal coherence); 0 for none")
                .accessibilityIdentifier("simulation.microscope.focalSpread")
            }
            InspectorRow("Angular spread") {
                OptionalNumericField(title: "Angular spread", value: optics.angularSpreadMrad, format: fineFormat, unit: "mrad") { spread in
                    set { $0.angularSpreadMrad = spread }
                }
                .help("The beam's divergence (spatial coherence); 0 for none, abTEM's default")
                .accessibilityIdentifier("simulation.microscope.angularSpread")
            }
        }
    }

    /// Edits the optics through the model's one validated path; true when the edit was kept (and the image follows).
    @discardableResult
    private func set(_ edit: (inout HRTEMOptics) -> Void) -> Bool {
        guard model.changeOptics(edit) else { return false }
        changed()
        return true
    }
}

/// The transfer function strip under a Simulation document's HRTEM image (#921): the curve of the document's optics at its defocus,
/// with the phase's strongest spacings within reach; the kit's refusal in its words when it draws none. Nothing for another image, or
/// once the document is closed.
struct HRTEMTransferStrip: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    var body: some View {
        if DemoDocuments.isHRTEM(item.url), let simulation = appState.simulationDocument(ofHRTEM: item) {
            let model = simulation.multislice
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                switch Result(catching: { try HRTEMTransferCurve.of(model.optics, defocusNM: model.effectiveDefocusNM) }) {
                case .success(let curve):
                    let reach = curve.frequencies.last ?? 0
                    SimulationTransferChart(curve: curve,
                                            spacings: simulation.diffraction.strongestSpacings().filter { 10 / $0.d <= reach })
                case .failure(let error):
                    InspectorWarning("No transfer function: \(ErrorDetail.text(error))", font: .callout)
                }
            }
        }
    }
}

/// The transfer function chart: it moves with Defocus.
struct SimulationTransferChart: View {
    let curve: HRTEMTransferCurve
    /// The phase's strongest spacings: hkl and d, Å.
    let spacings: [(label: String, d: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Transfer function").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                ForEach(curve.frequencies.indices, id: \.self) { i in
                    LineMark(x: .value("Spatial frequency", curve.frequencies[i]), y: .value("Transfer", curve.transfer[i]),
                             series: .value("Curve", "Transfer"))
                        .foregroundStyle(.blue)
                    if let envelope = curve.envelope {
                        LineMark(x: .value("Spatial frequency", curve.frequencies[i]), y: .value("Transfer", envelope[i]),
                                 series: .value("Curve", "Envelope"))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                if let r = curve.pointResolutionAngstrom {
                    RuleMark(x: .value("Point resolution", 10 / r))
                        .foregroundStyle(.orange)
                        .annotation(position: .top, alignment: .leading) { Text("point resolution \(UnitDisplay.number(r, digits: 3)) Å").font(.caption) }
                }
                if let edge = curve.apertureFrequency {
                    RuleMark(x: .value("Aperture", edge)).foregroundStyle(.red).lineStyle(StrokeStyle(dash: [2, 2]))
                        .annotation(position: .top, alignment: .trailing) { Text("aperture").font(.caption) }
                }
                ForEach(spacings.indices, id: \.self) { i in
                    RuleMark(x: .value("Spacing", 10 / spacings[i].d), yStart: .value("Transfer", -1), yEnd: .value("Transfer", -0.8))
                        .foregroundStyle(.secondary)
                        .annotation(position: .bottom) { Text(spacings[i].label).font(.caption) }
                }
            }
            .chartXAxisLabel("Spatial frequency (1/nm)")
            .chartYScale(domain: -1 ... 1)
            .frame(height: 140)   // science: the transfer function plot
            .accessibilityLabel("Transfer function")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("simulation.hrtem.transfer")
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let r = curve.pointResolutionAngstrom { parts.append("point resolution \(UnitDisplay.number(r, digits: 3)) ångström") }
        if let edge = curve.apertureFrequency { parts.append("aperture at \(UnitDisplay.number(edge, digits: 3)) per nanometre") }
        parts += spacings.map { "\($0.label) at \(UnitDisplay.number($0.d, digits: 3)) ångström" }
        return parts.joined(separator: ", ")
    }
}

private let wholeFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
private let fineFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
