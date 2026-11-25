//
//  PhaseCIFTests.swift
//  A phase is saved as CIF (#821, plan row X5): the text is DiffractoKit's `CIFExport` of the phase's structure with the app's `#`
//  lines; the saved file, added again the way Add Phase… > Open CIF… adds it (`CrystalLoading.load`), gives a phase with the same
//  content fingerprint; a Materials Project phase carries its id, the date it was fetched and "CC BY 4.0"; an edited lattice says
//  so; Save as CIF… is in a phase row's context menu and File > Save Phase as CIF… in the Diffraction room.
//  Red before: `PhaseCIF` did not exist.
//

import DiffractoCore
import ShellPhaseLibrary
import UniformTypeIdentifiers
import XCTest
@testable import macTEM

nonisolated final class PhaseCIFTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The text the panel writes, read back as Open CIF… reads it, as a phase again.
    private func addedAgain(_ text: String) throws -> Phase {
        let loaded = try CrystalLoading.load(bytes: Data(text.utf8), fileName: "saved.cif")
        return Phase(id: "cif-again", name: loaded.displayName, source: .cif(fileName: "saved.cif"), structure: loaded.structure)
    }

    /// Mutation: the text loses a site, a cell value or the symmetry the kit kept - red.
    func testASavedPhaseAddedAgainIsTheSamePhase() throws {
        let gold = Phase(id: "cif-gold", name: "gold", source: .cif(fileName: "Au.cif"), structure: CrystalPresets.gold)
        let outcome = try PhaseCIF.text(of: gold)
        guard case .kept = outcome.symmetry else { return XCTFail("gold in P1: \(outcome.symmetry)") }
        XCTAssertTrue(outcome.text.contains("_space_group_IT_number 225\n"))
        XCTAssertTrue(outcome.text.contains("data_gold\n"))
        XCTAssertTrue(outcome.text.contains("# Source:\n#   CIF Au.cif\n"))
        XCTAssertTrue(outcome.text.contains("_audit_creation_method 'Electron Microscopy Studio'"))
        XCTAssertFalse(outcome.text.contains("Lattice edited"))
        XCTAssertEqual(try addedAgain(outcome.text).sourceFingerprint, gold.snapshot.fingerprint)
    }

    func testAMaterialsProjectPhaseCarriesItsIdDateAndLicence() throws {
        let fetched = Date(timeIntervalSince1970: 1_795_000_000)   // 18 Nov 2026, 11:06 UTC
        let aluminium = Phase(id: "mp-134", name: "Al", source: .materialsProject(id: "mp-134", fetched: fetched),
                              structure: CrystalPresets.aluminum)
        XCTAssertEqual(PhaseCIF.sourceLines(aluminium.source),
                       ["Materials Project mp-134, fetched 2026-11-18, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
                        "https://next-gen.materialsproject.org/materials/mp-134"])
        let text = try PhaseCIF.text(of: aluminium).text
        XCTAssertTrue(text.contains("#   Materials Project mp-134, fetched 2026-11-18, CC BY 4.0"), text)
        XCTAssertEqual(try addedAgain(text).sourceFingerprint, aluminium.snapshot.fingerprint)
    }

    /// An edited lattice is saved as edited, says so, and comes back as the edited structure.
    func testAnEditedLatticeIsSavedAsEdited() throws {
        var gold = Phase(id: "cif-gold", name: "gold", source: .cif(fileName: "Au.cif"), structure: CrystalPresets.gold)
        gold.replaceStructure(try CrystalPresets.gold.editingLattice([.a: 4.1]))
        XCTAssertTrue(gold.isEdited)
        let text = try PhaseCIF.text(of: gold).text
        XCTAssertTrue(text.contains("# Lattice edited in Electron Microscopy Studio"))
        XCTAssertTrue(text.contains("_cell_length_a 4.1\n"))
        XCTAssertEqual(try addedAgain(text).sourceFingerprint, gold.snapshot.fingerprint)
    }

    func testTheNameAndTheDoneLine() {
        let phase = Phase(id: "x", name: "Al/Cu: θ'", source: .cif(fileName: "a.cif"), structure: CrystalPresets.aluminum)
        XCTAssertEqual(PhaseCIF.defaultName(phase), "Al-Cu- θ'")
        let blank = Phase(id: "y", name: "  ", source: .cif(fileName: "a.cif"), structure: CrystalPresets.aluminum)
        XCTAssertEqual(PhaseCIF.defaultName(blank), "phase")
        XCTAssertEqual(PhaseCIF.doneLine(name: "Al.cif", symmetry: .kept(operations: 192, sites: 1, expanded: 4)), "Saved Al.cif")
        XCTAssertTrue(PhaseCIF.doneLine(name: "Mg.cif", symmetry: .p1(reason: "x")).contains("in P1"))
        XCTAssertEqual(PhaseCIF.contentType.preferredFilenameExtension, "cif")
    }

    /// Save as CIF… on a phase row and in the File menu, both through `PhaseCIF.save`.
    func testTheRowAndTheFileMenuSave() throws {
        let row = try source("macTEM/UI/DiffractionRoomInspector.swift")
        XCTAssertTrue(row.contains("Button(\"Save as CIF…\") { PhaseCIF.save(phase, appState: appState) }"))
        XCTAssertTrue(row.contains("accessibilityIdentifier(\"diffraction.phases.saveCIF.\\(phase.id)\")"))
        let menu = try source("macTEM/App/ExportCommands.swift")
        XCTAssertTrue(menu.contains("Button(\"Save Phase as CIF…\")"))
        XCTAssertTrue(menu.contains("PhaseCIF.save(phase, appState: appState)"))
    }
}
