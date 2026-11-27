//
//  TIAImageReader.swift
//  Role: open an FEI/Thermo Fisher TIA image or diffraction pattern (`.ser`, with the `.emi` that describes it) as macTEM's
//        `CalibratedImage`, through FormatoKit's FormatoTIA (0.20.0: RosettaSciIO 049e7d70 `ser_reader` and `emi_reader`, HyperSpy
//        2.5.0's mapping; the parity is the kit's). This file is the seam: which series and which frame open, the calibration in
//        the app's terms, the notes, the refusal wording, and the folder rule an `.emi` is read with.
//
//  WHICH SERIES: an `.emi` opens its first series with two signal axes (an image or a pattern), as FormatoKit's Peek previews
//  it; the note names it when the `.emi` holds more than one ("series 1 of 2: ..._1.ser"). A `.ser` opens with the metadata of
//  the `.emi` of its acquisition (`<name>.emi` beside `<name>_<digit>.ser`) when that one reads, and alone otherwise: then the
//  image's units are assumed (TIA's `.ser` does not say whether its axes are lengths or reciprocal lengths; FormatoTIA calls
//  them metres, as RosettaSciIO does) and the note says "units assumed, no .emi". A series of spectra opens in its room
//  (`TIASpectra`, #906); an Open of an `.emi` that reads opens each of its series as a file of its own, so this reader is
//  handed an `.emi` only by a caller that reads it directly.
//
//  THE FRAME: a series of images (a preview, a STEM map of frames) opens its first frame, never a sum, and says "frame 1 of N".
//
//  CALIBRATION: the kit's scale per axis in its units ("nm", "1 / nm": FormatoTIA turns metres into nm and 1/metres into 1 / nm by
//  the scale only and keeps each offset in the stored metres or 1/metres, RosettaSciIO's behaviour). The origin, the pixel of the
//  physical zero, is the offset in the scale's unit over the scale, negated: for the public 64 x 64 pattern −3.25 1/nm over
//  0.1016 1/nm a pixel, pixel 32, its centre. A scale that is not finite and positive leaves its axis uncalibrated. The voltage is
//  the `.emi`'s high tension (kV, HyperSpy's `beam_energy`) in volts; none without the `.emi`.
//
//  THE FOLDER: the sandbox grants the file the person picked. An `.emi` is read with its `.ser` files, whose names are not its own
//  (`name_1.ser` beside `name.emi`), so they cannot be asked for as related items (`RelatedFileAccess`): the Open asks for the
//  folder once (`FolderGrants`, as for a NORDIF scan), and without it the `.emi` is refused in a sentence that says so
//  (`unreadableSeriesRefusal`). A `.ser` is never refused for its `.emi`: when the sandbox refuses the `.emi` beside it
//  (`emiOpenError`), the Open asks for the folder once too and routes the `.ser` again inside the grant (#955); declined, it
//  opens alone.
//

import Foundation
import FormatoCore
import FormatoTIA
import ImagoCore
import TEMBase
import TEMSEM

package nonisolated enum TIAImageReader {
    /// The extensions of a TIA acquisition, lower case.
    package static let extensions = ["ser", "emi"]

    package enum Refusal: Error, Equatable {
        /// The kit refused the file (not a TIA series, truncated, an .emi with no series beside it), in its words.
        case unreadable(String)
        /// The series are spectra (a point, a line profile, a spectrum image).
        case spectra
        /// An .emi none of whose series holds data.
        case noSeries

        package var reason: String {
            switch self {
            case .unreadable(let detail): "it could not be read (\(detail))."
            case .spectra: "it holds TIA spectra, which open in the EDS or EELS room from their .ser files."
            case .noSeries: "none of its series holds data."
            }
        }
    }

    /// The note of a `.ser` opened without its `.emi`.
    package static let unitsAssumedNote = "units assumed, no .emi"

    /// The image the file at `path` opens: the series and frame the rule above picks, with its calibration and notes.
    package static func read(path: String) throws -> CalibratedImage {
        let url = URL(fileURLWithPath: path)
        let chosen = try series(url: url)
        return try image(chosen, fileName: formatoDisplayFileName(path))
    }

    /// Whether the file at `path` holds a series of spectra and no image (header only for a `.ser`; the `.emi`'s series for an `.emi`).
    package static func holdsSpectraOnly(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "emi" {
            guard let all = try? TIAReader.readEMI(url: url), !all.isEmpty else { return false }
            return !all.contains(where: hasTwoSignalAxes)
        }
        return (try? TIAReader.header(url: url))?.isSpectrum ?? false
    }

    /// The series an Open shows, with what it says about how it was chosen.
    package struct Chosen {
        package var signal: FormatoLazySignal
        /// The `.ser` the series is, and how many series its `.emi` holds (1 for a `.ser`).
        package var seriesName: String
        package var seriesIndex: Int
        package var seriesCount: Int
        /// Whether the `.emi` gave the series its metadata and units.
        package var withEMI: Bool
    }

    /// The series of the rule above. Throws `Refusal` in the app's words.
    package static func series(url: URL) throws -> Chosen {
        do {
            if url.pathExtension.lowercased() == "emi" {
                let all = try TIAReader.readEMI(url: url)
                guard !all.isEmpty else { throw Refusal.noSeries }
                guard let index = all.firstIndex(where: hasTwoSignalAxes) else { throw Refusal.spectra }
                return Chosen(signal: all[index], seriesName: originalName(all[index]) ?? url.lastPathComponent,
                              seriesIndex: index, seriesCount: all.count, withEMI: true)
            }
            if try TIAReader.header(url: url).isSpectrum { throw Refusal.spectra }
            if let emi = emiBeside(ser: url), let all = try? TIAReader.readEMI(url: emi),
               let mine = all.first(where: { originalName($0) == url.lastPathComponent }) {
                return Chosen(signal: mine, seriesName: url.lastPathComponent, seriesIndex: 0, seriesCount: 1, withEMI: true)
            }
            return Chosen(signal: try TIAReader.read(url: url), seriesName: url.lastPathComponent, seriesIndex: 0, seriesCount: 1, withEMI: false)
        } catch let refusal as Refusal {
            throw refusal
        } catch let cancelled as FormatoCancelled {
            throw cancelled
        } catch {
            throw Refusal.unreadable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// The first frame of `chosen` as an image.
    package static func image(_ chosen: Chosen, fileName: String) throws -> CalibratedImage {
        let signal = chosen.signal
        let shape = signal.array.shape
        guard shape.count >= 2, hasTwoSignalAxes(signal) else { throw Refusal.spectra }
        let rows = shape[shape.count - 2], columns = shape[shape.count - 1]
        guard rows > 0, columns > 0 else { throw Refusal.noSeries }
        let lead = shape.dropLast(2)
        let frames = lead.reduce(1, *)
        let array: FormatoArray
        do {
            array = try signal.array.read(start: [Int](repeating: 0, count: shape.count),
                                          count: lead.map { _ in 1 } + [rows, columns])
        } catch let cancelled as FormatoCancelled {
            throw cancelled
        } catch {
            throw Refusal.unreadable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        let signalAxes = signal.axes.filter { !$0.navigate }
        let y = calibration(signalAxes[signalAxes.count - 2]), x = calibration(signalAxes[signalAxes.count - 1])
        var notes: [String] = []
        if chosen.seriesCount > 1 { notes.append("series \(chosen.seriesIndex + 1) of \(chosen.seriesCount): \(chosen.seriesName)") }
        if frames > 1 { notes.append("frame 1 of \(frames)") }
        if !chosen.withEMI { notes.append(unitsAssumedNote) }
        let kV = signal.metadata["Acquisition_instrument.TEM.beam_energy"]?.value.number
        return CalibratedImage(width: columns, height: rows, stored: StoredPixels(array), x: x, y: y, fileName: fileName,
                               source: chosen.seriesName, voltage: kV.flatMap { $0 > 0 && $0.isFinite ? $0 * 1000 : nil }, notes: notes)
    }

    /// An axis of the kit's in the app's terms (the rule above): nil for a scale that is not finite and positive.
    package static func calibration(_ axis: FormatoAxis) -> AxisCalibration? {
        guard axis.scale.isFinite, axis.scale > 0 else { return nil }
        let offset: Double
        switch axis.units {
        case "nm": offset = axis.offset * 1e9          // stored in metres
        case "1 / nm": offset = axis.offset / 1e9      // stored in 1/metres
        default: offset = axis.offset
        }
        let origin = offset.isFinite ? -offset / axis.scale : 0
        return AxisCalibration(scale: axis.scale, unit: axis.units, origin: origin.isFinite ? origin : 0)
    }

    /// The `.emi` of the acquisition a `.ser` belongs to: `<name>.emi` for `<name>_<digit>.ser`. Whether it is there and may be read
    /// is the read's question (`try? TIAReader.readEMI`): a sandboxed app is told a file it may not open is not there.
    package static func emiBeside(ser url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let cut = stem.lastIndex(of: "_") else { return nil }
        let digit = stem[stem.index(after: cut)...]
        guard digit.count == 1, let d = digit.first, d.isASCII, d.isNumber else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(String(stem[..<cut]) + ".emi")
    }

    /// Why the `.ser` files of an `.emi` cannot be opened: the `errno` of the first of `<name>_0.ser` to `<name>_9.ser` that is there
    /// and does not open (EPERM is the sandbox's), nil when each one there opens, for a `.ser`, and for an `.emi` with none beside it
    /// (the kit's refusal says so). Each name is opened, not asked after with `fileExists`, which answers false for a file the
    /// sandbox hides (as `NORDIFOpening.settingsOpenError` does).
    package static func seriesOpenError(_ url: URL) -> Int32? {
        guard url.pathExtension.lowercased() == "emi" else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        for n in 0...9 {
            let code: Int32 = folder.appendingPathComponent("\(stem)_\(n).ser").path.withCString { path in
                let probe = Darwin.open(path, O_RDONLY | O_NONBLOCK)
                guard probe >= 0 else { return errno }
                _ = Darwin.close(probe)
                return 0
            }
            if code != 0 && code != ENOENT { return code }
        }
        return nil
    }

    /// Why the `.emi` of a `.ser`'s acquisition (`emiBeside`) cannot be opened: its `errno` when it is there and does not open
    /// (EPERM is the sandbox's), nil when it opens, when none is there, for an `.emi`, and for a `.ser` whose name has no `.emi`
    /// (#955). The `.emi` is opened, not asked after with `fileExists` (as `seriesOpenError`).
    package static func emiOpenError(_ url: URL) -> Int32? {
        guard url.pathExtension.lowercased() == "ser", let emi = emiBeside(ser: url) else { return nil }
        let code: Int32 = emi.path.withCString { path in
            let probe = Darwin.open(path, O_RDONLY | O_NONBLOCK)
            guard probe >= 0 else { return errno }
            _ = Darwin.close(probe)
            return 0
        }
        return code != 0 && code != ENOENT ? code : nil
    }

    /// The sentence for an `.emi` whose `.ser` files macOS does not let the app open, or nil.
    package static func unreadableSeriesRefusal(_ url: URL) -> String? {
        guard let code = seriesOpenError(url), code == EPERM || code == EACCES else { return nil }
        return "The .ser files beside \(url.lastPathComponent) cannot be read: macOS does not let \(AppName.display) open them "
            + "(\(String(cString: strerror(code)))); a TIA .emi needs the acquisition's folder, not \(url.lastPathComponent) alone."
    }

    private static func hasTwoSignalAxes(_ signal: FormatoLazySignal) -> Bool {
        signal.axes.filter { !$0.navigate }.count == 2
    }

    private static func originalName(_ signal: FormatoLazySignal) -> String? {
        signal.metadata["General.original_filename"]?.value.text
    }
}
