//
//  CBEDTimingDiagnosticTests.swift
//  TEMPORARY diagnostic for #1078 (never merged): times the parts of one CBED stretch on the default grid and reports them in a
//  failure message, so the CI log carries the numbers.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoMultislice
import SimulatoProbe
import TEMCore

nonisolated final class CBEDTimingDiagnosticTests: XCTestCase {

    private func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try body()
        return (ContinuousClock.now - start) / .seconds(1)
    }

    func testTimeOneStretchOnTheDefaultGrid() throws {
        var lines: [String] = []
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(0, 0, 1), thicknessNM: 150).get()
        for step in [0.25, 0.26, 0.5] {
            var settings = CBEDSettings()
            settings.angularStepMrad = step
            settings.largestThicknessNM = 6
            let plan = try CBEDRun.plan(built, settings: settings, volts: 200_000)
            let slab = built.slab, box = built.box
            let perPeriod = slab.sliceThicknesses.count / slab.repeats.z
            let unit = try AtomicStructure(box: box, atoms: slab.structure.atoms.filter { $0.position.z < box.z })
            let across = try unit.repeated(plan.repeats.x, plan.repeats.y, 1)
            let periodSlices = Array(slab.sliceThicknesses.prefix(perPeriod))
            let k = plan.planePeriods.first ?? 1
            let lazy = try Potential(structure: try across.repeated(1, 1, k), nx: plan.grid.x, ny: plan.grid.y,
                                     sliceThicknesses: Array([[Double]](repeating: periodSlices, count: k).joined()))
            var built0: ProjectedPotential?
            let tBuild = try seconds { built0 = try lazy.build() }
            let beam = try ElectronBeam(energy: 200_000)
            let wave = try Probe(beam: beam, grid: built0!.grid, aperture: Aperture(semiangleCutoff: 6.5)).build(at: plan.box / 2)
            let tMetalBuilt = try seconds { _ = try Multislice.run(wave, through: built0!, exitPlanes: .last, backend: .metal) }
            let tMetalBuilt2 = try seconds { _ = try Multislice.run(wave, through: built0!, exitPlanes: .last, backend: .metal) }
            let tMetalLazy = try seconds { _ = try Multislice.run(wave, through: lazy, exitPlanes: .last, backend: .metal) }
            let stamps = Stamps()
            let start = ContinuousClock.now
            let tRun = try seconds {
                _ = try CBEDRun.run(built, settings: settings, semiangleMrad: 6.5, volts: 200_000, specimen: "Si [0 0 1]",
                                    progress: { _ in stamps.add((ContinuousClock.now - start) / .seconds(1)) })
            }
            let head = "step \(step): grid \(plan.grid.x)x\(plan.grid.y), k \(k) periods (\(k * perPeriod) slices), \(plan.planePeriods.count) planes"
            let parts = "build \(fmt(tBuild)) s; metal(built) \(fmt(tMetalBuilt)) s then \(fmt(tMetalBuilt2)) s; metal(lazy) \(fmt(tMetalLazy)) s"
            let runText = "CBEDRun.run 6 nm \(fmt(tRun)) s; stamps " + stamps.values.suffix(8).map(fmt).joined(separator: " ")
            lines.append(head + "; " + parts + "; " + runText)
        }
        XCTFail("CBED timing (#1078):\n" + lines.joined(separator: "\n"))
    }

    private final class Stamps: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        func add(_ v: Double) { lock.lock(); stored.append(v); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}
