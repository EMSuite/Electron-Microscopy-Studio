//
//  SlabDrawingTests.swift
//  A Simulation document's slab in the crystal pane and its atom columns on the HRTEM image (#897, plan row MA5). Si [1 1 0]
//  (a 5.4309 Å): the box is a × a√2 across the beam, 16 atoms a period, and its projection is eight columns in four dumbbells a / 4
//  = 1.358 Å apart. The marks sit on the maxima of the projected potential the multislice computes from (the design's truth: "the
//  crystal view's projected columns coincide with the maxima of the projected potential"), within one pixel. The pane draws the slab
//  in the crystal's frame, so its third axis is the zone axis, and caps a large slab at whole periods, naming the count. Red before:
//  there was no slab drawing and no column marks.
//

import XCTest
import DiffractoCore
import ImagoCore
import SimulatoCore
import SimulatoMultislice
import simd
import TEMCore
import TEMSession

nonisolated final class SlabDrawingTests: XCTestCase {
    private let a = 5.4309

    private func silicon(nm: Double = 2) throws -> SimulationSpecimen.Built {
        try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: nm).get()
    }

    private func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }

    /// Mutation: atoms of another period counted, columns not merged along the beam, the merge not periodic across the box.
    func testSiliconOneOneZeroColumnsAreTheDumbbells() throws {
        let columns = SlabDrawing.projectedColumns(try silicon())
        XCTAssertEqual(columns.count, 8, "four dumbbells in a × a√2")
        for c in columns {
            XCTAssertEqual(c.atomicNumbers, [14])
            let partner = columns.filter { ($0.x, $0.y) != (c.x, c.y) }
                .map { other -> Double in
                    let dx = abs(other.x - c.x), dy = abs(other.y - c.y)
                    let px = min(dx, a - dx), py = min(dy, a * 2.0.squareRoot() - dy)
                    return (px * px + py * py).squareRoot()
                }.min() ?? 0
            XCTAssertEqual(partner, a / 4, accuracy: 1e-6, "each column has its dumbbell partner a / 4 away")
        }
    }

    /// The marks are the columns of every whole unit the image tiles, each on its position over the image's own sampling: Si [1 1 0]
    /// on 216 × 150 pixels of a / 108 by a√2 / 150 is two units down and one across, sixteen marks. And on the kit's grid of one unit
    /// (120 × 160, the HRTEM image's), each mark lies within one pixel of a maximum of the projected potential of the period the
    /// multislice runs. Mutation: rows and columns swapped (x along the columns), the sampling in nm read as Å, a column off by half
    /// a pixel's convention (centres at whole numbers), the tiles not added.
    func testTheColumnsSitOnTheImagesPixelsOfTheirPositions() throws {
        let built = try silicon()
        let unit = SlabDrawing.projectedColumns(built)
        let marks = SlabDrawing.columns(built, rows: 216, columns: 150, rowSampling: a / 108, columnSampling: a * 2.0.squareRoot() / 150)
        XCTAssertEqual(marks.count, 16)
        for m in marks {
            let x = (m.row * a / 108).truncatingRemainder(dividingBy: a)
            let y = m.column * a * 2.0.squareRoot() / 150
            XCTAssertTrue(unit.contains { abs($0.x - x) < 1e-9 && abs($0.y - y) < 1e-9 }, "mark (\(m.row), \(m.column)) is a column's position")
        }

        let box = built.box
        let nx = 120, ny = 160
        let period = try AtomicStructure(box: box, atoms: built.slab.structure.atoms.filter { $0.position.z < box.z })
        let potential = try ProjectedPotential(structure: period, nx: nx, ny: ny, sliceThickness: SimulationSpecimen.sliceThickness)
        var projected = [Double](repeating: 0, count: nx * ny)
        for slice in potential.slices { for i in projected.indices { projected[i] += slice.values[i] } }
        let onGrid = SlabDrawing.columns(built, rows: nx, columns: ny, rowSampling: box.x / Double(nx), columnSampling: box.y / Double(ny))
        XCTAssertEqual(onGrid.count, 8)
        for m in onGrid {
            // The strongest pixel within 5 pixels of the mark (periodic: the potential repeats with the box).
            var best = (value: -Double.infinity, row: 0, column: 0)
            let r0 = Int(m.row.rounded()), c0 = Int(m.column.rounded())
            for dr in -5...5 {
                for dc in -5...5 {
                    let r = ((r0 + dr) % nx + nx) % nx, c = ((c0 + dc) % ny + ny) % ny
                    let v = projected[r * ny + c]
                    if v > best.value { best = (v, r0 + dr, c0 + dc) }
                }
            }
            let distance = ((Double(best.row) - m.row) * (Double(best.row) - m.row)
                            + (Double(best.column) - m.column) * (Double(best.column) - m.column)).squareRoot()
            XCTAssertLessThanOrEqual(distance, 1, "the mark at (\(m.row), \(m.column)) sits on its column's potential maximum")
        }
    }

    /// The pane draws the slab itself in the crystal's frame: every atom, its box along the zone axis [1 1 0] (cubic: the Cartesian
    /// (1, 1, 0) / √2) to the slab's whole thickness, and the bonds' lengths of the diamond lattice (a√3 / 4) kept. Mutation: the
    /// box frame drawn as the crystal's (the third axis along z), the rotation's transpose, the cap applied to a small slab.
    func testTheDrawnSlabIsTheSlabInTheCrystalsFrame() throws {
        let built = try silicon(nm: 10)
        let drawn = SlabDrawing.drawn(built)
        XCTAssertFalse(drawn.isCapped)
        XCTAssertEqual(drawn.atoms.count, 16 * 13)
        XCTAssertEqual(drawn.total, 16 * 13)
        let beam = drawn.cell.columns.2
        XCTAssertEqual(length(beam), 13 * a * 2.0.squareRoot(), accuracy: 1e-9)
        let axis = beam / length(beam)
        XCTAssertEqual(axis.x, 1 / 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(axis.y, 1 / 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(axis.z, 0, accuracy: 1e-9)
        XCTAssertEqual(length(drawn.cell.columns.0), a, accuracy: 1e-9)
        XCTAssertEqual(length(drawn.cell.columns.1), a * 2.0.squareRoot(), accuracy: 1e-9)
        var nearest = Double.infinity
        for i in drawn.atoms.indices { for j in drawn.atoms.indices where j > i {
            nearest = min(nearest, length(drawn.atoms[i].position - drawn.atoms[j].position))
        }}
        XCTAssertEqual(nearest, a * 3.0.squareRoot() / 4, accuracy: 1e-6, "a bond of diamond Si")
        XCTAssertEqual(drawn.caption, "Slab \(UnitDisplay.number(a / 10, digits: 3)) × \(UnitDisplay.number(a * 2.0.squareRoot() / 10, digits: 3)) × "
                       + "\(UnitDisplay.number(13 * a * 2.0.squareRoot() / 10, digits: 3)) nm, 208 atoms")
    }

    /// The slab's depth order is the crystal's: a cell with gold at 0.9 c and carbon at 0.1 c, seen down [0 0 1], draws the gold 0.8 c
    /// above the carbon in the crystal's frame, as the cell has it (Si [1 1 0] has a mirror normal to the beam and cannot tell). The
    /// kit stores z as the depth below the entrance face (SimulatoKit 0.7.0, #126: gold at about 1 Å deep, carbon at about 9 Å),
    /// so drawing z as stored would turn the slab upside down. Mutation: depth drawn as height, the rotation transposed.
    func testTheDrawnSlabKeepsTheCrystalsDepthOrder() throws {
        let c = 10.0
        let layered = CrystalStructure(cell: UnitCell(a: 4, b: 4, c: c, alphaDeg: 90, betaDeg: 90, gammaDeg: 90),
                                       sites: [AtomSite(z: 79, fractional: SIMD3(0, 0, 0.9), occupancy: 1, label: "Au1"),
                                               AtomSite(z: 6, fractional: SIMD3(0.5, 0.5, 0.1), occupancy: 1, label: "C1")],
                                       operations: [])
        let built = try SimulationSpecimen.build(layered, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 1).get()
        XCTAssertEqual(built.periods, 1)
        let drawn = SlabDrawing.drawn(built)
        let stored = try XCTUnwrap(built.slab.structure.atoms.first { $0.atomicNumber == 79 })
        XCTAssertLessThan(stored.position.z, c / 2, "the kit stores gold near the entrance face (its depth, SimulatoKit 0.7.0)")
        let gold = try XCTUnwrap(drawn.atoms.first { $0.atomicNumber == 79 })
        let carbon = try XCTUnwrap(drawn.atoms.first { $0.atomicNumber == 6 })
        XCTAssertEqual(gold.position.z - carbon.position.z, 0.8 * c, accuracy: 1e-6, "gold above carbon, as in the cell")
        XCTAssertEqual(drawn.cell.columns.2.z, c, accuracy: 1e-9, "the box runs up the zone axis [0 0 1]")
    }

    /// A slab over the limit is drawn from the entrance face in whole periods, and the caption names how many of how many atoms and
    /// how deep. Mutation: the cap ignored, a period cut in half, the count not named.
    func testALargeSlabIsCappedAtWholePeriodsAndSaysSo() throws {
        let built = try silicon(nm: 10)
        let drawn = SlabDrawing.drawn(built, limit: 50)
        XCTAssertTrue(drawn.isCapped)
        XCTAssertEqual(drawn.atoms.count, 48, "three whole periods of 16")
        XCTAssertEqual(drawn.drawnDepth, 3 * built.box.z, accuracy: 1e-9)
        XCTAssertEqual(length(drawn.cell.columns.2), 3 * built.box.z, accuracy: 1e-9)
        XCTAssertTrue(drawn.caption.hasSuffix("48 of 208 atoms drawn, the first \(UnitDisplay.number(3 * built.box.z / 10, digits: 3)) nm"),
                      drawn.caption)
        XCTAssertEqual(SlabDrawing.drawnAtomLimit, 20_000)
    }

    /// The document's model: Atom columns starts off, its switch turns it on, and the columns it gives are the drawing's for the
    /// shown phase on the image; none are drawn before the image is of this specimen. Mutation: the switch not kept, another
    /// specimen's columns, columns without a phase, rings over an image of another specimen.
    @MainActor func testTheModelMarksTheSpecimensColumnsOnItsImage() throws {
        let model = SimulationModel()
        XCTAssertFalse(model.marksColumns)
        model.setMarksColumns(true)
        XCTAssertTrue(model.marksColumns)
        let phase = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        let image = CalibratedImage(width: 160, height: 120, pixels: [Float](repeating: 0, count: 120 * 160),
                                    x: AxisCalibration(scale: a * 2.0.squareRoot() / 160 / 10, unit: "nm"),
                                    y: AxisCalibration(scale: a / 120 / 10, unit: "nm"), fileName: "f", source: "f", voltage: 200_000)
        let columns = try XCTUnwrap(model.columns(crystal: phase, zoneAxis: SIMD3(1, 1, 0), on: image))
        let built = try XCTUnwrap(try? model.specimen(crystal: phase, zoneAxis: SIMD3(1, 1, 0)).get())
        XCTAssertEqual(columns, SlabDrawing.columns(built, rows: 120, columns: 160, rowSampling: a / 120 / 10 * 10,
                                                         columnSampling: a * 2.0.squareRoot() / 160 / 10 * 10), "the image's nm per pixel, in Å")
        XCTAssertEqual(columns.count, 8)
        XCTAssertNil(model.columns(crystal: nil, zoneAxis: SIMD3(1, 1, 0), on: image), "no phase, no columns")
        XCTAssertEqual(model.drawnSlab(crystal: phase, zoneAxis: SIMD3(1, 1, 0)), SlabDrawing.drawn(built))
        // No exit waves yet: the rings wait for the image of this specimen, and the switch says so.
        XCTAssertEqual(model.columnsBlocker(crystal: phase, zoneAxis: SIMD3(1, 1, 0)), "The rings wait for the image of this specimen.")
        XCTAssertNil(model.drawnColumns(crystal: phase, zoneAxis: SIMD3(1, 1, 0), on: image))
        // Place Beside's pair is at the measured image's scale: no rings on it, whatever the waves, and the switch says why (#898).
        XCTAssertTrue(model.setBeside(HRTEMBeside(measured: URL(fileURLWithPath: "/measured.tif"))))
        XCTAssertEqual(model.columnsBlocker(crystal: phase, zoneAxis: SIMD3(1, 1, 0)),
                       "Column rings show on the simulation alone; turn Place Beside off.")
        XCTAssertNil(model.drawnColumns(crystal: phase, zoneAxis: SIMD3(1, 1, 0), on: image))
        XCTAssertTrue(model.setBeside(nil))
        XCTAssertEqual(model.columnsBlocker(crystal: phase, zoneAxis: SIMD3(1, 1, 0)), "The rings wait for the image of this specimen.")
    }
}
