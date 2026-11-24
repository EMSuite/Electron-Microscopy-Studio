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

import FormatoCore
import Foundation
import ImagoCore
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
