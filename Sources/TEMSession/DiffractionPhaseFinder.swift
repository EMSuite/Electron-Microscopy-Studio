//
//  DiffractionPhaseFinder.swift
//  Role: Find Phases for one open pattern (plan row R13, #812): which candidate phases explain the room's measured rings (or, with
//        no ring measured, its marked spots), ranked by the kit (`PhaseFinding.rank` over `PhaseFinder`), off the main actor.
//        Fit scale on lets each phase take the scale that suits it within Index's window (3 %); off holds the room's
//        calibration, which tells two phases with nearly equal lattices apart. A newer run, Stop, or a changed pattern drops the
//        answer of the one in flight. Until My Phases (A2) lands, the candidates are the room's standards and the open crystals.
//

import Foundation
import Observation
import ImagoCore
import DiffractoCore
import DiffractoOrientation
import TEMCore

@Observable
package final class DiffractionPhaseFinder {
    /// Each phase takes its own scale (on), or the room's calibration holds (off).
    package var fitScale = true
    /// The last ranking, nil before the first run.
    package private(set) var result: PhaseFindingResult?
    /// Why the last run gave no ranking, in the kit's words.
    package private(set) var refusal: String?
    package private(set) var isRunning = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    package init() {}

    /// What Find Phases reads: the measured rings' q, or with no ring measured the marked spots' (qx, qy) at the beam energy.
    /// nil without a scale, or with nothing measured.
    package static func pattern(analysis: DiffractionAnalysis, image: CalibratedImage) -> PhaseFindingPattern? {
        let rings = analysis.readout(image: image).filter { $0.kind == .ring }.compactMap(\.q)
        if !rings.isEmpty { return .rings(rings) }
        guard let centre = analysis.centre, let calibration = analysis.calibration(for: image), let volts = analysis.volts(for: image)
        else { return nil }
        let spots = analysis.spots.compactMap { s in
            s.row.flatMap { r in s.column.flatMap { c in PatternIndexing.q(row: r, column: c, centre: centre, calibration: calibration) } }
        }
        return spots.isEmpty ? nil : .spots(spots, volts: volts)
    }

    /// What the sheet and the door say for a ranking of a pattern that has since changed.
    package static let staleSentence = "The rings or spots changed since this ranking: rank again."

    /// The last ranking while it is of the room's pattern as it is now; nil before a run or once the pattern changed.
    package func current(analysis: DiffractionAnalysis, image: CalibratedImage) -> PhaseFindingResult? {
        guard let result, result.pattern == Self.pattern(analysis: analysis, image: image) else { return nil }
        return result
    }

    /// Why Find Phases cannot run now, in words; nil when it can.
    package static func blocker(analysis: DiffractionAnalysis, image: CalibratedImage) -> String? {
        if analysis.calibration(for: image) == nil { return "Find Phases needs a scale: calibrate on a standard's ring, or type Δq" }
        if pattern(analysis: analysis, image: image) == nil { return "Fit a ring or mark spots first" }
        return nil
    }

    /// Ranks `candidates` against the room's pattern; the answer lands in `result` or `refusal`.
    @discardableResult
    package func run(analysis: DiffractionAnalysis, image: CalibratedImage, candidates: [PhaseCandidate]) -> Task<Void, Never>? {
        guard let pattern = Self.pattern(analysis: analysis, image: image), !candidates.isEmpty else { return nil }
        task?.cancel()
        generation += 1
        let gen = generation, fit = fitScale
        isRunning = true
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: Result<PhaseFindingResult, PhaseFinderError>
            do throws(PhaseFinderError) {
                outcome = .success(try PhaseFinding.rank(pattern, candidates: candidates, fitScale: fit))
            } catch {
                outcome = .failure(error)
            }
            if Task.isCancelled { return }
            await self?.land(outcome, generation: gen)
        }
        self.task = task
        return task
    }

    package func stop() {
        task?.cancel(); task = nil
        generation += 1
        isRunning = false
    }

    private func land(_ outcome: Result<PhaseFindingResult, PhaseFinderError>, generation gen: Int) {
        guard gen == generation else { return }
        isRunning = false
        task = nil
        switch outcome {
        case .success(let ranked): result = ranked; refusal = nil
        case .failure(let error): result = nil; refusal = String(describing: error)
        }
    }
}
