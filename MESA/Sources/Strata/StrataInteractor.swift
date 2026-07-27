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

/// Default timeout duration for `StrataInteractor.execute` (5 minutes).
public let strataInteractorDefaultTimeout: TimeInterval = 300

// MARK: - StrataInteractor

/// Base class for one-shot business operations with built-in loading state.
/// Subclasses override `doWork(params:)` to implement business logic.
/// The `inProgress` state is automatically managed during execution.
open class StrataInteractor<P: Sendable, T: Sendable>: @unchecked Sendable {

    // MARK: - inProgress State

    /// Loading state and its stream continuation, kept under one lock.
    ///
    /// The two must be updated together: publishing a transition means reading the
    /// continuation, and a separate unsynchronised `var` for it would race `onTermination`
    /// (which fires on an arbitrary thread when a consumer stops iterating).
    private struct ProgressState {
        /// Number of `execute` calls currently running. Interactors are commonly injected as
        /// shared singletons, so concurrent execution must not flip the flag off early.
        var activeCount: Int = 0
        var continuation: AsyncStream<Bool>.Continuation?
    }

    private let progress = OSAllocatedUnfairLock<ProgressState>(initialState: ProgressState())

    /// Current loading state (thread-safe).
    ///
    /// `true` while at least one ``execute(params:timeout:)`` call is in flight.
    public var inProgress: Bool {
        progress.withLock { $0.activeCount > 0 }
    }

    /// Stream for observing loading state changes.
    ///
    /// Emits the current value immediately upon subscription, then emits when execution starts
    /// and when the last concurrent execution finishes. Created once, in `init`.
    ///
    /// - Important: `AsyncStream` is single-consumer. Only one `for await` loop should iterate
    ///   this stream. A second consumer on the same stream will receive no values. If you need
    ///   multiple observers, collect this stream once and fan out from the reducer.
    /// - Note: Buffering is `.bufferingNewest(1)` — a slow consumer sees the current state
    ///   rather than every transition, and an unconsumed stream cannot grow without bound.
    public let inProgressStream: AsyncStream<Bool>

    // MARK: - Initialization

    public init() {
        var builder: AsyncStream<Bool>.Continuation!
        // The build closure is non-escaping and runs synchronously, so `builder` is set
        // before the initializer returns.
        inProgressStream = AsyncStream<Bool>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            builder = continuation
        }
        // Bind to a `let` before touching the lock: `withLock` takes a `@Sendable` closure, and
        // Swift 6 rejects capturing a mutable local in one.
        let continuation = builder!
        progress.withLock { $0.continuation = continuation }
        continuation.yield(false)
    }

    deinit {
        // Let consumers' `for await` loops terminate instead of parking forever.
        let continuation = progress.withLock { state -> AsyncStream<Bool>.Continuation? in
            let value = state.continuation
            state.continuation = nil
            return value
        }
        continuation?.finish()
    }

    /// Increments the active count, publishing `true` on the leading edge.
    private func beginWork() {
        let continuation = progress.withLock { state -> AsyncStream<Bool>.Continuation? in
            state.activeCount += 1
            return state.activeCount == 1 ? state.continuation : nil
        }
        // Yield outside the lock: a consumer reacting synchronously must not re-enter it.
        continuation?.yield(true)
    }

    /// Decrements the active count, publishing `false` on the trailing edge.
    private func endWork() {
        let continuation = progress.withLock { state -> AsyncStream<Bool>.Continuation? in
            state.activeCount = max(0, state.activeCount - 1)
            return state.activeCount == 0 ? state.continuation : nil
        }
        continuation?.yield(false)
    }

    // MARK: - Execution

    /// Override this method to implement business logic.
    /// Do NOT call this directly — use `execute(params:)`.
    open func doWork(params: P) async -> StrataResult<T> {
        fatalError("doWork(params:) must be overridden")
    }

    /// Default timeout for interactor execution (5 minutes).
    public static var defaultTimeout: TimeInterval { strataInteractorDefaultTimeout }

    /// Executes the interactor, automatically managing `inProgress` state.
    ///
    /// - Parameters:
    ///   - params: The input parameters.
    ///   - timeout: Maximum execution time. Defaults to ``defaultTimeout`` (5 minutes).
    /// - Returns: A `StrataResult` containing the result or a timeout/execution failure.
    ///
    /// - Important: The timeout is a **cancellation signal, not a hard deadline**. When it
    ///   fires, the `doWork` task is cancelled — but `execute` cannot return until that task
    ///   actually finishes, because it is a child task of the same group. `doWork`
    ///   implementations that ignore cooperative cancellation (a tight synchronous loop, a
    ///   blocking C call, a network request with no cancellation wiring) will therefore run past
    ///   the timeout and hold the caller. Check `Task.isCancelled` in long-running work.
    public final func execute(
        params: P,
        timeout: TimeInterval = strataInteractorDefaultTimeout
    ) async -> StrataResult<T> {
        beginWork()
        defer { endWork() }

        do {
            return try await withThrowingTaskGroup(of: StrataResult<T>?.self) { group in
                group.addTask {
                    await self.doWork(params: params)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    return nil
                }

                for try await result in group {
                    group.cancelAll()
                    if let result = result {
                        return result
                    } else {
                        return .failure(StrataTimeoutException(duration: timeout))
                    }
                }
                // Unreachable with two tasks — the loop always executes and
                // returns above. Required by the compiler for exhaustive coverage.
                return .failure(StrataTimeoutException(duration: timeout))
            }
        } catch is CancellationError {
            return .failure(StrataCancellationException())
        } catch {
            return .failure(StrataExecutionException(error: error))
        }
    }

    /// Helper to bridge throws to StrataResult in doWork implementations.
    ///
    /// Delegates to ``strataRunCatching(_:)``, so `CancellationError` becomes
    /// `.failure(StrataCancellationException)`, `StrataException` is preserved as-is, and every
    /// other error is wrapped in `StrataExecutionException`. Nothing is re-thrown.
    public func executeCatching(params: P, block: (P) async throws -> T) async -> StrataResult<T> {
        await strataRunCatching { try await block(params) }
    }
}

// MARK: - Helper Functions

/// Wraps an async block in a `StrataResult`, catching any errors.
///
/// This function does not throw. `CancellationError` is mapped to
/// `.failure(StrataCancellationException)` so that cancellation is represented uniformly inside
/// `StrataResult` alongside every other failure — callers pattern-match one type instead of
/// mixing `try` with result handling.
public func strataRunCatching<T>(_ block: () async throws -> T) async -> StrataResult<T> {
    do {
        let result = try await block()
        return .success(result)
    } catch is CancellationError {
        return .failure(StrataCancellationException())
    } catch let error as any StrataException {
        return .failure(error)
    } catch {
        return .failure(StrataExecutionException(error: error))
    }
}

/// Wraps an unexpected (non-`StrataException`) error caught during interactor execution.
///
/// Stores a `Sendable` snapshot of the original error (its `localizedDescription`, type name,
/// and debug description) rather than the error itself, so the failure can cross isolation
/// boundaries inside a `StrataResult`.
public struct StrataExecutionException: StrataException {
    public let message: String
    public let underlyingErrorType: String
    public let underlyingErrorDescription: String

    public init(error: Error) {
        self.message = error.localizedDescription
        self.underlyingErrorType = String(describing: type(of: error))
        self.underlyingErrorDescription = String(describing: error)
    }
}
