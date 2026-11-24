//
//  DiffractionHolderSection.swift
//  Role: the Diffraction room's Holder section (plan row R16, #815; mockup brief 6 of the 2.4 design), after Index: α and β now
//        (from the file's stage tilts when it has both, else typed), the limits, the tilt axis (typed, or calibrated from another
//        open indexed pattern of the same crystal), a zone axis near the beam and the sentence for it, and the Tilt List CSV.
//        Presentation only: the numbers are `TiltPlanning`'s over DiffractoKit's holder and zone-axis map. Uncalibrated it says so
//        and shows no α or β for a zone axis. The Map tab (#814) picks the same `selected` zone axis on the crystal pane.
//

import ShellInspector
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession

struct DiffractionHolderSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var document = RoomExportFile(text: "")

    private static let degrees = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    /// The zone axes the picker offers: the nearest ones to the beam.
    private static let offered = 16

    var body: some View {
        let analysis = item.diffraction
        let holder = item.diffractionHolder
        let image = item.session.imageOrBlank
        let settings = holder.settings
        let plan = holder.plan(analysis: analysis, image: image)
        InspectorSection("Holder") {
            InspectorRow("α now") {
                OptionalNumericField(title: "Alpha tilt now", value: settings.alphaDeg, format: Self.degrees, unit: "°") {
                    holder.setTilts(alphaDeg: $0, betaDeg: settings.betaDeg)
                }
                .help("The stage's α tilt when this pattern was recorded")
                .accessibilityIdentifier("diffraction.holder.alpha")
            }
            InspectorRow("β now") {
                OptionalNumericField(title: "Beta tilt now", value: settings.betaDeg, format: Self.degrees, unit: "°") {
                    holder.setTilts(alphaDeg: settings.alphaDeg, betaDeg: $0)
                }
                .help("The stage's β tilt when this pattern was recorded")
                .accessibilityIdentifier("diffraction.holder.beta")
            }
            InspectorNote(settings.source == .file ? "α and β from the file's stage readout." : "α and β typed.")
            InspectorRow("α limit") {
                OptionalNumericField(title: "Alpha limit", value: settings.alphaLimitDeg, format: Self.degrees, unit: "°") {
                    holder.setLimits(alphaDeg: $0, betaDeg: settings.betaLimitDeg)
                }
                .help("How far the holder tilts in α either way (30° by default)")
                .accessibilityIdentifier("diffraction.holder.alphaLimit")
            }
            InspectorRow("β limit") {
                OptionalNumericField(title: "Beta limit", value: settings.betaLimitDeg, format: Self.degrees, unit: "°") {
                    holder.setLimits(alphaDeg: settings.alphaLimitDeg, betaDeg: $0)
                }
                .help("How far the holder tilts in β either way (30° by default)")
                .accessibilityIdentifier("diffraction.holder.betaLimit")
            }
            InspectorRow("Tilt axis") {
                OptionalNumericField(title: "Tilt axis", value: settings.axisAngleDeg, format: Self.degrees, unit: "°",
                                     prompt: "Not calibrated") { holder.setAxis(degrees: $0) }
                    .help("The α axis in the pattern, degrees from down the rows toward along the columns; calibrate it from a second pattern")
                    .accessibilityIdentifier("diffraction.holder.axis")
            }
            InspectorActionRow {
                calibrateMenu(analysis: analysis, holder: holder)
                Button("Forget") { holder.forgetAxis() }
                    .disabled(settings.axisAngleDeg == nil)
                    .help("Forgets the tilt axis; α and β are then not said")
                    .accessibilityIdentifier("diffraction.holder.forget")
            }
            if let refusal = holder.calibrationRefusal { InspectorWarning(refusal) }
            if let plan {
                InspectorNote(plan.calibrationSentence)
                InspectorRow("Zone axis") {
                    Picker("Zone axis", selection: Binding(get: { holder.selected.map(TiltPlanning.zoneText) ?? "" },
                                                           set: { id in holder.selected = plan.rows.first { $0.id == id }?.uvw })) {
                        Text("None").tag("")
                        ForEach(plan.rows.prefix(Self.offered)) { row in
                            Text("\(row.id)  \(String(format: "%.1f°", row.angleFromBeamDeg))").tag(row.id)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .help("A zone axis near the beam, nearest first: its angle from the beam and, with a calibrated axis, the tilts that bring it on")
                    .accessibilityIdentifier("diffraction.holder.zoneAxis")
                }
                if let uvw = holder.selected, let row = plan.row(uvw) { InspectorNote(plan.sentence(for: row)) }
                InspectorActionRow {
                    Button("Export Tilt List CSV…") { export(plan, image: image) }
                        .accessibilityIdentifier("diffraction.holder.export")
                }
            } else {
                InspectorNote("Index the pattern first: the zone axes and the tilts to them are placed from its orientation.")
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText,
                      defaultFilename: DiffractionTiltListExport.baseName(of: image.fileName)) { result in
            if case .failure(let error) = result { appState.present(error) }
        }
    }

    /// The other open patterns indexed on the same crystal, each a calibration partner.
    private func calibrateMenu(analysis: DiffractionAnalysis, holder: DiffractionHolder) -> some View {
        let partners = appState.openItems.items.filter { other in
            other.id != item.id && other.diffraction.indexOutcome?.orientation != nil
                && other.diffraction.crystal.name == analysis.crystal.name
        }
        return Menu("Calibrate from Another Pattern…") {
            ForEach(partners, id: \.id) { other in
                Button(other.session.imageOrBlank.fileName) {
                    holder.calibrate(analysis: analysis, other: other.diffraction, otherHolder: other.diffractionHolder,
                                     otherName: other.session.imageOrBlank.fileName)
                }
            }
        }
        .fixedSize()
        .disabled(partners.isEmpty || analysis.indexOutcome?.orientation == nil)
        .help("Finds the tilt axis from another open pattern of this crystal, indexed, at other stage tilts (10° or more apart is best)")
        .accessibilityIdentifier("diffraction.holder.calibrate")
    }

    private func export(_ plan: TiltPlan, image: CalibratedImage) {
        let text = ExportSnapshot.tiltListCSV(plan, image: image, openItems: appState.openItems)
        if let directory = appState.exportDirectory {
            do {
                let url = try DiffractionTiltListExport.write(text, imageFileName: image.fileName, into: directory)
                appState.statusText = "Exported \(url.lastPathComponent)"
            } catch { appState.present(error) }
        } else {
            document = RoomExportFile(text: text)
            exporting = true
        }
    }
}
