//
//  HyperSpySpectrumFile.swift
//  Role: one spectrum of a HyperSpy file (`.hspy`, or the same layout saved as `.h5`/`.hdf5`) for the EDS room's one-pixel spectrum image,
//        read through FormatoKit's HyperSpy reader (`HSPYReader`, pinned exact to RosettaSciIO 0.14.0 by its pin H4; #820, plan row X4:
//        the app's own HDF5 walk is gone). Counts, axis, beam energy, the elements and the EDS conditions (detector resolution, elevation,
//        azimuth, stage tilt, live time) are read exact from the metadata tree: no numerics.
//        The spectrum is the file's first experiment of one dimension that is not EELS (an EELS spectrum opens in the EELS room). A file
//        holding none is refused in words naming what it holds; its images and spectrum images open in their rooms (`HyperSpyOpening`).
//        The first file read is exspy's `EDS_SEM_TM002`, shipped as demo data (NOTICE).
//

import Foundation
import Formato
import FormatoCore
import FormatoHSPY
import TEMBase
import TEMSEM

package nonisolated enum HyperSpySpectrumFile {
    /// One spectrum as the file states it: counts per channel, the energy axis E(i) = offset + i · scale in `units`, and what the
    /// metadata tree says about how it was taken.
    package struct Spectrum: Equatable, Sendable {
        package var title: String
        package var signalType: String
        package var counts: [Double]
        package var offset: Double
        package var scale: Double
        package var units: String
        package var beamEnergyKeV: Double?
        package var microscope: String?
        /// `metadata.Sample.elements`, as written (symbols); empty when the file names none.
        package var elements: [String]
        /// The detector and stage as `Acquisition_instrument.SEM` (else `.TEM`) states them: energy resolution at Mn Kα, elevation and
        /// azimuth, stage tilts, live and real time; what the file leaves out takes exspy's defaults (`SEMEDSLines.Conditions`).
        package var conditions: SEMEDSLines.Conditions
        /// Whether the acquisition is an SEM's (`Acquisition_instrument.SEM`, or the signal type `EDS_SEM`).
        package var isSEM: Bool
    }

    /// The spectrum's experiment and its axis, found without reading the counts: what the Open route needs to say where the file goes.
    package struct Header: Equatable, Sendable {
        /// The experiment's path in the file (`/Experiments/<name>`).
        package var experiment: String
        package var title: String
        package var channels: Int
        package var offset: Double
        package var scale: Double
        package var units: String

        /// The experiment's group name, as `HSPYReader.read(url:experiment:)` takes it.
        var name: String { String(experiment.dropFirst("/Experiments/".count)) }
    }

    package struct Refusal: Error, LocalizedError, Equatable {
        package var text: String
        package var errorDescription: String? { text }
    }

    private static let hdf5Signature: [UInt8] = [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Whether `path` is a HyperSpy file: an `.hspy` by extension and HDF5 signature (eight bytes read; no HDF5 open), or a `.h5` or
    /// `.hdf5` that FormatoKit's sniff finds HyperSpy's layout in (one HDF5 open), as HyperSpy writes when given that extension.
    package static func isHyperSpyFile(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext == "h5" || ext == "hdf5" { return FormatoLoader.sniff(path: path) == .hyperSpy }
        guard ext == "hspy", let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: hdf5Signature.count)) ?? Data()
        return [UInt8](head).starts(with: hdf5Signature)
    }

    /// The file's first spectrum and its energy axis, or the refusal that says why the file holds none. One HDF5 open, no data read:
    /// run it off the main actor.
    package static func header(path: String) throws -> Header {
        let name = (path as NSString).lastPathComponent
        let experiments = try HyperSpyOpening.experiments(path: path)
        guard let found = experiments.first(where: { $0.refusal == nil && $0.shape.count == 1 && $0.signalType != "EELS" }) else {
            let first = experiments[0]
            if let refusal = first.refusal { throw Refusal(text: "\(name) is not read: \(refusal.localizedDescription)") }
            throw Refusal(text: "\(name) holds \(dimensionWords(first.shape.count)), not one spectrum: \(AppName.display) opens single spectra from HyperSpy files.")
        }
        guard let axis = found.axes.first, axis.scale > 0, axis.scale.isFinite, axis.offset.isFinite else {
            throw Refusal(text: "\(name) has no calibrated energy axis.")
        }
        return Header(experiment: "/Experiments/" + found.name, title: HyperSpyOpening.title(of: found, path: path), channels: axis.size,
                      offset: axis.offset, scale: axis.scale, units: axis.units)
    }

    /// "a 4-dimensional signal": what a HyperSpy file holds, in words. The experiment's group name is HyperSpy's own (a signal
    /// without a title is "__unnamed__"), so the refusals name the file instead.
    static func dimensionWords(_ count: Int) -> String {
        switch count {
        case 0: "a single value"
        case 1: "an EELS spectrum"
        case 2: "a 2-dimensional signal (an image or a line scan)"
        case 3: "a 3-dimensional signal (a spectrum image or an image stack)"
        case 4: "a 4-dimensional signal (a 4D-STEM or EBSD dataset)"
        default: "a \(count)-dimensional signal"
        }
    }

    /// The spectrum: `header` and the counts, with the beam energy (the SEM's, else the TEM's), the microscope and the elements the
    /// file names. Off the main actor.
    package static func read(path: String) throws -> Spectrum {
        let header = try header(path: path)
        let signal = try HSPYReader.readStored(url: URL(fileURLWithPath: path), experiment: header.name)
        let metadata = signal.metadata
        func number(_ key: String) -> Double? { metadata[key]?.value.number }
        func text(_ key: String) -> String? { metadata[key]?.value.text }
        let sem = "Acquisition_instrument.SEM.", tem = "Acquisition_instrument.TEM."
        let beam = number(sem + "beam_energy") ?? number(tem + "beam_energy")
        let microscope = text(sem + "microscope") ?? text(tem + "microscope")
        let signalType = signal.signalType
        let isSEM = signalType == "EDS_SEM" || metadata.entries.contains { $0.key.hasPrefix(sem) }
        let instrument = isSEM ? sem : tem
        let detector = instrument + "Detector.EDS.", stage = instrument + "Stage."
        let positiveBeam = beam.flatMap { $0 > 0 ? $0 : nil }
        let conditions = SEMEDSLines.Conditions(
            beamEnergyKeV: positiveBeam, energyResolutionMnKaEV: number(detector + "energy_resolution_MnKa"),
            elevationAngleDeg: number(detector + "elevation_angle"), azimuthAngleDeg: number(detector + "azimuth_angle"),
            tiltAlphaDeg: number(stage + "tilt_alpha"), tiltBetaDeg: number(stage + "tilt_beta"),
            liveTimeS: number(detector + "live_time"), realTimeS: number(detector + "real_time"))
        return Spectrum(title: header.title, signalType: signalType, counts: signal.data.doubles(),
                        offset: header.offset, scale: header.scale, units: header.units,
                        beamEnergyKeV: positiveBeam, microscope: microscope, elements: metadata["Sample.elements"]?.value.texts ?? [],
                        conditions: conditions, isSEM: isSEM)
    }
}
