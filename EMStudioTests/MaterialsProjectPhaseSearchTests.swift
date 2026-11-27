//
//  MaterialsProjectPhaseSearchTests.swift
//  #813 (plan row R14): Find Phases takes its elements typed or from the EDS room and searches the Materials Project for every
//  chemical system they span, keyless, taking the most stable entries near the hull within the stated limits, and says how many
//  candidates came from which source. The service is a stub transport that answers with DiffractoKit's recorded OPTIMADE answers
//  (Fixtures/mp-optimade: the search for Al, the entries mp-134 and mp-1183144); an entry it holds no answer for is a 404. Red before
//  #813: none of MaterialsProjectSearch, MaterialsProjectPhaseSearch or the sentences existed.
//

import DiffractoCore
import Foundation
import ShellEDXModel
import ShellPhaseLibrary
import TEMCore
import XCTest
@testable import EMStudio

/// Answers each request by `answer`, and keeps what was sent.
private final class RecordedTransport: PhaseTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    let answer: @Sendable (URLRequest) throws -> (Data, Int)
    init(answer: @escaping @Sendable (URLRequest) throws -> (Data, Int)) { self.answer = answer }
    var sent: [URLRequest] { lock.withLock { _sent } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _sent.append(request) }
        let (data, status) = try answer(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }
}

nonisolated final class MaterialsProjectPhaseSearchTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent("mp-optimade")

    private static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }

    /// The recorded answers: any search is the search for Al, an entry is its recorded file or a 404.
    private static func recorded(_ request: URLRequest) throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/structures") { return (try fixture("search-Al.json"), 200) }
        let id = request.url?.lastPathComponent ?? ""
        if let data = try? fixture("entry-\(id).json") { return (data, 200) }
        return (Data(#"{"errors":[{"status":"404","detail":"not found"}]}"#.utf8), 404)
    }

    private func client(_ transport: RecordedTransport) -> MaterialsProjectClient {
        MaterialsProjectClient(transport: transport, now: Date.init, sleep: { _ in })
    }

    // MARK: The elements and the systems

    /// Mutation: elements not checked, not ordered by atomic number, or no limit on how many - red.
    func testElementsAreTypedCheckedAndLimited() throws {
        XCTAssertEqual(try MaterialsProjectSearch.elements(typed: "al cu, Mg"), ["Mg", "Al", "Cu"])
        XCTAssertEqual(try MaterialsProjectSearch.elements(typed: "AlCuMg"), ["Mg", "Al", "Cu"])
        XCTAssertEqual(try MaterialsProjectSearch.elements(typed: "Al Al"), ["Al"])
        XCTAssertThrowsError(try MaterialsProjectSearch.elements(typed: "Al, Xx")) {
            XCTAssertEqual($0 as? MaterialsProjectSearch.Refusal, .notAnElement("Xx"))
        }
        XCTAssertThrowsError(try MaterialsProjectSearch.elements(typed: "  ")) {
            XCTAssertEqual($0 as? MaterialsProjectSearch.Refusal, .noElements)
        }
        XCTAssertThrowsError(try MaterialsProjectSearch.elements(typed: "Al Cu Mg Si Fe")) { error in
            XCTAssertTrue(String(describing: error).contains("at most 4 elements"), "\(error)")
        }
    }

    /// Mutation: a system left out, or a system searched with other elements allowed in - red.
    func testEverySystemTheElementsSpanIsOneExactSearch() throws {
        XCTAssertEqual(MaterialsProjectSearch.systems(["Mg", "Al"]), [["Mg"], ["Al"], ["Mg", "Al"]])
        XCTAssertEqual(MaterialsProjectSearch.systems(["Mg", "Al", "Cu"]).count, 7)
        XCTAssertEqual(try MaterialsProjectOptimade.filter(for: MaterialsProjectSearch.query(["Mg", "Al"])),
                       #"elements HAS ALL "Al","Mg" AND nelements=2"#)
    }

    /// The recorded search for Al holds ten entries, six within 0.1 eV/atom of the hull; the three most stable are taken.
    /// Mutation: the hull limit or the per-system cap not applied, or the sentence leaving out a limit that applied - red.
    func testTheMostStableEntriesNearTheHullAreTakenAndTheSentenceSaysSo() throws {
        guard case .rows(let rows, _) = try MaterialsProjectOptimade.decodeSearch(Self.fixture("search-Al.json")) else {
            return XCTFail("the recorded search has rows")
        }
        let answers = [MaterialsProjectSearch.SystemAnswer(system: ["Al"], rows: rows)]
        XCTAssertEqual(MaterialsProjectSearch.chosen(answers).map(\.materialID), ["mp-134", "mp-1183144", "mp-2647008"])
        let summary = MaterialsProjectSearch.Summary(elements: ["Al"], answers: answers)
        XCTAssertEqual(summary.found, 10)
        XCTAssertEqual(summary.nearHull, 6)
        XCTAssertEqual(summary.taken, 3)
        XCTAssertTrue(summary.cappedPerSystem)
        XCTAssertTrue(summary.sentence.contains("1 chemical system searched, 10 entries found"), summary.sentence)
        XCTAssertTrue(summary.sentence.contains("the 3 most stable of each system: 3 taken"), summary.sentence)
        XCTAssertEqual(MaterialsProjectSearch.sourcesSentence(myPhases: 5, materialsProject: 2),
                       "7 candidates: 5 from My Phases, 2 from the Materials Project.")
        XCTAssertEqual(MaterialsProjectSearch.sourcesSentence(myPhases: 5, materialsProject: 0), "5 candidates, all from My Phases.")
    }

    // MARK: The search on recorded responses

    /// Mutation: a key sent, the elements not searched as an exact system, an unreadable entry dropping the whole search, or the
    /// candidates not marked as the Materials Project's - red.
    @MainActor func testASearchOnRecordedResponsesGivesMaterialsProjectCandidates() async throws {
        let transport = RecordedTransport(answer: Self.recorded)
        let search = MaterialsProjectPhaseSearch()
        search.elementsText = "Al"
        let task = try XCTUnwrap(search.run(client: client(transport)))
        XCTAssertTrue(search.isRunning)
        await task.value

        guard case .done(let summary) = search.state else { return XCTFail("\(search.state)") }
        XCTAssertEqual(summary.taken, 3)
        XCTAssertEqual(Array(summary.unread.keys), ["mp-2647008"], "the entry the service did not answer")
        XCTAssertTrue(summary.sentence.contains("1 could not be read"), summary.sentence)
        XCTAssertEqual(search.candidates.map(\.id), ["Al (mp-134)", "Al (mp-1183144)"])
        XCTAssertTrue(search.candidates.allSatisfy { $0.source == .materialsProject && $0.candidate.source == .materialsProject })
        XCTAssertEqual(search.candidates.first?.candidate.formula, "Al")
        XCTAssertEqual(search.sourcesSentence(myPhases: 4), "6 candidates: 4 from My Phases, 2 from the Materials Project.")

        let sent = transport.sent
        XCTAssertEqual(sent.count, 4, "one search and three downloads")
        XCTAssertTrue(sent.allSatisfy { $0.value(forHTTPHeaderField: MaterialsProjectClient.keyHeader) == nil }, "keyless")
        let query = try XCTUnwrap(sent.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        XCTAssertEqual(query.first { $0.name == "filter" }?.value, #"elements HAS ALL "Al" AND nelements=1"#)
    }

    /// Mutation: an offline search answered as "nothing found", or refused elements sending a request - red.
    @MainActor func testOfflineAndRefusedElementsAreSaid() async throws {
        let offline = RecordedTransport { _ in throw URLError(.notConnectedToInternet) }
        let search = MaterialsProjectPhaseSearch()
        search.elementsText = "Al, Mg"
        await search.run(client: client(offline))?.value
        XCTAssertEqual(search.state, .failed("this Mac is offline"))
        XCTAssertTrue(search.candidates.isEmpty)

        let none = RecordedTransport(answer: Self.recorded)
        search.elementsText = "Al Cu Mg Si Fe"
        XCTAssertNil(search.run(client: client(none)))
        guard case .refused(let why) = search.state else { return XCTFail("\(search.state)") }
        XCTAssertTrue(why.contains("at most 4 elements"), why)
        XCTAssertTrue(none.sent.isEmpty, "nothing is sent for elements that are refused")
    }

    /// An EDS room with no spectrum image has no elements to give. Mutation: From EDS enabled with nothing to take - red.
    @MainActor func testFromEDSNeedsAnOpenSpectrumImage() {
        let session = EDXSession(host: .macTEM)
        XCTAssertNil(MaterialsProjectPhaseSearch.edsElements(session))
        let search = MaterialsProjectPhaseSearch()
        XCTAssertFalse(search.takeFromEDS(session))
        XCTAssertEqual(search.elementsText, "")
    }
}
