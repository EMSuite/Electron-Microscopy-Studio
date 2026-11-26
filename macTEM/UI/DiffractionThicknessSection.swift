//
//  DiffractionThicknessSection.swift
//  Role: the Diffraction room's Thickness section (#916, plan row MA15): Measure Thickness on a two-beam CBED pattern, the design's
//        sentence (found, two candidates, poor), the profile across the diffracted disc with the fitted curve and the numbered minima,
//        the method line, and Use in Simulation for a Simulation document or its CBED pattern. The numbers are `CBEDThickness`'s.
//
//        Departure from the design (stated in the PR): the profile sits in this section, not under the pattern, so the pattern
//        pane keeps its one picture and the chart sits beside the sentence that reads it.
//

import Charts
import ShellInspector
import SwiftUI
import TEMCore
import TEMSession

struct DiffractionThicknessSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    private static let chartHeight: CGFloat = 120

    var body: some View {
        let model = item.thickness
        let inputs = item.thicknessInputs
        // Open: it is the Thickness part's one job since #1044 (it sat closed at the foot of fifteen sections before).
        InspectorSection("Thickness") {
            InspectorActionRow {
                Button("Measure Thickness") { Task { await model.measure(inputs) } }
                    .disabled(model.isMeasuring)
                    .help("Fits the two-beam intensity across the diffracted disc (Kelly et al. 1975): tilt so one reflection is strong")
                    .accessibilityIdentifier("diffraction.thickness.measure")
            }
            if model.isMeasuring {
                InspectorNote("Measuring…")
            } else if let outcome = model.outcome, model.isCurrent(try? inputs.get()) || (try? outcome.get()) == nil {
                switch outcome {
                case .failure(let refusal):
                    InspectorWarning(refusal.sentence).accessibilityIdentifier("diffraction.thickness.sentence")
                case .success(let measurement):
                    found(measurement)
                }
            }
        }
    }

    @ViewBuilder
    private func found(_ m: CBEDThickness.Measurement) -> some View {
        if m.verdict == "found" {
            InspectorNote(m.sentence).accessibilityIdentifier("diffraction.thickness.sentence")
        } else {
            InspectorWarning(m.sentence).accessibilityIdentifier("diffraction.thickness.sentence")
            // A poor fit's number, greyed under the warning: seen, never taken as the result.
            if let line = m.unreliableThicknessLine {
                InspectorNote(line).accessibilityIdentifier("diffraction.thickness.unreliable")
            }
        }
        ThicknessProfileChart(measurement: m)
            .frame(height: Self.chartHeight)
        InspectorNote(m.methodLine).accessibilityIdentifier("diffraction.thickness.method")
        if m.thicknessNM != nil, !m.isPoor, let refusal = appState.useInSimulationRefusal(of: item) {
            InspectorNote(refusal).accessibilityIdentifier("diffraction.thickness.useInSimulationRefusal")
        } else if let nm = m.thicknessNM, !m.isPoor, let simulation = appState.thicknessSimulation(of: item) {
            InspectorActionRow {
                Button("Use in Simulation") { simulation.multislice.setThickness(nm: nm) }
                    .help("Sets the Simulation document's specimen thickness to \(UnitDisplay.number(nm, digits: 3)) nm")
                    .accessibilityIdentifier("diffraction.thickness.useInSimulation")
            }
        }
    }
}

/// The measured profile (points), the fitted curve (a line) and the minima the fit predicts, numbered by order.
private struct ThicknessProfileChart: View {
    let measurement: CBEDThickness.Measurement

    private struct Sample: Identifiable {
        let id: Int
        let offset: Double
        let measured: Double
        let fitted: Double
    }

    var body: some View {
        let d = measurement.discs
        let fitted = measurement.fittedCurve
        let samples = d.offsets.indices.map { Sample(id: $0, offset: d.offsets[$0], measured: d.intensities[$0], fitted: fitted[$0]) }
        let minima = measurement.minima.enumerated().map { (id: $0.offset, order: $0.element.order, offset: $0.element.offset) }
        Chart {
            ForEach(samples) { s in
                PointMark(x: .value("Offset", s.offset), y: .value("Intensity", s.measured))
                    .symbolSize(8)
                    .foregroundStyle(.secondary)
            }
            ForEach(samples) { s in
                LineMark(x: .value("Offset", s.offset), y: .value("Intensity", s.fitted))
            }
            ForEach(minima, id: \.id) { m in
                RuleMark(x: .value("Offset", m.offset))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .annotation(position: .top) { Text("\(m.order)").font(.caption2) }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel("px along g from the disc's centre", alignment: .center)
        .accessibilityLabel("Disc profile")
        .accessibilityValue("\(samples.count) samples, \(minima.count) fitted minima; \(measurement.verdict)")
    }
}
