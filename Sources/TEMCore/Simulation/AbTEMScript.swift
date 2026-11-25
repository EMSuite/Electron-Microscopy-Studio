//
//  AbTEMScript.swift
//  Role: a Simulation document's HRTEM run written as an abTEM script (#915, plan row MA11), so a person reruns it in Python, changes
//        it, or checks the app. The script rebuilds the run from the app's own numbers: the specimen atom for atom (the slab the app
//        built, so no orientation step can differ), the grid, the slices, the stored exit planes, the voltage, the lens and the defocus
//        and thickness the image is at. Run with abTEM 1.0.10 and ASE 3.29.0, a static run reproduces the app's image at the kit's pin
//        (SimulatoKit's parity is abTEM 1.0.10, float64). What abTEM cannot take from the app is written as a comment, never dropped:
//        the frozen-phonon configurations are drawn by NumPy's generator there and by the kit's seeded one here, so the two agree as
//        ensembles, not configuration by configuration.
//
//  Numbers are written in Swift's shortest round-trip form ("5.4309", "1e-07"), which Python reads back to the same double.
//

import DiffractoCore
import Foundation
import SimulatoCore

package nonisolated enum AbTEMScript {
    /// The versions the script is written for: SimulatoKit's pins (its docs/parity.md).
    package static let abTEMVersion = "1.0.10"
    package static let aseVersion = "3.29.0"

    /// One HRTEM run as the image shows it.
    package struct Run: Sendable {
        /// The specimen the exit waves were computed on: one orthogonal unit across for a static lattice, the frozen-phonon supercell
        /// otherwise.
        package var built: SimulationSpecimen.Built
        package var optics: HRTEMOptics
        package var defocusNM: Double
        /// The periods the exit waves were stored at, and which of them the image shows.
        package var planePeriods: [Int]
        package var planeIndex: Int
        /// The frozen phonons; nil is the static lattice.
        package var thermal: HRTEMThermal?
        /// "Si [1 1 0]", and the image's method line.
        package var specimen: String
        package var methodLine: String
        /// "Electron Microscopy Studio 2.6.0, SimulatoKit 0.7.0": what wrote it.
        package var writtenBy: String

        package init(built: SimulationSpecimen.Built, optics: HRTEMOptics, defocusNM: Double, planePeriods: [Int], planeIndex: Int,
                     thermal: HRTEMThermal?, specimen: String, methodLine: String, writtenBy: String) {
            self.built = built
            self.optics = optics
            self.defocusNM = defocusNM
            self.planePeriods = planePeriods
            self.planeIndex = planeIndex
            self.thermal = thermal
            self.specimen = specimen
            self.methodLine = methodLine
            self.writtenBy = writtenBy
        }
    }

    /// "Electron Microscopy Studio 2.6.0, SimulatoKit 0.7.0": the app and the kit the run was made with.
    package static func writtenBy(appVersion: String) -> String {
        let kit = SEMReferenceVersions.builtWith.first { $0.name == "SimulatoKit" }.map { ", SimulatoKit \($0.value)" } ?? ""
        return "\(AppName.display) \(appVersion)\(kit)"
    }

    /// The script's file name: "Si [1 1 0] HRTEM.py", with a path separator or colon in the phase's name made a hyphen.
    package static func fileName(_ run: Run) -> String {
        "\(oneLine(run.specimen).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")) HRTEM.py"
    }

    /// Text for a comment line: line breaks made spaces, so a name cannot end the comment.
    static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    /// The script of `run`.
    package static func text(_ run: Run) throws -> String {
        let slab = run.built.slab
        let periods = slab.repeats.z
        let perPeriod = slab.sliceThicknesses.count / max(periods, 1)
        let plane = min(max(run.planeIndex, 0), run.planePeriods.count - 1)
        let thermal = run.thermal
        // A static lattice runs one orthogonal unit across, repeated along the beam; frozen phonons the whole supercell.
        let box = thermal == nil ? run.built.box : run.built.slabBox
        let atoms = thermal == nil ? slab.structure.atoms.filter { $0.position.z < box.z } : slab.structure.atoms
        let (nx, ny) = try thermal == nil ? HRTEMImage.grid(run.built, optics: run.optics)
            : HRTEMImage.thermalGrid(run.built, optics: run.optics)
        let exitPlanes = run.planePeriods.map { $0 * perPeriod - 1 }
        let optics = run.optics

        var lines: [String] = []
        lines += [
            "# HRTEM of \(oneLine(run.specimen)), written by \(oneLine(run.writtenBy)).",
            "# Runs with abTEM \(abTEMVersion) and ASE \(aseVersion):  pip install \"abtem==\(abTEMVersion)\" \"ase==\(aseVersion)\"",
            "# The app's method line: \(oneLine(run.methodLine))",
            "#",
            "# The specimen is the slab the app built, atom for atom (its slab builder is a port of abTEM's orthogonalize_cell), so no",
            "# orientation step can differ. Lengths in Å, angles in mrad, energies in eV; abTEM's defocus is positive for underfocus.",
        ]
        if let thermal {
            lines += [
                "#",
                "# Frozen phonons: abTEM draws its \(thermal.configurations) configurations with NumPy's generator (seed \(HRTEMThermal.seed)),",
                "# the app with SimulatoKit's seeded generator. The two agree as ensembles, not configuration by configuration.",
            ]
        }
        lines += [
            "",
            "import numpy as np",
            "from ase import Atoms",
            "import abtem",
            "",
            "abtem.config.set({\"precision\": \"float64\", \"device\": \"cpu\"})",
            "",
            "numbers = [\(atoms.map { "\($0.atomicNumber)" }.joined(separator: ", "))]",
            "positions = [",
        ]
        lines += atoms.map { "    (\(number($0.position.x)), \(number($0.position.y)), \(number($0.position.z))),"}
        lines += [
            "]",
            "cell = (\(number(box.x)), \(number(box.y)), \(number(box.z)))",
        ]
        let perPeriodSlices = Array(slab.sliceThicknesses.prefix(perPeriod)).map { number($0) }.joined(separator: ", ")
        if thermal == nil {
            lines += [
                "unit = Atoms(numbers=numbers, positions=positions, cell=cell, pbc=True)",
                "atoms = unit * (1, 1, \(periods))   # \(periods) periods along the beam",
            ]
        } else {
            lines += ["atoms = Atoms(numbers=numbers, positions=positions, cell=cell, pbc=True)   # \(periods) periods along the beam"]
        }
        lines += [
            "slice_thickness = (\(perPeriodSlices),) * \(periods)",
            "exit_planes = (\(exitPlanes.map(String.init).joined(separator: ", ")),)   # after periods \(run.planePeriods.map(String.init).joined(separator: ", "))",
            "",
        ]
        if let thermal {
            let sigmas = thermal.sigmas.keys.sorted().map { z in
                "\"\(Element.symbol(forAtomicNumber: z) ?? "Z\(z)")\": \(number(thermal.sigmas[z] ?? 0))"
            }.joined(separator: ", ")
            lines += [
                "specimen = abtem.FrozenPhonons(atoms, num_configs=\(thermal.configurations), sigmas={\(sigmas)}, seed=\(HRTEMThermal.seed),",
                "                                ensemble_mean=False)",
            ]
        } else {
            lines += ["specimen = atoms"]
        }
        lines += [
            "potential = abtem.Potential(specimen, gpts=(\(nx), \(ny)), slice_thickness=slice_thickness, parametrization=\"lobato\",",
            "                            projection=\"infinite\", exit_planes=exit_planes)",
            "wave = abtem.PlaneWave(energy=\(number(optics.volts)))",
            "exit_waves = wave.multislice(potential)",
            "",
            "ctf = abtem.CTF(Cs=\(number(optics.csMM * 1e7)), defocus=\(number(run.defocusNM * 10)), "
                + "semiangle_cutoff=\(optics.apertureMrad.map { number($0) } ?? "np.inf"), soft=True,",
            "                focal_spread=\(number(optics.focalSpreadNM * 10)), angular_spread=\(number(optics.angularSpreadMrad)), "
                + "energy=\(number(optics.volts)))",
        ]
        let tiles = (x: HRTEMImage.tiles(box.x, optics.fieldOfViewNM), y: HRTEMImage.tiles(box.y, optics.fieldOfViewNM))
        let thicknessNM = Double(run.planePeriods[plane]) * run.built.box.z / 10
        // abTEM adds the exit-plane axis only when there is more than one plane (multislice.py), so one stored plane takes no index.
        let planeAxis = run.planePeriods.count > 1
        if thermal == nil {
            let waves = planeAxis ? "exit_waves[\(plane)]" : "exit_waves"
            lines += ["image = \(waves).apply_ctf(ctf).intensity()   # \(number(thicknessNM)) nm"]
        } else {
            let waves = planeAxis ? "exit_waves[:, \(plane)]" : "exit_waves"
            lines += ["image = \(waves).apply_ctf(ctf).intensity().mean(0)   # \(number(thicknessNM)) nm, the ensemble mean"]
        }
        lines += [
            "image = image.tile((\(tiles.x), \(tiles.y))).compute()",
            "",
            "# The array is indexed [x, y] as the app's image is drawn: x down the rows, y along the columns.",
            "np.save(\"hrtem.npy\", image.array)",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// A double as Python reads it back exactly: Swift's shortest round-trip form.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "float(\"nan\")" : (value > 0 ? "np.inf" : "-np.inf") }
        return "\(value)"
    }
}
