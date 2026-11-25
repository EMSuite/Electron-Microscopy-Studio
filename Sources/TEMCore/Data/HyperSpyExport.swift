//
//  HyperSpyExport.swift
//  Role: File > Export HyperSpy File… (#819, plan row X3): an image, a diffraction pattern or an EELS cube as a HyperSpy file (.hspy, layout
//        3.3, FormatoKit's `HSPYWriter`) that `hs.load` opens as the class HyperSpy's own reader builds (pin H2: Signal2D for an
//        image, pyxem's ElectronDiffraction2D for a pattern, exspy's EELSSpectrum for a cube, written a band of rows at a time with
//        progress and Stop). The pixels keep their stored type (uint8, uint16 or float32), the
//        axes their calibration, and the file's metadata tree carries the methods record (`recordKey`, the record's JSON) and the
//        beam energy where the file states one. The file is built in the system's scratch folder and moved onto the destination
//        when whole, so a failed or refused write leaves the destination as it was.
//
//        FREE SPACE is checked before anything is written: a volume with less free than the file's size and a margin is refused in
//        words (`Refusal.notEnoughSpace`), with what it needs and what the disk has.
//

import FormatoCore
import FormatoHSPY
import Foundation
import ImagoCore
import ShellExport
import SpectroEELS

package nonisolated enum HyperSpyExport {
    /// The methods record's key in the file's metadata tree: `s.metadata.Processing.methods_record`, the record's JSON.
    package static let recordKey = "Processing.methods_record"
    /// HyperSpy's key for the beam energy in keV, which exspy and pyxem read.
    package static let beamEnergyKey = "Acquisition_instrument.TEM.beam_energy"
    /// Room for the file's structure (groups, attributes, the metadata tree) beside its data.
    static let structureBytes = 1 << 20
    /// About this many bytes a band of a cube: the unit between two progress reports and cancellation checks.
    static let slabBytes = 16 << 20

    /// A refusal before anything is written.
    package enum Refusal: Error, Equatable, LocalizedError {
        case notEnoughSpace(needed: Int64, free: Int64)

        package var errorDescription: String? {
            switch self {
            case .notEnoughSpace(let needed, let free):
                let format = ByteCountFormatter()
                format.countStyle = .file
                return "The HyperSpy file needs about \(format.string(fromByteCount: needed)), and this disk has "
                    + "\(format.string(fromByteCount: free)) free. Choose another place, or free some space first."
            }
        }
    }

    /// What a pattern's reciprocal axes are, when the Diffraction room has a scale: Δq in Å⁻¹ per pixel and the centre (row,
    /// column) in pixels, which becomes the axes' zero, as pyxem's `set_diffraction_calibration` and `center_direct_beam` give.
    package struct PatternScale: Sendable, Equatable {
        package var deltaQ: Double
        package var centreRow: Double
        package var centreColumn: Double

        package init(deltaQ: Double, centreRow: Double, centreColumn: Double) {
            self.deltaQ = deltaQ
            self.centreRow = centreRow
            self.centreColumn = centreColumn
        }
    }

    // MARK: - The signal

    /// The image as HyperSpy's Signal2D holds it: shape (height, width), the y axis then the x, each with the file's calibration.
    package static func imageSignal(_ image: CalibratedImage) throws -> FormatoSignal {
        let axes = [axis("y", image.y, size: image.height), axis("x", image.x, size: image.width)]
        return FormatoSignal(title: stem(image.fileName), signalType: "", axes: axes, metadata: FormatoMetadata(), data: try array(image))
    }

    /// The pattern as pyxem's ElectronDiffraction2D holds it: the axes ky and kx in Å⁻¹ with the zero at the centre when the room
    /// has a scale, else the file's calibration.
    package static func patternSignal(_ image: CalibratedImage, scale: PatternScale?) throws -> FormatoSignal {
        let axes: [FormatoAxis]
        if let scale {
            axes = [FormatoAxis(name: "ky", size: image.height, scale: scale.deltaQ, offset: -scale.centreRow * scale.deltaQ, units: "Å⁻¹",
                                navigate: false),
                    FormatoAxis(name: "kx", size: image.width, scale: scale.deltaQ, offset: -scale.centreColumn * scale.deltaQ, units: "Å⁻¹",
                                navigate: false)]
        } else {
            axes = [axis("ky", image.y, size: image.height), axis("kx", image.x, size: image.width)]
        }
        return FormatoSignal(title: stem(image.fileName), signalType: HSPYSignalKind.electronDiffraction.signalType, axes: axes,
                             metadata: FormatoMetadata(), data: try array(image))
    }

    /// The pixels as stored, in C order (rows slowest): a uint8 or uint16 file keeps its type.
    static func array(_ image: CalibratedImage) throws -> FormatoArray {
        let shape = [image.height, image.width]
        switch image.stored {
        case .uint8(let values): return try FormatoArray(dataType: .uint8, shape: shape, bytes: Data(values))
        case .uint16(let values): return try FormatoArray(dataType: .uint16, shape: shape, bytes: values.withUnsafeBytes { Data($0) })
        case .float32(let values): return try FormatoArray(dataType: .float32, shape: shape, bytes: values.withUnsafeBytes { Data($0) })
        }
    }

    /// One signal axis from the file's calibration: the scale, the unit and the zero at the calibration's origin; an uncalibrated
    /// axis counts pixels from 0, without a unit, as HyperSpy's own default.
    static func axis(_ name: String, _ calibration: AxisCalibration?, size: Int) -> FormatoAxis {
        guard let calibration else { return FormatoAxis(name: name, size: size, scale: 1, offset: 0, units: "", navigate: false) }
        return FormatoAxis(name: name, size: size, scale: calibration.scale, offset: -calibration.origin * calibration.scale,
                           units: calibration.unit, navigate: false)
    }

    /// The options the file is written with: its title, the software line, the record's JSON and the beam energy.
    package static func options(title: String, software: String, record: MethodsRecord?, beamEnergyKeV: Double?) throws -> HSPYWriteOptions {
        var metadata: [String: FormatoValue] = [:]
        if let record { metadata[recordKey] = .text(try record.json()) }
        if let beamEnergyKeV, beamEnergyKeV.isFinite, beamEnergyKeV > 0 { metadata[beamEnergyKey] = .number(beamEnergyKeV) }
        return HSPYWriteOptions(title: title, software: software, metadata: metadata)
    }

    // MARK: - The write

    /// Writes `signal` as `kind` at `url` once the volume has room for it; off the main actor (a large image is tens of megabytes).
    @concurrent package static func write(_ signal: FormatoSignal, kind: HSPYSignalKind, options: HSPYWriteOptions, to url: URL) async throws {
        try checkSpace(for: Int64(signal.data.bytes.count + structureBytes), at: url)
        try HSPYWriter.write(signal, kind: kind, options: options, to: url)
    }

    // MARK: - A cube

    /// An EELS spectrum image's axes: the scan's y and x (navigation, in the file's scan unit or pixels) and the energy loss.
    package struct CubeAxes: Sendable, Equatable {
        package var scanStep: Double?
        package var scanUnit: String?
        package var energyOffsetEV: Double
        package var energyScaleEV: Double

        package init(scanStep: Double?, scanUnit: String?, energyOffsetEV: Double, energyScaleEV: Double) {
            self.scanStep = scanStep
            self.scanUnit = scanUnit
            self.energyOffsetEV = energyOffsetEV
            self.energyScaleEV = energyScaleEV
        }

        /// In array order (y, x, energy), as exspy's EELSSpectrum holds a map.
        func formatoAxes(nx: Int, ny: Int, channels: Int) -> [FormatoAxis] {
            let step = scanStep ?? 1, unit = scanStep == nil ? "" : scanUnit ?? ""
            return [FormatoAxis(name: "y", size: ny, scale: step, offset: 0, units: unit, navigate: true),
                    FormatoAxis(name: "x", size: nx, scale: step, offset: 0, units: unit, navigate: true),
                    FormatoAxis(name: "Energy loss", size: channels, scale: energyScaleEV, offset: energyOffsetEV, units: "eV", navigate: false)]
        }
    }

    /// The EELS-specific metadata exspy reads: the convergence and collection semi-angles in mrad.
    package static let convergenceKey = "Acquisition_instrument.TEM.convergence_angle"
    package static let collectionKey = "Acquisition_instrument.TEM.Detector.EELS.collection_angle"

    /// Writes an EELS cube (`counts[(y * nx + x) * channels + c]`) as exspy's EELSSpectrum, a band of scan rows at a time from the
    /// counts where they lie (a float32 cube stays float32), reporting the fraction written and stopping when the task is
    /// cancelled (the file is then removed and the destination left as it was).
    @concurrent package static func writeCube(_ counts: EELSCounts, nx: Int, ny: Int, channels: Int, axes: CubeAxes, options: HSPYWriteOptions,
                                              to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let size = counts.precision.bytes
        try checkSpace(for: Int64(counts.count * size + structureBytes), at: url)
        let writer = try HSPYWriter.open(shape: [ny, nx, channels], dataType: size == 4 ? .float32 : .float64,
                                         axes: axes.formatoAxes(nx: nx, ny: ny, channels: channels), kind: .eels, options: options, to: url)
        do {
            let rowBytes = nx * channels * size
            let rowsPerSlab = max(1, slabBytes / max(1, rowBytes))
            func bands(_ all: UnsafeRawBufferPointer) throws {
                var row = 0
                while row < ny {
                    let rows = min(rowsPerSlab, ny - row)
                    let slab = UnsafeRawBufferPointer(rebasing: all[(row * rowBytes)..<((row + rows) * rowBytes)])
                    try writer.write(bytes: slab, count: [rows, nx, channels], at: [row, 0, 0])
                    row += rows
                    progress(Double(row) / Double(ny))
                }
            }
            if let singles = counts.singles {
                try singles.withUnsafeBytes { try bands($0) }
            } else {
                try counts.withDoubles { try bands(UnsafeRawBufferPointer($0)) }
            }
            try writer.publish()
        } catch {
            writer.cancel()
            throw error
        }
    }

    /// Refuses a write the destination's volume has no room for; a volume that does not say how much it has is not refused.
    package static func checkSpace(for bytes: Int64, at url: URL, free: Int64? = nil) throws {
        let available = free ?? freeBytes(at: url.deletingLastPathComponent())
        guard let available else { return }
        if available < bytes { throw Refusal.notEnoughSpace(needed: bytes, free: available) }
    }

    /// The free bytes of the volume holding `folder`, for an important write, as the system counts them; nil when it does not say.
    static func freeBytes(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// "scan.dm4" as "scan": the file's title in HyperSpy and the name the save panel offers.
    package static func stem(_ fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? "signal" : stem
    }
}
