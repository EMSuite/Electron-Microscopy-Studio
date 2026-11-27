//
//  DiffractionPowderExport.swift
//  Role: the Powder section's two files (#811): the peak table as CSV with its methods record inside (#817's rule), and one phase's
//        drawn profile as .xy, two columns of numbers and nothing else. Written into the launch's `--export-dir` when there is one
//        (a UI journey cannot drive the panel), else handed to the section's exporter.
//

import Foundation
import ImagoCore
import TEMCore
import TEMSession
import UniformTypeIdentifiers

nonisolated enum DiffractionPowderExport {
    /// The .xy profile's type: plain text named .xy, so the save panel keeps the extension instead of adding .txt.
    static let xyType = UTType(filenameExtension: "xy", conformingTo: .plainText) ?? .plainText

    /// "<image> powder" for the CSV, "<image> powder <phase>" for a profile.
    static func baseName(of imageFileName: String, phase: String? = nil) -> String {
        let base = (imageFileName as NSString).deletingPathExtension + " powder"
        return phase.map { base + " " + $0.replacingOccurrences(of: "/", with: "-") } ?? base
    }

    static func write(_ text: String, named name: String, into directory: URL) throws -> URL {
        try ExportDirectoryFile.write(text, named: name, into: directory)
    }
}

extension ExportSnapshot {
    /// The powder CSV with its methods record inside.
    static func powderCSV(_ table: PowderTable, image: CalibratedImage, openItems: OpenItems) -> String {
        embeddingMethods(in: table.csv(), of: image, openItems: openItems) {
            ExportMethods.powderRecord(app: $0, source: $1, table: table)
        }
    }
}
