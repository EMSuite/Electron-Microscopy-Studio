//
//  Signposts.swift
//  Role: the app's own timings. An `os_signpost` interval around each heavy action's compute (open, FFT spectrum, spot, find spots,
//        EDX refresh, EELS map, particles, stack frame) in one subsystem, so a UI test reads them with `XCTOSSignpostMetric` and Instruments
//        shows them. No numerics, no state; a signpost costs nothing measurable when nothing is listening.
//        A unit test can ask for the names begun (`recording`): CI's runners are no clock, so the tests there check that a budget's
//        signposts fire, and the budgets themselves are measured on the reference Mac (docs/performance.md).
//

import os

package enum Signposts {
    package static let subsystem = "com.mac4dstem.macTEM"
    package static let category = "performance"
    private static let log = OSLog(subsystem: subsystem, category: category)

    package struct Interval {
        fileprivate let id: OSSignpostID
        fileprivate let name: StaticString
    }

    /// The names begun while a test records, in order; nil (nothing kept) otherwise.
    private static let recorded = OSAllocatedUnfairLock<[String]?>(initialState: nil)

    /// Starts keeping the names begun (a unit test's check that a budget's interval fires). Not for app code.
    package static func startRecording() { recorded.withLock { $0 = [] } }

    /// The names begun since `startRecording`, in order; recording stops.
    package static func stopRecording() -> [String] {
        recorded.withLock { names in
            defer { names = nil }
            return names ?? []
        }
    }

    package static func begin(_ name: StaticString) -> Interval {
        recorded.withLock { names in if names != nil { names?.append(name.description) } }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Interval(id: id, name: name)
    }

    package static func end(_ interval: Interval) {
        os_signpost(.end, log: log, name: interval.name, signpostID: interval.id)
    }
}
