//
//  PictureImageReader.swift
//  Role: open a PNG or JPEG as macEM's `CalibratedImage` (#792): a diffraction pattern from a paper, a camera's export, a screen
//        capture. Read in the app through ImageIO, not in a kit (the kits import no Apple image framework). The values are the
//        file's decoded samples, taken from the decoded image's own buffer with no drawing, so no colour management touches them
//        (a colour-managed draw changes code values). Colour becomes grey by the app's rule for colour renders (#541): each pixel
//        the brightest of its red, green and blue. Alpha is not data and is dropped. EXIF rotation is applied, as Pillow's
//        `ImageOps.exif_transpose` does. A picture has no scale: the axes are nil, and the room's scale is typed or fitted to a
//        ring of a known phase, which the room names as its source.
//
//  Reference: RosettaSciIO 0.14.0 `rsciio.image.file_reader` (imageio over Pillow 12.3.0), pins I1 to I3 in
//  tools/parity/picture-parity. One named deviation: the reference keeps RGB, the app reads grey (the brightest channel).
//

import CoreGraphics
import Foundation
import FormatoCore
import ImageIO
import TEMBase
import TEMSEM

package nonisolated enum PictureImageReader {
    /// The extensions read here, lower case. PNG and JPEG only: HEIC and BMP are not read (docs/design/files-exports.md).
    package static let extensions = ["png", "jpg", "jpeg"]

    /// The most pixels a picture may hold: 16384 × 16384. A larger one is refused in words before its pixels are decoded.
    package static let maxPixels = 16_384 * 16_384

    /// What a picture says about itself, worded once. The header shows it: it is a picture, not counts, and its scale is not in it.
    package enum Note {
        package static let picture = "Picture, not counts, scale not in the file"
        package static let colour = "colour shown as grey: each pixel is the brightest of its red, green and blue"
    }

    /// Why a picture is not read. Each names what the file holds.
    package enum Refusal: Error, Equatable {
        case notPicture
        case animated(frames: Int)
        case cmyk
        case tooLarge(width: Int, height: Int)
        case layout(String)

        /// One sentence for the person who opened the file.
        package var reason: String {
            switch self {
            case .notPicture: "it is not a PNG or JPEG picture (or its extension and its contents disagree)."
            case .animated(let frames): "it is an animation of \(frames) frames; only a still picture is read."
            case .cmyk: "it is a CMYK picture, made for print; save it as RGB or grey."
            case .tooLarge(let width, let height):
                "it is \(width) × \(height) pixels, more than the \(PictureImageReader.maxPixels / 1_000_000) million a picture may have."
            case .layout(let what): "its pixel layout is not read (\(what))."
            }
        }
    }

    package static func isPicture(path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: - Reading

    package static func read(path: String) throws -> CalibratedImage {
        let url = URL(fileURLWithPath: path)
        // ImageIO declines a header past its own limits without saying why, so the file's own header is read first: a picture
        // too large is refused by its size, not as "not a picture".
        if let size = headerSize(url: url) {
            let pixels = size.width.multipliedReportingOverflow(by: size.height)
            if pixels.overflow || pixels.partialValue > maxPixels { throw Refusal.tooLarge(width: size.width, height: size.height) }
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { throw Refusal.notPicture }
        return try read(source: source, fileName: formatoDisplayFileName(path))
    }

    /// The width and height a PNG's IHDR or a JPEG's start-of-frame states, read from the first 256 KiB; nil when neither is there.
    private static func headerSize(url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1_024) else { return nil }
        return headerSize(bytes: [UInt8](data))
    }

    private static func headerSize(bytes: [UInt8]) -> (width: Int, height: Int)? {
        func big(_ at: Int, _ count: Int) -> Int? {
            guard at >= 0, at + count <= bytes.count else { return nil }
            return bytes[at ..< at + count].reduce(0) { $0 << 8 | Int($1) }
        }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if bytes.starts(with: png) {
            guard bytes.count >= 24, Array(bytes[12 ..< 16]) == Array("IHDR".utf8),
                  let width = big(16, 4), let height = big(20, 4) else { return nil }
            return (width, height)
        }
        guard bytes.starts(with: [0xFF, 0xD8]) else { return nil }
        var at = 2
        while at + 4 <= bytes.count {
            guard bytes[at] == 0xFF else { return nil }
            let marker = bytes[at + 1]
            if marker == 0xFF { at += 1; continue }
            if marker == 0x01 || (0xD0 ... 0xD7).contains(marker) { at += 2; continue }
            guard let length = big(at + 2, 2), length >= 2 else { return nil }
            let frame = (0xC0 ... 0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker)
            if frame {
                guard let height = big(at + 5, 2), let width = big(at + 7, 2) else { return nil }
                return (width, height)
            }
            if marker == 0xDA { return nil }
            at += 2 + length
        }
        return nil
    }

    private static func read(source: CGImageSource, fileName: String) throws -> CalibratedImage {
        guard let type = CGImageSourceGetType(source) as String?, let format = Format(type) else { throw Refusal.notPicture }
        // The header's size first, so a picture too large is refused before anything else is asked of it.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        func integer(_ key: CFString) -> Int? { (properties[key] as? NSNumber)?.intValue }
        if let width = integer(kCGImagePropertyPixelWidth), let height = integer(kCGImagePropertyPixelHeight), width > 0, height > 0 {
            let pixels = width.multipliedReportingOverflow(by: height)
            if pixels.overflow || pixels.partialValue > maxPixels { throw Refusal.tooLarge(width: width, height: height) }
        }
        let frames = CGImageSourceGetCount(source)
        guard frames > 0 else { throw Refusal.notPicture }
        guard frames == 1 else { throw Refusal.animated(frames: frames) }
        if (properties[kCGImagePropertyColorModel] as? String) == (kCGImagePropertyColorModelCMYK as String) { throw Refusal.cmyk }
        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions) else { throw Refusal.notPicture }
        guard image.width > 0, image.height > 0 else { throw Refusal.notPicture }
        guard image.width.multipliedReportingOverflow(by: image.height).partialValue <= maxPixels else {
            throw Refusal.tooLarge(width: image.width, height: image.height)
        }
        let decoded = try grey(image)
        let orientation = integer(kCGImagePropertyOrientation) ?? 1
        let oriented = orient(decoded.pixels, width: image.width, height: image.height, orientation: orientation)
        var notes = [Note.picture]
        if decoded.wasColour { notes.append(Note.colour) }
        return CalibratedImage(width: oriented.width, height: oriented.height, stored: oriented.pixels, x: nil, y: nil,
                               fileName: fileName, source: format.sourceText, voltage: nil, notes: notes)
    }

    private enum Format {
        case png, jpeg
        init?(_ uti: String) {
            switch uti {
            case "public.png": self = .png
            case "public.jpeg": self = .jpeg
            default: return nil
            }
        }
        var sourceText: String {
            switch self {
            case .png: "PNG picture"
            case .jpeg: "JPEG picture"
            }
        }
    }

    // MARK: - Samples

    /// The decoded samples as grey at their own depth: one byte a pixel for 8 bits and less, two for 16 bits.
    package static func grey(_ image: CGImage) throws -> (pixels: StoredPixels, wasColour: Bool) {
        guard let space = image.colorSpace else { throw Refusal.layout("no colour space") }
        switch space.model {
        case .cmyk: throw Refusal.cmyk
        case .indexed: return try indexed(image, space: space)
        case .monochrome, .rgb: break
        default: throw Refusal.layout("colour model \(space.model.rawValue)")
        }
        guard !image.bitmapInfo.contains(.floatComponents) else { throw Refusal.layout("floating-point samples") }
        let colours = space.model == .monochrome ? 1 : 3
        let alpha = image.alphaInfo
        let hasAlphaSlot = alpha != .none && alpha != .alphaOnly
        guard alpha != .alphaOnly else { throw Refusal.layout("alpha only") }
        let bpc = image.bitsPerComponent, bpp = image.bitsPerPixel
        let components = colours + (hasAlphaSlot ? 1 : 0)
        guard bpc > 0, bpp == bpc * components else { throw Refusal.layout("\(bpp) bits a pixel in \(bpc)-bit samples") }
        guard let data = image.dataProvider?.data as Data? else { throw Refusal.layout("no decoded samples") }
        let width = image.width, height = image.height, rowBytes = image.bytesPerRow
        guard rowBytes * (height - 1) + (width * bpp + 7) / 8 <= data.count else { throw Refusal.layout("short sample buffer") }

        let alphaFirst = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
        let premultiplied = alpha == .premultipliedFirst || alpha == .premultipliedLast
        let order = image.byteOrderInfo
        // The slot a logical component sits in: alpha first or last; within a 32- or 16-bit little-endian word the order reverses.
        func slot(_ logical: Int) -> Int {
            if bpc == 8, order == .order32Little, components == 4 { return 3 - logical }
            if bpc == 8, order == .order16Little, components == 2 { return 1 - logical }
            return logical
        }
        let colourSlots = (0..<colours).map { slot(alphaFirst && hasAlphaSlot ? $0 + 1 : $0) }
        let alphaSlot = hasAlphaSlot ? slot(alphaFirst ? 0 : colours) : nil

        switch bpc {
        case 8:
            guard order != .order32Little || components == 4, order != .order16Little || components == 2 else {
                throw Refusal.layout("8-bit samples in a little-endian word of another size")
            }
            var out = [UInt8](repeating: 0, count: width * height)
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for row in 0..<height {
                    let base = row * rowBytes
                    for column in 0..<width {
                        let p = base + column * components
                        var value = 0
                        for s in colourSlots { value = max(value, Int(raw[p + s])) }
                        if premultiplied, let a = alphaSlot.map({ Int(raw[p + $0]) }) {
                            value = a == 0 ? 0 : min(255, (value * 255 + a / 2) / a)
                        }
                        out[row * width + column] = UInt8(value)
                    }
                }
            }
            return (.uint8(out), colours == 3)
        case 16:
            guard [CGImageByteOrderInfo.orderDefault, .order16Big, .order16Little].contains(order) else {
                throw Refusal.layout("16-bit samples in a 32-bit word")
            }
            let little = order == .order16Little
            var out = [UInt16](repeating: 0, count: width * height)
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                func sample(_ at: Int) -> Int {
                    little ? Int(raw[at]) | Int(raw[at + 1]) << 8 : Int(raw[at]) << 8 | Int(raw[at + 1])
                }
                for row in 0..<height {
                    let base = row * rowBytes
                    for column in 0..<width {
                        let p = base + column * components * 2
                        var value = 0
                        for s in colourSlots { value = max(value, sample(p + 2 * s)) }
                        if premultiplied, let a = alphaSlot.map({ sample(p + 2 * $0) }) {
                            value = a == 0 ? 0 : min(65_535, (value * 65_535 + a / 2) / a)
                        }
                        out[row * width + column] = UInt16(value)
                    }
                }
            }
            return (.uint16(out), colours == 3)
        case 1, 2, 4:
            guard components == 1 else { throw Refusal.layout("\(bpc)-bit colour samples") }
            let mask = (1 << bpc) - 1
            var out = [UInt8](repeating: 0, count: width * height)
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for row in 0..<height {
                    for column in 0..<width {
                        let bit = column * bpc
                        let byte = Int(raw[row * rowBytes + bit / 8])
                        out[row * width + column] = UInt8((byte >> (8 - bpc - bit % 8)) & mask)
                    }
                }
            }
            return (.uint8(out), false)
        default:
            throw Refusal.layout("\(bpc)-bit samples")
        }
    }

    /// A palette picture ImageIO hands over as indices: each index looked up in the palette, as Pillow and imageio expand it.
    /// The palette is read by drawing the indices into a context of the palette's own colour space at one pixel for one pixel,
    /// so the colours are the palette's entries, not converted.
    private static func indexed(_ image: CGImage, space: CGColorSpace) throws -> (pixels: StoredPixels, wasColour: Bool) {
        guard let base = space.baseColorSpace, base.model == .rgb || base.model == .monochrome else {
            throw Refusal.layout("a palette that is not RGB or grey")
        }
        let colours = base.model == .rgb ? 3 : 1
        let components = base.model == .rgb ? 4 : 1
        let info: UInt32 = base.model == .rgb ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.none.rawValue
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * components, space: base, bitmapInfo: info) else {
            throw Refusal.layout("a palette that could not be expanded")
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { throw Refusal.layout("a palette that could not be expanded") }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: width * height * components)
        var out = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            var value: UInt8 = 0
            for c in 0..<colours { value = max(value, bytes[i * components + c]) }
            out[i] = value
        }
        return (.uint8(out), colours == 3)
    }

    // MARK: - EXIF orientation

    /// The pixels turned as EXIF orientation `orientation` asks (1 to 8), as Pillow's `ImageOps.exif_transpose`: 2 mirrors left to
    /// right, 3 turns 180°, 4 mirrors top to bottom, 5 transposes, 6 turns 90° clockwise, 7 transverses, 8 turns 90° counter-clockwise.
    /// Any other value leaves the pixels as stored.
    package static func orient(_ pixels: StoredPixels, width w: Int, height h: Int,
                               orientation: Int) -> (pixels: StoredPixels, width: Int, height: Int) {
        guard (2...8).contains(orientation) else { return (pixels, w, h) }
        let swaps = orientation >= 5
        let outWidth = swaps ? h : w, outHeight = swaps ? w : h
        // The stored index of output pixel (r, c).
        func source(_ r: Int, _ c: Int) -> Int {
            switch orientation {
            case 2: r * w + (w - 1 - c)
            case 3: (h - 1 - r) * w + (w - 1 - c)
            case 4: (h - 1 - r) * w + c
            case 5: c * w + r
            case 6: (h - 1 - c) * w + r
            case 7: (h - 1 - c) * w + (w - 1 - r)
            default: c * w + (w - 1 - r)   // 8
            }
        }
        func turned<T>(_ values: [T]) -> [T] {
            var out = values
            for r in 0..<outHeight { for c in 0..<outWidth { out[r * outWidth + c] = values[source(r, c)] } }
            return out
        }
        switch pixels {
        case .uint8(let v): return (.uint8(turned(v)), outWidth, outHeight)
        case .uint16(let v): return (.uint16(turned(v)), outWidth, outHeight)
        case .float32(let v): return (.float32(turned(v)), outWidth, outHeight)
        }
    }
}
