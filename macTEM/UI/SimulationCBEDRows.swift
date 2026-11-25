//
//  SimulationCBEDRows.swift
//  Role: Parallel | Convergent in a Simulation document's Simulation section (#912, plan row MA9). Convergent shows the CBED
//        settings: the convergence semiangle with Fit Discs (the largest that keeps the discs apart), the largest thickness, the
//        angular step (it sets the box, which the plan names), the pattern's edge; Show CBED Pattern opens the pattern as its own item
//        in the Diffraction room and runs the probe (Stop ends it); the thickness slider steps through the stored patterns. The
//        overlap sentence, the small-box chip and the beyond-the-validated-depth chip are the design's. Presentation only: the state
//        is `CBEDModel`, every number SimulatoKit's.
//

import ShellControls
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct SimulationCBEDRows: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    private let mradFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
    private let nmFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    var body: some View {
        let model = item.cbed
        let analysis = item.diffraction
        let volts = analysis.typedBeamKV.map { $0 * 1000 }
        let shortestG = appState.cbedShortestG(of: item)
        let separated = volts.flatMap { v in shortestG.flatMap { try? CBEDRun.separatedSemiangle(shortestG: $0, volts: v) } }
        let semiangle = volts.flatMap { model.semiangle(shortestG: shortestG, volts: $0) }
        SegmentedPicker(label: "Beam",
                        items: [(false, .title("Parallel", help: "A plane wave: the spots")),
                                (true, .title("Convergent", help: "A probe: the discs of convergent-beam diffraction (CBED), as a run"))],
                        selection: Binding(get: { model.isConvergent }, set: { model.setConvergent($0) }))
            .accessibilityIdentifier("diffraction.simulation.beam")
        if model.isConvergent {
            InspectorRow("Semiangle") {
                OptionalNumericField(title: "Convergence semiangle", value: semiangle, format: mradFormat, unit: "mrad") { new in
                    model.changeSettings { $0.semiangleMrad = new }
                }
                .help("The probe's convergence semiangle; Fit Discs sets the largest that keeps the discs apart"
                      + (separated.map { " (\(UnitDisplay.number($0, digits: 3)) mrad here)" } ?? ""))
                .accessibilityIdentifier("diffraction.simulation.cbed.semiangle")
            }
            InspectorActionRow {
                Button("Fit Discs") { model.fitDiscs() }
                    .disabled(item.multislice.atomModel != nil)
                    .help("Sets the semiangle to half the angle of the shortest reflection of the zone: the discs just touch")
                    .accessibilityIdentifier("diffraction.simulation.cbed.fitDiscs")
            }
            if item.multislice.atomModel != nil { InspectorNote(SimulationModel.modelFitDiscsSentence) }
            if let semiangle, let separated, let sentence = CBEDRun.overlapSentence(semiangleMrad: semiangle, separatedMrad: separated) {
                InspectorNote(sentence)
            }
            InspectorRow("Largest thickness") {
                OptionalNumericField(title: "Largest thickness", value: model.settings.largestThicknessNM, format: nmFormat, unit: "nm") { new in
                    model.changeSettings { $0.largestThicknessNM = new }
                }
                .help("One run stores a pattern about every \(UnitDisplay.number(model.settings.thicknessStepNM, digits: 3)) nm to this thickness (fewer when they would pass the memory kept for them; the plan names how many)")
                .accessibilityIdentifier("diffraction.simulation.cbed.largestThickness")
            }
            InspectorRow("Angular step") {
                OptionalNumericField(title: "Angular step", value: model.settings.angularStepMrad, format: mradFormat, unit: "mrad/px") { new in
                    model.changeSettings { $0.angularStepMrad = new }
                }
                .help("The pattern's angle per pixel; it sets the box across (λ over the step: 100 Å for 0.25 mrad at 200 kV)")
                .accessibilityIdentifier("diffraction.simulation.cbed.angularStep")
            }
            InspectorRow("Pattern edge") {
                OptionalNumericField(title: "Pattern edge", value: model.settings.edgeMrad, format: mradFormat, unit: "mrad") { new in
                    model.changeSettings { $0.edgeMrad = new }
                }
                .help("The largest angle the pattern shows; it sets the sampling, so it must hold the probe and the first ring (20 to 400 mrad)")
                .accessibilityIdentifier("diffraction.simulation.cbed.edge")
            }
            let blocker = appState.cbedBlocker(of: item)
            planRows()
            if let blocker, !model.isComputing { InspectorWarning(blocker) }
            InspectorActionRow {
                if model.isComputing {
                    Button("Stop") { model.stop() }
                        .help("Stops the run; the patterns already stored stay")
                        .accessibilityIdentifier("diffraction.simulation.cbed.stop")
                } else {
                    Button("Show CBED Pattern") { appState.showCBEDPattern(of: item) }
                        .disabled(blocker != nil)
                        .help("Opens the pattern in the Diffraction room and runs the probe through the slab")
                        .accessibilityIdentifier("diffraction.simulation.cbed.show")
                }
            }
            if model.isComputing {
                if let fraction = model.progress {
                    ProgressView(value: fraction) { Text("Computing the CBED patterns") }
                        .progressViewStyle(.linear).labelsHidden()
                        .accessibilityIdentifier("diffraction.simulation.cbed.progress")
                } else {
                    InspectorNote("Computing the CBED patterns…")
                }
            }
            if let failure = model.failure { InspectorWarning("No CBED pattern: \(failure)") }
            storedRows(model)
        }
    }

    /// The plan before a run: the box the angular step needs, and the small-box chip.
    @ViewBuilder
    private func planRows() -> some View {
        if let plan = appState.cbedPlan(of: item) {
            InspectorNote(plan.sentence).accessibilityIdentifier("diffraction.simulation.cbed.plan")
            if let small = plan.smallBoxSentence { InspectorWarning(small) }
        }
    }

    /// The stored patterns: the thickness slider, the chip past the registered depth and the method line.
    @ViewBuilder
    private func storedRows(_ model: CBEDModel) -> some View {
        if let pattern = model.pattern, let index = model.shownIndex {
            InspectorRow("CBED thickness") {
                Text("\(UnitDisplay.number(pattern.thicknessesNM[index], digits: 3)) nm").monospacedDigit()
                    .accessibilityIdentifier("diffraction.simulation.cbed.thicknessValue")
            }
            if pattern.patterns.count > 1 {
                Slider(value: Binding(get: { Double(index) }, set: {
                    model.setThicknessIndex(Int($0.rounded()))
                    appState.refreshCBEDPattern(of: item)
                }), in: 0 ... Double(pattern.patterns.count - 1), step: 1) {
                    Text("CBED thickness")
                }
                .labelsHidden()
                .help("Steps through the patterns stored about every \(UnitDisplay.number(model.settings.thicknessStepNM, digits: 3)) nm")
                .accessibilityValue("\(UnitDisplay.number(pattern.thicknessesNM[index], digits: 3)) nanometres, "
                                    + "\(index + 1) of \(pattern.patterns.count) stored thicknesses")
                .accessibilityIdentifier("diffraction.simulation.cbed.thickness")
            }
            if let chip = pattern.depthChip {
                InspectorWarning(chip)
                    .accessibilityIdentifier("diffraction.simulation.cbed.depthChip")
            }
            InspectorNote(pattern.methodLine(at: index)).accessibilityIdentifier("diffraction.simulation.cbed.method")
        }
    }
}
