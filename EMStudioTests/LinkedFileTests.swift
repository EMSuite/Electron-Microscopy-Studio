//
//  LinkedFileTests.swift
//  A document keeps its links to other files (#824, plan row X8; the suite's files-exports design, "The sandbox rule for documents
//  that point at other files"): the six cases of the rule with real files and real bookmarks (moved, renamed, missing, no
//  bookmark, wrong file) and the system's answer stood in for the one a test Mac cannot make (an unmounted volume); a bookmark that
//  does not answer is not waited on past its bound; Locate… links a file again, and a pick with other contents is linked only with
//  Link Anyway; the link a document keeps is name, size and fingerprint, and its JSON holds no path (nor does the session
//  sidecar's source record); the app keeps the bookmark under the link's id. Place Beside's measured image is the first link: closed,
//  its file is found where it moved, and once deleted the section says it is not connected. Red before: no document kept a link,
//  Place Beside named its measured image by a URL only, and a closed measured image was never looked for.
//

import Foundation
import ImagoCore
import TEMCore
import TEMSession
import XCTest
@testable import EMStudio

nonisolated final class LinkedFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("linked-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("b"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Plain bookmarks, resolved without interface or mounting: the rule's own calls without the sandbox's scope, which a test host
    /// signed without entitlements cannot make.
    static let plain = LinkedFileSystem(
        resolve: { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            return (url, stale)
        },
        makeBookmark: { try $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) },
        volume: { LinkedFileSystem.bookmarkVolume($0) },
        fingerprint: { try LinkedFile.fingerprint(ofFileAt: $0) })

    /// A file of `count` bytes, each its index modulo 251, at `name` in folder `a`.
    private func file(_ name: String = "frame_012.dm4", count: Int = 4096) throws -> URL {
        let url = folder.appendingPathComponent("a").appendingPathComponent(name)
        try Data((0 ..< count).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    private func same(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func connectedURL(_ state: LinkedFileState) -> URL? {
        if case .connected(let url) = state { return url }
        return nil
    }

    // MARK: - The six cases

    /// Moved to another folder: the bookmark finds it there. Mutation: the link resolved by its path - red.
    func testAMovedFileIsFoundWhereItIs() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let bookmark = try Self.plain.makeBookmark(url)
        let moved = folder.appendingPathComponent("b").appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: moved)

        let found = try XCTUnwrap(connectedURL(LinkedFiles.resolve(link, bookmark: bookmark, system: Self.plain).state))
        XCTAssertTrue(same(found, moved), "\(found.path)")
    }

    /// Renamed in place: the bookmark finds it under its new name, and the link still matches it.
    func testARenamedFileIsFoundUnderItsNewName() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let bookmark = try Self.plain.makeBookmark(url)
        let renamed = url.deletingLastPathComponent().appendingPathComponent("frame_012 renamed.dm4")
        try FileManager.default.moveItem(at: url, to: renamed)

        let resolution = LinkedFiles.resolve(link, bookmark: bookmark, system: Self.plain)
        let found = try XCTUnwrap(connectedURL(resolution.state))
        XCTAssertTrue(same(found, renamed), "\(found.path)")
        XCTAssertNil(resolution.state.line(for: link), "a connected link shows no line")
    }

    /// Deleted: not connected, in the design's words. Mutation: a failed resolution read as connected or as a server - red.
    func testAMissingFileIsNotConnected() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let bookmark = try Self.plain.makeBookmark(url)
        try FileManager.default.removeItem(at: url)

        let state = LinkedFiles.resolve(link, bookmark: bookmark, system: Self.plain).state
        XCTAssertEqual(state, .notConnected)
        XCTAssertEqual(state.line(for: link), "frame_012.dm4 is not connected.")
    }

    /// No bookmark (another Mac, a cleared store): not connected, and nothing is asked of the system.
    func testNoBookmarkIsNotConnected() throws {
        let link = try LinkedFile(describing: try file())
        let asked = LinkedFileSystem(resolve: { _ in XCTFail("resolved"); throw CocoaError(.fileNoSuchFile) },
                                     makeBookmark: { _ in throw CocoaError(.fileNoSuchFile) },
                                     volume: { _ in XCTFail("asked for a volume"); return nil },
                                     fingerprint: { _ in XCTFail("read"); throw CocoaError(.fileNoSuchFile) })
        XCTAssertEqual(LinkedFiles.resolve(link, bookmark: nil, system: asked).state, .notConnected)
    }

    /// The bookmark finds a file whose contents changed: named as different, not connected. Mutation: the name or the size taken
    /// for the identity - red (same name, same size here).
    func testAFileWithOtherContentsIsDifferent() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let bookmark = try Self.plain.makeBookmark(url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 10)
        try handle.write(contentsOf: Data([0xFF, 0xFE]))
        try handle.close()

        let state = LinkedFiles.resolve(link, bookmark: bookmark, system: Self.plain).state
        guard case .different(let found) = state else { return XCTFail("\(state)") }
        XCTAssertTrue(same(found, url))
        XCTAssertEqual(state.line(for: link),
                       "frame_012.dm4 is not frame_012.dm4: its contents differ. Link it anyway only if it is the same data.")
    }

    /// The bookmark's volume is not mounted (a server): said so with its name, and nothing is mounted to look. A volume that is
    /// mounted with the file gone is not connected. The test Mac has no server, so the system's answers are stood in for.
    func testAFileOnAnUnmountedVolumeSaysSo() throws {
        let link = LinkedFile(name: "scan.emd", byteCount: 10, fingerprint: String(repeating: "0", count: 64))
        func system(mounted: Bool) -> LinkedFileSystem {
            LinkedFileSystem(resolve: { _ in throw CocoaError(.fileNoSuchFile) },
                             makeBookmark: { _ in throw CocoaError(.fileNoSuchFile) },
                             volume: { _ in (name: "Lab Share", isMounted: mounted) },
                             fingerprint: { _ in throw CocoaError(.fileNoSuchFile) })
        }
        let state = LinkedFiles.resolve(link, bookmark: Data([1]), system: system(mounted: false)).state
        XCTAssertEqual(state, .serverNotConnected(volume: "Lab Share"))
        XCTAssertEqual(state.line(for: link), "scan.emd is on a server that is not connected.")
        XCTAssertEqual(LinkedFiles.resolve(link, bookmark: Data([1]), system: system(mounted: true)).state, .notConnected)
    }

    /// A bookmark that does not answer (a server asleep) is not waited on past the bound: opening never blocks.
    func testABookmarkThatDoesNotAnswerIsNotWaitedOn() async throws {
        let link = LinkedFile(name: "scan.emd", byteCount: 10, fingerprint: String(repeating: "0", count: 64))
        let slow = LinkedFileSystem(resolve: { _ in Thread.sleep(forTimeInterval: 3); throw CocoaError(.fileNoSuchFile) },
                                    makeBookmark: { _ in throw CocoaError(.fileNoSuchFile) }, volume: { _ in nil },
                                    fingerprint: { _ in throw CocoaError(.fileNoSuchFile) })
        let start = Date()
        let resolution = await LinkedFiles.resolve(link, bookmark: Data([1]), system: slow, within: 0.2)
        XCTAssertEqual(resolution.state, .notConnected)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    // MARK: - Locate…

    /// Locate… with the same file (moved, under another name) connects it with a new bookmark; with other contents it is different
    /// and gets no bookmark until Link Anyway, which keeps the link's id and takes the new file's name and fingerprint.
    func testLocateLinksAFileAgain() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let copy = folder.appendingPathComponent("b").appendingPathComponent("copied.dm4")
        try FileManager.default.copyItem(at: url, to: copy)

        let located = LinkedFiles.locate(link, picked: copy, system: Self.plain)
        XCTAssertEqual(located.state, .connected(copy))
        let bookmark = try XCTUnwrap(located.bookmark)
        XCTAssertTrue(same(try XCTUnwrap(connectedURL(LinkedFiles.resolve(link, bookmark: bookmark, system: Self.plain).state)), copy))

        let other = try file("other.dm4", count: 4000)
        let picked = LinkedFiles.locate(link, picked: other, system: Self.plain)
        XCTAssertEqual(picked.state, .different(other))
        XCTAssertNil(picked.bookmark, "a different file is not linked until the person says so")
        let relinked = try XCTUnwrap(LinkedFiles.relinked(link, to: other, system: Self.plain))
        XCTAssertEqual(relinked.link.id, link.id)
        XCTAssertEqual(relinked.link.name, "other.dm4")
        XCTAssertEqual(relinked.link.byteCount, 4000)
        let again = LinkedFiles.resolve(relinked.link, bookmark: relinked.bookmark, system: Self.plain).state
        XCTAssertTrue(same(try XCTUnwrap(connectedURL(again)), other), "\(again)")
    }

    // MARK: - What a document holds

    /// The fingerprint reads the size and both ends: a byte changed at either end, or one more byte, is another file; a byte in the
    /// middle of a large file is not read (the design's two reads). Mutation: only the head hashed, the size left out - red.
    func testTheFingerprintIsTheSizeAndBothEnds() throws {
        let count = 3 * LinkedFile.edgeBytes
        let url = try file("big.dm4", count: count)
        let base = try LinkedFile.fingerprint(ofFileAt: url)
        XCTAssertEqual(base.byteCount, count)
        XCTAssertEqual(base.fingerprint.count, 64)
        func changed(at offset: UInt64) throws -> String {
            let copy = folder.appendingPathComponent("b").appendingPathComponent("\(offset).dm4")
            try FileManager.default.copyItem(at: url, to: copy)
            let handle = try FileHandle(forWritingTo: copy)
            try handle.seek(toOffset: offset)
            try handle.write(contentsOf: Data([0xFF]))
            try handle.close()
            return try LinkedFile.fingerprint(ofFileAt: copy).fingerprint
        }
        XCTAssertNotEqual(try changed(at: 0), base.fingerprint, "the head")
        XCTAssertNotEqual(try changed(at: UInt64(count - 1)), base.fingerprint, "the tail")
        XCTAssertEqual(try changed(at: UInt64(count / 2)), base.fingerprint, "the middle is not read")
        let longer = try file("longer.dm4", count: count + 1)
        XCTAssertNotEqual(try LinkedFile.fingerprint(ofFileAt: longer).fingerprint, base.fingerprint, "the size")
    }

    /// No saved document holds a path: the link's JSON is its id, name, size and fingerprint, and the folders it was linked from
    /// appear nowhere in it; the session sidecar's source record holds the file's name only. Mutation: a path or URL field - red.
    func testNoSavedDocumentHoldsAPath() throws {
        let url = try file()
        let link = try LinkedFile(describing: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(link), as: UTF8.self)
        let keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["byteCount", "fingerprint", "id", "name"])
        XCTAssertFalse(json.contains("/"), json)
        XCTAssertFalse(json.contains(folder.lastPathComponent), json)
        XCTAssertEqual(try JSONDecoder().decode(LinkedFile.self, from: Data(json.utf8)), link, "read back exactly")

        let image = CalibratedImage(width: 2, height: 1, pixels: [1, 2], x: nil, y: nil, fileName: url.lastPathComponent, source: "ImageList.1",
                                    voltage: nil)
        let source = try SessionSourceIdentity.of(image, fileByteSize: 4096).jsonString()
        XCTAssertFalse(source.contains(folder.lastPathComponent), source)
        XCTAssertFalse(source.contains(url.deletingLastPathComponent().path), source)
    }

    /// The app keeps the bookmark under the link's id, outside the document: never under a path.
    @MainActor func testTheAppKeepsTheBookmarkUnderTheLinksID() throws {
        let suite = "linked-file-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try file()
        let link = try XCTUnwrap(LinkedFileGrants.link(to: url, system: Self.plain, defaults: defaults))
        XCTAssertEqual(link.name, "frame_012.dm4")
        XCTAssertEqual(LinkedFileGrants.key(for: link), "linkedFile.grant.\(link.id)")
        XCTAssertNotNil(LinkedFileGrants.bookmark(for: link, defaults: defaults))
        XCTAssertNil(LinkedFileGrants.link(to: URL(string: "memory://demo")!, system: Self.plain, defaults: defaults),
                     "an image with no file has no link")
        LinkedFileGrants.store(nil, for: link, defaults: defaults)
        XCTAssertNil(LinkedFileGrants.bookmark(for: link, defaults: defaults))
    }

    // MARK: - Place Beside

    /// Place Beside names an open measured image by its link. Closed, its file is looked for through the app's bookmark: found
    /// where it moved (offered to open again), and once deleted the section says it is not connected, with Locate…. Mutation: the
    /// link not made when the image is named, the closed image not looked for, a stale state kept after the link changes - red.
    @MainActor func testPlaceBesideKeepsItsLinkToTheMeasuredFile() async throws {
        let suite = "linked-file-beside-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.newSimulation()?.value
        let simulation = try XCTUnwrap(state.openItems.items.first { DemoDocuments.isSimulation($0.url) })

        let url = try file("Si110.dm4")
        let link = try LinkedFile(describing: url)
        LinkedFileGrants.store(try Self.plain.makeBookmark(url), for: link, defaults: defaults)
        XCTAssertTrue(simulation.multislice.setBeside(HRTEMBeside(measured: url, link: link)))
        XCTAssertEqual(state.besideStatus(of: simulation), .closed("Si110.dm4", file: nil), "not looked for yet")

        let moved = folder.appendingPathComponent("b").appendingPathComponent("Si110.dm4")
        try FileManager.default.moveItem(at: url, to: moved)
        await state.resolveBesideLink(of: simulation, system: Self.plain, defaults: defaults)
        guard case .closed("Si110.dm4", let found?) = state.besideStatus(of: simulation) else {
            return XCTFail("\(state.besideStatus(of: simulation))")
        }
        XCTAssertTrue(same(found, moved))

        try FileManager.default.removeItem(at: moved)
        await state.resolveBesideLink(of: simulation, system: Self.plain, defaults: defaults)
        XCTAssertEqual(state.besideStatus(of: simulation), .unlinked("Si110.dm4 is not connected.", different: false))
        XCTAssertEqual(state.besideStatus(of: simulation).lines, ["Si110.dm4 is not connected."])

        // Another file named: the old link's state is not shown for it.
        var other = try XCTUnwrap(simulation.multislice.beside)
        other.link = LinkedFile(name: "other.dm4", byteCount: 1, fingerprint: String(repeating: "1", count: 64))
        XCTAssertTrue(simulation.multislice.setBeside(other))
        XCTAssertNil(simulation.multislice.besideLinkState)
        simulation.multislice.setBesideLinkState(.notConnected, for: link)
        XCTAssertNil(simulation.multislice.besideLinkState, "a state for a link no longer named is dropped")
    }
}
