//
//  HyperSpyOpening.swift
//  Role: what a HyperSpy file (`.hspy`, layouts 1.2 to 3.3) opens as, through FormatoKit's reader (`HSPYReader`, pinned exact to
//        RosettaSciIO 0.14.0; #820, plan row X4). Each experiment of the file goes to its room, as a Velox file's images and streams do:
//        a two-dimensional signal (Signal2D, pyxem's ElectronDiffraction2D) to the Image room, an EELS spectrum or spectrum image to
//        the EELS room, an EDS spectrum image (EDS_SEM, EDS_TEM) or a single spectrum to the EDS room. The files the app's own
//        Export as HyperSpy File… writes (#819) open again with their counts, type and axes as written.
//        A file none of whose experiments a room takes is refused naming what it holds (a 4D-STEM file: 4DSTEM Studio).
//

import Foundation
import FormatoCore
import FormatoHSPY
import ImagoCore
import SpectroCore
import TEMBase

package nonisolated enum HyperSpyOpening {
    /// The experiments of the file at `path`, each with what it holds or why the kit's reader refuses it; no data read.
    package static func experiments(path: String) throws -> [HSPYExperiment] {
        let name = (path as NSString).lastPathComponent
        do {
            return try HSPYReader.experiments(url: URL(fileURLWithPath: path))
        } catch {
            throw HyperSpySpectrumFile.Refusal(text: "\(name) could not be opened as a HyperSpy file: \(error.localizedDescription)")
        }
    }

    /// The experiments a room takes, by room, in the file's order (group names).
    package struct Contents: Equatable, Sendable {
        package var images: [String] = []
        package var eels: [String] = []
        package var edsSpectrumImages: [String] = []
        package var spectra: [String] = []

        package var isEmpty: Bool { images.isEmpty && eels.isEmpty && edsSpectrumImages.isEmpty && spectra.isEmpty }
    }

    /// Sorts `experiments` into the rooms: an image has two signal axes and no navigation axis, an EELS signal one signal axis over
    /// none or two navigation axes, an EDS spectrum image one signal axis over two navigation axes, a spectrum one axis.
    package static func contents(of experiments: [HSPYExperiment]) -> Contents {
        var found = Contents()
        for experiment in experiments where experiment.refusal == nil {
            let rank = experiment.shape.count, navigation = experiment.axes.filter(\.navigate).count
            if experiment.signalType == "EELS" {
                if rank == 1 || (rank == 3 && navigation == 2) { found.eels.append(experiment.name) }
            } else if rank == 2, navigation == 0 {
                found.images.append(experiment.name)
            } else if rank == 3, navigation == 2, experiment.signalType.hasPrefix("EDS") {
                found.edsSpectrumImages.append(experiment.name)
            } else if rank == 1 {
                found.spectra.append(experiment.name)
            }
        }
        return found
    }

    /// What the file holds, for the Open route; one HDF5 open, run off the main actor. A file whose experiments no room takes is refused
    /// naming what its first one holds.
    package static func inventory(path: String) -> FileInventory {
        let name = (path as NSString).lastPathComponent
        let experiments: [HSPYExperiment]
        do { experiments = try self.experiments(path: path) } catch {
            return FileInventory(refusal: (error as? LocalizedError)?.errorDescription ?? "\(name) is not a HyperSpy file \(AppName.display) opens.")
        }
        let found = contents(of: experiments)
        if found.isEmpty {
            let first = experiments.first
            if let refusal = first?.refusal { return FileInventory(refusal: "\(name) is not read: \(refusal.localizedDescription)") }
            let rank = first?.shape.count ?? 0
            let elsewhere = rank == 4 ? " Open a 4D-STEM file in 4DSTEM Studio." : ""
            return FileInventory(refusal: "\(name) holds \(HyperSpySpectrumFile.dimensionWords(rank)), which no room of "
                                 + "\(AppName.display) opens: it opens images, spectra and spectrum images from HyperSpy files." + elsewhere)
        }
        var inventory = FileInventory(image: !found.images.isEmpty, edsSpectrumImage: !found.edsSpectrumImages.isEmpty,
                                      eelsSpectrumImage: !found.eels.isEmpty)
        // Spectra only when there is nothing else to open, as for a Velox file.
        if !found.spectra.isEmpty, inventory.landing == nil { inventory.singleSpectrum = true }
        return inventory
    }

    /// The experiment's title as the app shows it: the stated one, else the group's name; HyperSpy's "__unnamed__" is the file's stem.
    static func title(of experiment: HSPYExperiment, path: String) -> String {
        if !experiment.title.isEmpty, experiment.title != "__unnamed__" { return experiment.title }
        return experiment.name == "__unnamed__" ? ((path as NSString).lastPathComponent as NSString).deletingPathExtension : experiment.name
    }

    // MARK: - An image

    /// The file's first image, at its stored type where the app holds that type (uint8, uint16, float32) and as Float32 otherwise; each
    /// axis's calibration from the file (zero at `-offset / scale`), an axis of scale 1 without a unit as uncalibrated. Off the main actor.
    package static func image(path: String) throws -> CalibratedImage {
        let name = (path as NSString).lastPathComponent
        guard let first = contents(of: try experiments(path: path)).images.first else {
            throw HyperSpySpectrumFile.Refusal(text: "\(name) holds no image: its experiments open in the EELS or EDS room.")
        }
        let signal = try HSPYReader.readStored(url: URL(fileURLWithPath: path), experiment: first)
        let data = signal.data
        let height = data.shape[0], width = data.shape[1]
        let stored: StoredPixels
        switch data.dataType {
        case .uint8: stored = .uint8([UInt8](data.bytes))
        case .uint16: stored = .uint16(data.bytes.withUnsafeBytes { p in (0..<data.count).map { UInt16(littleEndian: p.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) } })
        default: stored = .float32(data.floats())
        }
        let beam = signal.metadata["Acquisition_instrument.TEM.beam_energy"]?.value.number
            ?? signal.metadata["Acquisition_instrument.SEM.beam_energy"]?.value.number
        let title = signal.title.isEmpty ? first : signal.title
        return CalibratedImage(width: width, height: height, stored: stored, x: calibration(signal.axes[1]), y: calibration(signal.axes[0]),
                               fileName: name, source: "HyperSpy experiment \(title)", voltage: beam.flatMap { $0 > 0 ? $0 * 1000 : nil })
    }

    /// An axis's calibration: nil for HyperSpy's default (scale 1, offset 0, no unit).
    static func calibration(_ axis: FormatoAxis) -> AxisCalibration? {
        guard axis.scale.isFinite, axis.scale != 0, axis.offset.isFinite else { return nil }
        if axis.units.isEmpty, axis.scale == 1, axis.offset == 0 { return nil }
        return AxisCalibration(scale: axis.scale, unit: axis.units, origin: -axis.offset / axis.scale)
    }

    // MARK: - An EDS spectrum image

    /// The file's first EDS spectrum image as the EDS room holds it: whole counts (a float cube rounded; negative or non-finite counts
    /// refused), the energy axis in keV, the scan step and the beam energy where the file states them. Off the main actor.
    package static func edsSpectrumImage(path: String) throws -> LoadedSpectrumImage {
        let name = (path as NSString).lastPathComponent
        guard let first = contents(of: try experiments(path: path)).edsSpectrumImages.first else {
            throw HyperSpySpectrumFile.Refusal(text: "\(name) holds no EDS spectrum image.")
        }
        let signal = try HSPYReader.readStored(url: URL(fileURLWithPath: path), experiment: first)
        let ny = signal.data.shape[0], nx = signal.data.shape[1], channels = signal.data.shape[2]
        let axis = signal.axes[2]
        let toKeV = axis.units.lowercased() == "kev" ? 1.0 : 0.001
        guard axis.scale > 0 else { throw HyperSpySpectrumFile.Refusal(text: "\(name): the energy axis's channel width is not positive.") }
        let image: DenseSpectrumImage
        if signal.data.dataType == .uint16 {
            let counts = signal.data.bytes.withUnsafeBytes { p in
                (0..<signal.data.count).map { UInt16(littleEndian: p.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
            }
            image = DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts16: counts)
        } else {
            var counts = [UInt32](repeating: 0, count: signal.data.count)
            for (i, value) in signal.data.doubles().enumerated() {
                guard value.isFinite, value >= 0 else {
                    throw HyperSpySpectrumFile.Refusal(text: "\(name): the EDS spectrum image holds negative or non-finite values: it is not counts.")
                }
                counts[i] = UInt32(min(value.rounded(), Double(UInt32.max)))
            }
            image = DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: counts)
        }
        let step = signal.axes[1]
        let calibrated = step.scale > 0 && !step.units.isEmpty
        var meta = SpectrumImageMetadata(fileName: name, filePath: path, scanWidth: nx, scanHeight: ny, channelCount: channels,
                                         energyOffsetEV: axis.offset * toKeV * 1000, energyDispersionEV: axis.scale * toKeV * 1000,
                                         scanPixelSize: calibrated ? step.scale : nil, scanPixelUnit: calibrated ? step.units : nil)
        let beam = signal.metadata["Acquisition_instrument.TEM.beam_energy"]?.value.number
            ?? signal.metadata["Acquisition_instrument.SEM.beam_energy"]?.value.number
        meta.beamEnergyKeV = beam.flatMap { $0 > 0 ? $0 : nil }
        return LoadedSpectrumImage(image: image, metadata: meta,
                                   energyAxis: EnergyAxis(offset: axis.offset * toKeV, scale: axis.scale * toKeV, size: channels))
    }
}
