//
//  InspectorSwitchRowTests.swift
//  An on/off in an inspector row is a switch (#1040, control-placement §3: "An on/off is a switch in a row; a checkbox only inside a
//  list"), its label hidden and the same noun as the row's, which VoiceOver reads; the row says no "Show". The STEM detector chart's
//  log axis reads powers of ten ("10⁻⁷"), never Charts' "1,0E-7".
//  Red before: the HRTEM section drew `Aperture  ☐ Objective aperture`, the Thermal Vibrations section `Frozen phonons  ☐ Frozen
//  phonons`, the Diffraction inspector's switches said "Show simulated spots" beside a row "Overlay"; no `DecadeAxis`.
//

import XCTest
@testable import macTEM

nonisolated final class InspectorSwitchRowTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Each `InspectorRow("…") { Toggle("…", …` in `path`: the row's title, the toggle's title and the toggle's modifier lines.
    private func switchRows(_ path: String) throws -> [(row: String, toggle: String, modifiers: String)] {
        let text = try source(path)
        let pattern = #"InspectorRow\("([^"\\]+)"\)\s*\{\s*Toggle\("([^"]*)",[^\n]*\n((?:[^\n]*\n){0,3})"#
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            func group(_ i: Int) -> String { Range(match.range(at: i), in: text).map { String(text[$0]) } ?? "" }
            return (group(1), group(2), group(3))
        }
    }

    func testEveryOnOffRowIsASwitchNamedAsItsRow() throws {
        let files = ["macTEM/UI/SimulationHRTEMSection.swift", "macTEM/UI/SimulationThermalSection.swift",
                     "macTEM/UI/DiffractionRoomInspector.swift", "macTEM/UI/DiffractionPowderSection.swift",
                     "macTEM/UI/DiffractionPrecipitateSection.swift"]
        var seen: [String] = []
        for file in files {
            for row in try switchRows(file) {
                seen.append(row.row)
                XCTAssertTrue(row.modifiers.contains(".toggleStyle(.switch).labelsHidden()"), "\(file): \(row.row) is not a switch")
                XCTAssertEqual(row.toggle, row.row, "\(file): the switch's label is the row's noun")
                XCTAssertFalse(row.row.hasPrefix("Show"), "\(file): \(row.row)")
            }
        }
        for noun in ["Objective aperture", "Frozen phonons", "Atom columns", "Fit scale", "Unit cell", "Simulated spots",
                     "Double diffraction", "Mark overlaps", "Variants"] {
            XCTAssertTrue(seen.contains(noun), "\(noun) is a switch row")
        }
    }

    /// `hkl labels` is no on/off since #1045 but a pop-up of three (Strongest · All · None), so it is not a switch row.
    func testTheHKLLabelsRowIsAPopUp() throws {
        XCTAssertFalse(try switchRows("macTEM/UI/DiffractionRoomInspector.swift").contains { $0.row == "hkl labels" })
        XCTAssertTrue(try source("macTEM/UI/DiffractionRoomInspector.swift").contains(#"Picker("hkl labels""#))
    }

    func testTheDetectorChartsAxisReadsPowersOfTen() {
        XCTAssertEqual(DecadeAxis.label(1e-7), "10⁻⁷")
        XCTAssertEqual(DecadeAxis.label(1), "10⁰")
        XCTAssertEqual(DecadeAxis.label(1e-2), "10⁻²")
        XCTAssertEqual(DecadeAxis.label(10), "10¹")
        // Eight decades crowd a 100 pt chart: every other one, from the top.
        XCTAssertEqual(DecadeAxis.values([3e-8, 0.5]).map(DecadeAxis.label), ["10⁻⁸", "10⁻⁶", "10⁻⁴", "10⁻²", "10⁰"])
        XCTAssertEqual(DecadeAxis.values([2e-3, 0.5]).map(DecadeAxis.label), ["10⁻³", "10⁻²", "10⁻¹", "10⁰"])
        XCTAssertEqual(DecadeAxis.values([0, -1]), [])
    }
}
