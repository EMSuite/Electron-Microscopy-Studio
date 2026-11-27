//
//  EELSFigures.swift
//  Role: the EELS room's spectrum as a vector figure (#902, plan row X10): the core loss with its fitted edges marked at their onsets
//        when the file has one, else the low loss, counts against energy loss as one path (ShellExport's `FigurePlot.spectrum`).
//        The maps figure is the shared `EDXFigureContent.vectorScene`.
//

import Foundation
import ShellExport
import TEMCore

nonisolated enum EELSFigures {
    /// The plot's spectrum: the core loss and its edges, or the low loss of a file without one.
    static func spectrum(_ plot: EELSPlotData) -> FigurePlot.Spectrum {
        if let core = plot.core, !core.counts.isEmpty {
            return spectrum(core, markers: plot.edges.map { FigurePlot.Spectrum.Marker(x: $0.onsetEV, label: $0.title) })
        }
        return spectrum(plot.low, markers: [])
    }

    static func spectrum(_ curve: EELSPlotCurve, markers: [FigurePlot.Spectrum.Marker]) -> FigurePlot.Spectrum {
        FigurePlot.Spectrum(x: curve.counts.indices.map { curve.energy($0) }, y: curve.counts, xTitle: "Energy loss (eV)", yTitle: "Counts",
                            markers: markers)
    }
}
