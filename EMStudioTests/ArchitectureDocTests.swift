//
//  ArchitectureDocTests.swift
//  docs/architecture.md against the tree it describes: every folder of TEMCore, and every folder of the SEM program's target TEMSEM, is
//  named there, and so is each Metal path in the package (a `…Metal.swift` file). A new folder or GPU path the page does not mention goes
//  red here.
//  These read the folders and the page beside this test file.
//

import XCTest

nonisolated final class ArchitectureDocTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func architecture() throws -> String {
        try String(contentsOf: root.appendingPathComponent("docs/architecture.md"), encoding: .utf8)
    }

    /// The folders directly under `relative`, by name, sorted.
    private func folders(in relative: String) throws -> [String] {
        let base = root.appendingPathComponent(relative)
        return try FileManager.default.contentsOfDirectory(atPath: base.path).filter { name in
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: base.appendingPathComponent(name).path, isDirectory: &isFolder)
            return !name.hasPrefix(".") && exists && isFolder.boolValue
        }.sorted()
    }

    /// Each folder of `Sources/TEMCore` is named by its path, each folder of `Sources/TEMSEM` (the SEM program's target, #849) as
    /// `` `<name>/` `` in the SEM table. Red before the SEM section: the page named neither the SEM folder nor any of its twelve
    /// folders (nor `Analysis/`).
    func testEveryTEMCoreAndSEMFolderIsNamedInTheArchitecture() throws {
        let doc = try architecture()
        let core = try folders(in: "Sources/TEMCore")
        XCTAssertFalse(core.isEmpty)
        for name in core {
            XCTAssertTrue(doc.contains("Sources/TEMCore/\(name)/"), "docs/architecture.md does not name Sources/TEMCore/\(name)/")
        }
        XCTAssertTrue(doc.contains("Sources/TEMSEM/"), "docs/architecture.md does not name Sources/TEMSEM/")
        let sem = try folders(in: "Sources/TEMSEM")
        XCTAssertFalse(sem.isEmpty)
        for name in sem {
            XCTAssertTrue(doc.contains("`\(name)/`"), "docs/architecture.md does not name Sources/TEMSEM/\(name)/")
        }
    }

    /// Each Metal path in the package (a `…Metal.swift` file) is named by its path below `Sources/`.
    /// Red before the SEM section: neither `DictionaryIndexingMetal` nor `MasterPatternProjectionMetal` was named.
    func testEveryTEMCoreMetalPathIsNamedInTheArchitecture() throws {
        let doc = try architecture()
        let metal = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Sources").path)
            .filter { $0.hasSuffix("Metal.swift") }
        XCTAssertGreaterThanOrEqual(metal.count, 2, "the dictionary indexing and the master pattern projection each have a Metal path")
        for path in metal {
            XCTAssertTrue(doc.contains(path), "docs/architecture.md does not name Sources/\(path)")
        }
    }
}
