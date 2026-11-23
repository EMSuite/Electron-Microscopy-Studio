//
//  PictureImageReader.swift
//  Role: open a PNG or a JPEG (a pattern from a paper, a camera's export) as macTEM's `CalibratedImage` (#792, plan row E1). Read in the
//        app through ImageIO, not in a kit: the kits import no Apple image framework. The decoded samples are taken as they are, never
//        drawn through a colour-managed context, so no profile, gamma chunk or colour space changes a value (pin I1). Colour becomes
//        grey by the app's rule for colour pictures (TIFF #541): each pixel the brightest of its red, green and blue; alpha is left
//        out. EXIF orientation is applied, as Pillow's `ImageOps.exif_transpose` does (pin I3).
//
//  A picture holds no counts and no scale: `source` and `notes` say so ("Picture, not counts, scale not in the file"), every axis is
//  nil, and intensity results built on it say "not quantitative". Its scale is typed or fitted to a ring of a known phase in the
//  Diffraction room, which names where it came from.
//
//  REFUSED BY NAME: CMYK, an animated picture (more than one frame), a picture past `maximumPixels` or `maximumSide`, floating-point
//  samples, and a layout ImageIO hands over that is not one of grey, grey and alpha, RGB, RGBA (alpha first or last) or a palette.
//
//  PINS (macTEMTests/Fixtures/pictures, tools/parity/picture-pins/generate.py): RosettaSciIO 0.14.0 `rsciio.image.file_reader`
//  (imageio 2.38.1 over Pillow 13.0.0) on 9 PNGs, exact; 4 JPEGs, grey within 1 level, colour within the tolerance the test states
//  (two decoders may differ by the JPEG standard); EXIF orientations 1 to 8 against Pillow's `exif_transpose`.
//

import CoreGraphics
import Foundation
import FormatoCore
import ImageIO

package nonisolated enum PictureImageReader {
    /// The extensions read here, lower case.
    package static let extensions = ["png", "jpg", "jpeg"]

    /// The largest picture read: 2^28 pixels (256 MP, 256 MB at one byte a pixel) and 65,535 pixels a side.
    package static let maximumPixels = 1 << 28
    package static let maximumSide = 65_535

    /// The notes a picture carries, worded once.
    package enum Note {
        /// What every picture says: its values are a picture's, not a detector's, and it carries no scale.
        package static let picture = "Picture, not counts, scale not in the file"
        /// A colour picture shown as grey.
        package static let colour = "Colour picture shown as grey: each pixel is the brightest of its red, green and blue"
    }

    package enum Refusal: Error, Equatable, Sendable {
        case notPicture
        case animated(frames: Int)
        case cmyk
        case tooLarge(width: Int, height: Int)
        case layout(String)

        package var reason: String {
            switch self {
            case .notPicture: "it is not a PNG or JPEG picture ImageIO can decode."
            case .animated(let frames): "it is an animated picture of \(frames) frames; only a still picture is read."
            case .cmyk: "it is a CMYK picture (made for print); only grey and RGB pictures are read."
            case .tooLarge(let width, let height):
                "it is \(width) × \(height) pixels; a picture is read up to \(PictureImageReader.maximumSide) pixels a side and "
                    + "\(PictureImageReader.maximumPixels / (1 << 20)) MP."
            case .layout(let what): "its pixel layout is not read (\(what))."
            }
        }
    }

    /// Reads the picture at `path`, synchronously (off the main actor).
    package static func read(path: String) throws -> CalibratedImage {
        let url = URL(fileURLWithPath: path)
        let fileName = formatoDisplayFileName(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            if !FileManager.default.isReadableFile(atPath: path) { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path]) }
            throw Refusal.notPicture
        }
        return try read(source, fileName: fileName)
    }

    /// Reads the picture in `data` (a test's planted bytes).
    package static func read(data: Data, fileName: String) throws -> CalibratedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Refusal.notPicture
        }
        return try read(source, fileName: fileName)
    }

    private static func read(_ source: CGImageSource, fileName: String) throws -> CalibratedImage {
        guard let type = CGImageSourceGetType(source) as String?, type == "public.png" || type == "public.jpeg" else {
            throw Refusal.notPicture
        }
        let frames = CGImageSourceGetCount(source)
        guard frames >= 1 else { throw Refusal.notPicture }
        guard frames == 1 else { throw Refusal.animated(frames: frames) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        if properties[kCGImagePropertyColorModel] as? String == (kCGImagePropertyColorModelCMYK as String) { throw Refusal.cmyk }
        // The size is checked from the header, before anything is decoded.
        if let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int {
            try checkSize(width: w, height: h)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw Refusal.notPicture }
        try checkSize(width: image.width, height: image.height)
        let decoded = try samples(of: image)
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let (width, height, stored) = oriented(decoded.stored, width: image.width, height: image.height, orientation: orientation)
        var notes = [Note.picture]
        if decoded.colour { notes.append(Note.colour) }
        let kind = type == "public.png" ? "PNG" : "JPEG"
        return CalibratedImage(width: width, height: height, stored: stored, x: nil, y: nil, fileName: fileName,
                               source: "\(kind) picture · " + notes.joined(separator: " · "), voltage: nil, notes: notes)
    }

    package static func checkSize(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw Refusal.notPicture }
        guard width <= maximumSide, height <= maximumSide, width * height <= maximumPixels else {
            throw Refusal.tooLarge(width: width, height: height)
        }
    }

    // MARK: - The decoded samples

    /// The grey of each pixel at the decoded bit depth (8 or 16), and whether any pixel's colour channels differ.
    private static func samples(of image: CGImage) throws -> (stored: StoredPixels, colour: Bool) {
        let info = image.bitmapInfo
        guard !info.contains(.floatComponents) else { throw Refusal.layout("floating-point samples") }
        let bits = image.bitsPerComponent
        guard bits == 8 || bits == 16 else { throw Refusal.layout("\(bits) bits a sample") }
        guard image.bitsPerPixel % bits == 0 else { throw Refusal.layout("\(image.bitsPerPixel) bits a pixel") }
        let perPixel = image.bitsPerPixel / bits
        guard let space = image.colorSpace else { throw Refusal.layout("no colour space") }
        guard let provider = image.dataProvider, let cfData = provider.data else { throw Refusal.notPicture }
        let data = cfData as Data
        let (width, height, rowBytes) = (image.width, image.height, image.bytesPerRow)
        guard data.count >= (height - 1) * rowBytes + width * image.bitsPerPixel / 8 else { throw Refusal.notPicture }

        // Where the colour channels sit among the pixel's samples (logical order, before the byte order is applied).
        let alpha = image.alphaInfo
        guard alpha != .alphaOnly else { throw Refusal.layout("alpha only") }
        guard alpha != .premultipliedFirst && alpha != .premultipliedLast else { throw Refusal.layout("premultiplied alpha") }
        let hasAlpha = alpha != .none
        let alphaFirst = alpha == .first || alpha == .noneSkipFirst
        var palette: [[UInt8]]?
        let colourChannels: Int
        switch space.model {
        case .monochrome: colourChannels = 1
        case .rgb: colourChannels = 3
        case .indexed:
            guard bits == 8, let base = space.baseColorSpace, base.model == .rgb || base.model == .monochrome else {
                throw Refusal.layout("a palette over another colour space")
            }
            let channels = base.model == .rgb ? 3 : 1
            let table = space.colorTable ?? []
            let count = min(space.colorTableCount, table.count / channels)
            palette = (0..<count).map { Array(table[$0 * channels..<($0 + 1) * channels]) }
            colourChannels = 1
        case .cmyk: throw Refusal.cmyk
        default: throw Refusal.layout("colour space model \(space.model.rawValue)")
        }
        guard perPixel == colourChannels + (hasAlpha ? 1 : 0) else {
            throw Refusal.layout("\(perPixel) samples a pixel for \(colourChannels) colour channels")
        }
        let firstColour = hasAlpha && alphaFirst ? 1 : 0

        // Byte order: a 32-bit little-endian pixel of four 8-bit samples is stored reversed; 16-bit samples are big-endian unless
        // the image says little.
        let order = CGBitmapInfo(rawValue: info.rawValue & CGBitmapInfo.byteOrderMask.rawValue)
        let reversed8 = bits == 8 && perPixel == 4 && order == .byteOrder32Little
        let little16 = bits == 16 && order == .byteOrder16Little
        guard !(bits == 8 && order == .byteOrder16Little), !(bits == 16 && order == .byteOrder32Little || bits == 16 && order == .byteOrder32Big)
        else { throw Refusal.layout("byte order \(order.rawValue)") }

        let count = width * height
        var colour = false
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (StoredPixels, Bool) in
            func sample(_ row: Int, _ column: Int, _ k: Int) -> Int {
                let index = reversed8 ? perPixel - 1 - k : k
                if bits == 8 { return Int(raw[row * rowBytes + column * perPixel + index]) }
                let at = row * rowBytes + (column * perPixel + index) * 2
                let a = Int(raw[at]), b = Int(raw[at + 1])
                return little16 ? a | b << 8 : a << 8 | b
            }
            func grey(_ row: Int, _ column: Int) -> Int {
                if let palette {
                    let index = sample(row, column, firstColour)
                    guard palette.indices.contains(index) else { return 0 }
                    let entry = palette[index]
                    let value = Int(entry.max() ?? 0)
                    if entry.count == 3, entry[0] != entry[1] || entry[1] != entry[2] { colour = true }
                    return value
                }
                if colourChannels == 1 { return sample(row, column, firstColour) }
                let r = sample(row, column, firstColour), g = sample(row, column, firstColour + 1), b = sample(row, column, firstColour + 2)
                if r != g || g != b { colour = true }
                return max(r, g, b)
            }
            if bits == 8 {
                var out = [UInt8](repeating: 0, count: count)
                for row in 0..<height { for column in 0..<width { out[row * width + column] = UInt8(grey(row, column)) } }
                return (.uint8(out), colour)
            }
            var out = [UInt16](repeating: 0, count: count)
            for row in 0..<height { for column in 0..<width { out[row * width + column] = UInt16(grey(row, column)) } }
            return (.uint16(out), colour)
        }
    }

    // MARK: - EXIF orientation

    /// The picture turned upright by its EXIF orientation (1 to 8), as Pillow's `exif_transpose`; any other value leaves it.
    package static func oriented(_ stored: StoredPixels, width w: Int, height h: Int, orientation: Int) -> (Int, Int, StoredPixels) {
        guard (2...8).contains(orientation) else { return (w, h, stored) }
        let swaps = orientation >= 5
        let (ow, oh) = swaps ? (h, w) : (w, h)
        /// The source index of output pixel (r, c).
        func from(_ r: Int, _ c: Int) -> Int {
            let (sr, sc): (Int, Int) = switch orientation {
            case 2: (r, w - 1 - c)
            case 3: (h - 1 - r, w - 1 - c)
            case 4: (h - 1 - r, c)
            case 5: (c, r)
            case 6: (h - 1 - c, r)
            case 7: (h - 1 - c, w - 1 - r)
            default: (c, w - 1 - r)   // 8
            }
            return sr * w + sc
        }
        func turn<T>(_ values: [T]) -> [T] {
            var out = values
            for r in 0..<oh { for c in 0..<ow { out[r * ow + c] = values[from(r, c)] } }
            return out
        }
        switch stored {
        case .uint8(let v): return (ow, oh, .uint8(turn(v)))
        case .uint16(let v): return (ow, oh, .uint16(turn(v)))
        case .float32(let v): return (ow, oh, .float32(turn(v)))
        }
    }
}

extension CalibratedImage {
    /// Whether this image is a picture (a PNG or JPEG): not counts, no scale from the file.
    package var isPicture: Bool { notes.contains(PictureImageReader.Note.picture) }
}
