//
//  DiffractionWordsAndExportsTests.swift
//  The Diffraction room reads one word per thing and writes every file from its Export section (#922, control placement §4): the
//  readout and spots, the tilt list, the powder CSV and XY and the figure are plain buttons in width sets in the last section, with no
//  "Export" in their titles; the Holder and Powder sections hold none; "In-plane rotation" and "q max" replace "Turn" and "k_max".
//  Red before: the tilt list sat in Holder, the powder files in Powder, Readout and Spots on two rows titled "Export …", no Figure…
//  in the section, and the rows read "Turn" and "k_max".
//

import XCTest
@testable import macTEM

nonisolated final class DiffractionWordsAndExportsTests: XCTestCase {

    private func ui(_ name: String) throws -> String { try FFTRoomWiringTests.squeezedUI(name) }

    /// The Export section of DiffractionRoomInspector.swift, squeezed.
    private func exportSection() throws -> String {
        let source = try ui("DiffractionRoomInspector.swift")
        return try XCTUnwrap(source.components(separatedBy: "private struct DiffractionExportSection: View {").last)
    }

    /// Every file the room writes is a button of the Export section, in width sets of two, by its identifier.
    func testTheExportSectionListsEveryExport() throws {
        let export = try exportSection()
        let rows: [[(title: String, id: String)]] = [
            [("Readout CSV…", "diffraction.export"), ("Spots CSV…", "diffraction.export.spots")],
            [("Tilt List CSV…", "diffraction.holder.export"), ("Powder CSV…", "diffraction.powder.exportCSV")],
            [("Powder XY…", "diffraction.powder.exportXY"), ("Figure…", "diffraction.export.figure")],
        ]
        let actionRows = export.components(separatedBy: "InspectorActionRow {").dropFirst()
        XCTAssertEqual(actionRows.count, rows.count, "one width set a pair")
        for (row, source) in zip(rows, actionRows) {
            for button in row {
                XCTAssertTrue(source.contains("Button(\"\(button.title)\")"), "\(button.title) in its width set")
                XCTAssertTrue(source.contains(".accessibilityIdentifier(\"\(button.id)\")"), "\(button.id) kept")
            }
        }
        XCTAssertFalse(export.contains("Button(\"Export "), "no \"Export\" in a title: the section says it")
        XCTAssertTrue(export.contains("ExportPanels.exportDiffractionFigure(appState: appState)"), "Figure… is File > Export Figure…'s panel")
        XCTAssertTrue(try ui("DiffractionRoomInspector.swift").contains("DiffractionExportSection(item: item, isSimulation: isSimulation) }"),
                      "Export is the last section")
    }

    /// The job sections hold settings only: no file is written from Holder or Powder.
    func testTheHolderAndPowderSectionsWriteNoFile() throws {
        for name in ["DiffractionHolderSection.swift", "DiffractionPowderSection.swift"] {
            let source = try ui(name)
            XCTAssertFalse(source.contains("Button(\"Export"), "\(name): its export moved to the Export section")
            XCTAssertFalse(source.contains(".fileExporter("), "\(name): no save panel of its own")
        }
    }

    /// One word per thing: the rotation about the beam and the reflection list's reach say what the rest of the room says.
    func testTheRowsSayInPlaneRotationAndQMax() throws {
        let source = try ui("DiffractionRoomInspector.swift")
        XCTAssertTrue(source.contains("InspectorRow(\"In-plane rotation\") { OptionalNumericField(title: \"In-plane rotation\","))
        XCTAssertTrue(source.contains("InspectorRow(\"q max\") { OptionalNumericField(title: \"q max\","))
        XCTAssertFalse(source.contains("InspectorRow(\"Turn\")") || source.contains("InspectorRow(\"k_max\")"))
        XCTAssertTrue(try ui("DiffractionPowderSection.swift").contains("InspectorRow(\"q max\")"), "Powder says q max too")
        XCTAssertTrue(try ui("DiffractionHolderSection.swift").contains("Button(\"Clear\")"), "the Calibration section's word")
        XCTAssertTrue(try ui("DiffractionFindPhasesSheet.swift").contains("Button(\"Use Phase\")"))
    }
}
