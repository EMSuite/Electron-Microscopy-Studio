//
//  TIAImageReaderTests.swift
//  A TIA image or pattern opens (#901): the routing sends a `.ser` or an `.emi` of an image series to the image rooms and sends a
//  series of spectra to their rooms (`TIASpectraTests`); the open reads the image with its calibration in the app's terms (the scale, and the origin from the
//  offset the kit keeps in metres or 1/metres), its voltage and the panel's metadata from the `.emi`; a `.ser` alone says its units
//  are assumed; an `.emi` whose `.ser` cannot be opened is refused in a sentence that names the folder. The files are planted here
//  (the TIA layout FormatoTIA reads: series header, one dimension, the offset arrays, one element and its time tag; an `.emi` with
//  one `<ObjectInfo>`), each checked against HyperSpy 2.5.0's `load` when written: a 3 x 4 float32 image of 0 to 11, flipped as
//  RosettaSciIO flips it (first row 8, 9, 10, 11), scale 0.1 1 / nm with offset −2e8 1/m (the pattern with its `.emi`), 0.2 nm
//  with offset −4e−10 m (the image alone); the `.emi` maps beam_energy 200, camera_length 490, acquisition_mode TEM, the
//  microscope, the camera WA-Orius and 2016-02-21 17:51:15. Red before: `.ser` and `.emi` were not openable extensions, and the
//  routing had no TIA arm.
//

import XCTest
import Darwin
import FormatoCore
import ImagoCore
import TEMCore
@testable import macTEM

nonisolated final class TIAImageReaderTests: XCTestCase {

    // MARK: Planting

    private struct Bytes {
        var data = Data()
        mutating func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        mutating func f32(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        mutating func text(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
    }

    /// A `.ser` of one element (SeriesVersion 528, one dimension of size 1 named "Number", a time tag), float32: an image of
    /// `rows` x `columns` values, or a spectrum of `columns` channels, with the calibration offset and delta on both axes.
    private static func ser(rows: Int, columns: Int, values: [Float], delta: Double, offset: Double, spectrum: Bool = false) -> Data {
        var dims = Bytes()
        dims.u32(1); dims.f64(0); dims.f64(1); dims.u32(0); dims.u32(6); dims.text("Number"); dims.u32(0)
        let offsetsAt = 30 + dims.data.count
        let elementAt = offsetsAt + 8
        var element = Bytes()
        if spectrum {
            element.f64(offset); element.f64(delta); element.u32(0); element.u16(7); element.u32(columns)
        } else {
            element.f64(offset); element.f64(delta); element.u32(0); element.f64(offset); element.f64(delta); element.u32(0)
            element.u16(7); element.u32(columns); element.u32(rows)
        }
        for v in values { element.f32(v) }
        var file = Bytes()
        file.u16(0x4949); file.u16(0x0197); file.u16(528)
        file.u32(spectrum ? 0x4120 : 0x4122); file.u32(0x4152); file.u32(1); file.u32(1); file.u32(offsetsAt); file.u32(1)
        file.data.append(dims.data)
        file.u32(elementAt); file.u32(elementAt + element.data.count)
        file.data.append(element.data)
        file.u16(0x4152); file.u16(0); file.u32(0)
        return file.data
    }

    /// An `.emi` of one `<ObjectInfo>`: 200 kV, the Tecnai, `mode`, a 0.49 m camera length, the WA-Orius camera.
    private static func emi(mode: String) -> Data {
        var file = Bytes()
        file.data.append(contentsOf: [0x4A, 0x4B, 0x00, 0x02])
        file.text("<ObjectInfo><AcquireDate>Sun Feb 21 17:51:15 2016</AcquireDate><ExperimentalDescription><Root>"
            + "<Data><Label>High tension</Label><Value>200</Value><Unit>kV</Unit></Data>"
            + "<Data><Label>Microscope</Label><Value>Microscope Tecnai 200 kV D2267 SuperTwin</Value><Unit></Unit></Data>"
            + "<Data><Label>Mode</Label><Value>\(mode)</Value><Unit></Unit></Data>"
            + "<Data><Label>Camera length</Label><Value>0.49</Value><Unit>m</Unit></Data>"
            + "</Root></ExperimentalDescription>"
            + "<AcquireInfo><CameraNamePath>WA-Orius</CameraNamePath><DwellTimePath>0.0625</DwellTimePath></AcquireInfo></ObjectInfo>")
        return file.data
    }

    private static let ramp = (0..<12).map(Float.init)

    /// A folder of its own with `files` in it.
    private func folder(_ files: [String: Data]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: dir.appendingPathComponent(name)) }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func patternFolder() throws -> URL {
        try folder(["pattern.emi": Self.emi(mode: "TEM Diffraction"),
                    "pattern_1.ser": Self.ser(rows: 3, columns: 4, values: Self.ramp, delta: 1.0e8, offset: -2.0e8)])
    }

    // MARK: Routing

    /// Mutation: the `.tia` arm sends a spectrum to the image rooms, or `ser`/`emi` leave `openableExtensions`.
    func testTheRoutingSendsATIAImageToTheImageRoomsAndSpectraElsewhere() throws {
        XCTAssertTrue(FileRouting.openableExtensions.contains("ser"))
        XCTAssertTrue(FileRouting.openableExtensions.contains("emi"))
        let patterns = try patternFolder()
        XCTAssertEqual(FileRouting.inventory(path: patterns.appendingPathComponent("pattern.emi").path), FileInventory(image: true))
        XCTAssertEqual(FileRouting.inventory(path: patterns.appendingPathComponent("pattern_1.ser").path), FileInventory(image: true))
        let spectra = try folder(["spectrum_1.ser": Self.ser(rows: 1, columns: 8, values: (0..<8).map(Float.init), delta: 10, offset: 100,
                                                            spectrum: true)])
        let found = FileRouting.inventory(path: spectra.appendingPathComponent("spectrum_1.ser").path)
        XCTAssertFalse(found.image)
        XCTAssertTrue(found.asksForSpectraRoom, "spectra go to their room (TIASpectraTests), never the image rooms")
        XCTAssertThrowsError(try ImageOpening.openNow(path: spectra.appendingPathComponent("spectrum_1.ser").path)) { error in
            XCTAssertEqual(error as? ImageOpening.Refusal, .tia(file: "spectrum_1.ser", .spectra))
        }
    }

    // MARK: The image

    /// The pattern of an `.emi`: its pixels flipped as RosettaSciIO flips them, 0.1 1 / nm a pixel with the zero at pixel 2 (−0.2
    /// 1 / nm over 0.1), 200 kV in volts, no note. Mutation: the offset taken as 1 / nm (origin 2e9), the voltage left in kV, the
    /// rows not flipped.
    func testAnEMIOpensItsPatternWithTheCalibrationAndVoltageItRecords() throws {
        let image = try ImageOpening.openNow(path: try patternFolder().appendingPathComponent("pattern.emi").path)
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)
        XCTAssertEqual(image.stored, .float32([8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3]))
        for axis in [image.x, image.y] {
            let axis = try XCTUnwrap(axis)
            XCTAssertEqual(axis.unit, "1 / nm")
            XCTAssertEqual(axis.scale, 0.1, accuracy: 1e-15)
            XCTAssertEqual(axis.origin, 2, accuracy: 1e-9)
        }
        XCTAssertEqual(image.voltage, 200_000)
        XCTAssertEqual(image.source, "pattern_1.ser")
        XCTAssertEqual(image.notes, [])
    }

    /// A `.ser` with its `.emi` beside it takes the `.emi`'s units and voltage; alone, its units are assumed and the note says so.
    /// Mutation: the `.emi` beside a `.ser` not looked for, or the note left out.
    func testASerTakesItsEMIWhenItIsBesideItAndSaysItsUnitsAreAssumedAlone() throws {
        let withEMI = try ImageOpening.openNow(path: try patternFolder().appendingPathComponent("pattern_1.ser").path)
        XCTAssertEqual(withEMI.x?.unit, "1 / nm")
        XCTAssertEqual(withEMI.voltage, 200_000)
        XCTAssertEqual(withEMI.notes, [])

        let alone = try folder(["image_1.ser": Self.ser(rows: 3, columns: 4, values: Self.ramp, delta: 2.0e-10, offset: -4.0e-10)])
        let image = try ImageOpening.openNow(path: alone.appendingPathComponent("image_1.ser").path)
        let x = try XCTUnwrap(image.x)
        XCTAssertEqual(x.unit, "nm")
        XCTAssertEqual(x.scale, 0.2, accuracy: 1e-12)
        XCTAssertEqual(x.origin, 2, accuracy: 1e-9)
        XCTAssertNil(image.voltage)
        XCTAssertEqual(image.notes, [TIAImageReader.unitsAssumedNote])
        XCTAssertEqual(TIAImageReader.unitsAssumedNote, "units assumed, no .emi")
    }

    /// The panel's fields from the `.emi`, as HyperSpy maps them; a `.ser` alone records nothing. Mutation: the camera length
    /// taken in metres, the exposure's text not read as a number, the date without its time.
    func testTheEMIGivesTheAcquisitionPanelItsFields() throws {
        let found = AcquisitionMetadata.read(path: try patternFolder().appendingPathComponent("pattern.emi").path)
        XCTAssertEqual(found.highTensionKV?.value, 200)
        XCTAssertEqual(try XCTUnwrap(found.cameraLengthMM?.value), 490, accuracy: 1e-9)
        XCTAssertEqual(found.exposureS?.value, 0.0625)
        XCTAssertEqual(found.mode?.value, "TEM")
        XCTAssertEqual(found.instrument?.value, "Tecnai 200 kV D2267 SuperTwin")
        XCTAssertEqual(found.detector?.value, "WA-Orius")
        XCTAssertEqual(found.acquired?.value, "2016-02-21 17:51:15")

        let alone = try folder(["image_1.ser": Self.ser(rows: 3, columns: 4, values: Self.ramp, delta: 2.0e-10, offset: -4.0e-10)])
        XCTAssertEqual(AcquisitionMetadata.read(path: alone.appendingPathComponent("image_1.ser").path), AcquisitionMetadata())
    }

    // MARK: The folder

    /// An `.emi` whose `.ser` does not open is refused in a sentence that says it needs the folder; a TIA file is read with its
    /// folder's grant, and a sandbox refusal (EPERM) asks for the folder. Mutation: the `.ser` files not looked at, the TIA
    /// extensions left out of `readsItsFolder`. A file mode (EACCES) stands in for the sandbox here: the tests are not sandboxed.
    func testAnEMIWhoseSeriesCannotBeOpenedSaysItNeedsTheFolder() throws {
        let dir = try patternFolder()
        let ser = dir.appendingPathComponent("pattern_1.ser"), emi = dir.appendingPathComponent("pattern.emi")
        XCTAssertNil(TIAImageReader.seriesOpenError(emi))
        XCTAssertEqual(chmod(ser.path, 0), 0)
        defer { chmod(ser.path, 0o644) }
        XCTAssertEqual(TIAImageReader.seriesOpenError(emi), EACCES)
        XCTAssertNil(TIAImageReader.seriesOpenError(ser), "a .ser is never refused for its .emi")
        let sentence = try XCTUnwrap(TIAImageReader.unreadableSeriesRefusal(emi))
        XCTAssertTrue(sentence.hasPrefix("The .ser files beside pattern.emi cannot be read: macOS does not let Electron Microscopy Studio open them ("),
                      sentence)
        XCTAssertTrue(sentence.hasSuffix("); a TIA .emi needs the acquisition's folder, not pattern.emi alone."), sentence)
        XCTAssertEqual(FileRouting.inventory(path: emi.path).refusal, sentence)

        XCTAssertTrue(FolderGrants.readsItsFolder(emi))
        XCTAssertTrue(FolderGrants.readsItsFolder(ser))
        XCTAssertFalse(FolderGrants.asksForFolder(of: emi, refused: true), "a file mode is not the sandbox's: no grant changes it")
        XCTAssertTrue(FolderGrants.askSentence(for: emi).contains("reads the TIA file pattern.emi with the .ser series beside it"))
    }
}
