//
//  OffMainActor.swift
//  Role: a view's short render (a map tile, a histogram, a mask tint) run off the main actor as part of the task that asked for it, so
//        a newer `.task(id:)` that cancels the old one reaches the old one's work, and its priority goes with it (#622). A
//        `Task.detached` inside `.task` is a new, unstructured task: the view's cancellation never reaches it.
//
import TEMBase
import TEMSEM


/// Runs `work` off the main actor as part of the calling task: the caller's cancellation (`Task.isCancelled` inside `work`) and
/// priority reach it, as they do not reach a `Task.detached`.
@concurrent package func offMainActor<T: Sendable>(_ work: @Sendable () -> T) async -> T {
    work()
}
