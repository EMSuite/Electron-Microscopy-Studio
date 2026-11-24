//
//  ExportImageOptions.swift
//  Role: the accessory of the Export Image save panel: two
//        checkboxes, Scale bar and Marks, in one row. SwiftUI, hosted by `ExportPanels` (App/), which owns the AppKit
//        panel: the macOS 27 SDK's `fileExporter` and `fileDialog*` modifiers offer no accessory, and the options belong
//        in the save panel, as Preview's export does. Presentation only: what the options start as is
//        `ExportSnapshot`'s (`ExportImageDefaults`), what they become when the panel is confirmed is read from
//        `ExportImageChoices` by the code that presents it.
//
//        Marks is omitted, never dimmed, when the file has none. The hosting view takes its size once, from
//        `fittingSize`, so the panel never changes height after it is up.
//

import ShellExport
import SwiftUI
import TEMCore

/// What the panel's checkboxes are now. Lives as long as the panel does (`ExportPanels` holds it across the await).
@Observable
final class ExportImageChoices {
    var scaleBar: Bool
    var marks: Bool
    /// Whether the panel offers Marks at all: fixed when it opens.
    let offersMarks: Bool
    /// What the second checkbox draws: the Image room's marks, or the FFT room's measured spots.
    let kind: Kind
    /// The FFT transform's "As shown" (#636): offered only when its bins are not square, off by default (one pixel per bin).
    let offersAsShown: Bool
    var asShown = false
    /// "Leave out file names" (#817): offered by the Image room's panel, whose PNG carries a methods record; nil elsewhere.
    var fileNames: ExportFileNameChoice?
    /// Export Figure…'s Format and Width (#822): offered by the Image room's panel only; PNG is the image's own pixels as before,
    /// PDF and SVG a vector figure `width` wide. `formatChanged` lets the panel follow the format with its file type.
    let offersFigure: Bool
    /// Whether a PNG is a figure too, `width` wide at 300 dpi (the Diffraction room's, which has no PNG of its own pixels).
    var pngIsFigure = false
    var format: FigureExport.Format = .png
    var width: FigureStyle.Width = .mm90
    @ObservationIgnored var formatChanged: ((FigureExport.Format) -> Void)?

    enum Kind: Sendable {
        case marks, spots
        /// The Diffraction room's figure (#822): the d of each ring and spot and the hkl of the simulated spots.
        case labels

        var title: String {
            switch self {
            case .marks: "Marks"
            case .spots: "Spots"
            case .labels: "Labels"
            }
        }
        var help: String {
            switch self {
            case .marks: "Draw this file's distances, angles and profiles on the image"
            case .spots: "Draw a ring and the number of each measured spot on the transform"
            case .labels: "Write the d of each ring and spot and the hkl of the simulated spots"
            }
        }
        var identifier: String {
            switch self {
            case .marks: "export.marksToggle"
            case .spots: "export.spotsToggle"
            case .labels: "export.labelsToggle"
            }
        }
    }

    init(scaleBar: Bool, marks: Bool, offersMarks: Bool, kind: Kind = .marks, offersAsShown: Bool = false, offersFigure: Bool = false) {
        self.scaleBar = scaleBar
        self.marks = marks
        self.offersMarks = offersMarks
        self.kind = kind
        self.offersAsShown = offersAsShown
        self.offersFigure = offersFigure
    }

    convenience init(_ defaults: ExportImageDefaults, kind: Kind = .marks, offersAsShown: Bool = false, offersFigure: Bool = false) {
        self.init(scaleBar: defaults.scaleBar, marks: defaults.marks, offersMarks: defaults.offersMarks, kind: kind,
                  offersAsShown: offersAsShown, offersFigure: offersFigure)
    }
}

/// Scale bar, and Marks when the file has some.
struct ExportImageOptions: View {
    @Bindable var choices: ExportImageChoices

    /// Between the two checkboxes, and around them: the accessory is a strip under the panel's name field, and
    /// without padding the checkboxes' focus rings would touch its edge. A panel's own gutter, not a science number.
    private static let spacing: CGFloat = 16
    private static let padding: CGFloat = 8

    /// A journal's column widths, named as journals name them.
    static func widthTitle(_ width: FigureStyle.Width) -> String {
        switch width {
        case .mm90: "One column (90 mm)"
        case .mm140: "1.5 columns (140 mm)"
        case .mm190: "Two columns (190 mm)"
        }
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            if choices.offersFigure {
                Picker("Format", selection: $choices.format) {
                    ForEach(FigureExport.Format.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                .onChange(of: choices.format) { _, format in choices.formatChanged?(format) }
                .help("PDF and SVG keep the scale bar, the marks and their labels as lines and text; PNG is the image's own pixels")
                .accessibilityIdentifier("export.formatPicker")
                // Left out, never dimmed, for PNG: the PNG has the image's own pixels, not a width.
                if choices.format.isVector || choices.pngIsFigure {
                    Picker("Width", selection: $choices.width) {
                        ForEach(FigureStyle.Width.allCases, id: \.self) { Text(Self.widthTitle($0)).tag($0) }
                    }
                    .fixedSize()
                    .help("The figure's width on the page: one column (90 mm), one and a half (140 mm) or two (190 mm)")
                    .accessibilityIdentifier("export.widthPicker")
                }
            }
            Toggle("Scale bar", isOn: $choices.scaleBar)
                .help("Draw the scale bar at the bottom left of the " + (choices.kind == .spots ? "transform" : choices.kind == .labels ? "pattern" : "image"))
                .accessibilityIdentifier("export.scaleBarToggle")
            if choices.offersMarks {
                Toggle(choices.kind.title, isOn: $choices.marks)
                    .help(choices.kind.help)
                    .accessibilityIdentifier(choices.kind.identifier)
            }
            if choices.offersAsShown {
                Toggle("As shown", isOn: $choices.asShown)
                    .help("Resample to the shape the room shows (square pixels in q); off, the PNG has one pixel per bin")
                    .accessibilityIdentifier("export.asShownToggle")
            }
            if let fileNames = choices.fileNames {
                ExportFileNameOption(choice: fileNames)
            }
        }
        .toggleStyle(.checkbox)
        .padding(Self.padding)
        // One group for VoiceOver, so the two checkboxes are read as the panel's drawing options.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(choices.kind == .spots ? "Drawn on the transform" : choices.kind == .labels ? "Drawn on the pattern" : "Drawn on the image")
    }
}
