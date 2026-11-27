//
//  EBSDReadErrorWordsTests.swift
//  #852: FormatoKit reads the EBSD files now and words its refusals without naming an app or a room ("this process", "these
//  readers"); the app says them as it did before (`EBSDReadError.inAppWords`, Sources/TEMSEM/EBSDFileMaps.swift). Each reason the
//  app rewords, with the kit's sentence as FormatoKit 0.23.0 writes it, reads as the app's sentence of 2.6.0; a sentence the app
//  does not reword passes as the kit says it, and the reason is kept.
//  Red before: the kit's sentences reached the user ("the system does not let this process read it.").
//

import Foundation
import TEMCore
import XCTest

nonisolated final class EBSDReadErrorWordsTests: XCTestCase {

    private static let app = "Electron Microscopy Studio"

    private func words(_ reason: EBSDReadError.Reason, _ kit: String) -> EBSDReadError {
        EBSDReadError(reason, kit).inAppWords
    }

    func testEachRefusalTheAppRewordsReadsAsTheAppSaidIt() {
        let app = Self.app
        let cases: [(EBSDReadError.Reason, String, String)] = [
            (.notPermitted, "scan.h5 cannot be read: the system does not let this process read it.",
             "scan.h5 cannot be read: \(app) was not given access to it: open it with File > Open…, drop it on the window or open it from the Finder."),
            (.notPermitted, "Setting.txt beside Pattern.dat cannot be read: macOS does not let this process open it (Operation not permitted); "
                + "a NORDIF scan needs the acquisition's folder, not Pattern.dat alone.",
             "Setting.txt beside Pattern.dat cannot be read: macOS does not let \(app) open it (Operation not permitted); "
                + "a NORDIF scan needs the acquisition's folder, not Pattern.dat alone."),
            (.filter, "scan.h5 cannot be read: its data is compressed with a filter the HDF5 library here does not have.",
             "scan.h5 cannot be read: its data is compressed with a filter \(app) does not have."),
            (.tooLarge, "scan.h5 cannot be read: it holds more than is read in one piece.",
             "scan.h5 cannot be read: it holds more than \(app) reads in one piece."),
            (.unsupportedType, "scan.h5 cannot be read: it stores its data in a type that is not read.",
             "scan.h5 cannot be read: it stores its data in a type \(app) does not read."),
            (.edsOnly, "eds.h5oina holds EDS data from AZtec but no EBSD data.",
             "eds.h5oina holds EDS data from AZtec but no EBSD data. \(app) does not read EDS from an .h5oina file yet; a spectrum AZtec "
                + "exports as .msa opens in the EDS room."),
            (.holdsPatterns, "scan.h5 holds EBSD patterns; its map comes with them.",
             "scan.h5 holds EBSD patterns: it opens in the Patterns room, which shows its map."),
            (.holdsMapOnly, "map.h5oina holds an orientation map but no EBSD patterns.",
             "map.h5oina holds an orientation map but no EBSD patterns: it opens in the Maps room."),
            (.notAMap, "x.h5 is not an orientation map these readers read (.ang, .ctf, .h5oina, or an .h5 from orix, Bruker Esprit, EDAX OIM or EMsoft).",
             "x.h5 is not an orientation map \(app) reads (.ang, .ctf, .h5oina, or an .h5 from orix, Bruker Esprit, EDAX OIM or EMsoft)."),
            (.manufacturer("acme"), "x.h5 is an EBSD file written by Acme, which these readers do not read; they read kikuchipy, Bruker Esprit, "
                + "EDAX OIM and Oxford AZtec files.",
             "x.h5 is an EBSD file written by Acme, which \(app) does not read; it reads kikuchipy, Bruker Esprit, EDAX OIM and Oxford AZtec files."),
        ]
        for (reason, kit, ours) in cases {
            let worded = words(reason, kit)
            XCTAssertEqual(worded.text, ours, "\(reason)")
            XCTAssertEqual(worded.reason, reason)
            for leak in ["this process", "these readers", "HDF5 library here", "that is not read"] {
                XCTAssertFalse(worded.text.contains(leak), "\(reason) still says \(leak): \(worded.text)")
            }
        }
    }

    /// A sentence the app does not reword, and an error that is not a reader's refusal, pass as they are.
    func testOtherRefusalsPassAsTheKitSaysThem() {
        let kit = "scan.h5 has no scan named 'Scan 2'; it holds Scan 1."
        XCTAssertEqual(words(.noScan(named: "Scan 2", scans: ["Scan 1"]), kit).text, kit)
        let other = CocoaError(.fileReadCorruptFile)
        XCTAssertEqual(EBSDReadError.appWorded(other) as? CocoaError, other)
        XCTAssertEqual((EBSDReadError.appWorded(EBSDReadError(.holdsMapOnly, "m.h5oina holds an orientation map but no EBSD patterns.")) as? EBSDReadError)?.text,
                       "m.h5oina holds an orientation map but no EBSD patterns: it opens in the Maps room.")
    }
}
