//
//  OffMainActorTests.swift
//  A view's short render runs off the main actor as part of the task that asked for it (`offMainActor`, TEMCore, #622): the work
//  runs on no main thread, and the asking task's cancellation reaches it, as a newer `.task(id:)` cancels the older one.
//  Red under: `offMainActor` built on `Task.detached` (the work then sees no cancellation).
//

import Foundation
import TEMCore
import XCTest

nonisolated final class OffMainActorTests: XCTestCase {

    @MainActor func testTheWorkRunsOffTheMainThread() async {
        let onMain = await offMainActor { Thread.isMainThread }
        XCTAssertFalse(onMain, "the render runs off the main thread")
    }

    @MainActor func testTheAskingTasksCancellationReachesTheWork() async {
        let asking = Task { @MainActor () -> Bool in
            await offMainActor { Task.isCancelled }
        }
        asking.cancel()
        let sawCancellation = await asking.value
        XCTAssertTrue(sawCancellation, "the work sees that the task that asked for it was cancelled")
    }
}
