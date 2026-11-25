//
//  CBEDTiltTests.swift
//  A Simulation document's CBED pattern at the beam tilt drawn by hand (#1013): the orientation read as SimulatoKit's small-angle
//  probe tilt (abTEM 1.0.10's `Probe(tilt=…)`) and back, the run at that tilt against abTEM's own run of the same slab
//  (Fixtures/cbed-tilt.json, tools/parity/cbed-tilt/cbed_tilt.py), the disc the overlay's Laue circle excites being the bright
//  one, the refusal past the small-angle range, and Measure Thickness closing on a tilted simulated pattern. Red before: the run
//  sent the beam down the exact zone axis whatever the drawn orientation, and its key had no tilt.
//
//  Si [1 1 0] at 200 kV: the slab's box x is [0 0 1̄] and y [1̄ 1 0] (`SlabBuilder`, py4DSTEM's x reference), so 2 2̄ 0 sits
//  √8 / a = 0.5208 Å⁻¹ along −y (left of the direct beam). abTEM's tilt t excites a zero-order g at t · g = −λ|g|²/2: 2 2̄ 0 at
//  t_y = +λ|g| / 2 = +6.53 mrad. The tilt along x, at right angles to g, takes the beam off the 1 1 1 discs.
//

import XCTest
import DiffractoCore
import DiffractoGeometry
import DiffractoScattering
import ImagoCore
import SimulatoMultislice
import TEMCore
import TEMSession

nonisolated final class CBEDTiltTests: XCTestCase {

    private static let volts = 200_000.0
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/cbed-tilt.json")

    /// The fixture, read per test: a shared static of `[String: Any]` is not Sendable under Swift 6.
    private var reference: [String: Any] {
        get throws {
            let data = try Data(contentsOf: Self.fixture)
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    /// Si [1 1 0]'s slab and its box as an orientation (the zone axis at the specimen's in-plane angle).
    private func slab() throws -> (built: SimulationSpecimen.Built, box: CrystalOrientation) {
        let si = CrystalPresets.silicon
        let built = try SimulationSpecimen.build(si, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2).get()
        let box = try CrystalOrientation(zoneAxis: SIMD3(1, 1, 0), inPlaneAngle: built.inPlaneAngle, cell: si.cell)
        return (built, box)
    }

    /// "2 -2 0" as the fixture writes it.
    private func hkl(_ key: String) throws -> MillerIndex {
        let v = key.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(v.count, 3, key)
        return MillerIndex(v[0], v[1], v[2])
    }

    /// The sum of `pattern` over the pixels within the semiangle of g's disc, the script's `disc_sums`: the centre at g / Δq
    /// from the direct beam's pixel, g in the box (row = box x, column = box y).
    private func discSum(_ pattern: CBEDPattern, index: Int, g: SIMD3<Double>) -> Double {
        let lambda = ElectronWavelength.angstroms(volts: pattern.volts)
        let rows = pattern.rows, columns = pattern.columns
        let centre = SIMD2(Double(rows / 2) + g.x / pattern.rowDeltaQ, Double(columns / 2) + g.y / pattern.columnDeltaQ)
        let radius = SIMD2(pattern.semiangleMrad / 1000 / (pattern.rowDeltaQ * lambda), pattern.semiangleMrad / 1000 / (pattern.columnDeltaQ * lambda))
        var sum = 0.0
        let values = pattern.patterns[index]
        for r in max(0, Int(centre.x - radius.x) - 1) ... min(rows - 1, Int(centre.x + radius.x) + 1) {
            for c in max(0, Int(centre.y - radius.y) - 1) ... min(columns - 1, Int(centre.y + radius.y) + 1) {
                let u = (Double(r) - centre.x) / radius.x, v = (Double(c) - centre.y) / radius.y
                if u * u + v * v <= 1 { sum += Double(values[r * columns + c]) }
            }
        }
        return sum
    }

    /// The fixture's frame is the app's: the slab's box puts 2 2̄ 0 along −y and 0 0 2 along −x, which is the script's
    /// box x = [0 0 1̄], y = [1̄ 1 0]. Mutation: the slab's x along [0 0 1]; rows along the box's y.
    func testTheSlabsBoxIsTheScriptsFrame() throws {
        let (_, box) = try slab()
        let si = CrystalPresets.silicon, a = 5.4309
        let g220 = box.labCoordinates(of: si.cell.gVector(MillerIndex(2, -2, 0)))
        XCTAssertEqual(g220.x, 0, accuracy: 1e-9)
        XCTAssertEqual(g220.y, -8.0.squareRoot() / a, accuracy: 1e-9)
        XCTAssertEqual(g220.z, 0, accuracy: 1e-9)
        let g002 = box.labCoordinates(of: si.cell.gVector(MillerIndex(0, 0, 2)))
        XCTAssertEqual(g002.x, -2 / a, accuracy: 1e-9)
        XCTAssertEqual(g002.y, 0, accuracy: 1e-9)
    }

    /// The kit's tilt of an orientation and the orientation of a tilt are inverse; the zone axis is 0; a Tilt-tool drag of 1° down
    /// the rows turns the crystal +1° about lab y, so the beam runs 1° along +x of the box: a tilt of +17.45 mrad along x. Mutation:
    /// the sign of b_x or b_y kept; the inverse's two angles swapped.
    func testTheTiltDrawnByHandIsTheKitsTiltAndBack() throws {
        let (_, box) = try slab()
        XCTAssertEqual(CBEDTilt.tilt(of: box, slab: box), SIMD2(0, 0))
        for t in [SIMD2(35.0, 6.53), SIMD2(-12.5, 0), SIMD2(0, -40), SIMD2(30, -30)] {
            let o = CBEDTilt.orientation(slab: box, tiltMrad: t)
            let back = try XCTUnwrap(CBEDTilt.tilt(of: o, slab: box))
            XCTAssertEqual(back.x, t.x, accuracy: 1e-9, "\(t)")
            XCTAssertEqual(back.y, t.y, accuracy: 1e-9, "\(t)")
            // The beam lies (tan tx, tan ty) off the zone axis, away from the tilt: b = (−tan tx, −tan ty, 1) / n in the box.
            let b = box.labCoordinates(of: o.beamDirection)
            XCTAssertEqual(b.x / b.z, -tan(t.x / 1000), accuracy: 1e-12)
            XCTAssertEqual(b.y / b.z, -tan(t.y / 1000), accuracy: 1e-12)
        }
        // The Tilt tool: 1° down the rows (`ZoneAxisOverlay.tilted`).
        let dragged = ZoneAxisOverlay.tilted(box, drag: SIMD2(1, 0) / ZoneAxisOverlay.degreesPerPoint)
        let t = try XCTUnwrap(CBEDTilt.tilt(of: dragged, slab: box))
        XCTAssertEqual(t.x, 17.45, accuracy: 0.01)
        XCTAssertEqual(t.y, 0, accuracy: 0.01)
    }

    /// The run at the fixture's tilt is abTEM's run of the same slab: each disc's share of the probe within 1 % (plus 1e−4 of the
    /// probe), at every stored thickness, and the brightest diffracted disc is abTEM's. The overlay at the run's tilt (the
    /// orientation the CBED item draws) puts its strongest spot, the reflection its Laue circle excites, on that disc. Mutation:
    /// the tilt's sign flipped (the opposite 2̄ 2 0 lights up); the tilt along x and y swapped; the tilt left off the probe.
    func testTheTiltedRunIsAbTEMsAndLightsTheDiscTheOverlayExcites() throws {
        let doc = try reference
        let (built, box) = try slab()
        let si = CrystalPresets.silicon
        let tiltValues = try XCTUnwrap(doc["tilt_mrad"] as? [Double])
        let tilt = SIMD2(tiltValues[0], tiltValues[1])
        let given = try XCTUnwrap(doc["settings"] as? [String: Double])
        var settings = CBEDSettings()
        settings.angularStepMrad = try XCTUnwrap(given["angular_step_mrad"])
        settings.edgeMrad = try XCTUnwrap(given["edge_mrad"])
        settings.largestThicknessNM = try XCTUnwrap(given["largest_thickness_nm"])
        settings.thicknessStepNM = try XCTUnwrap(given["thickness_step_nm"])
        let semiangle = try XCTUnwrap(doc["semiangle_mrad"] as? Double)
        let pattern = try CBEDRun.run(built, settings: settings, semiangleMrad: semiangle, volts: Self.volts, specimen: "Si [1 1 0]",
                                      shortestG: si.cell.gLength(MillerIndex(1, 1, 1)), tiltMrad: tilt, zoneAxis: SIMD3(1, 1, 0),
                                      reference: true)
        XCTAssertEqual(pattern.tiltMrad, tilt)
        let shape = try XCTUnwrap(doc["shape"] as? [Int])
        XCTAssertEqual([pattern.rows, pattern.columns], shape)
        let cases = try XCTUnwrap(doc["cases"] as? [[String: Any]])
        XCTAssertEqual(pattern.patterns.count, cases.count)

        // The overlay at the run's tilt, as `refreshCBEDPattern` draws it on the CBED item: the reflection on its Laue circle (the
        // kit's smallest excitation error) and where the overlay draws it.
        let drawn = CBEDTilt.orientation(slab: box, tiltMrad: tilt)
        var overlay = ZoneAxisOverlay.Settings()
        overlay.zoneAxis = SIMD3(1, 1, 0)
        overlay.indexed = drawn
        let simulator = try SpotPatternSimulator(structure: si, kMax: 1)
        let laue = try XCTUnwrap(try simulator.pattern(orientation: drawn, volts: Self.volts, settings: overlay.patternSettings).spots
            .min { abs($0.excitationError) < abs($1.excitationError) })
        XCTAssertEqual(laue.hkl, MillerIndex(2, -2, 0), "the overlay's Laue circle runs through 2 2̄ 0")
        let deltaQ = (pattern.rowDeltaQ + pattern.columnDeltaQ) / 2
        let spots = try ZoneAxisOverlay.spots(simulator: simulator, settings: overlay, volts: Self.volts,
                                              calibration: DiffractionCalibration(source: .typed, deltaQ: deltaQ, ring: nil),
                                              centre: DiffractionCentre(row: Double(pattern.rows / 2), column: Double(pattern.columns / 2), source: .typed),
                                              width: pattern.columns, height: pattern.rows)
        let excited = try XCTUnwrap(spots.first { $0.hkl == laue.hkl }, "the overlay draws 2 2̄ 0")

        for (index, item) in cases.enumerated() {
            let thickness = try XCTUnwrap(item["thickness_nm"] as? Double)
            XCTAssertEqual(pattern.thicknessesNM[index], thickness, accuracy: 1e-9)
            let discs = try XCTUnwrap(item["discs"] as? [String: Double])
            var brightest: (hkl: MillerIndex, sum: Double)?
            for (key, expected) in discs.sorted(by: { $0.key < $1.key }) {
                let h = try hkl(key)
                let sum = discSum(pattern, index: index, g: box.labCoordinates(of: si.cell.gVector(h)))
                XCTAssertEqual(sum, expected, accuracy: 0.01 * expected + 1e-4, "\(key) at \(thickness) nm")
                if h != MillerIndex(0, 0, 0), sum > brightest?.sum ?? -1 { brightest = (h, sum) }
            }
            let named = try hkl(try XCTUnwrap(item["brightest_diffracted"] as? String))
            XCTAssertEqual(brightest?.hkl, named, "abTEM's brightest disc at \(thickness) nm")
            XCTAssertEqual(brightest?.hkl, excited.hkl, "the overlay's excited spot is the bright disc at \(thickness) nm")
        }
        // The overlay's spot sits on that disc's centre.
        let g = box.labCoordinates(of: si.cell.gVector(excited.hkl))
        XCTAssertEqual(excited.row, Double(pattern.rows / 2) + g.x / deltaQ, accuracy: 1)
        XCTAssertEqual(excited.column, Double(pattern.columns / 2) + g.y / deltaQ, accuracy: 1)
        XCTAssertTrue(pattern.methodLine(at: 0).contains("beam tilt \(UnitDisplay.number(tilt.x, digits: 3)), "
                                                         + "\(UnitDisplay.number(tilt.y, digits: 3)) mrad (x, y)"), pattern.methodLine(at: 0))
    }

    /// Measure Thickness closes on a simulated pattern (#916, #1013): Si [1 1 0] tilted (45, 6.53) mrad, so 2 2̄ 0 is the one strong
    /// reflection, stored every 50 nm to 250 nm; on the pattern of 250 nm (not the first stored) the room's measurement finds the
    /// 2 2̄ 0 disc and gives 250 nm within the method's 3 % (docs/parity.md). The run is the app's, on Metal where this Mac has it
    /// (2604 slices on a 1200 × 1120 grid). In abTEM 1.0.10 (float32, tools/parity/cbed-tilt/cbed_tilt.py's slab, this measurement
    /// ported to NumPy with DiffractoKit's twin of the fit) the same run measured 247.1 nm (−1.2 %), and 150.4 and 197.0 nm at
    /// the stored 150 and 200 nm. Mutation: the tilt left off the probe (no disc stands out: the
    /// zone axis puts every Bragg condition outside its disc); the tilt's sign flipped (2̄ 2 0 lights up, and the disc is found
    /// on the other side).
    func testMeasureThicknessClosesOnATiltedSimulatedPattern() throws {
        let (built, box) = try slab()
        let si = CrystalPresets.silicon
        var settings = CBEDSettings()
        settings.angularStepMrad = 1
        settings.edgeMrad = 20
        settings.largestThicknessNM = 250
        settings.thicknessStepNM = 50
        let pattern = try CBEDRun.run(built, settings: settings, semiangleMrad: 3.9, volts: Self.volts, specimen: "Si [1 1 0]",
                                      shortestG: si.cell.gLength(MillerIndex(1, 1, 1)), tiltMrad: SIMD2(45, 6.53),
                                      zoneAxis: SIMD3(1, 1, 0))
        let index = pattern.index(nearest: 250)
        XCTAssertGreaterThan(index, 0, "a stored thickness other than the first")
        let stored = pattern.thicknessesNM[index]
        XCTAssertEqual(stored, 250, accuracy: 0.5)
        let image = pattern.image(at: index, name: "CBED of Simulation 1")
        let centre = SIMD2(Double(pattern.rows / 2), Double(pattern.columns / 2))
        let families = try DiffractionCompute.list(of: si, kMax: 1).families.map(\.family)
        let m = try CBEDThickness.measure(image: image, centre: centre, deltaQ: pattern.columnDeltaQ, structure: si, families: families,
                                          phase: "Si", volts: Self.volts)
        // The disc found is 2 2̄ 0's, where the box puts it (along −y, the columns to the left).
        let g = box.labCoordinates(of: si.cell.gVector(MillerIndex(2, -2, 0)))
        XCTAssertEqual(m.discs.diffracted.x, centre.x + g.x / pattern.rowDeltaQ, accuracy: 2, "the 2 2̄ 0 disc's row")
        XCTAssertEqual(m.discs.diffracted.y, centre.y + g.y / pattern.columnDeltaQ, accuracy: 2, "the 2 2̄ 0 disc's column")
        XCTAssertEqual(m.discs.gLength, si.cell.gLength(MillerIndex(2, 2, 0)), accuracy: 1e-12)
        XCTAssertEqual(m.verdict, "found", m.sentence)
        XCTAssertEqual(try XCTUnwrap(m.thicknessNM, m.sentence), stored, accuracy: 0.03 * stored, m.sentence)
    }

    /// Past the small-angle range the run is refused in words before it starts, and the key and method line carry the tilt.
    /// Mutation: the limit on one component, not the angle; no refusal.
    @MainActor func testATiltPastTheRangeIsRefusedAndTheKeyCarriesIt() throws {
        let (built, _) = try slab()
        XCTAssertNil(CBEDTilt.refusal(SIMD2(CBEDTilt.largestMrad, 0), zoneAxis: SIMD3(1, 1, 0)))
        let past = SIMD2(40.0, 40.0) // 56.5 mrad off the axis, each component inside
        let sentence = try XCTUnwrap(CBEDTilt.refusal(past, zoneAxis: SIMD3(1, 1, 0)))
        XCTAssertTrue(sentence.hasPrefix("The beam is tilted 3.24° (56.5 mrad) off [110]; CBED simulates a beam tilt of at most 2.86° (50 mrad)"), sentence)
        XCTAssertThrowsError(try CBEDRun.run(built, settings: CBEDSettings(), semiangleMrad: 3.9, volts: Self.volts, specimen: "Si [1 1 0]",
                                             tiltMrad: past, zoneAxis: SIMD3(1, 1, 0), reference: true)) {
            XCTAssertEqual(($0 as? CBEDTiltRefusal)?.sentence, sentence)
        }
        let model = CBEDModel()
        let zone = model.key(source: "Si", zoneAxis: SIMD3(1, 1, 0), maximumStrain: 0.001, volts: Self.volts, semiangleMrad: 3.9)
        let tilted = model.key(source: "Si", zoneAxis: SIMD3(1, 1, 0), maximumStrain: 0.001, volts: Self.volts, semiangleMrad: 3.9,
                               tiltMrad: SIMD2(35, 6.53))
        XCTAssertNotEqual(zone, tilted, "a new tilt is a new run")
        XCTAssertEqual(zone.tiltMrad, .zero)
        XCTAssertNil(CBEDTilt.methodPart(.zero))
        XCTAssertEqual(CBEDTilt.note(SIMD2(35, 6.53), zoneAxis: SIMD3(1, 1, 0)),
                       "The beam is tilted 2.04° off [110] by hand: 35, 6.53 mrad along the rows and columns.")
    }
}
