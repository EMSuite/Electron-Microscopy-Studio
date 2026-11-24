//
//  DynamicalSpotsTests.swift
//  A Simulation document's dynamical spot intensities (#911, plan row MA8): SimulatoKit's `BeamIntensities` read in the HRTEM exit
//  waves (one orthogonal unit of Si [1 1 0], every whole period), by hkl, and drawn by the Diffraction room's overlay in place of the
//  kinematical intensities, the forbidden 002 as an open ring. The kit is pinned to abTEM 1.0.10 (SimulatoKit's beam-intensity pins);
//  this file pins the app's use of it: the exit planes at whole periods, the hkl naming, the placement and the method line. Red
//  before: the overlay had kinematical intensities only.
//
//  Si a = 5.4309 Å along [1 1 0]: a period is a√2 = 7.6805 Å, so 2 nm is 3 periods. 002 is forbidden in diamond, yet 1̄11 + 11̄1
//  lands there: the multislice gives it intensity after one period.
//

import XCTest
import DiffractoCore
import SimulatoCore
import SimulatoMultislice
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class DynamicalSpotsTests: XCTestCase {

    private func silicon() throws -> (SimulationSpecimen.Built, HRTEMExitWaves) {
        let built = try SimulationSpecimen.build(CrystalPresets.silicon, zoneAxis: SIMD3(1, 1, 0), thicknessNM: 2).get()
        return (built, try HRTEMImage.exitWaves(built, optics: HRTEMOptics(), specimen: "Si [1 1 0]"))
    }

    /// Each stored wave's beams are the kit's, named by hkl, with the kit's thickness equal to the stored wave's whole periods (so the
    /// exit planes passed are the run's own), and no 000. Mutation: the planes off by one slice; hkl read in another order; 000 kept.
    func testTheBeamsAreTheKitsAtEveryStoredPeriod() throws {
        let (built, exit) = try silicon()
        let spots = try DynamicalSpots(exit, built: built)
        let perPeriod = built.slab.sliceThicknesses.count / built.slab.repeats.z
        let kit = try BeamIntensities(exitWaves: exit.waves, of: built.slab, exitPlanes: .afterSlices(exit.planePeriods.map { $0 * perPeriod - 1 }))
        XCTAssertEqual(spots.intensities.count, 3)
        XCTAssertEqual(spots.thicknessesNM.count, 3)
        for t in 0 ..< 3 {
            XCTAssertEqual(kit.thicknesses[t] / 10, spots.thicknessesNM[t], accuracy: 1e-9, "the kit's slices end at period \(t + 1)")
            XCTAssertNil(spots.intensities[t][.zero])
            for (beam, value) in zip(kit.beams, kit.intensities[t]) where beam.hkl != .zero {
                XCTAssertEqual(spots.intensities[t][MillerIndex(beam.hkl.x, beam.hkl.y, beam.hkl.z)], value)
            }
        }
        XCTAssertEqual(spots.specimen, "Si [1 1 0]")
        XCTAssertEqual(spots.beams(at: 9).thicknessNM, spots.thicknessesNM[2], "an index past the last is the thickest")
    }

    /// Every beam is in the zero-order Laue zone of [1 1 0] (h + k = 0 for Si's cubic cell), and the forbidden 002 has intensity once
    /// the wave has crossed a period: the double diffraction kinematical theory leaves out. Mutation: a beam outside the zone kept.
    func testSilicons002HasDynamicalIntensity() throws {
        let (built, exit) = try silicon()
        let spots = try DynamicalSpots(exit, built: built)
        for hkl in spots.intensities[2].keys { XCTAssertEqual(hkl.h + hkl.k, 0, "\(hkl) is not in [1 1 0]") }
        let i002 = try XCTUnwrap(spots.intensities[2][MillerIndex(0, 0, 2)])
        let i111 = try XCTUnwrap(spots.intensities[2][MillerIndex(1, -1, 1)])
        XCTAssertGreaterThan(i002, 1e-5, "002 is excited by 1̄11 + 11̄1")
        XCTAssertGreaterThan(i111, i002, "the allowed 11̄1 is stronger")
    }

    /// The overlay draws the beams in place of the kinematical intensities: a beam the kinematical pattern has is a spot at the
    /// kinematical spot's own place, 002 an open ring, relative to the strongest beam drawn; the summary is unchanged in form.
    /// Mutation: the beam placed by another frame than the kit's lab coordinates; forbidden beams drawn as spots; relative over the
    /// kinematical maximum.
    @MainActor func testTheOverlayDrawsTheBeamsWith002AsARing() throws {
        let (built, exit) = try silicon()
        let beams = try DynamicalSpots(exit, built: built).beams(at: 2)
        let image = CalibratedImage(width: 256, height: 256, pixels: [Float](repeating: 1, count: 256 * 256), x: nil, y: nil,
                                    fileName: "blank", source: "test", voltage: 200_000)
        let analysis = DiffractionAnalysis()
        analysis.bind(image)
        analysis.typedDeltaQ = 0.01
        analysis.simulation.isShown = true
        analysis.simulation.zoneAxis = SIMD3(1, 1, 0)
        analysis.setCrystal(.preset(try XCTUnwrap(StandardCrystals.named("Si"))))
        let kinematical = try XCTUnwrap(analysis.simulatedSpots(image: image)).get()
        let dynamical = try XCTUnwrap(analysis.simulatedSpots(image: image, dynamical: beams)).get()

        let ring = try XCTUnwrap(dynamical.first { $0.hkl == MillerIndex(0, 0, 2) })
        XCTAssertTrue(ring.isDoubleDiffraction, "002 is forbidden: an open ring")
        XCTAssertEqual(ring.intensity, beams.intensities[MillerIndex(0, 0, 2)])
        XCTAssertEqual(hypot(ring.row - 128, ring.column - 128), 2 / 5.4309 / 0.01, accuracy: 1e-6)
        // Open rings are exactly diamond's forbidden reflections, not allowed beams the excitation envelope left out of the pattern.
        func allowed(_ m: MillerIndex) -> Bool {
            let odd = [m.h, m.k, m.l].allSatisfy { $0 % 2 != 0 }, even = [m.h, m.k, m.l].allSatisfy { $0 % 2 == 0 }
            return odd || (even && (m.h + m.k + m.l) % 4 == 0)
        }
        for spot in dynamical { XCTAssertEqual(spot.isDoubleDiffraction, !allowed(spot.hkl), "\(spot.hkl)") }
        for spot in dynamical where !spot.isDoubleDiffraction {
            guard let twin = kinematical.first(where: { $0.hkl == spot.hkl }) else { continue }
            XCTAssertEqual(spot.row, twin.row, accuracy: 1e-9)
            XCTAssertEqual(spot.column, twin.column, accuracy: 1e-9)
        }
        XCTAssertEqual(dynamical.first?.relative, 1)
        XCTAssertEqual(dynamical.map(\.intensity), dynamical.map(\.intensity).sorted(by: >), "strongest first")
        XCTAssertTrue(beams.methodLine.hasPrefix("Dynamical · Si [1 1 0] · 2.3 nm · 200 kV · "), beams.methodLine)
    }

    /// The switch is off by default, and the model gives no beams while it is off or before a run. Mutation: beams before a run;
    /// Dynamical on by default.
    @MainActor func testDynamicalIsASwitchAndNeedsARun() async throws {
        let model = SimulationModel()
        model.setThickness(nm: 2)
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        XCTAssertFalse(model.isDynamical)
        model.setDynamical(true)
        XCTAssertNil(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0)), "no run yet")
        await model.updateExitWaves(crystal: si, zoneAxis: SIMD3(1, 1, 0))
        let beams = try XCTUnwrap(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0)))
        XCTAssertEqual(beams.thicknessNM, try XCTUnwrap(model.exitWaves).thicknessNM(at: 2), accuracy: 1e-12, "the thickest by default")
        model.setThicknessIndex(0)
        XCTAssertEqual(try XCTUnwrap(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0))).thicknessNM,
                       try XCTUnwrap(model.exitWaves).thicknessNM(at: 0), accuracy: 1e-12, "the slider's thickness")
        XCTAssertNil(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(0, 0, 1)), "the waves are of [1 1 0]")
        model.setDynamical(false)
        XCTAssertNil(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0)))
    }

    /// Thermal vibrations switched on after a static run, before Simulate: the static waves stay stored but are not current, so no
    /// beams are drawn, the slider's waves are stale, and the room says why. Mutation: the absence read from the stored spots only
    /// (nil here); the beams kept from the static waves.
    @MainActor func testThermalOnBeforeARunSaysWhyAndDrawsNoBeams() async throws {
        let model = SimulationModel()
        model.setThickness(nm: 2)
        let si = DiffractionCrystal.phase(PhaseCrystal(id: "mp-149", name: "Si", structure: CrystalPresets.silicon))
        model.setDynamical(true)
        await model.updateExitWaves(crystal: si, zoneAxis: SIMD3(1, 1, 0))
        XCTAssertNotNil(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0)))
        XCTAssertNil(model.dynamicalAbsence(crystal: si, zoneAxis: SIMD3(1, 1, 0)))
        XCTAssertTrue(model.setThermal(HRTEMThermal(sigmas: [14: 0.1], configurations: 2)))
        await model.updateExitWaves(crystal: si, zoneAxis: SIMD3(1, 1, 0))
        XCTAssertFalse(model.exitWavesAreCurrent(crystal: si, zoneAxis: SIMD3(1, 1, 0)), "the slider hides")
        XCTAssertNil(model.dynamicalBeams(crystal: si, zoneAxis: SIMD3(1, 1, 0)))
        XCTAssertEqual(model.dynamicalAbsence(crystal: si, zoneAxis: SIMD3(1, 1, 0)), SimulationModel.thermalDynamicalSentence)
        model.setDynamical(false)
        XCTAssertNil(model.dynamicalAbsence(crystal: si, zoneAxis: SIMD3(1, 1, 0)), "nothing to say with Dynamical off")
    }

    /// Dynamical's beams are those of the exact axis: a turn about the beam and Flip keep the drawn orientation along it; a 0.05°
    /// tilt and the antiparallel axis do not. Mutation: a looser cosine; the absolute value of the cosine.
    func testOnlyTheExactAxisIsAlong() throws {
        let cell = CrystalPresets.silicon.cell, axis = SIMD3(1, 1, 0)
        let exact = try CrystalOrientation(zoneAxis: axis, inPlaneAngle: 0, cell: cell)
        XCTAssertTrue(ZoneAxisOverlay.isAlong(exact, zoneAxis: axis, cell: cell))
        XCTAssertTrue(ZoneAxisOverlay.isAlong(try CrystalOrientation(zoneAxis: axis, inPlaneAngle: 0.7, cell: cell), zoneAxis: axis, cell: cell))
        XCTAssertTrue(ZoneAxisOverlay.isAlong(exact.rotatedInPlane(by: .pi), zoneAxis: axis, cell: cell), "Flip")
        XCTAssertFalse(ZoneAxisOverlay.isAlong(exact.tilted(by: SIMD2(0.05 * .pi / 180, 0)), zoneAxis: axis, cell: cell))
        XCTAssertFalse(ZoneAxisOverlay.isAlong(try CrystalOrientation(zoneAxis: SIMD3(-1, -1, 0), inPlaneAngle: 0, cell: cell),
                                               zoneAxis: axis, cell: cell))
    }

    /// The Spots table's I dyn % (#911): an explained spot takes its hkl's beam, in percent to three decimals; an unexplained spot, an hkl
    /// that is no beam and Dynamical off show a dash. Mutation: the fraction left unscaled; the beams read by another hkl.
    func testTheSpotTableReadsEachSpotsBeam() {
        let beams = DynamicalBeams(intensities: [MillerIndex(1, 1, 1): 0.0123456, MillerIndex(0, 0, 2): 0.0004], thicknessNM: 9.98,
                                   specimen: "Si [1 1 0]", volts: 200_000)
        func row(_ hkl: MillerIndex?) -> PatternIndexing.SpotRow {
            PatternIndexing.SpotRow(id: UUID(), number: 1, hkl: hkl, radiusPx: 30, q: 0.3, d: 3.1, dExpected: 3.13, deltaPercent: -1,
                                    phase: hkl == nil ? "" : "Si")
        }
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(DiffractionSpotFormat.cell(.dynamical, row(MillerIndex(1, 1, 1)).withDynamical(beams), locale: locale), "1.235")
        XCTAssertEqual(DiffractionSpotFormat.cell(.dynamical, row(MillerIndex(0, 0, 2)).withDynamical(beams), locale: locale), "0.040")
        XCTAssertEqual(DiffractionSpotFormat.cell(.dynamical, row(MillerIndex(2, 2, 0)).withDynamical(beams), locale: locale), UnitDisplay.noValue)
        XCTAssertEqual(DiffractionSpotFormat.cell(.dynamical, row(nil).withDynamical(beams), locale: locale), UnitDisplay.noValue)
        XCTAssertEqual(DiffractionSpotFormat.cell(.dynamical, row(MillerIndex(1, 1, 1)).withDynamical(nil), locale: locale), UnitDisplay.noValue)
    }
}
