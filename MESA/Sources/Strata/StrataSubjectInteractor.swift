/*
 * Copyright 2026 Jason Jamieson
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import os

/// Base class for interactors that produce a continuous stream of data.
///
/// Subclass this for observation-style use cases (e.g. watching a database query).
/// Override ``createObservable(params:)`` to define how input parameters map to an output stream.
///
/// ```swift
/// final class ObserveLastValueUseCase: StrataSubjectInteractor<Void, Int?> {
///     override func createObservable(params: Void) -> AsyncStream<Int?> {
///         repository.observeLastValue()
///     }
/// }
///
/// // In the store:
/// collect(observeLastValue.stream) { [weak self] value in
///     self?.update { $0.lastSaved = value }
/// }
/// observeLastValue(())   // trigger
/// ```
///
/// - Note: ``createObservable(params:)`` is the method you *override*, never the one you call.
///   Trigger with ``callAsFunction(_:)`` and consume ``stream``; calling `createObservable`
///   directly bypasses re-trigger cancellation and the ``value`` cache.
/// - Note: The ``value`` property provides thread-safe synchronous access to the latest emitted value.
open class StrataSubjectInteractor<P: Sendable, T: Sendable>: @unchecked Sendable {

    private let paramContinuation: AsyncStream<P>.Continuation

    /// Downstream consumers of ``stream``. Broadcast, so every consumer sees every emission.
    private let subscribers = ContinuationRegistry<T>()

    /// The long-lived task that maps parameters to output streams.
    private let driver = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// The latest value emitted by the stream (thread-safe, read-only externally).
    private let _value = OSAllocatedUnfairLock<T?>(initialState: nil)
    public private(set) var value: T? {
        get { _value.withLock { $0 } }
        set { _value.withLock { $0 = newValue } }
    }

    public init() {
        var continuation: AsyncStream<P>.Continuation!
        // Only the most recent trigger matters — a new parameter cancels the previous inner
        // stream anyway — so buffering one keeps an idle interactor bounded.
        let params = AsyncStream<P>(bufferingPolicy: .bufferingNewest(1)) { cont in
            continuation = cont
        }
        self.paramContinuation = continuation

        // Every stored property is initialized, so `self` may now be captured. Weakly: the
        // driver must not keep the interactor alive.
        let task = Task { [weak self] in
            var inner: Task<Void, Never>?
            for await param in params {
                inner?.cancel()
                inner = Task { [weak self] in
                    guard let self else { return }
                    for await output in self.createObservable(params: param) {
                        if Task.isCancelled { break }
                        self.value = output
                        self.subscribers.yield(output)
                    }
                }
            }
            inner?.cancel()
        }
        driver.withLock { $0 = task }
    }

    deinit {
        // Ends the driver loop, which in turn cancels any inner stream.
        paramContinuation.finish()
        driver.withLock { $0 }?.cancel()
        // `subscribers` finishes its continuations in its own deinit, so consumers terminate.
    }

    /// Triggers the stream with new parameters.
    ///
    /// Cancels any in-flight inner stream from a previous trigger before starting the new one.
    ///
    /// - Parameter params: The input to pass to ``createObservable(params:)``.
    public func callAsFunction(_ params: P) {
        paramContinuation.yield(params)
    }

    /// The output stream that yields values from ``createObservable(params:)``.
    ///
    /// Each access opens an independent subscription; **all subscriptions receive every
    /// emission**. Subscriptions end when the consumer stops iterating, or when this
    /// interactor deallocates.
    ///
    /// - Note: Emissions are not replayed. A consumer that subscribes after a value has
    ///   already been produced sees the next one; read ``value`` for the current cache.
    /// - Note: Buffering is `.bufferingNewest(16)` per subscription, so one slow consumer
    ///   cannot grow memory without bound or stall the others.
    public var stream: AsyncStream<T> {
        let registry = subscribers
        return AsyncStream<T>(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let id = registry.register(continuation)
            // Weak: the registry holds the continuation, and the continuation holds this
            // closure. A strong capture here would be a cycle, keeping the registry — and so
            // the stream — alive after the interactor is gone.
            continuation.onTermination = { [weak registry] _ in
                registry?.unregister(id)
            }
        }
    }

    /// Override to define how input parameters produce an output stream.
    ///
    /// - Parameter params: The input parameters provided via ``callAsFunction(_:)``.
    /// - Returns: An `AsyncStream` of output values to forward to subscribers.
    open func createObservable(params: P) -> AsyncStream<T> {
        fatalError("createObservable(params:) must be implemented")
    }
}
