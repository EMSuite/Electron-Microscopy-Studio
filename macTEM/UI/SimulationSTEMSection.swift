//
//  SimulationSTEMSection.swift
//  Role: the STEM section of the Image room for a Simulation document's STEM image (#913, plan row MA10): the probe (semiangle,
//        defocus with Scherzer), the scan step (Nyquist by default), the collection angle, the plan line, Simulate / Stop / Continue
//        with the progress, the detector (BF, ABF, ADF, HAADF or Custom, with Inner and Outer) moved after the run with no new run,
//        the scattered intensity against angle with the band and the probe angle marked, the "not quantitative" chip and the method
//        line. The thermal vibrations are the document's (the HRTEM image's Thermal Vibrations section sets them).
//
//        Departures from the design, stated in the PR: the band is set by its fields and presets, not by dragging handles on the
//        plot (the plot shows it); Source size and the Four Up view are later rows.
//

import Charts
import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationSTEMSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    private let mradFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    private let lengthFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
    private static let chartHeight: CGFloat = 120

    var body: some View {
        if let simulation = appState.simulationDocument(ofSTEM: item) {
            content(simulation)
        } else {
            InspectorSection("STEM") {
                InspectorWarning("Its Simulation document is closed: this image no longer changes.")
            }
        }
    }

    @ViewBuilder
    private func content(_ simulation: OpenItem) -> some View {
        let model = simulation.stem
        let run = appState.stemRun(of: simulation)
        let volts = simulation.diffraction.typedBeamKV.map { $0 * 1000 }
        InspectorSection("STEM") {
            InspectorRow("Semiangle") {
                OptionalNumericField(title: "Convergence semiangle", value: model.settings.semiangleMrad, format: mradFormat, unit: "mrad") { new in
                    model.changeSettings { $0.semiangleMrad = new }
                }
                .help("The probe's convergence semiangle (1 to 60 mrad); 10 for an uncorrected probe, 20 for a corrected one")
                .accessibilityIdentifier("simulation.stem.semiangle")
            }
            InspectorRow("Defocus") {
                OptionalNumericField(title: "Probe defocus", value: volts.flatMap { try? STEMImage.defocusNM(model.settings, csMM: simulation.multislice.optics.csMM, volts: $0) },
                                     format: lengthFormat, unit: "nm") { new in
                    model.changeSettings { $0.defocusNM = new }
                }
                .help("The probe's defocus, positive is underfocus (abTEM's sign); Scherzer for the optics' Cs until one is typed")
                .accessibilityIdentifier("simulation.stem.defocus")
                Button("Scherzer") { model.changeSettings { $0.defocusNM = nil } }
                    .help("Sets the probe's defocus to Scherzer defocus for the optics' Cs")
                    .accessibilityIdentifier("simulation.stem.scherzer")
            }
            InspectorRow("Scan step") {
                OptionalNumericField(title: "Scan step", value: model.settings.scanStepAngstrom
                                        ?? volts.flatMap { try? STEMImage.nyquistStep(semiangleMrad: model.settings.semiangleMrad, volts: $0) },
                                     format: lengthFormat, unit: "Å") { new in
                    model.changeSettings { $0.scanStepAngstrom = new }
                }
                .help("The distance between probe positions; Nyquist for the probe, λ over 4α, until one is typed (0.05 to 2 Å)")
                .accessibilityIdentifier("simulation.stem.scanStep")
            }
            InspectorRow("Collect to") {
                OptionalNumericField(title: "Collect to", value: model.settings.collectMrad, format: mradFormat, unit: "mrad") { new in
                    model.changeSettings { $0.collectMrad = new }
                }
                .help("The largest scattering angle the detector collects, in whole mrad; it sets the sampling (20 to 400 mrad)")
                .accessibilityIdentifier("simulation.stem.collect")
            }
            runRows(simulation, run: run, volts: volts)
            detectorRows(model, simulation: simulation)
            resultRows(model)
        }
    }

    /// The plan, Simulate / Stop, the progress and the failure.
    @ViewBuilder
    private func runRows(_ simulation: OpenItem, run: Result<(key: STEMModel.RunKey, built: SimulationSpecimen.Built, specimen: String), STEMRefusal>,
                         volts: Double?) -> some View {
        let model = simulation.stem
        switch run {
        case .failure(let refusal):
            InspectorWarning(refusal.sentence)
        case .success(let run):
            let configurations = simulation.multislice.thermal?.configurations ?? 1
            switch Result(catching: { try STEMImage.planLine(run.built, settings: model.settings, volts: run.key.volts, configurations: configurations) }) {
            case .success(let line): InspectorNote(line).accessibilityIdentifier("simulation.stem.plan")
            case .failure(let error): InspectorWarning(ErrorDetail.text(error))
            }
            if let wrap = appState.stemWrapSentence(of: simulation) { InspectorWarning(wrap).accessibilityIdentifier("simulation.stem.wrap") }
            if simulation.multislice.thermal == nil {
                InspectorNote("Static lattice: switch on Thermal vibrations in the HRTEM image's section for frozen phonons.")
            }
            if let blocker = model.blocker, !model.isRunning { InspectorWarning(blocker) }
            InspectorActionRow {
                if model.isRunning {
                    Button("Stop") { model.stop() }
                        .help("Stops after the current positions; what is finished stays, and Continue goes on from there")
                        .accessibilityIdentifier("simulation.stem.stop")
                } else {
                    Button(model.holds(run.key) && !(model.scan?.isComplete ?? true) ? "Continue" : "Simulate") {
                        Task { await appState.simulateSTEM(of: simulation) }
                    }
                    .disabled(model.blocker != nil || (model.holds(run.key) && model.scan?.isComplete == true))
                    .help("Scans the probe over one projected unit; the image fills as it is computed")
                    .accessibilityIdentifier("simulation.stem.simulate")
                }
            }
            if model.isRunning {
                if let fraction = model.progress {
                    ProgressView(value: fraction) { Text("Scanning the probe") }
                        .progressViewStyle(.linear).labelsHidden()
                        .accessibilityIdentifier("simulation.stem.progress")
                } else {
                    InspectorNote("Scanning the probe…")
                }
            } else if model.scan != nil, !model.holds(run.key) {
                InspectorNote("The settings changed since this image: Simulate runs them.")
            }
            if let failure = model.failure { InspectorWarning("No STEM image: \(failure)") }
        }
    }

    /// The detector: a preset or Custom, and the band's inner and outer angles; moving them redraws the image with no new run.
    @ViewBuilder
    private func detectorRows(_ model: STEMModel, simulation: OpenItem) -> some View {
        let presets: [(STEMDetector?, SegmentedControl.Segment)] = STEMDetector.allCases.map {
            ($0, .title($0.title, help: helpText($0), disabledReason: model.fits($0) ? nil : "Its band runs past the angles collected"))
        }
        let items = presets + [(nil, .title("Custom", help: "The inner and outer angles typed below"))]
        SegmentedPicker(label: "Detector", items: items,
                        selection: Binding(get: { model.detector }, set: { model.setDetector($0); appState.refreshSTEMImage(of: simulation) }))
            .accessibilityIdentifier("simulation.stem.detector")
        InspectorRow("Inner") {
            OptionalNumericField(title: "Inner angle", value: model.band.inner, format: mradFormat, unit: "mrad") { new in
                model.setBand(STEMBand(inner: new, outer: model.band.outer))
                appState.refreshSTEMImage(of: simulation)
            }
            .help("The band's inner angle, on a whole ring (1 mrad); moved after the run, the image is summed again with no new run")
            .accessibilityIdentifier("simulation.stem.inner")
        }
        InspectorRow("Outer") {
            OptionalNumericField(title: "Outer angle", value: model.band.outer, format: mradFormat, unit: "mrad") { new in
                model.setBand(STEMBand(inner: model.band.inner, outer: new))
                appState.refreshSTEMImage(of: simulation)
            }
            .help("The band's outer angle, on a whole ring, at most the collection angle")
            .accessibilityIdentifier("simulation.stem.outer")
        }
        if let refusal = model.bandRefusal { InspectorWarning(refusal).accessibilityIdentifier("simulation.stem.bandRefusal") }
    }

    private func helpText(_ d: STEMDetector) -> String {
        switch d {
        case .bf: "Bright field: 0 to half the semiangle"
        case .abf: "Annular bright field: half the semiangle to the semiangle"
        case .adf: "Annular dark field: 1.5 to 3 times the semiangle"
        case .haadf: "High-angle annular dark field: 60 to 200 mrad"
        }
    }

    /// The radial plot with the band and the probe angle, the chip and the method line.
    @ViewBuilder
    private func resultRows(_ model: STEMModel) -> some View {
        if let scan = model.scan, !scan.isEmpty {
            let profile = scan.radialProfile()
            STEMRadialChart(angles: profile.angles, intensities: profile.intensities, band: model.band,
                            semiangleMrad: scan.settings.semiangleMrad)
                .frame(height: Self.chartHeight)
            if let chip = scan.notQuantitative(band: model.band) {
                InspectorWarning(chip).accessibilityIdentifier("simulation.stem.notQuantitative")
            }
            InspectorNote(scan.methodLine(band: model.band)).accessibilityIdentifier("simulation.stem.method")
        }
    }
}

/// The scattered intensity against angle (log), mean over the positions done, with the band shaded and the probe angle marked.
private struct STEMRadialChart: View {
    let angles: [Double]
    let intensities: [Double]
    let band: STEMBand
    let semiangleMrad: Double

    private struct Sample: Identifiable {
        let id: Int
        let angle: Double
        let intensity: Double
    }

    var body: some View {
        // Log scale: zero rings (beyond the cutoff, or before the first position) are left out.
        let samples = zip(angles, intensities).enumerated().filter { $0.element.1 > 0 }
            .map { Sample(id: $0.offset, angle: $0.element.0, intensity: $0.element.1) }
        Chart {
            RectangleMark(xStart: .value("Inner", band.inner), xEnd: .value("Outer", band.outer))
                .foregroundStyle(.tint.opacity(0.15))
            ForEach(samples) { s in
                LineMark(x: .value("Angle", s.angle), y: .value("Intensity", s.intensity))
            }
            RuleMark(x: .value("Probe", semiangleMrad))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) { Text("α").font(.caption2) }
        }
        .chartYScale(type: .log)
        .chartXAxisLabel("mrad", alignment: .center)
        .accessibilityLabel("Scattered intensity against angle")
        .accessibilityValue("Band \(UnitDisplay.number(band.inner, digits: 3)) to \(UnitDisplay.number(band.outer, digits: 3)) mrad, "
                            + "probe \(UnitDisplay.number(semiangleMrad, digits: 3)) mrad")
    }
}
