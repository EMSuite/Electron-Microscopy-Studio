//
//  PermissionDenial.swift
//  Role: whether an error is the system refusing access (a file mode's EACCES, the sandbox's EPERM, the Cocoa no-permission
//        codes), told by its code and never by English words: on a Mac set to another language `strerror` and Cocoa speak
//        that language (#628).
//

import Foundation

package nonisolated enum PermissionDenial {
    /// The POSIX codes that mean the system refused access.
    package static let posixCodes: Set<Int32> = [EACCES, EPERM]

    /// The Cocoa codes that mean the same.
    package static let cocoaCodes: Set<Int> = [NSFileReadNoPermissionError, NSFileWriteNoPermissionError]

    /// True when `error`, or an error under it, carries a permission code.
    package static func isDenied(_ error: any Error) -> Bool {
        var next: NSError? = error as NSError
        var depth = 0
        while let ns = next, depth < 8 {
            if ns.domain == NSPOSIXErrorDomain, posixCodes.contains(Int32(truncatingIfNeeded: ns.code)) { return true }
            if ns.domain == NSCocoaErrorDomain, cocoaCodes.contains(ns.code) { return true }
            next = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// True when a kit's error text names a permission code. The kits write `strerror(code)` (and HDF5 writes `errno = 13`), in
    /// this process's language, so the text is compared with this process's own `strerror` of each code, not with English.
    package static func isDenied(detail: String) -> Bool {
        let text = detail.lowercased()
        for code in posixCodes {
            if text.contains(String(cString: strerror(code)).lowercased()) { return true }
            if text.range(of: "errno = \(code)\\b", options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// The system's words for a refused access, in the Mac's language: the detail a refusal built from a Cocoa error carries,
    /// so `isDenied(detail:)` knows it again.
    package static var deniedWords: String { String(cString: strerror(EACCES)) }
}
