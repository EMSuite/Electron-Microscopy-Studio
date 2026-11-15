//
//  PermissionDenialTests.swift
//  A refused access is told by its code (`PermissionDenial`, #628): the POSIX and Cocoa codes, an error under another, the kits'
//  `strerror` text in this process's own language and HDF5's `errno = 13`. Red while the save matched English words only: a Cocoa
//  no-permission error's text named no English word the test knew, and the grant stayed.
//

import XCTest
import Foundation
import TEMCore
import TEMSession

nonisolated final class PermissionDenialTests: XCTestCase {

    func testThePermissionCodesAreDenials() {
        XCTAssertTrue(PermissionDenial.isDenied(POSIXError(.EACCES)))
        XCTAssertTrue(PermissionDenial.isDenied(POSIXError(.EPERM)))
        XCTAssertTrue(PermissionDenial.isDenied(CocoaError(.fileWriteNoPermission)))
        XCTAssertTrue(PermissionDenial.isDenied(CocoaError(.fileReadNoPermission)))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertTrue(PermissionDenial.isDenied(wrapped), "an error under another counts")
    }

    func testOtherCodesAreNotDenials() {
        XCTAssertFalse(PermissionDenial.isDenied(POSIXError(.ENOSPC)))
        XCTAssertFalse(PermissionDenial.isDenied(CocoaError(.fileWriteOutOfSpace)))
        XCTAssertFalse(PermissionDenial.isDenied(CocoaError(.fileNoSuchFile)))
    }

    /// The kits write `strerror(code)`; this process's own `strerror` is what the detail is compared with, whatever the language.
    func testAKitDetailIsToldByThisProcessesStrerror() {
        let words = String(cString: strerror(EACCES))
        XCTAssertTrue(PermissionDenial.isDenied(detail: "rename(2) refused: \(words)"))
        XCTAssertTrue(PermissionDenial.isDenied(detail: String(cString: strerror(EPERM))))
        XCTAssertTrue(PermissionDenial.isDenied(detail: "H5FD_sec2_open(): unable to open file, errno = 13, error message = '…'"))
        XCTAssertFalse(PermissionDenial.isDenied(detail: "errno = 130"))
        XCTAssertFalse(PermissionDenial.isDenied(detail: String(cString: strerror(ENOSPC))))
    }

    /// A save refused with a Cocoa permission code takes the permission path: the grant is dropped and the alert says to choose the file.
    @MainActor func testACocoaPermissionRefusalDropsTheGrant() {
        let detail = "\(PermissionDenial.deniedWords): \(CocoaError(.fileWriteNoPermission))"
        let refusal = SessionSave.Refusal.file(.cannotWrite(operation: "writing the file", detail: detail))
        XCTAssertTrue(refusal.isPermissionDenied)
        XCTAssertTrue(SessionSaving.Failure.refused(name: "scan.dm4.mactem.h5", refusal).dropsGrant)
        let full = SessionSave.Refusal.file(.cannotWrite(operation: "writing the file", detail: String(cString: strerror(ENOSPC))))
        XCTAssertFalse(full.isPermissionDenied)
    }
}
