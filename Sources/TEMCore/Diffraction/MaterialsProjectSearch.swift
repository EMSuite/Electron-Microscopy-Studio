//
//  MaterialsProjectSearch.swift
//  Role: which Materials Project entries Find Phases ranks (plan row R14, #813), and the sentences that say so. The elements come
//        from the EDS room's quantified elements or are typed; every chemical system they span (each non-empty subset: Al, Mg and
//        Al-Mg for Al and Mg) is one keyless OPTIMADE search (DiffractoKit's `MaterialsProjectOptimade`, exact systems through
//        `only`), and of each answer the most stable entries near the hull are taken, within a total cap. Pure: the app sends the
//        requests through its one client and hands the answers back here.
//
//        Limits, named in the sheet so the person knows what was left out: at most four elements (15 systems), the three most
//        stable entries per system, within 0.1 eV/atom of the hull, 20 candidates in all. Materials Project holds calculated,
//        mostly stable phases; a metastable precipitate is usually not in it (`PhaseFindingResult.materialsProjectNote`).
//

import Foundation
import DiffractoCore

package nonisolated enum MaterialsProjectSearch {
    /// The most elements one search spans: 2⁴ − 1 = 15 chemical systems, one request each.
    package static let maximumElements = 4
    /// The most stable entries taken per chemical system.
    package static let perSystem = 3
    /// Entries further above the hull than this (eV/atom) are left out.
    package static let hullLimit = 0.1
    /// The most Materials Project candidates in one ranking.
    package static let maximumCandidates = 20

    /// The element symbols in `text` ("Al, Cu Mg", "al cu", "AlCuMg"), checked, without repeats, in order of atomic number.
    /// Throws the first word that is no element symbol.
    package static func elements(typed text: String) throws(Refusal) -> [String] {
        var symbols: [String] = []
        for token in text.split(whereSeparator: { !$0.isLetter }) {
            if token.allSatisfy(\.isLowercase) {
                symbols.append(token.prefix(1).uppercased() + token.dropFirst())
                continue
            }
            var current = ""
            for ch in token {
                if ch.isUppercase, !current.isEmpty { symbols.append(current); current = "" }
                current.append(ch)
            }
            if !current.isEmpty { symbols.append(current) }
        }
        return try checked(symbols)
    }

    /// The symbols checked against the periodic table, without repeats, in order of atomic number.
    package static func checked(_ symbols: [String]) throws(Refusal) -> [String] {
        var out: [String] = []
        for symbol in symbols {
            guard let z = Element.atomicNumber(forSymbol: symbol), z > 0, Element.symbol(forAtomicNumber: z) == symbol else {
                throw .notAnElement(symbol)
            }
            if !out.contains(symbol) { out.append(symbol) }
        }
        guard !out.isEmpty else { throw .noElements }
        guard out.count <= maximumElements else { throw .tooManyElements(out) }
        return out.sorted { (Element.atomicNumber(forSymbol: $0) ?? 0) < (Element.atomicNumber(forSymbol: $1) ?? 0) }
    }

    /// Why a search cannot run, in the sheet's words.
    package nonisolated enum Refusal: Error, Equatable, Sendable, CustomStringConvertible {
        case noElements
        case notAnElement(String)
        case tooManyElements([String])

        package var description: String {
            switch self {
            case .noElements: "Name the elements to search for, such as Al, Cu, Mg, or take them from EDS."
            case .notAnElement(let word): "\"\(word)\" is not an element symbol."
            case .tooManyElements(let symbols):
                "Find Phases searches at most \(MaterialsProjectSearch.maximumElements) elements; \(symbols.joined(separator: ", ")) are "
                    + "\(symbols.count). Leave out the ones that are not in the phases you look for (a support film's C, a surface's O)."
            }
        }
    }

    /// Every chemical system the elements span, smallest first, each in the elements' order: [Al], [Mg], [Mg, Al] for Mg, Al.
    package static func systems(_ elements: [String]) -> [[String]] {
        let n = elements.count
        guard n > 0 else { return [] }
        let subsets = (1..<(1 << n)).map { mask in elements.indices.filter { mask & (1 << $0) != 0 }.map { elements[$0] } }
        return subsets.enumerated().sorted { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }.map(\.element)
    }

    /// The OPTIMADE query of one system: entries with exactly these elements.
    package static func query(_ system: [String]) -> MaterialsProjectOptimade.Query { .elements(system, only: true) }

    /// What one system's search gave.
    package nonisolated struct SystemAnswer: Sendable, Equatable {
        // periphery:ignore - read by the synthesized ==
        package let system: [String]
        /// The entries the service holds for the system, the most stable first (the kit's order); empty when none.
        package let rows: [MaterialsProjectOptimade.Row]
        package init(system: [String], rows: [MaterialsProjectOptimade.Row]) { self.system = system; self.rows = rows }
    }

    /// The entries to download, in the systems' order: of each system the `perSystem` most stable within `hullLimit`, then at most
    /// `maximumCandidates` in all. An entry the service states no stability for is left out (it cannot be placed against the hull).
    package static func chosen(_ answers: [SystemAnswer]) -> [MaterialsProjectOptimade.Row] {
        var out: [MaterialsProjectOptimade.Row] = []
        for answer in answers {
            let near = answer.rows.filter { ($0.lowestEnergyAboveHull ?? .infinity) <= hullLimit + 1e-12 }
            for row in near.prefix(perSystem) where !out.contains(where: { $0.materialID == row.materialID }) { out.append(row) }
        }
        return Array(out.prefix(maximumCandidates))
    }

    /// The name a candidate goes by in the table: its formula and its id, "Al2Cu (mp-985806)".
    package static func name(of row: MaterialsProjectOptimade.Row) -> String {
        "\(row.formula ?? row.materialID) (\(row.materialID))"
    }

    /// What one search did, for the sheet's sentences and the agent door.
    package nonisolated struct Summary: Sendable, Equatable {
        package let elements: [String]
        package let systems: Int
        /// Entries the service holds across the systems.
        package let found: Int
        /// Entries within the hull limit across the systems.
        package let nearHull: Int
        /// Entries taken for ranking (before downloads).
        package let taken: Int
        /// Entries taken whose structure could not be downloaded or read, by id, with why.
        package let unread: [String: String]
        /// A system held more entries near the hull than `perSystem`.
        package let cappedPerSystem: Bool
        /// Systems whose search failed, with why ("Al-Mg: offline").
        package let failedSystems: [String]

        package init(elements: [String], systems: Int, found: Int, nearHull: Int, taken: Int, cappedPerSystem: Bool,
                     unread: [String: String] = [:], failedSystems: [String] = []) {
            self.elements = elements; self.systems = systems; self.found = found; self.nearHull = nearHull; self.taken = taken
            self.cappedPerSystem = cappedPerSystem; self.unread = unread; self.failedSystems = failedSystems
        }

        /// The summary of a search before its downloads: what each system answered and which systems failed.
        package init(elements: [String], answers: [SystemAnswer], failedSystems: [String] = []) {
            let near = answers.map { $0.rows.filter { ($0.lowestEnergyAboveHull ?? .infinity) <= MaterialsProjectSearch.hullLimit + 1e-12 }.count }
            self.init(elements: elements, systems: answers.count + failedSystems.count, found: answers.map(\.rows.count).reduce(0, +),
                      nearHull: near.reduce(0, +), taken: MaterialsProjectSearch.chosen(answers).count,
                      cappedPerSystem: near.contains { $0 > MaterialsProjectSearch.perSystem }, failedSystems: failedSystems)
        }

        /// The same search once its downloads are in.
        package func with(unread: [String: String]) -> Summary {
            Summary(elements: elements, systems: systems, found: found, nearHull: nearHull, taken: taken, cappedPerSystem: cappedPerSystem,
                    unread: unread, failedSystems: failedSystems)
        }

        /// "Al, Mg: 3 chemical systems searched, 18 entries found, 9 within 0.1 eV/atom of the hull; the 3 most stable of each
        /// system, 20 at most: 7 taken, 1 could not be read." Says each limit, and only those that applied, so the person knows
        /// what was left out.
        package var sentence: String {
            var text = "\(elements.joined(separator: ", ")): \(count(systems, "chemical system")) searched, \(count(found, "entry", "entries")) found"
            if found > 0 {
                text += ", \(nearHull) within \(MaterialsProjectSearch.hullLimit.formatted()) eV/atom of the hull"
            }
            var limits: [String] = []
            if cappedPerSystem {
                limits.append("the \(MaterialsProjectSearch.perSystem) most stable of each system")
            }
            if taken == MaterialsProjectSearch.maximumCandidates { limits.append("\(MaterialsProjectSearch.maximumCandidates) at most") }
            text += limits.isEmpty ? "; \(taken) taken" : "; " + limits.joined(separator: ", ") + ": \(taken) taken"
            if !unread.isEmpty { text += ", \(unread.count) could not be read" }
            text += "."
            if !failedSystems.isEmpty { text += " Not searched: " + failedSystems.joined(separator: "; ") + "." }
            return text
        }
    }

    /// "12 candidates: 5 from My Phases, 7 from the Materials Project."
    package static func sourcesSentence(myPhases: Int, materialsProject: Int) -> String {
        let total = myPhases + materialsProject
        guard materialsProject > 0 else { return "\(count(total, "candidate")), all from My Phases." }
        return "\(count(total, "candidate")): \(myPhases) from My Phases, \(materialsProject) from the Materials Project."
    }

    static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) " + (n == 1 ? one : many ?? one + "s") }
}
