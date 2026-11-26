//
//  DiffractionEventLine.swift
//  Role: the Output line of a Diffraction room result (#1113), as the EBSD rooms write one for every run ("Indexed 4124 of 4125
//        patterns with Hough in 2,4 s"): Calibrate on Ring names the standard's ring, its radius, the scale it set and how far that is
//        from the file's axis; Index names its answer as the pattern's header does. Numbers in the reader's locale (`Num`), the
//        header's own digits. Pure, so a test pins the words.
//

import Foundation
import TEMCore
import TEMSession

nonisolated enum DiffractionEventLine {
    /// The line for `event` on the pattern `fileName`.
    static func line(_ event: DiffractionEvent, fileName: String, locale: Locale = .autoupdatingCurrent) -> String {
        switch event {
        case .calibrated(let standard, let family, let radius, let deltaQ, let versusFile):
            let versus = versusFile.map { ", \(Num.signed($0, 2, locale: locale)) % from the file's axis" } ?? ""
            return "Calibrated \(fileName) on the \(standard) \(family) ring: R \(Num.fixed(radius, 2, locale: locale)) px, "
                + "Δq \(Num.fixed(deltaQ, 5, locale: locale)) Å⁻¹/px" + versus
        case .calibrationRefused(let why):
            return "Calibrate on Ring set no scale on \(fileName): \(why)"
        case .indexed(let outcome, let solutions):
            // Always ending on the count: a line ending in "%" (the misfit) is taken for a progress tick and kept out of Output
            // (EMSuiteUI's `ActivityLog.record`).
            let count = solutions == 1 ? " · 1 solution" : solutions > 1 ? " · \(solutions) solutions" : ""
            return "Index on \(fileName): \(PatternIndexing.header(outcome, locale: locale))" + count
        }
    }
}
