//
//  ExportMethods.swift
//  Role: the methods record (EMSuiteUI's `MethodsRecord`, pin M1) as the app fills it and puts it inside its exports (#817, plan
//        row X1). The record travels inside the file the save panel chose, never beside it: the sandbox grants that one file.
//
//  WHERE IT GOES:
//    - a PNG: one text chunk, keyword `emsuite.methods`, the record's canonical JSON (iTXt when it holds non-ASCII text);
//    - a CSV or an `.ang`: one header line `# methods: <JSON>`, after the file's other `#` lines and before its first data line,
//      so a reader that skips `#` lines (pandas `comment="#"`, orix, numpy) reads the data as before.
//  `record(inPNG:)` and `record(inText:)` read it back.
//
//  WHAT IT HOLDS: the app and the kits it is built with, the source (file name, byte count, fingerprint, shape, the calibrations as
//  the file states them), the lineage's measurements as steps, and what the export draws. Never a path, a user name or a host:
//  the record has no field for one and its writer refuses a text that looks like a path. `withoutFileNames()` is the save panel's
//  "Leave out file names": each source becomes "source 1", "source 2", ... in the record and in the export's own header.
//

import CryptoKit
import FormatoCore
import Foundation
import ImagoCore
import ImagoFFT
import ShellExport

package nonisolated enum ExportMethods {
    /// The PNG text chunk's keyword.
    package static let pngKeyword = "emsuite.methods"
    /// The header line's start in a CSV or an `.ang`.
    package static let textPrefix = "# methods: "
    /// The remembered "Leave out file names" choice of the save panels (UserDefaults).
    package static let leaveOutFileNamesKey = "export.leaveOutFileNames"

    // MARK: - Embedding

    /// `png` with the record's JSON as one more text chunk.
    /// Throws `ExportFile.Failure.encodeFailed` when the record does not read back from what was written (the writer reads its own
    /// output, as the lineage's does).
    package static func embedding(_ record: MethodsRecord, inPNG png: Data) throws -> Data {
        let written = try FormatoPNG.inserting([PNGTextEntry(keyword: pngKeyword, value: record.json())], into: png)
        guard self.record(inPNG: written) == record else { throw ExportFile.Failure.encodeFailed }
        return written
    }

    /// The record a PNG holds, or nil when it holds none (or one this build cannot read).
    package static func record(inPNG png: Data) -> MethodsRecord? {
        guard let entry = (try? FormatoPNG.textEntries(in: png))?.first(where: { $0.keyword == pngKeyword }) else { return nil }
        return try? MethodsRecord.decode(entry.value)
    }

    /// `text` (a CSV or an `.ang`, LF line ends) with the record's line after its leading `#` lines. Throws as the PNG's does.
    package static func embedding(_ record: MethodsRecord, inText text: String) throws -> String {
        let line = try textPrefix + record.json()
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let firstData = lines.firstIndex { !$0.hasPrefix("#") } ?? lines.endIndex
        lines.insert(line, at: firstData)
        let written = lines.joined(separator: "\n")
        guard self.record(inText: written) == record else { throw ExportFile.Failure.encodeFailed }
        return written
    }

    /// The record a CSV or an `.ang` holds, or nil when it holds none.
    package static func record(inText text: String) -> MethodsRecord? {
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("#") else { return nil }
            if line.hasPrefix(textPrefix) { return try? MethodsRecord.decode(String(line.dropFirst(textPrefix.count))) }
        }
        return nil
    }

    // MARK: - Filling

    /// The kits the app is built with, as `Package.resolved` pins them (`SEMReferenceVersions.builtWith`).
    package static var kits: [MethodsRecord.Software] {
        SEMReferenceVersions.builtWith.map { MethodsRecord.Software(name: $0.name, version: $0.value) }
    }

    /// The source as an image export states it: its file name, byte count and pixel fingerprint (the lineage's SHA-256 of the
    /// opened pixels), its shape, and each calibrated axis's sampling as the file states it.
    package static func source(_ source: ExportSource, byteCount: Int, fingerprint: String, kind: String) -> MethodsRecord.Source {
        var calibrations: [FormatoMetadataEntry] = []
        let provenance = FormatoProvenance(file: source.fileName, source: source.object, rule: "as the file states it")
        for (name, axis) in [("x", source.x), ("y", source.y)] {
            guard let axis else { continue }
            calibrations.append(FormatoMetadataEntry(key: "\(name) sampling", value: .number(axis.scale), units: axis.unit,
                                                     provenance: provenance))
        }
        return MethodsRecord.Source(fileName: source.fileName, byteCount: byteCount, fingerprint: fingerprint, kind: kind,
                                    shape: [source.width, source.height], calibrations: calibrations)
    }

    /// The lineage's live measurements as steps, in the order they were recorded: the node's kind and its parameters, and its
    /// results as the record's results, named "<node id> <result>", in the unit the node states.
    package static func steps(from lineage: SessionLineage) -> (steps: [MethodsRecord.Step], results: [MethodsRecord.Quantity]) {
        var steps: [MethodsRecord.Step] = []
        var results: [MethodsRecord.Quantity] = []
        for node in lineage.liveNodes {
            let settings = node.parameters.keys.sorted().map { key in
                MethodsRecord.Quantity(name: key, value: value(node.parameters[key] ?? ""), units: "px")
            }
            steps.append(MethodsRecord.Step(name: "\(node.id) \(node.kind)", method: method(ofKind: node.kind), settings: settings))
            // The scales a mark was measured with are the source's calibrations; the record keeps them there once.
            let skipped: Set<String> = ["unit", "scale_x", "scale_y", "unit_x", "unit_y"]
            for key in node.results.keys.sorted() where !skipped.contains(key) {
                results.append(MethodsRecord.Quantity(name: "\(node.id) \(key)", value: value(node.results[key] ?? ""),
                                                      units: units(ofResult: key, unit: node.results["unit"])))
            }
        }
        return (steps, results)
    }

    /// The Image room's record of one export: the image, its measurements, and what the export draws.
    package static func imageRecord(app: MethodsRecord.Software, exportKind: String, source: MethodsRecord.Source,
                                    lineage: SessionLineage, drawn: [String]) -> MethodsRecord {
        let measured = steps(from: lineage)
        return MethodsRecord(app: app, room: "image", exportKind: exportKind, kits: kits,
                             references: [MethodsRecord.Software(name: "scikit-image", version: "0.26.0")],
                             sources: [source], steps: measured.steps, results: measured.results, drawn: drawn)
    }

    /// What an FFT room export is of, beyond the transform itself.
    package enum FFTProduct: Sendable {
        /// The spectrum as a PNG.
        case transform
        /// The radial profile, its `bins` rows.
        case radialProfile(bins: Int)
        /// The measured spots, `count` rows, with the inverse's mask.
        case spots(count: Int, maskRadius: Double, maskEdge: Double)
    }

    /// The FFT room's record of one export: the transform of the region (numpy's `fft2`, as ImagoKit's parity tests hold it) with its
    /// region and frequency steps, then the radial profile or the spot measurement it was read from.
    package static func fftRecord(app: MethodsRecord.Software, exportKind: String, source: MethodsRecord.Source, header: FFTExportHeader,
                                  product: FFTProduct, drawn: [String]) -> MethodsRecord {
        let numpy = MethodsRecord.Software(name: "numpy", version: "2.5.4")
        var region = [MethodsRecord.Quantity(name: "width", value: .number(Double(header.spectrumWidth)), units: "px"),
                      MethodsRecord.Quantity(name: "height", value: .number(Double(header.spectrumHeight)), units: "px")]
        if let crop = header.crop {
            region += [MethodsRecord.Quantity(name: "left column", value: .number(Double(crop.col)), units: "px"),
                       MethodsRecord.Quantity(name: "top row", value: .number(Double(crop.row)), units: "px")]
        }
        region += [MethodsRecord.Quantity(name: "frequency step x", value: .number(header.spacingX), units: header.unitsX),
                   MethodsRecord.Quantity(name: "frequency step y", value: .number(header.spacingY), units: header.unitsY)]
        var steps = [MethodsRecord.Step(name: header.crop == nil ? "FFT of the whole image" : "FFT of a region",
                                        method: "unnormalised forward 2D FFT of the pixels as read, no window, the mean not removed; |F|² centred",
                                        reference: numpy, settings: region)]
        var results: [MethodsRecord.Quantity] = []
        switch product {
        case .transform:
            break
        case .radialProfile(let bins):
            steps.append(MethodsRecord.Step(name: "Radial profile", method: "mean |F|² over rings of |q|, the DC bin left out",
                                            reference: numpy))
            results.append(MethodsRecord.Quantity(name: "bins", value: .number(Double(bins))))
        case .spots(let count, let maskRadius, let maskEdge):
            steps.append(MethodsRecord.Step(name: "Spot measurement",
                                            method: "centroid of |F|² over the 5 × 5 bins around the largest power near the click, "
                                                + "on a Hann-windowed, mean-removed copy of the region; d = 1/|q|",
                                            reference: numpy,
                                            settings: [MethodsRecord.Quantity(name: "mask radius", value: .number(maskRadius), units: "bins"),
                                                       MethodsRecord.Quantity(name: "mask edge", value: .number(maskEdge), units: "bins")]))
            results.append(MethodsRecord.Quantity(name: "spots", value: .number(Double(count))))
        }
        return MethodsRecord(app: app, room: "fft", exportKind: exportKind, kits: kits, references: [numpy], sources: [source],
                             steps: steps, results: results, drawn: drawn)
    }

    /// The Particles section's record of its CSV: the image, the segmentation's settings (each step scikit-image's, as ImagoKit's
    /// parity tests hold it) and what it found.
    package static func particleRecord(app: MethodsRecord.Software, source: MethodsRecord.Source, settings: ParticleSettings,
                                       thresholdValue: Float, summary: ParticleSummary) -> MethodsRecord {
        let skimage = MethodsRecord.Software(name: "scikit-image", version: "0.26.0")
        var threshold = [MethodsRecord.Quantity(name: "objects", value: .text(settings.polarity.rawValue)),
                         MethodsRecord.Quantity(name: "threshold method", value: .text(settings.method.rawValue))]
        if settings.method == .manual {
            threshold.append(MethodsRecord.Quantity(name: "threshold fraction of the range", value: .number(settings.thresholdFraction)))
        }
        threshold.append(MethodsRecord.Quantity(name: "threshold value", value: .number(Double(thresholdValue))))
        let steps = [
            MethodsRecord.Step(name: "Smoothing", method: "Gaussian filter", reference: skimage,
                               settings: [MethodsRecord.Quantity(name: "sigma", value: .number(settings.sigma), units: "px")]),
            MethodsRecord.Step(name: "Threshold", method: settings.method == .otsu ? "Otsu's level" : "a level on the raw range",
                               reference: skimage, settings: threshold),
            MethodsRecord.Step(name: "Objects", method: "small objects removed, connected components labelled, the objects' moments",
                               reference: skimage,
                               settings: [MethodsRecord.Quantity(name: "minimum area", value: .number(Double(settings.minimumArea)), units: "px"),
                                          MethodsRecord.Quantity(name: "connectivity", value: .number(Double(settings.connectivity.rawValue)))]),
        ]
        let results = [("objects found", summary.total), ("counted", summary.counted), ("touching the edge", summary.edge),
                       ("removed as small", summary.small)]
            .map { MethodsRecord.Quantity(name: $0.0, value: .number(Double($0.1))) }
        return MethodsRecord(app: app, room: "image", exportKind: "particles-csv", kits: kits, references: [skimage], sources: [source],
                             steps: steps, results: results, drawn: [])
    }

    /// The Diffraction room's record of the pattern's readout, in the order a methods section tells it: where the centre came from,
    /// the scale (a ring fit on a standard with the wavelength and camera length it gives, the file's reciprocal axis, or a typed Δq),
    /// what the rings and spots were indexed against, and how many were measured and indexed. Each number to five significant digits,
    /// as a paper states it; the CSV's own header keeps them in full.
    package static func diffractionRecord(app: MethodsRecord.Software, source: MethodsRecord.Source, header h: DiffractionExportHeader,
                                          rows: [DiffractionReadoutRow], exportKind: String = "diffraction-readout-csv") -> MethodsRecord {
        func number(_ name: String, _ value: Double?, _ units: String? = nil) -> MethodsRecord.Quantity? {
            guard let value, value.isFinite else { return nil }
            return MethodsRecord.Quantity(name: name, value: .number(significant(value)), units: units)
        }
        var steps = [MethodsRecord.Step(name: "Centring", method: h.centreSource == "typed" ? "a typed position" : h.centreSource,
                                        settings: [number("centre row", h.centreRow, "px"), number("centre column", h.centreColumn, "px")]
                                            .compactMap { $0 })]
        let scale: String
        if h.calibration.hasPrefix("fit ") {
            scale = "a ring fit to the \(h.calibration.dropFirst(4)) ring of the standard"
        } else if h.calibration == "the file's axis" {
            scale = "the file's reciprocal axis"
        } else if h.calibration == "typed" {
            scale = "a typed scale"
        } else {
            scale = "no scale"
        }
        var calibration = [number("Δq", h.deltaQ, "Å⁻¹ per pixel"), number("wavelength", h.wavelengthAngstroms, "Å")].compactMap { $0 }
        if let mm = number("camera length", h.lengthMM, "mm") {
            calibration.append(mm)
        } else if let px = number("camera length", h.lengthPixels, "px") {
            calibration.append(px)
        }
        steps.append(MethodsRecord.Step(name: "Calibration", method: scale, settings: calibration))
        steps.append(MethodsRecord.Step(name: "Indexing", method: "the listed d-spacings of \(h.crystal) (d = 1/q)",
                                        settings: [number("tolerance", h.tolerancePercent, "%"), number("k_max", h.kMax, "Å⁻¹")]
                                            .compactMap { $0 }))
        var results = [
            ("The number of rings measured", rows.filter { $0.kind == .ring }.count),
            ("The number of spots measured", rows.filter { $0.kind == .spot }.count),
            ("The number indexed", rows.filter { $0.family != nil }.count),
        ].map { MethodsRecord.Quantity(name: $0.0, value: .number(Double($0.1))) }
        if let percent = number("The fitted scale's difference from the stored scale", h.fitVersusFilePercent, "%") {
            results.append(percent)
        }
        return MethodsRecord(app: app, room: "diffraction", exportKind: exportKind, kits: kits, references: [], sources: [source],
                             steps: steps, results: results, drawn: [])
    }

    /// `value` to `digits` significant digits: the numbers a methods paragraph states.
    package static func significant(_ value: Double, digits: Int = 5) -> Double {
        Double(String(format: "%.\(digits)g", value)) ?? value
    }

    /// The EELS room's record of one export, read from the room's method JSON (`EELSCompute.methodJSON`): the thickness map's rule
    /// with its settings and counts, the Deconvolve stage and the edge fit when they ran, each paper the JSON names as a citation.
    package static func eelsRecord(app: MethodsRecord.Software, exportKind: String, source: MethodsRecord.Source, methodJSON: String?,
                                   drawn: [String] = []) -> MethodsRecord {
        let object = methodJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        var steps: [MethodsRecord.Step] = []
        var results: [MethodsRecord.Quantity] = []
        var citations: [MethodsRecord.Citation] = []
        func cite(_ text: Any?) {
            guard let text = text as? String, !text.isEmpty, !citations.contains(where: { $0.text == text }) else { return }
            citations.append(MethodsRecord.Citation(text: text))
        }
        if let method = object["method"] as? String {
            let settingKeys = ["zero_loss", "estimated_tolerance_counts_per_eV", "mean_free_path_nm", "angular_correction"]
            steps.append(MethodsRecord.Step(name: "Thickness t/λ", method: method,
                                            settings: quantities(object.filter { settingKeys.contains($0.key) })))
            results += quantities(object.filter { ["pixels_with_t_over_lambda", "pixels_unavailable"].contains($0.key) })
            cite(object["reference"])
        }
        for (key, name) in [("deconvolution", "Deconvolution"), ("edge_fit", "Edge fit")] {
            guard let stage = object[key] as? [String: Any] else { continue }
            let method = (stage["method"] as? String) ?? (stage["model"] as? String) ?? name.lowercased()
            steps.append(MethodsRecord.Step(name: name, method: method,
                                            settings: quantities(stage.filter { !["method", "model", "reference"].contains($0.key) })))
            cite(stage["reference"])
        }
        return MethodsRecord(app: app, room: "eels", exportKind: exportKind, kits: kits, sources: [source], steps: steps, results: results,
                             drawn: drawn, citations: citations)
    }

    /// A JSON object's plain values as quantities, by key: a number as a number, a boolean as a flag, a text as text, a list of texts
    /// as texts and a list of numbers as one text; a nested object is left out. A number's key states its unit: "_per_eV" counts per
    /// eV, "_eV" eV, "_nm" nm. A text has none ("axis end" where an energy could stand).
    static func quantities(_ object: [String: Any]) -> [MethodsRecord.Quantity] {
        func isFlag(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
        func units(_ key: String) -> String? {
            key.hasSuffix("_per_eV") ? "counts/eV" : key.hasSuffix("_eV") ? "eV" : key.hasSuffix("_nm") ? "nm" : nil
        }
        return object.sorted { $0.key < $1.key }.compactMap { key, value in
            switch value {
            case let number as NSNumber where isFlag(number):
                return MethodsRecord.Quantity(name: key, value: .flag(number.boolValue))
            case let number as NSNumber where number.doubleValue.isFinite:
                return MethodsRecord.Quantity(name: key, value: .number(number.doubleValue), units: units(key))
            case let text as String:
                return MethodsRecord.Quantity(name: key, value: .text(text))
            case let texts as [String]:
                return MethodsRecord.Quantity(name: key, value: .texts(texts))
            case let numbers as [NSNumber] where numbers.allSatisfy({ !isFlag($0) && $0.doubleValue.isFinite }):
                return MethodsRecord.Quantity(name: key, value: .text(numbers.map { "\($0.doubleValue)" }.joined(separator: ", ")),
                                              units: units(key))
            default:
                return nil
            }
        }
    }

    /// An SEM room's record of one export, from the record the session keeps of it (`SEMExportedFile`): each method that made it a
    /// step, with the pinned package its parity tests hold it to, and the room's settings as the export's own step.
    package static func semRecord(_ file: SEMExportedFile, app: MethodsRecord.Software, exportKind: String,
                                  source: MethodsRecord.Source) -> MethodsRecord {
        var references: [MethodsRecord.Software] = []
        var steps: [MethodsRecord.Step] = []
        for method in file.methods {
            // In the order the method names them: the package a port follows first ("pyebsdindex 0.3.10.1 as kikuchipy 0.13.1 drives it").
            let named = method.parityReference
            let pinned = SEMReferenceVersions.pinned
                .compactMap { package in named.range(of: "\(package.name) \(package.version)").map { (package, $0.lowerBound) } }
                .sorted { $0.1 < $1.1 }
                .map { MethodsRecord.Software(name: $0.0.name, version: $0.0.version) }
            for package in pinned where !references.contains(package) { references.append(package) }
            steps.append(MethodsRecord.Step(name: method.title, method: method.sentence, reference: pinned.first))
        }
        if !file.fields.isEmpty {
            steps.append(MethodsRecord.Step(name: file.what, method: "the room's settings when it wrote the file",
                                            settings: file.fields.map { MethodsRecord.Quantity(name: $0.name, value: value($0.value)) }))
        }
        return MethodsRecord(app: app, room: file.room.lowercased(), exportKind: exportKind, kits: kits, references: references,
                             sources: [source], steps: steps, drawn: [file.what])
    }

    /// `data` with the record inside, by the file's extension: a PNG's text chunk, or a CSV's or an `.ang`'s header line. Any other
    /// kind (a method JSON, an Oxford `.ctf`, whose first line must be its own) comes back as it was.
    package static func embedding(_ record: MethodsRecord, inFileWithExtension fileExtension: String, data: Data) throws -> Data {
        switch fileExtension.lowercased() {
        case "png": return try embedding(record, inPNG: data)
        case "csv", "ang":
            guard let text = String(data: data, encoding: .utf8) else { return data }
            return Data(try embedding(record, inText: text).utf8)
        default: return data
        }
    }

    /// The SHA-256 of the file at `url` (64 lowercase hexadecimal digits) and its size, read in 8 MiB blocks. Off the main actor: a
    /// pattern file is gigabytes.
    package static func fingerprint(ofFileAt url: URL) throws -> (sha256: String, byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count = 0
        while let block = try handle.read(upToCount: 8 * 1_024 * 1_024), !block.isEmpty {
            hasher.update(data: block)
            count += block.count
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), count)
    }

    /// The SHA-256 of bytes held in memory, hashed in place: a spectrum image's stored counts when its file cannot be read again.
    /// The build is arm64 only, so the bytes are already little-endian.
    package static func fingerprint(ofBytes bytes: UnsafeRawBufferPointer) -> String {
        var hasher = SHA256()
        hasher.update(bufferPointer: bytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    /// What the lineage's kinds are, in words.
    static func method(ofKind kind: String) -> String {
        switch kind {
        case SessionLineage.Kind.distance: "distance between two points on the image"
        case SessionLineage.Kind.angle: "angle between two lines on the image"
        case SessionLineage.Kind.profile: "line profile, linear interpolation, averaged across its width"
        default: kind
        }
    }

    /// The unit of a lineage result: pixels in px, a length in the unit the node states, an angle in degrees; none for a count or words.
    static func units(ofResult key: String, unit: String?) -> String? {
        switch key {
        case "pixels": "px"
        case "length": unit
        case "degrees": "°"
        default: nil
        }
    }

    /// A lineage string as a number when it is one (the lineage writes numbers as their shortest round-trip text), else as text.
    static func value(_ text: String) -> FormatoValue {
        if let number = Double(text), number.isFinite { return .number(number) }
        return .text(text)
    }
}

extension MethodsRecord {
    /// The record with each source named "source 1", "source 2", ... instead of its file name, in the calibrations' provenance too.
    package func withoutFileNames() -> MethodsRecord {
        var copy = self
        copy.sources = sources.enumerated().map { index, source in
            let name = ExportMethods.anonymousName(index)
            let calibrations = source.calibrations.map { entry in
                FormatoMetadataEntry(key: entry.key, value: entry.value, units: entry.units,
                                     provenance: FormatoProvenance(file: name, source: entry.provenance.source, rule: entry.provenance.rule))
            }
            return MethodsRecord.Source(fileName: name, byteCount: source.byteCount, fingerprint: source.fingerprint, kind: source.kind,
                                        shape: source.shape, calibrations: calibrations)
        }
        return copy
    }
}

extension ExportMethods {
    /// "source 1" for the first source: the name an export uses for a file whose name it leaves out.
    package static func anonymousName(_ index: Int) -> String { "source \(index + 1)" }
}
