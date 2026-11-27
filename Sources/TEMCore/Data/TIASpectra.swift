//
//  TIASpectra.swift
//  Role: the TIA spectra of an FEI/Thermo Fisher acquisition (#906): a `.ser` series of spectra (a point, a line profile, a spectrum
//        image) opens in its room, the EDS room or the EELS room, and each series of a picked `.emi` is an item of its own. Read
//        through FormatoKit's FormatoTIA (RosettaSciIO 049e7d70 `ser_reader`, HyperSpy 2.5.0's mapping; the parity is the kit's), as
//        `TIAImageReader` reads the images and patterns. This file is the seam: which room, which files an `.emi` stands for, and the
//        counts in the EDS room's terms (the EELS room converts its own, `EELSOpening`).
//
//  WHICH ROOM: RosettaSciIO gives every TIA series the signal type "" and FormatoTIA keeps it, so the `.emi` beside the series says it,
//  by what its `<ObjectInfo>` documents record of the detector: an EDS detector records its `<ShapingTime>` (TIA's FEI-Edx and EDAX
//  documents), the EELS spectrometer's camera its `<GainCorrection>` and `<BiasCorrection>` (the GIF's CCD). The whole `.emi` is read,
//  not the series' own document: RosettaSciIO's document of `_1.ser` is the first, which is the scan's in every public file (the
//  detector's document is the second). An `.emi` that records both, or neither, or a series with no `.emi` beside it, says nothing,
//  and the Open asks once which room (`AppState.open(urls:)`; the agent door's `open_file` takes `room`).
//
//  THE SERIES OF AN .EMI: the files `<name>_0.ser` to `<name>_9.ser` that open, in that order, each probed by opening it (a sandboxed
//  app is told a file it may not open is not there, `TIAImageReader.seriesOpenError`). Each opens as any `.ser` does: an image or a
//  pattern in the image rooms with the `.emi`'s metadata, a series of spectra in its room.
//
//  THE COUNTS: TIA writes the navigation axes first and the energy last, rows before columns (HyperSpy's (y, x, energy)); a point is a
//  1 x 1 spectrum image and a line profile one row. The energy axis is in eV. The EDS room holds whole counts: each value is rounded,
//  and a series with a negative or non-finite value is refused, as for a single spectrum (`FileRouting.countImage`). A spectrum image
//  stopped early has its unfilled positions empty (0), not refused (`counts`).
//

import Foundation
import FormatoCore
import FormatoTIA
import SpectroCore
import TEMSEM

package nonisolated enum TIASpectra {
    /// The room a series of TIA spectra opens in.
    package enum Room: String, CaseIterable, Sendable {
        case eds = "EDS"
        case eels = "EELS"
    }

    /// The question an Open asks when no `.emi` says which room (`room(of:)` is nil), and its two answers' words.
    package static func askTitle(names: [String]) -> String {
        names.count == 1 ? "Which room opens the TIA spectra of \(names[0])?" : "Which room opens the TIA spectra of \(names.count) files?"
    }
    package static let askDetail = "No .emi file beside them says whether the spectra are EDS or EELS. "
        + "EDS spectra open in the EDS room, EELS spectra in the EELS room."

    /// Whether the file at `url` is a `.ser` series of spectra (its header only).
    package static func isSpectra(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "ser" && ((try? TIAReader.header(url: url))?.isSpectrum ?? false)
    }

    /// The room of the `.ser` at `url` by the `.emi` of its acquisition (the rule above); nil when none says.
    package static func room(of url: URL) -> Room? {
        guard let emi = url.pathExtension.lowercased() == "emi" ? url : TIAImageReader.emiBeside(ser: url),
              let data = try? Data(contentsOf: emi, options: .alwaysMapped) else { return nil }
        return room(emi: data)
    }

    /// The room an `.emi`'s documents say (the rule above), from its bytes.
    package static func room(emi data: Data) -> Room? {
        func holds(_ tag: String) -> Bool { data.range(of: Data("<\(tag)>".utf8)) != nil }
        let eds = holds("ShapingTime"), eels = holds("GainCorrection") || holds("BiasCorrection")
        switch (eds, eels) {
        case (true, false): return .eds
        case (false, true): return .eels
        default: return nil
        }
    }

    /// `urls` without each `.ser` whose `.emi` is in it too and stands for its series (all of them open): the `.emi` opens them,
    /// once. A `.ser` picked beside an `.emi` that does not open all its series keeps its place.
    package static func withoutSeriesOfPickedEMI(_ urls: [URL]) -> [URL] {
        let standing = Set(urls.filter { TIAImageReader.seriesOpenError($0) == nil && !seriesFiles(of: $0).isEmpty }
            .map { $0.standardizedFileURL.path })
        guard !standing.isEmpty else { return urls }
        return urls.filter { url in
            guard url.pathExtension.lowercased() == "ser", let emi = TIAImageReader.emiBeside(ser: url) else { return true }
            return !standing.contains(emi.standardizedFileURL.path)
        }
    }

    /// The series of the `.emi` at `url`: `<name>_0.ser` to `<name>_9.ser`, each that opens, in that order (the rule above). Empty for
    /// any other file, and when none opens (the `.emi` then keeps its own routing, which names why).
    package static func seriesFiles(of url: URL) -> [URL] {
        guard url.pathExtension.lowercased() == "emi" else { return [] }
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        return (0...9).map { folder.appendingPathComponent("\(stem)_\($0).ser") }.filter { ser in
            ser.path.withCString { path in
                let probe = Darwin.open(path, O_RDONLY | O_NONBLOCK)
                guard probe >= 0 else { return false }
                _ = Darwin.close(probe)
                return true
            }
        }
    }

    /// The spectra of the `.ser` at `url`, with the `.emi`'s metadata when the `.emi` of its acquisition reads (as
    /// `TIAImageReader.series` takes it), and its navigation as rows and columns.
    package struct Series {
        package var signal: FormatoLazySignal
        package var rows: Int
        package var columns: Int
        package var channels: Int
        /// The energy axis, in eV.
        package var energy: FormatoAxis
        /// The scan's pixel size along x and its unit, when the file states a length.
        package var pixel: (size: Double, unit: String)?
        /// E₀ in kV, from the `.emi`; nil without it.
        package var beamEnergyKeV: Double?
        package var microscope: String?
        /// The scan positions TIA filled: fewer than rows x columns when the acquisition was stopped early.
        package var filledPositions: Int
        package var stoppedEarly: Bool { filledPositions < rows * columns }
    }

    /// The spectra of the `.ser` at `url`. Throws `TIAImageReader.Refusal` in the app's words.
    package static func read(url: URL) throws -> Series {
        let signal: FormatoLazySignal
        let filled: Int
        do {
            let header = try TIAReader.header(url: url)
            filled = header.validElements
            guard header.isSpectrum else { throw TIAImageReader.Refusal.unreadable("it holds images, not spectra") }
            if let emi = TIAImageReader.emiBeside(ser: url), let all = try? TIAReader.readEMI(url: emi),
               let mine = all.first(where: { $0.metadata["General.original_filename"]?.value.text == url.lastPathComponent }) {
                signal = mine
            } else {
                signal = try TIAReader.read(url: url)
            }
        } catch let refusal as TIAImageReader.Refusal {
            throw refusal
        } catch let cancelled as FormatoCancelled {
            throw cancelled
        } catch {
            throw TIAImageReader.Refusal.unreadable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        let shape = signal.array.shape
        guard let energy = signal.axes.last, !energy.navigate, energy.units == "eV", let channels = shape.last, channels > 0 else {
            throw TIAImageReader.Refusal.unreadable("its spectra have no energy axis in eV")
        }
        let navigation = shape.dropLast()
        guard navigation.count <= 2, navigation.allSatisfy({ $0 > 0 }) else {
            throw TIAImageReader.Refusal.unreadable("its spectra are laid out in \(navigation.count) navigation dimensions")
        }
        let rows = navigation.count == 2 ? navigation[navigation.startIndex] : 1
        let columns = navigation.last ?? 1
        let x = signal.axes.filter(\.navigate).last
        let pixel = x.flatMap { $0.scale > 0 && $0.scale.isFinite && $0.units == "nm" ? (size: $0.scale, unit: $0.units) : nil }
        let kV = signal.metadata["Acquisition_instrument.TEM.beam_energy"]?.value.number
        return Series(signal: signal, rows: rows, columns: columns, channels: channels, energy: energy, pixel: pixel,
                      beamEnergyKeV: kV.flatMap { $0 > 0 && $0.isFinite ? $0 : nil },
                      microscope: signal.metadata["Acquisition_instrument.TEM.microscope"]?.value.text, filledPositions: filled)
    }

    /// Every count of `series` as stored, laid out rows, columns, channels.
    package static func values(_ series: Series) throws -> FormatoArray {
        do {
            return try series.signal.array.readAll()
        } catch let cancelled as FormatoCancelled {
            throw cancelled
        } catch {
            throw TIAImageReader.Refusal.unreadable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// Every count of `series` as Doubles: the positions a stopped acquisition left unfilled (NaN in a float series, as RosettaSciIO
    /// fills them) are 0, an empty spectrum, in both rooms.
    package static func counts(_ series: Series) throws -> [Double] {
        let values = try values(series).doubles()
        return series.stoppedEarly ? values.map { $0.isFinite ? $0 : 0 } : values
    }

    /// The note of a spectrum image stopped early.
    package static func stoppedNote(_ series: Series) -> String {
        "stopped early: \(series.filledPositions) of \(series.rows * series.columns) positions acquired, the others empty"
    }

    /// The `.ser` at `url` as the EDS room's spectrum image: whole counts on a keV axis, E₀ and the microscope from the `.emi`.
    package static func edsSpectrumImage(url: URL) throws -> LoadedSpectrumImage {
        let series = try read(url: url)
        let loaded = try FileRouting.countImage(name: url.lastPathComponent, path: url.path, values: try counts(series),
                                                rows: series.rows, columns: series.columns, offset: series.energy.offset,
                                                scale: series.energy.scale, units: series.energy.units,
                                                beamEnergyKeV: series.beamEnergyKeV, instrument: series.microscope)
        var metadata = loaded.metadata
        metadata.scanPixelSize = series.pixel?.size
        metadata.scanPixelUnit = series.pixel?.unit
        return LoadedSpectrumImage(image: loaded.image, metadata: metadata, energyAxis: loaded.energyAxis)
    }
}
