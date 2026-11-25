//
//  DiffractionTiltListExport.swift
//  Role: the Holder section's Tilt List CSV (#815): the plan's CSV with its methods record inside (#817's rule), written into the
//        launch's `--export-dir` when there is one (a UI journey cannot drive the panel), else handed to the section's exporter.
//

import Foundation
import ImagoCore
import TEMCore
import TEMSession

nonisolated enum DiffractionTiltListExport {
    static func baseName(of imageFileName: String) -> String { (imageFileName as NSString).deletingPathExtension + " tilt list" }

    static func write(_ text: String, imageFileName: String, into directory: URL) throws -> URL {
        try ExportDirectoryFile.write(text, named: baseName(of: imageFileName) + ".csv", into: directory)
    }
}

extension ExportSnapshot {
    /// The tilt list CSV with its methods record inside.
    static func tiltListCSV(_ plan: TiltPlan, image: CalibratedImage, openItems: OpenItems) -> String {
        embeddingMethods(in: plan.csv(), of: image, openItems: openItems) {
            ExportMethods.tiltListRecord(app: $0, source: $1, plan: plan)
        }
    }
}
