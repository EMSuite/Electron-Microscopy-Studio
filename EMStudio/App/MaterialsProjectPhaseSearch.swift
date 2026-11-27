//
//  MaterialsProjectPhaseSearch.swift
//  Role: Find Phases' Materials Project candidates for one window (plan row R14, #813). The elements are typed or taken from the
//        EDS room's quantified elements; each chemical system they span is one search of the keyless OPTIMADE service through the
//        app's one client (`PhaseServices.client`: its pacing, its day of cached searches), and the entries `MaterialsProjectSearch`
//        chooses are downloaded and read by DiffractoKit into candidates the sheet ranks beside My Phases. The sheet and the agent
//        door's find_phases call the same `run`. No key is sent: the open service answers without one.
//
//        ONE SOURCE PER FACT: which entries, the limits and the sentences are `MaterialsProjectSearch`'s (TEMCore); every request,
//        answer and structure is DiffractoKit's (`MaterialsProjectOptimade`).
//

import DiffractoCore
import Foundation
import Observation
import ShellEDXModel
import ShellPhaseLibrary
import TEMCore
import TEMSession

@Observable
final class MaterialsProjectPhaseSearch {
    enum State: Equatable {
        case idle
        case searching([String])
        case done(MaterialsProjectSearch.Summary)
        /// The elements could not be searched (none, not an element, too many), in the sheet's words.
        case refused(String)
        /// The service could not be reached, in the sheet's words.
        case failed(String)
    }

    /// What the elements field holds.
    var elementsText = ""
    private(set) var state: State = .idle
    /// The candidates the last search gave, the most stable of each system first.
    private(set) var candidates: [DiffractionPhaseCandidate] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    var isRunning: Bool { if case .searching = state { true } else { false } }

    /// The quantified elements of the EDS room's spectrum image, in its order; nil when it has none.
    static func edsElements(_ session: EDXSession) -> [String]? {
        guard session.hasImage else { return nil }
        let symbols = session.picks.filter { $0.role == .quantify }.map(\.symbol)
        return symbols.isEmpty ? nil : symbols
    }

    static let noEDSReason = "The EDS room has no quantified elements: open a spectrum image there and pick its elements"

    /// Fills the elements field from the EDS room; false when it has none.
    @discardableResult
    func takeFromEDS(_ session: EDXSession) -> Bool {
        guard let symbols = Self.edsElements(session) else { return false }
        elementsText = symbols.joined(separator: ", ")
        return true
    }

    /// Searches the Materials Project for the field's elements; the answer lands in `state` and `candidates`. A newer search or
    /// Stop drops the one in flight. nil when the elements are refused (said in `state`).
    @discardableResult
    func run(client: MaterialsProjectClient = PhaseServices.client) -> Task<Void, Never>? {
        let elements: [String]
        do {
            elements = try MaterialsProjectSearch.elements(typed: elementsText)
        } catch {
            stop()
            state = .refused(String(describing: error))
            candidates = []
            return nil
        }
        task?.cancel()
        generation += 1
        let gen = generation
        state = .searching(elements)
        candidates = []
        let task = Task { [weak self] in
            let outcome = await Self.search(elements, client: client)
            guard let self, gen == self.generation, !Task.isCancelled else { return }
            self.task = nil
            self.candidates = outcome.candidates
            self.state = outcome.state
        }
        self.task = task
        return task
    }

    func stop() {
        task?.cancel()
        task = nil
        generation += 1
        if isRunning { state = .idle }
    }

    /// The searches and downloads of one run: each system in turn (the client paces them), then the chosen entries.
    static func search(_ elements: [String], client: MaterialsProjectClient) async -> (candidates: [DiffractionPhaseCandidate], state: State) {
        var answers: [MaterialsProjectSearch.SystemAnswer] = []
        var failed: [String] = []
        var firstFailure: String?
        for system in MaterialsProjectSearch.systems(elements) {
            if Task.isCancelled { return ([], .idle) }
            let label = system.joined(separator: "-")
            do {
                let request = try MaterialsProjectOptimade.searchRequest(MaterialsProjectSearch.query(system))
                let data = try await client.search(request, key: nil)
                switch try await decodeSearch(data) {
                case .rows(let rows, _): answers.append(.init(system: system, rows: rows))
                case .noResults: answers.append(.init(system: system, rows: []))
                case .serviceEmpty: failed.append("\(label): the service answered with no structures")
                }
            } catch {
                let why = reason(error)
                firstFailure = firstFailure ?? why
                failed.append("\(label): \(why)")
            }
        }
        if answers.isEmpty, let firstFailure { return ([], .failed(firstFailure)) }
        let summary = MaterialsProjectSearch.Summary(elements: elements, answers: answers, failedSystems: failed)
        var candidates: [DiffractionPhaseCandidate] = []
        var unread: [String: String] = [:]
        for row in MaterialsProjectSearch.chosen(answers) {
            if Task.isCancelled { return ([], .idle) }
            do {
                let data = try await client.download(MaterialsProjectOptimade.entryRequest(materialID: row.materialID), key: nil)
                let structure = try await read(data)
                let name = MaterialsProjectSearch.name(of: row)
                candidates.append(DiffractionPhaseCandidate(crystal: .phase(PhaseCrystal(id: row.materialID, name: name, structure: structure)),
                                                            source: .materialsProject, formula: row.formula))
            } catch {
                unread[row.materialID] = reason(error)
            }
        }
        return (candidates, .done(summary.with(unread: unread)))
    }

    /// The kit reads an entry off the main actor (the symmetry is found from the atoms).
    @concurrent nonisolated static func read(_ data: Data) async throws -> CrystalStructure {
        try MaterialsProjectOptimade.structure(from: MaterialsProjectOptimade.decodeEntry(data)).structure
    }

    /// The kit decodes a search answer off the main actor: since DiffractoKit 0.26.0 it detects each row's space group, up to 500
    /// rows a system, as Add Phase's own decode does (EMSuiteUI#283).
    @concurrent nonisolated static func decodeSearch(_ data: Data) async throws -> MaterialsProjectOptimade.SearchAnswer {
        try MaterialsProjectOptimade.decodeSearch(data)
    }

    /// Why a request gave nothing, in a few words.
    nonisolated static func reason(_ error: any Error) -> String {
        switch error {
        case let failure as MaterialsProjectClient.Failure:
            switch failure {
            case .offline: return "this Mac is offline"
            case .timedOut: return "the Materials Project did not answer in time"
            case .keyRefused: return "the Materials Project refused the request"
            case .busy: return "the Materials Project is busy; search again in a minute"
            case .status(let code): return "the Materials Project answered \(code)"
            case .notHTTP: return "the answer was not from the Materials Project"
            }
        case is CancellationError: return "interrupted by another search"
        case let failure as MaterialsProjectOptimade.AnswerError: return failure.description
        case let failure as MaterialsProjectOptimade.RequestError: return failure.description
        case let failure as MaterialsProjectImport.Failure: return failure.errorDescription ?? "\(failure)"
        default: return "\(error)"
        }
    }

    /// What the sheet and the door say about the candidates: how many from each source.
    func sourcesSentence(myPhases: Int) -> String {
        MaterialsProjectSearch.sourcesSentence(myPhases: myPhases, materialsProject: candidates.count)
    }
}
