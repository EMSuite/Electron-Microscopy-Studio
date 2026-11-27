//
//  DiffractionPhasesTests.swift
//  #779: the Diffraction room takes its phases from the library. A shown phase is the crystal Index, the readout and the
//  simulated spots use, and hiding it returns the room to its calibration standard; each phase keeps a marker shape and colour
//  by the order it was added; a CIF opened from Add Phase is a library phase that a fresh read of the folder (a new launch,
//  offline) finds again. Red before: the room's crystal was a standard or a loose CIF, with no library and no markers.
//

import XCTest
import DiffractoCore
import ShellPhaseLibrary
import TEMCore
import TEMSession
@testable import EMStudio

nonisolated final class DiffractionPhasesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DiffractionPhasesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func gold(added: Date = Date(timeIntervalSince1970: 1_795_000_000)) -> Phase {
        Phase(id: "mp-81", name: "Au", source: .materialsProject(id: "mp-81", fetched: added), added: added,
              structure: StandardCrystals.all[0].structure)
    }

    /// Showing a phase makes it the crystal in use, under its own identity; hiding it gives the room back its standard.
    @MainActor func testAShownPhaseIsTheCrystalAndHidingItReturnsToTheStandard() {
        let analysis = DiffractionAnalysis()
        let phase = gold()
        DiffractionPhases.set(phase, shown: true, in: analysis)
        XCTAssertEqual(analysis.crystal.phaseID, "mp-81")
        XCTAssertEqual(analysis.crystal.name, "Au")
        XCTAssertEqual(analysis.crystal.structure, phase.structure())
        XCTAssertTrue(analysis.crystal.identity.hasPrefix("phase|mp-81|"), analysis.crystal.identity)
        XCTAssertNotEqual(analysis.crystal.identity, DiffractionCrystal.preset(analysis.standard).identity,
                          "a phase of the same atoms as the standard is still its own crystal for the caches")
        XCTAssertNil(analysis.crystalFailure)

        let other = Phase(id: "mp-30", name: "Cu", source: .materialsProject(id: "mp-30", fetched: Date()),
                          structure: StandardCrystals.all[0].structure)
        DiffractionPhases.set(other, shown: false, in: analysis)
        XCTAssertEqual(analysis.crystal.phaseID, "mp-81", "hiding a phase that is not shown changes nothing")

        DiffractionPhases.set(phase, shown: false, in: analysis)
        XCTAssertEqual(analysis.crystal, .preset(analysis.standard))
        XCTAssertNil(analysis.crystal.phaseID)
    }

    /// An edited lattice is another crystal for the caches: the fingerprint is part of the identity.
    func testTheIdentityFollowsTheStructure() {
        let structure = StandardCrystals.all[0].structure
        let a = PhaseCrystal(id: "mp-81", name: "Au", structure: structure)
        let fingerprint = CrystalStructure.Snapshot(structure).fingerprint
        XCTAssertEqual(a.fingerprint, fingerprint)
        XCTAssertEqual(DiffractionCrystal.phase(a).identity, "phase|mp-81|\(fingerprint)")
    }

    /// No two of the first 30 phases share both shape and colour, and a phase keeps its style when a newer one is added.
    func testEachPhaseHasItsOwnMarkerAndKeepsIt() {
        let styles = (0..<30).map { DiffractionPhases.style(at: $0) }
        XCTAssertEqual(Set(styles.map { "\($0.marker)|\($0.colourIndex)" }).count, 30)
        XCTAssertTrue(styles.allSatisfy { (0..<6).contains($0.colourIndex) })

        let old = gold(added: Date(timeIntervalSince1970: 1_000))
        let new = Phase(id: "mp-30", name: "Cu", source: .materialsProject(id: "mp-30", fetched: Date()),
                        added: Date(timeIntervalSince1970: 2_000), structure: StandardCrystals.all[0].structure)
        XCTAssertEqual(DiffractionPhases.ordered([new, old]).map(\.id), ["mp-81", "mp-30"], "the library lists newest first; styles go by age")
    }

    func testTheLatticeReadsInOneLine() {
        let gold = StandardCrystals.all[0].structure.cell
        let text = DiffractionPhases.latticeText(gold)
        XCTAssertEqual(text, String(format: "a %.4f Å", gold.a))
        let tetragonal = UnitCell(a: 4.04, b: 4.04, c: 5.8, alphaDeg: 90, betaDeg: 90, gammaDeg: 90)
        XCTAssertEqual(DiffractionPhases.latticeText(tetragonal), "a 4.0400, b 4.0400, c 5.8000 Å; 90.00°, 90.00°, 90.00°")
    }

    /// Open CIF… adds the file to the library with its bytes, once per content, and a new read of the folder finds it again.
    @MainActor func testACIFIsALibraryPhaseThatANewLaunchFindsOffline() async throws {
        let bytes = Data(BetaDoublePrimeCIF.text.utf8)
        let loaded = try CrystalLoading.load(bytes: bytes, fileName: "beta.cif")
        let library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        let phase = try DiffractionPhases.addCIF(loaded, bytes: bytes, fileName: "beta.cif", to: library)
        XCTAssertEqual(phase.id, "cif-" + loaded.sha256.prefix(16))
        XCTAssertEqual(phase.name, loaded.displayName)
        XCTAssertEqual(phase.source, .cif(fileName: "beta.cif"))
        XCTAssertNil(phase.source.attribution)
        let again = try DiffractionPhases.addCIF(loaded, bytes: bytes, fileName: "copy of beta.cif", to: library)
        XCTAssertEqual(again.id, phase.id)
        XCTAssertEqual(library.phases.count, 1, "the same file twice is one phase")

        let relaunched = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        await relaunched.load()
        XCTAssertEqual(relaunched.phases.map(\.id), [phase.id])
        XCTAssertTrue(relaunched.unreadable.isEmpty)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(relaunched.sourceFile(of: phase.id))), bytes)
        let cell = try XCTUnwrap(relaunched.phases.first?.structure().cell)
        XCTAssertEqual(cell.a, loaded.structure.cell.a, accuracy: 1e-9)
        XCTAssertEqual(cell.c, loaded.structure.cell.c, accuracy: 1e-9)
    }

    // MARK: #780, the room's own copy

    /// A change to the library's phase changes nothing the room computes until Update from Library; then the room takes it.
    /// Red before #780: no copy was kept apart from the library, and nothing said the library had moved on.
    @MainActor func testResultsDoNotChangeWhenTheLibraryChanges() throws {
        let library = PhaseLibrary(store: PhaseLibraryStore(folder: folder))
        var phase = gold()
        try library.add(phase, source: Data("{}".utf8), sourceExtension: "json")
        let analysis = DiffractionAnalysis()
        DiffractionPhases.set(phase, shown: true, in: analysis)
        let before = analysis.crystal
        XCTAssertFalse(DiffractionPhases.isOutdated(phase, in: analysis))

        let cell = phase.structure().cell
        // Another structure in the library's record, as a lattice edit would leave it (the edit itself is A4's).
        let other = try XCTUnwrap(StandardCrystals.all.first { $0.structure.cell.a != cell.a }).structure
        phase.replaceStructure(other)
        try library.update(phase)
        XCTAssertEqual(analysis.crystal, before, "the room keeps the copy it was shown")
        XCTAssertEqual(analysis.crystal.structure.cell.a, cell.a, accuracy: 1e-12)
        XCTAssertTrue(DiffractionPhases.isOutdated(phase, in: analysis))

        DiffractionPhases.set(phase, shown: true, in: analysis)
        XCTAssertEqual(analysis.crystal.structure.cell.a, other.cell.a, accuracy: 1e-9)
        XCTAssertFalse(DiffractionPhases.isOutdated(phase, in: analysis))
        XCTAssertNotEqual(analysis.crystal.identity, before.identity, "the caches see another crystal")
    }

    /// The readout CSV names the phase, its fingerprint and the lattice; the door says the same.
    func testTheExportNamesThePhaseAndItsLattice() {
        let structure = StandardCrystals.all[0].structure
        let crystal = DiffractionCrystal.phase(PhaseCrystal(id: "mp-81", name: "Au", structure: structure))
        let fingerprint = CrystalStructure.Snapshot(structure).fingerprint
        XCTAssertEqual(crystal.phaseText, "phase mp-81, fingerprint \(fingerprint)")
        XCTAssertNil(DiffractionCrystal.preset(StandardCrystals.all[0]).phaseText)
        var header = DiffractionExportHeader(fileName: "a.dm4", centreRow: 1, centreColumn: 1, centreSource: "typed", calibration: "none",
                                             deltaQ: nil, wavelengthAngstroms: nil, lengthPixels: nil, lengthMM: nil, fitVersusFilePercent: nil,
                                             crystal: "Au", crystalSHA256: nil, kMax: 2, tolerancePercent: 3)
        header.crystalPhase = crystal.phaseText
        header.crystalLattice = DiffractionCrystal.latticeText(structure.cell, ascii: true)
        let line = DiffractionExport.text(rows: [], header: header).split(separator: "\n")[4]
        XCTAssertEqual(line, "# crystal: Au (phase mp-81, fingerprint \(fingerprint)); lattice a \(String(format: "%.4f", structure.cell.a)) A; k_max 2 per A; tolerance 3 % of q")
    }
}
