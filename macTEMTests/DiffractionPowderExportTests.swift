//
//  DiffractionPowderExportTests.swift
//  The powder pattern's two files and the ring table's listed intensity (#811): the CSV's rows are the table's rows with the
//  record inside and its table lines as they were; the .xy is two columns of numbers, one line a step over the range; a ring on
//  the planted Au pattern's {111} lists 100 (the strongest family), and every listed intensity is the family's share of the list's
//  strongest. Red before: no powder record, no listed intensity.
//

import XCTest
import DiffractoCore
import DiffractoScattering
import ImagoCore
import ShellExport
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DiffractionPowderExportTests: XCTestCase {

    private static let app = MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.4.0 (1)")
    private static let source = MethodsRecord.Source(fileName: "p.dm4", byteCount: 2000, fingerprint: String(repeating: "cd", count: 32),
                                                     kind: "image", shape: [512, 512])

    private func aluminiumAndGold() -> PowderTable {
        let phases = ["Al", "Au"].map { name in
            let s = StandardCrystals.all.first { $0.name == name }!
            return PowderPhase(name: s.name, structure: s.structure)
        }
        return PowderTable.make(phases: phases, settings: PowderSettings())
    }

    func testTheCSVRowsAreTheTableWithTheRecordInside() throws {
        let table = aluminiumAndGold()
        let record = ExportMethods.powderRecord(app: Self.app, source: Self.source, table: table)
        XCTAssertEqual(record.exportKind, "powder-csv")
        XCTAssertEqual(record.results.map(\.value), [.number(2), .number(Double(table.rows.count))])
        let csv = table.csv()
        let written = try ExportMethods.embedding(record, inText: csv)
        XCTAssertEqual(ExportMethods.record(inText: written), record)
        let data = written.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(data.count, table.rows.count + 1, "a header, then one line a row")
        for (line, row) in zip(data.dropFirst(), table.rows) {
            XCTAssertTrue(line.hasPrefix(CSVText.quoted(row.phase) + "," + CSVText.quoted(row.hkl) + ",\(row.multiplicity),"), String(line))
        }
    }

    func testTheXYIsTwoColumnsOfNumbers() throws {
        let table = aluminiumAndGold()
        let xy = try XCTUnwrap(table.xy(phase: 0))
        let lines = xy.split(separator: "\n")
        let range = table.settings.range
        XCTAssertEqual(lines.count, Int(((range.upperBound - range.lowerBound) / table.profileStep).rounded(.down)) + 1)
        for line in lines {
            let cells = line.split(separator: " ")
            XCTAssertEqual(cells.count, 2, String(line))
            XCTAssertNotNil(Double(cells[0])); XCTAssertNotNil(Double(cells[1]))
        }
        XCTAssertEqual(DiffractionPowderExport.baseName(of: "pattern.dm4", phase: "Al"), "pattern powder Al")
    }

    @MainActor func testTheRingTableListsTheFamilysIntensity() async throws {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        let family = try XCTUnwrap(analysis.standardFamilies().first { $0.name == "{111}" })
        await analysis.fitRing(image: image, inner: 29, outer: 37, calibrateOn: family.family)?.value
        let row = try XCTUnwrap(analysis.readout(image: image).first)
        XCTAssertEqual(row.family, "{111}")
        XCTAssertEqual(try XCTUnwrap(row.listedIntensity), 100, accuracy: 1e-9, "Au {111} is the strongest family")
        XCTAssertEqual(DiffractionReadoutFormat.cell(.intensity, row, locale: Locale(identifier: "en_US")), "100")

        let list = try XCTUnwrap(analysis.list())
        let strongest = try XCTUnwrap(list.families.map(\.intensity).max())
        for f in list.families {
            XCTAssertEqual(try XCTUnwrap(DiffractionAnalysis.relativeIntensity(of: f.family, in: list)), 100 * f.intensity / strongest,
                           accuracy: 1e-12)
        }
    }
}
