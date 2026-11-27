//
//  RunOverlap.swift
//  Role: how many of a room's runs are working at once, and the most there have been. A run that replaces another (Stop, then the
//        verb again) waits for the one it replaced to end before it starts its work, so this never passes one; the tests read it
//        (#622). Counting costs a lock per run, nothing per row.
//

import Synchronization
import TEMBase
import TEMSEM

/// The live count of a room's runs and its peak, read from any thread.
package nonisolated final class RunOverlap: Sendable {
    private struct Counts {
        var live = 0
        var peak = 0
    }

    private let counts: Mutex<Counts>

    package init() {
        counts = Mutex(Counts())
    }

    /// The runs working now.
    package var live: Int { counts.withLock { $0.live } }

    /// The most runs that have worked at once.
    package var peak: Int { counts.withLock { $0.peak } }

    /// A run starts its work.
    package func enter() {
        counts.withLock { c in
            c.live += 1
            c.peak = max(c.peak, c.live)
        }
    }

    /// A run's work has ended (landed, stopped or failed).
    package func leave() {
        counts.withLock { $0.live -= 1 }
    }
}
