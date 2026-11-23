//
//  PictureImageReaderTests.swift
//  The app's PNG and JPEG reader (#792, plan pins I1 to I3) against RosettaSciIO 0.14.0 (imageio 2.38.1 over Pillow 13.0.0) on the
//  planted files of Fixtures/pictures (tools/parity/picture-pins/generate.py): a PNG's stored values exact, a JPEG's grey within one
//  level and its colour within the stated tolerance, EXIF orientations 1 to 8 as Pillow's exif_transpose. Colour is grey by the app's
//  brightest-channel rule (a named deviation: the reference keeps RGB). CMYK, animated and oversized pictures are refused by name. A
//  picture says it is one, carries no axis, opens through `ImageOpening`, is routed to the Image room, and the Diffraction header says
//  "Picture, not counts" and "scale not in the file" until a scale is typed.
//

import Foundation
import ImagoCore
import TEMCore
import XCTest
@testable import macTEM

nonisolated final class PictureImageReaderTests: XCTestCase {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pictures")
    private static func path(_ name: String) -> String { folder.appendingPathComponent(name).path }

    /// The largest difference allowed between ImageIO's and Pillow's decoding of a colour JPEG, in grey levels (pin I2). Measured on
    /// GitHub's macos-26 runner by this test's first run and stated here; the JPEG standard lets two decoders differ.
    private static let colourJPEGTolerance = 2

    private struct Pin: Decodable { let name: String; let kind: String; let shape: [Int]; let dtype: String; let compare: String; let grey: [Int] }
    private struct Pins: Decodable { let cases: [Pin]; let refused: [String] }
    private static func pins() throws -> Pins {
        try JSONDecoder().decode(Pins.self, from: Data(contentsOf: folder.appendingPathComponent("pins.json")))
    }

    private static func values(_ stored: StoredPixels) -> [Int] {
        switch stored {
        case .uint8(let v): v.map(Int.init)
        case .uint16(let v): v.map(Int.init)
        case .float32(let v): v.map { Int($0) }
        }
    }

    /// Pins I1 to I3. Mutation: a colour-managed draw (gamma or profile applied), RGB read as its red channel, the 16-bit byte order
    /// swapped, a palette read as its indices, or an orientation turned the wrong way - red.
    func testEveryPlantedPictureEqualsTheReference() throws {
        let pins = try Self.pins()
        XCTAssertEqual(pins.cases.count, 22)
        var measured: [String: Int] = [:]
        for pin in pins.cases {
            let image = try PictureImageReader.read(path: Self.path(pin.name))
            XCTAssertEqual([image.height, image.width], pin.shape, pin.name)
            switch image.stored {
            case .uint8: XCTAssertEqual(pin.dtype, "uint8", pin.name)
            case .uint16: XCTAssertEqual(pin.dtype, "uint16", pin.name)
            case .float32: XCTFail("\(pin.name): a picture is never Float32")
            }
            let got = Self.values(image.stored)
            guard got.count == pin.grey.count else { XCTFail("\(pin.name): \(got.count) pixels"); continue }
            let worst = zip(got, pin.grey).map { abs($0 - $1) }.max() ?? 0
            measured[pin.name] = worst
            switch pin.compare {
            case "exact": XCTAssertEqual(got, pin.grey, pin.name)
            case "level1": XCTAssertLessThanOrEqual(worst, 1, pin.name)
            default: XCTAssertLessThanOrEqual(worst, Self.colourJPEGTolerance, "\(pin.name): the measured difference is \(worst)")
            }
            XCTAssertNil(image.x, pin.name)
            XCTAssertNil(image.y, pin.name)
            XCTAssertTrue(image.isPicture, pin.name)
        }
        // The measured JPEG differences, for the PR and docs/parity.md.
        print("PictureImageReader JPEG differences:", measured.filter { $0.key.hasSuffix(".jpg") }.sorted { $0.key < $1.key })
    }

    /// A colour picture says it is shown as grey; a grey one, and RGB with equal channels, do not.
    func testColourIsNamed() throws {
        XCTAssertTrue(try PictureImageReader.read(path: Self.path("rgb.png")).notes.contains(PictureImageReader.Note.colour))
        XCTAssertFalse(try PictureImageReader.read(path: Self.path("grey8.png")).notes.contains(PictureImageReader.Note.colour))
        XCTAssertFalse(try PictureImageReader.read(path: Self.path("rgb-grey.png")).notes.contains(PictureImageReader.Note.colour))
        let grey = try PictureImageReader.read(path: Self.path("grey8.png"))
        XCTAssertEqual(grey.notes, [PictureImageReader.Note.picture])
        XCTAssertEqual(grey.source, "PNG picture · Picture, not counts, scale not in the file")
    }

    /// CMYK, animated and oversized pictures are refused by name, never read. Mutation: a refusal dropped - red.
    func testCMYKAnimatedAndOversizedAreRefused() throws {
        XCTAssertThrowsError(try PictureImageReader.read(path: Self.path("cmyk.jpg"))) { XCTAssertEqual($0 as? PictureImageReader.Refusal, .cmyk) }
        XCTAssertThrowsError(try PictureImageReader.read(path: Self.path("animated.png"))) {
            XCTAssertEqual($0 as? PictureImageReader.Refusal, .animated(frames: 3))
        }
        XCTAssertThrowsError(try PictureImageReader.checkSize(width: 70_000, height: 2)) {
            XCTAssertEqual($0 as? PictureImageReader.Refusal, .tooLarge(width: 70_000, height: 2))
        }
        XCTAssertThrowsError(try PictureImageReader.checkSize(width: 20_000, height: 20_000)) {
            XCTAssertEqual($0 as? PictureImageReader.Refusal, .tooLarge(width: 20_000, height: 20_000))
        }
        XCTAssertNoThrow(try PictureImageReader.checkSize(width: 16_384, height: 16_384))
        XCTAssertThrowsError(try PictureImageReader.read(data: Data("not a picture".utf8), fileName: "x.png"))
        let refusal = ImageOpening.Refusal.picture(file: "print.jpg", .cmyk)
        XCTAssertEqual(refusal.errorDescription, "print.jpg is not read: it is a CMYK picture (made for print); only grey and RGB pictures are read.")
    }

    /// The EXIF turn on a known 2 × 3 grid, by hand: each orientation as Pillow's exif_transpose turns it.
    func testOrientationsTurnAsPillowDoes() {
        // 0 1 2
        // 3 4 5
        let grid = StoredPixels.uint8([0, 1, 2, 3, 4, 5])
        func turned(_ o: Int) -> (Int, Int, [Int]) {
            let (w, h, s) = PictureImageReader.oriented(grid, width: 3, height: 2, orientation: o)
            return (w, h, Self.values(s))
        }
        XCTAssertEqual(turned(1).2, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(turned(2).2, [2, 1, 0, 5, 4, 3])
        XCTAssertEqual(turned(3).2, [5, 4, 3, 2, 1, 0])
        XCTAssertEqual(turned(4).2, [3, 4, 5, 0, 1, 2])
        XCTAssertEqual(turned(5).0, 2); XCTAssertEqual(turned(5).1, 3)
        XCTAssertEqual(turned(5).2, [0, 3, 1, 4, 2, 5])
        XCTAssertEqual(turned(6).2, [3, 0, 4, 1, 5, 2])
        XCTAssertEqual(turned(7).2, [5, 2, 4, 1, 3, 0])
        XCTAssertEqual(turned(8).2, [2, 5, 1, 4, 0, 3])
    }

    /// A PNG or JPEG is routed to the Image room and opens through the one entry point. Mutation: the extensions left out of
    /// `ImageOpening` or the routing - red.
    func testAPictureOpensAsAnImage() throws {
        for ext in ["png", "jpg", "jpeg"] { XCTAssertTrue(ImageOpening.readableExtensions.contains(ext)) }
        XCTAssertEqual(FileRouting.inventory(path: Self.path("grey8.png")), FileInventory(image: true))
        XCTAssertEqual(FileRouting.inventory(path: Self.path("grey.jpg")), FileInventory(image: true))
        let image = try ImageOpening.openNow(path: Self.path("grey8.png"))
        XCTAssertTrue(image.isPicture)
        XCTAssertNotNil(ParticleCompute.renderNote(notes: image.notes), "burnt-in labels in a picture are pixels")
    }

    /// The Diffraction room's header says what a picture is, and where its scale came from once there is one.
    /// Mutation: the picture words dropped, or "no scale yet" for a picture - red.
    func testTheDiffractionHeaderSaysPictureAndWhereTheScaleCameFrom() throws {
        let picture = try PictureImageReader.read(path: Self.path("grey8.png"))
        XCTAssertEqual(DiffractionHeaderText.summary(image: picture, calibration: nil, volts: nil),
                       "Picture, not counts · 12 × 9 px · scale not in the file")
        let typed = DiffractionCalibration(source: .typed, deltaQ: 0.0125, ring: nil)
        let withScale = DiffractionHeaderText.summary(image: picture, calibration: typed, volts: nil)
        XCTAssertTrue(withScale.hasPrefix("Picture, not counts · 12 × 9 px · scale: typed · Δq "), withScale)
        let counts = CalibratedImage(width: 2, height: 2, stored: .uint8([0, 1, 2, 3]), x: nil, y: nil, fileName: "a.dm4", source: "",
                                     voltage: nil)
        XCTAssertEqual(DiffractionHeaderText.summary(image: counts, calibration: nil, volts: nil), "2 × 2 px · no scale yet")
    }
}
