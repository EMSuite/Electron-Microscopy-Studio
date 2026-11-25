//
//  FFTExportSnapshot.swift
//  Role: what the FFT room's three exports take from the selected file when their panel opens: Export Transform… (a PNG), Export Radial Profile… and Export Spots… (CSVs).
//        As `ExportSnapshot` does for the Image room: pure functions from the file's own owners (its image and `FFTAnalysis`)
//        to TEMCore's inputs, the words a panel shows, and when each command is enabled. Sendable values taken once; the
//        render and the write that follow run off the main actor on them. The one hand-over to the writers is each
//        snapshot's `write(to:)`, which the panels only call.
//
//        NOTHING STALE IS EXPORTED: all three need the spectrum on screen to be the one asked for (`isSpectrumCurrent`), and the
//        spots are those measured on THAT spectrum.
//

import ShellMetal
import Foundation
import ShellExport
import TEMCore
import TEMSession
import ImagoCore
import ImagoFFT

// MARK: - Values

/// Which of the three FFT commands is enabled.
nonisolated struct FFTExportAvailability: Sendable, Equatable {
    let transform: Bool
    let profile: Bool
    let spots: Bool
}

/// Everything Export Transform… needs.
nonisolated struct ExportTransformSnapshot: Sendable {
    let header: FFTExportHeader
    let display: ImageExport.Display
    /// One `.spot` mark per measured spot on this spectrum, in list order.
    let marks: [ImageExport.Mark]
    let defaultName: String
    let directory: URL?
    let message: String
    /// Scale bar on, Spots on and offered only when there are some.
    let defaults: ExportImageDefaults
    /// The methods record the PNG carries (#817), its `drawn` set at the write from the options; nil for an image read from no file.
    var methods: MethodsRecord?

    /// Whether the bins are not square in q, so the panel offers "As shown" (#636).
    var offersAsShown: Bool {
        !ExportSnapshot.aspectSentence(width: header.spectrumWidth, height: header.spectrumHeight, spacingX: header.spacingX,
                                       spacingY: header.spacingY).isEmpty
    }

    /// What the panel's OK does: this snapshot's own source, display and spots, to the chosen file; with `asShown`, the picture
    /// resampled to the shape the pane draws (`FFTExport.asShown`), else one pixel per bin.
    nonisolated func write(to url: URL, options: ImageExport.Options, asShown: Bool = false,
                           leaveOutFileNames: Bool = false) async throws -> ImageExport.Rendered {
        let (header, methods) = ExportSnapshot.named(header: header, methods: methods, leaveOutFileNames: leaveOutFileNames)
        let spotsDrawn = options.marks ? marks.count : 0
        var drawn: [String] = ["the transform, log₁₀|F|² in the window shown, grey"]
        if options.scaleBar { drawn.append("a scale bar") }
        if spotsDrawn > 0 { drawn.append("the measured spots") }
        if asShown { drawn.append("resampled to the shape the room shows") }
        var record = methods
        record?.drawn = drawn
        guard asShown else {
            return try await ImageExport.export(source: FFTExport.transformSource(header), display: display, marks: marks, options: options,
                                                provenance: FFTExport.transformProvenance(header, spotsDrawn: spotsDrawn), methods: record,
                                                to: url)
        }
        let shown = FFTExport.asShown(display: display, marks: marks, header: header)
        let bins = shown.header.spectrumWidth == header.spectrumWidth && shown.header.spectrumHeight == header.spectrumHeight
            ? nil : (width: header.spectrumWidth, height: header.spectrumHeight)
        return try await ImageExport.export(source: FFTExport.transformSource(shown.header), display: shown.display, marks: shown.marks,
                                            options: options,
                                            provenance: FFTExport.transformProvenance(shown.header, spotsDrawn: spotsDrawn, resampledFrom: bins),
                                            methods: record, to: url)
    }
}

extension ExportTransformSnapshot {
    /// The transform as a vector figure (#902, plan row X10): the picture at its own bins (or as shown), the spots and their
    /// labels and the reciprocal scale bar as vectors and text, through the Image room's figure (`FigureExport.export`).
    nonisolated func writeFigure(to url: URL, options: ImageExport.Options, asShown: Bool, width: FigureStyle.Width,
                                 format: FigureExport.Format, leaveOutFileNames: Bool = false) async throws
        -> (scene: FigureScene, barLeftOut: Bool) {
        let (header, methods) = ExportSnapshot.named(header: header, methods: methods, leaveOutFileNames: leaveOutFileNames)
        var drawn: [String] = ["the transform, log₁₀|F|² in the window shown, grey", "as a vector figure"]
        if options.scaleBar { drawn.append("a scale bar") }
        if options.marks, !marks.isEmpty { drawn.append("the measured spots") }
        if asShown { drawn.append("resampled to the shape the room shows") }
        var record = methods
        record?.drawn = drawn
        let shown = asShown ? FFTExport.asShown(display: display, marks: marks, header: header) : (display: display, marks: marks, header: header)
        return try await FigureExport.export(source: FFTExport.transformSource(shown.header), display: shown.display, marks: shown.marks,
                                             options: options, width: width, format: format, methods: record, to: url)
    }
}

/// Everything Export Radial Profile… needs.
nonisolated struct ExportRadialProfileSnapshot: Sendable {
    let header: FFTExportHeader
    let profile: RadialProfile
    let defaultName: String
    let directory: URL?
    let message: String
    /// The rows the file will hold (bins with a pixel).
    let bins: Int
    /// The methods record the CSV carries (#817); nil for an image read from no file.
    var methods: MethodsRecord?

    /// `leaveOutFileNames` names the image "source 1" in the CSV's header and in its record (the panel's "Leave out file names").
    nonisolated func write(to url: URL, leaveOutFileNames: Bool = false) async throws {
        let (header, methods) = ExportSnapshot.named(header: header, methods: methods, leaveOutFileNames: leaveOutFileNames)
        try await RadialProfileCSV.export(profile, header: header, methods: methods, to: url)
    }
}

/// Everything Export Spots… needs.
nonisolated struct ExportSpotsSnapshot: Sendable {
    let header: FFTExportHeader
    let rows: [SpotsCSV.Row]
    let omitted: Int
    let maskRadius: Double
    let maskEdge: Double
    let notes: [String]
    let defaultName: String
    let directory: URL?
    let message: String
    /// The methods record the CSV carries (#817); nil for an image read from no file.
    var methods: MethodsRecord?

    /// `leaveOutFileNames` names the image "source 1" in the CSV's header and in its record (the panel's "Leave out file names").
    nonisolated func write(to url: URL, leaveOutFileNames: Bool = false) async throws {
        let (header, methods) = ExportSnapshot.named(header: header, methods: methods, leaveOutFileNames: leaveOutFileNames)
        try await SpotsCSV.export(rows: rows, omitted: omitted, maskRadius: maskRadius, maskEdge: maskEdge, notes: notes,
                                  header: header, methods: methods, to: url)
    }
}

// MARK: - The rules

extension ExportSnapshot {

    /// An FFT export's header and record as written: unchanged, or with the image's file name left out of both ("source 1").
    nonisolated static func named(header: FFTExportHeader, methods: MethodsRecord?, leaveOutFileNames: Bool)
        -> (header: FFTExportHeader, methods: MethodsRecord?) {
        guard leaveOutFileNames else { return (header, methods) }
        var header = header
        header.fileName = ExportMethods.anonymousName(0)
        return (header, methods?.withoutFileNames())
    }

    // MARK: Enabled

    /// The transform, the profile and the spots need an image in the FFT room, no read running and the spectrum on screen
    /// current; the profile also a bin outside the DC, the spots a measured spot on that spectrum. Exhaustive over the rooms on
    /// purpose, as `availability` is.
    static func fftAvailability(hasImage: Bool, area: WorkspaceArea, isLoading: Bool, spectrumIsCurrent: Bool,
                                profileHasBins: Bool, measuredSpots: Int) -> FFTExportAvailability {
        let inExportingRoom: Bool
        switch area {
        case .fft: inExportingRoom = true
        case .image, .diffraction, .results, .edx, .eels, .patterns, .indexing, .maps: inExportingRoom = false
        }
        let ready = hasImage && inExportingRoom && !isLoading && spectrumIsCurrent
        return FFTExportAvailability(transform: ready, profile: ready && profileHasBins, spots: ready && measuredSpots > 0)
    }

    static func fftAvailability(of appState: AppState) -> FFTExportAvailability {
        let analysis = appState.openItems.selected?.fft
        let spectrum = analysis?.isSpectrumCurrent == true ? analysis?.spectrum : nil
        let spots = analysis.flatMap { a in spectrum.map { measuredSpots(on: $0.key, in: a.spots) } } ?? []
        return fftAvailability(hasImage: appState.hasImage, area: appState.navigation.workspaceArea,
                               isLoading: appState.imageSession.isLoading, spectrumIsCurrent: spectrum != nil,
                               profileHasBins: spectrum?.profile.map { !$0.points.isEmpty } ?? false,
                               measuredSpots: spots.count)
    }

    /// The measured spots of `key`'s spectrum, in list order: a spot of another region belongs to a transform no longer shown.
    static func measuredSpots(on key: FFTSpectrumKey, in spots: [FFTSpot]) -> [FFTSpot] {
        spots.filter { $0.spectrumKey == key && $0.measured != nil }
    }

    // MARK: Names and words

    /// "scan-fft", "scan-radial-profile", "scan-spots"; a region adds "-r256x256-x812-y404" (size, then the corner's column and row).
    nonisolated static func fftName(fileName: String, product: String, crop: PixelCrop?) -> String {
        let region = crop.map { "-r\($0.width)x\($0.height)-x\($0.col)-y\($0.row)" } ?? ""
        return "\(stem(of: fileName))-\(product)\(region)"
    }

    nonisolated static func transformMessage(crop: PixelCrop?, imageWidth: Int, imageHeight: Int, width: Int, height: Int,
                                             spacingX: Double, spacingY: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let of = crop == nil ? "the whole image" : FFTRoomFormat.transformed(crop, imageWidth: imageWidth, imageHeight: imageHeight)
        return "Transform of \(of), \(width) × \(height) bins, log₁₀|F|² in the window shown."
            + aspectSentence(width: width, height: height, spacingX: spacingX, spacingY: spacingY, locale: locale)
    }

    /// The PNG, PDF and SVG draw one square pixel per bin (width : height); the room draws the box at width·Δq_x : height·Δq_y. When the two
    /// differ the panel says so, in words (the file is not resampled), the ratios to three significant digits in `locale`. Empty when they agree.
    nonisolated static func aspectSentence(width: Int, height: Int, spacingX: Double, spacingY: Double,
                                           locale: Locale = .autoupdatingCurrent) -> String {
        guard width > 0, height > 0, spacingX > 0, spacingY > 0 else { return "" }
        let file = Double(width) / Double(height)
        let room = (Double(width) * spacingX) / (Double(height) * spacingY)
        guard abs(file - room) > 1e-6 * room else { return "" }
        func ratio(_ r: Double) -> String {
            func g(_ v: Double) -> String { Num.sig(v, 3, locale: locale) }
            return r >= 1 ? "\(g(r)) : 1" : "1 : \(g(1 / r))"
        }
        return " This region is \(width) × \(height) bins: the file has one pixel per bin, so it is \(ratio(file)) where the room shows it \(ratio(room))."
    }

    nonisolated static func radialProfileMessage(bins: Int, reciprocalLabel: String, nativeUnit: String) -> String {
        "\(bins == 1 ? "1 bin" : "\(bins) bins") · |q| in \(reciprocalLabel) and \(nativeUnit) · mean |F|² of the transform, unwindowed"
    }

    nonisolated static func spotsMessage(listed: Int, omitted: Int) -> String {
        let base = listed == 1 ? "1 spot measured" : "\(listed) spots measured"
        return omitted > 0 ? "\(base) · \(omitted) not listed (refused, still measuring or no peak)" : base
    }

    nonisolated static func transformDoneLine(name: String, width: Int, height: Int, spots: Int, barLeftOut: Bool,
                                              asShown: Bool = false) -> String {
        let size = asShown ? "\(width) × \(height) px as shown" : "\(width) × \(height) bins"
        let drawn = spots == 0 ? "" : (spots == 1 ? " (1 spot drawn)" : " (\(spots) spots drawn)")
        return barLeftOut ? "Exported \(name) without the scale bar (the transform is too small) — \(size)\(drawn)"
                          : "Exported \(name) — \(size)\(drawn)"
    }

    nonisolated static func radialProfileDoneLine(name: String, bins: Int) -> String {
        "Exported \(name) — \(bins == 1 ? "1 bin" : "\(bins) bins")"
    }

    nonisolated static func spotsDoneLine(name: String, spots: Int) -> String {
        "Exported \(name) — \(spots == 1 ? "1 spot" : "\(spots) spots")"
    }

    // MARK: From the owners

    /// The header every FFT export names, from the file's image and the spectrum on screen.
    nonisolated static func fftHeader(image: CalibratedImage, spectrum: FFTSpectrumProduct, software: String) -> FFTExportHeader {
        FFTExportHeader(software: software, fileName: image.fileName, object: image.source, imageWidth: image.width,
                        imageHeight: image.height, x: image.x, y: image.y, notes: image.notes, crop: spectrum.key.crop,
                        spectrumWidth: spectrum.width, spectrumHeight: spectrum.height, spacingX: spectrum.spacingX,
                        spacingY: spectrum.spacingY, unitsX: spectrum.unitsX, unitsY: spectrum.unitsY)
    }

    /// The transform through the owner's window as the shader gets it (grey, gamma 1), and one ring per measured spot.
    static func transformSnapshot(image: CalibratedImage, url: URL?, analysis: FFTAnalysis, software: String)
        -> ExportTransformSnapshot? {
        guard analysis.isSpectrumCurrent, let spectrum = analysis.spectrum,
              spectrum.canvas.width == spectrum.width, spectrum.canvas.height == spectrum.height else { return nil }
        let window = FFTSpectrumLayout.window(low: analysis.spectrumWindowLow, high: analysis.spectrumWindowHigh, spectrum: spectrum)
        let canvas = spectrum.canvas
        let display = ImageExport.Display(
            normalized: canvas.normalized, width: canvas.width, height: canvas.height, low: window.low, high: window.high,
            gamma: 1, lut: Colormaps.lutRGBA(.gray), colormap: ColormapKind.gray.rawValue,
            windowLow: analysis.spectrumWindowLow ?? spectrum.defaultWindow?.low,
            windowHigh: analysis.spectrumWindowHigh ?? spectrum.defaultWindow?.high, rawRange: canvas.rawRange)
        let marks: [ImageExport.Mark] = measuredSpots(on: spectrum.key, in: analysis.spots).compactMap { spot in
            guard let m = spot.measured else { return nil }
            return ImageExport.Mark(kind: .spot, points: [ImagePoint(x: m.centroidCol, y: m.centroidRow)], width: 1,
                                    label: "\(spot.number)")
        }
        let crop = spectrum.key.crop
        return ExportTransformSnapshot(
            header: fftHeader(image: image, spectrum: spectrum, software: software), display: display, marks: marks,
            defaultName: fftName(fileName: image.fileName, product: "fft", crop: crop),
            directory: ExportPanels.defaultFolder(for: url),
            message: transformMessage(crop: crop, imageWidth: image.width, imageHeight: image.height, width: spectrum.width,
                                      height: spectrum.height, spacingX: spectrum.spacingX, spacingY: spectrum.spacingY),
            defaults: ExportImageDefaults(scaleBar: true, marks: true, offersMarks: !marks.isEmpty))
    }

    static func radialProfileSnapshot(image: CalibratedImage, url: URL?, analysis: FFTAnalysis, software: String)
        -> ExportRadialProfileSnapshot? {
        guard analysis.isSpectrumCurrent, let spectrum = analysis.spectrum, let profile = spectrum.profile else { return nil }
        let bins = profile.points.count   // the rows of the file and the points of the chart: one rule
        guard bins > 0 else { return nil }
        let shown = FFTUnits.spectrumUnit(profile.units)
        return ExportRadialProfileSnapshot(
            header: fftHeader(image: image, spectrum: spectrum, software: software), profile: profile,
            defaultName: fftName(fileName: image.fileName, product: "radial-profile", crop: spectrum.key.crop),
            directory: ExportPanels.defaultFolder(for: url),
            message: radialProfileMessage(bins: bins, reciprocalLabel: shown.label, nativeUnit: profile.units), bins: bins)
    }

    static func spotsSnapshot(image: CalibratedImage, url: URL?, analysis: FFTAnalysis, software: String) -> ExportSpotsSnapshot? {
        guard analysis.isSpectrumCurrent, let spectrum = analysis.spectrum else { return nil }
        let listed = measuredSpots(on: spectrum.key, in: analysis.spots)
        guard !listed.isEmpty else { return nil }
        let rows = listed.compactMap { spot in spot.measured.map { SpotsCSV.Row(number: spot.number, measured: $0, inMask: spot.inMask) } }
        let omitted = analysis.spots.count - rows.count
        let notes = FFTRoomFormat.accuracyNote(width: spectrum.key.crop?.width ?? image.width, height: spectrum.key.crop?.height ?? image.height,
                                               locale: labelLocale).map { [$0] } ?? []
        return ExportSpotsSnapshot(
            header: fftHeader(image: image, spectrum: spectrum, software: software), rows: rows, omitted: omitted,
            maskRadius: analysis.maskRadius, maskEdge: analysis.maskEdge, notes: notes,
            defaultName: fftName(fileName: image.fileName, product: "spots", crop: spectrum.key.crop),
            directory: ExportPanels.defaultFolder(for: url), message: spotsMessage(listed: rows.count, omitted: omitted))
    }

    /// The window's selected item's: an export is of the file on screen, never of another open one.
    static func transformSnapshot(in openItems: OpenItems, software: String = softwareName()) -> ExportTransformSnapshot? {
        guard let item = openItems.selected, let image = item.session.image,
              var snapshot = transformSnapshot(image: image, url: item.url, analysis: item.fft, software: software) else { return nil }
        snapshot.methods = fftMethods(of: item, image: image, header: snapshot.header, exportKind: "fft-transform-png", product: .transform,
                                      software: software)
        return snapshot
    }

    static func radialProfileSnapshot(in openItems: OpenItems, software: String = softwareName()) -> ExportRadialProfileSnapshot? {
        guard let item = openItems.selected, let image = item.session.image,
              var snapshot = radialProfileSnapshot(image: image, url: item.url, analysis: item.fft, software: software) else { return nil }
        snapshot.methods = fftMethods(of: item, image: image, header: snapshot.header, exportKind: "fft-radial-profile-csv",
                                      product: .radialProfile(bins: snapshot.bins), software: software)
        return snapshot
    }

    static func spotsSnapshot(in openItems: OpenItems, software: String = softwareName()) -> ExportSpotsSnapshot? {
        guard let item = openItems.selected, let image = item.session.image,
              var snapshot = spotsSnapshot(image: image, url: item.url, analysis: item.fft, software: software) else { return nil }
        snapshot.methods = fftMethods(of: item, image: image, header: snapshot.header, exportKind: "fft-spots-csv",
                                      product: .spots(count: snapshot.rows.count, maskRadius: snapshot.maskRadius, maskEdge: snapshot.maskEdge),
                                      software: software)
        return snapshot
    }

    /// The FFT room's record of a file's export (#817): the image by name, size and pixel fingerprint, the transform and what was read
    /// from it. Nil for an item read from no file, as the Image room's.
    static func fftMethods(of item: OpenItem, image: CalibratedImage, header: FFTExportHeader, exportKind: String,
                           product: ExportMethods.FFTProduct, software: String) -> MethodsRecord? {
        guard let identity = item.openedIdentity else { return nil }
        let source = ExportMethods.source(ExportSource(image: image, software: software), byteCount: Int(identity.byteSize),
                                          fingerprint: identity.pixelSHA256, kind: "image")
        return ExportMethods.fftRecord(app: methodsApp(), exportKind: exportKind, source: source, header: header, product: product,
                                       drawn: [])
    }
}
