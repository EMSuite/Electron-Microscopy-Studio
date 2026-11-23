//
//  PictureImageReaderTests.swift
//  A PNG or JPEG opens as a picture (#792). Pins I1 to I3 (docs/design/files-exports.md in the suite): the planted files and
//  their truth are tools/parity/picture-parity/make_fixtures.py's, the reference imageio 2.37.4 over Pillow 12.3.0 (what
//  RosettaSciIO 0.14.0's image reader calls), grey by the app's brightest-channel rule (a named deviation: the reference keeps RGB).
//  I1 PNG exact; I2 JPEG grey within 1 level, colour (4:4:4) within 2; I3 the eight EXIF orientations as Pillow's exif_transpose.
//  Red before: no reader, .png and .jpg were refused as files macEM does not open.
//

import XCTest
import ImageIO
import UniformTypeIdentifiers
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class PictureImageReaderTests: XCTestCase {

    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent("picture")

    private struct Truth: Decodable {
        struct File: Decodable { var pin: String; var tolerance: Int; var width: Int; var height: Int; var values: [Int] }
        var files: [String: File]
    }

    private func truth() throws -> Truth {
        try JSONDecoder().decode(Truth.self, from: Data(contentsOf: Self.folder.appendingPathComponent("truth.json")))
    }

    private func values(_ image: CalibratedImage) -> [Int] { (0..<(image.width * image.height)).map { Int(image.value(at: $0)) } }

    // MARK: Pins I1 to I3

    func testEveryPlantedPictureReadsTheReferenceValues() throws {
        let files = try truth().files
        XCTAssertEqual(files.count, 20, "the generator's planted set")
        for (name, want) in files.sorted(by: { $0.key < $1.key }) {
            let image = try PictureImageReader.read(path: Self.folder.appendingPathComponent(name).path)
            XCTAssertEqual(image.width, want.width, name)
            XCTAssertEqual(image.height, want.height, name)
            guard image.width == want.width, image.height == want.height else { continue }
            let got = values(image)
            let largest = zip(got, want.values).map { abs($0 - $1) }.max() ?? 0
            // The measured difference, printed for the record (pin I2's colour tolerance is stated from it).
            print("picture-parity \(want.pin) \(name): largest difference \(largest) levels (tolerance \(want.tolerance))")
            XCTAssertLessThanOrEqual(largest, want.tolerance, "\(name) (\(want.pin))")
        }
    }

    func testDepthIsKept() throws {
        let sixteen = try PictureImageReader.read(path: Self.folder.appendingPathComponent("grey16.png").path)
        guard case .uint16 = sixteen.stored else { return XCTFail("a 16-bit PNG stays 16-bit: \(sixteen.stored.bytesPerPixel) bytes") }
        let eight = try PictureImageReader.read(path: Self.folder.appendingPathComponent("rgb8.png").path)
        guard case .uint8 = eight.stored else { return XCTFail("an 8-bit colour PNG is one byte a pixel") }
    }

    // MARK: What the header says

    /// The header reads "Picture, not counts, scale not in the file"; colour says how it became grey. No axes: the scale is typed or
    /// fitted to a ring, and the room names that source.
    func testAPictureSaysItIsAPictureAndHasNoScale() throws {
        let grey = try PictureImageReader.read(path: Self.folder.appendingPathComponent("grey8.png").path)
        XCTAssertEqual(grey.notes, ["Picture, not counts, scale not in the file"], "the wording, pinned literally")
        XCTAssertNil(grey.x)
        XCTAssertNil(grey.y)
        XCTAssertNil(grey.voltage)
        XCTAssertEqual(grey.source, "PNG picture")
        XCTAssertEqual(grey.fileName, "grey8.png")
        let colour = try PictureImageReader.read(path: Self.folder.appendingPathComponent("colour-baseline.jpg").path)
        XCTAssertEqual(colour.notes, [PictureImageReader.Note.picture, PictureImageReader.Note.colour])
        XCTAssertEqual(colour.source, "JPEG picture")
        XCTAssertFalse(ImagePresentation.startsWithScaleBar(notes: grey.notes), "a figure's own bar is pixels: ours starts hidden")
        XCTAssertNotNil(ParticleFormat.renderNote(notes: grey.notes))
    }

    // MARK: Refusals

    func testAnimationsCMYKAndOversizedPicturesAreRefusedByName() {
        func refusal(_ name: String) -> PictureImageReader.Refusal? {
            do { _ = try PictureImageReader.read(path: Self.folder.appendingPathComponent(name).path); return nil }
            catch { return error as? PictureImageReader.Refusal }
        }
        XCTAssertEqual(refusal("refused-animated.png"), .animated(frames: 3))
        XCTAssertEqual(refusal("refused-cmyk.jpg"), .cmyk)
        XCTAssertEqual(refusal("refused-large.png"), .tooLarge(width: 20_000, height: 20_000))
        XCTAssertEqual(PictureImageReader.Refusal.tooLarge(width: 20_000, height: 20_000).reason,
                       "it is 20000 × 20000 pixels, more than the 268 million a picture may have.")
        XCTAssertEqual(PictureImageReader.Refusal.cmyk.reason, "it is a CMYK picture, made for print; save it as RGB or grey.")
    }

    func testBytesThatAreNoPictureAreRefused() throws {
        let path = try DM4TestFile.write(Data("not a picture".utf8), named: "pattern.png", for: self)
        XCTAssertThrowsError(try PictureImageReader.read(path: path)) { error in
            XCTAssertEqual(error as? PictureImageReader.Refusal, .notPicture)
        }
        XCTAssertThrowsError(try ImageOpening.openNow(path: path)) { error in
            XCTAssertEqual((error as? ImageOpening.Refusal)?.errorDescription,
                           "pattern.png is not read: it is not a PNG or JPEG picture (or its extension and its contents disagree).")
        }
    }

    // MARK: Routing

    /// Open, a drop and Finder's Open With route a picture to the image rooms (the Diffraction room among them). Mutation: the
    /// inventory line removed (the sniff calls a PNG unknown and refuses it).
    func testAPictureIsRoutedToTheImageRooms() throws {
        let png = try DM4TestFile.write(Data(contentsOf: Self.folder.appendingPathComponent("grey8.png")), named: "SAED 1.PNG", for: self)
        XCTAssertEqual(FileRouting.inventory(path: png), FileInventory(image: true))
        XCTAssertEqual(FileRouting.inventory(path: png).landing, .image)
        let jpg = URL(fileURLWithPath: "/tmp/pattern.jpeg")
        XCTAssertEqual(FileRouting.dropped([jpg]).accepted, [jpg])
        for ext in ["png", "jpg", "jpeg"] { XCTAssertTrue(FileRouting.openableExtensions.contains(ext), ext) }
        let opened = try ImageOpening.openNow(path: png)
        XCTAssertEqual(opened.width, 13)
        XCTAssertEqual(opened.notes, [PictureImageReader.Note.picture])
    }

    // MARK: Orientation

    func testOrientationTurnsAsPillowDoes() {
        // 3 × 2: 0 1 2 / 3 4 5
        let stored = StoredPixels.uint8([0, 1, 2, 3, 4, 5])
        func turned(_ o: Int) -> [Float] {
            let r = PictureImageReader.orient(stored, width: 3, height: 2, orientation: o)
            return (0..<(r.width * r.height)).map { r.pixels[$0] }
        }
        XCTAssertEqual(turned(1), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(turned(2), [2, 1, 0, 5, 4, 3])
        XCTAssertEqual(turned(3), [5, 4, 3, 2, 1, 0])
        XCTAssertEqual(turned(4), [3, 4, 5, 0, 1, 2])
        XCTAssertEqual(turned(5), [0, 3, 1, 4, 2, 5])
        XCTAssertEqual(turned(6), [3, 0, 4, 1, 5, 2])
        XCTAssertEqual(turned(7), [5, 2, 4, 1, 3, 0])
        XCTAssertEqual(turned(8), [2, 5, 1, 4, 0, 3])
        XCTAssertEqual(turned(9), [0, 1, 2, 3, 4, 5], "an unknown value leaves the pixels as stored")
    }
}

/// A PNG written in a test through ImageIO, for tests that need a picture and not its parity.
nonisolated enum PicturePlant {
    static func png(grey8 values: [UInt8], width: Int, height: Int) -> Data {
        let provider = CGDataProvider(data: Data(values) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return out as Data
    }
}
