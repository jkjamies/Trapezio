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

/// Launches work off the main thread and delivers the result to the main thread for state reduction.
///
/// `work` runs in a detached task on the cooperative thread pool — completely off the main thread,
/// whether or not a `StrataInteractor` is used. `reduce` is called on the `@MainActor` once work
/// completes, guaranteeing all UI state updates happen on the main thread.
///
/// After `work` completes, `Task.isCancelled` is checked. If the task was cancelled during execution,
/// `reduce` is skipped entirely — preventing stale results from being applied to state.
///
/// - Important: Inside a `TrapezioStore`, prefer the store's own `launch(...)` — it tracks the
///   returned task and cancels it when the store deallocates. This free function returns an
///   untracked task, so the caller owns its lifetime. Note also that `work` runs off the main
///   actor and therefore must not read store state directly; capture the values it needs first,
///   or use the store's `launch(snapshot:work:reduce:)`.
///
/// ```swift
/// // With interactor
/// let count = state.count
/// strataLaunch(
///     work: { await interactor.execute(params: count) },
///     reduce: { result in
///         result.fold(
///             onSuccess: { data in update { $0.data = data } },
///             onFailure: { error in update { $0.error = error.message } }
///         )
///     }
/// )
///
/// // Without interactor
/// let url = endpoint
/// strataLaunch(
///     work: { await strataRunCatching { try await URLSession.shared.data(from: url) } },
///     reduce: { result in update { $0.data = result.getOrNull() } }
/// )
///
/// // Parallel — replaces nested strataLaunches
/// let (x, y) = (paramA, paramB)
/// strataLaunch(
///     work: {
///         async let a = interactorA.execute(params: x)
///         async let b = interactorB.execute(params: y)
///         return await (a, b)
///     },
///     reduce: { (a, b) in
///         update { $0.a = a.getOrNull(); $0.b = b.getOrNull() }
///     }
/// )
/// ```
@discardableResult
public func strataLaunch<T: Sendable>(
    priority: TaskPriority? = nil,
    work: @escaping @Sendable () async -> T,
    reduce: @escaping @MainActor @Sendable (T) -> Void
) -> Task<Void, Never> {
    Task.detached(priority: priority) {
        let result = await work()
        guard !Task.isCancelled else { return }
        await MainActor.run { reduce(result) }
    }
}

/// Legacy/migration interop — launches throwing work off the main thread with `@MainActor` reduce and catch.
///
/// `work` runs in a detached task on the cooperative thread pool — completely off the main thread.
/// On success, `reduce` is called on the `@MainActor` with the result value.
/// On failure, `catch` is called on the `@MainActor` with the plain `Error`.
/// No MESA types (`StrataResult`, `StrataException`) are required — use `strataLaunch` with interactors
/// for new code that has fully adopted Strata.
///
/// After `work` completes successfully, `Task.isCancelled` is checked. If the task was cancelled during
/// execution, `catch` is called with a `CancellationError()` on the `@MainActor` and `reduce` is skipped —
/// preventing stale results from being applied to state.
///
/// ```swift
/// // Fire-and-forget with error handling (reduce omitted)
/// strataLaunchInterop(
///     work: { try await legacyService.sync() },
///     catch: { error in update { $0.error = error.localizedDescription } }
/// )
///
/// // With result
/// strataLaunchInterop(
///     work: { try await legacyAPI.fetchItems() },
///     reduce: { items in update { $0.items = items } },
///     catch: { error in update { $0.error = error.localizedDescription } }
/// )
/// ```
@discardableResult
public func strataLaunchInterop<T: Sendable>(
    priority: TaskPriority? = nil,
    work: @escaping @Sendable () async throws -> T,
    reduce: @escaping @MainActor @Sendable (T) -> Void = { _ in },
    catch: @escaping @MainActor @Sendable (Error) -> Void
) -> Task<Void, Never> {
    Task.detached(priority: priority) {
        do {
            let result = try await work()
            if Task.isCancelled {
                await MainActor.run { `catch`(CancellationError()) }
                return
            }
            await MainActor.run { reduce(result) }
        } catch {
            await MainActor.run { `catch`(error) }
        }
    }
}

/// Launches work off the main thread, wrapping the result in `StrataResult`.
///
/// Returns a `Task` handle for deferred awaiting, parallel execution, or cancellation.
/// The operation closure may throw — errors are caught and returned as `.failure`.
/// When `.value` is awaited from a `@MainActor` context, execution resumes on the main thread.
///
/// ```swift
/// let a = strataLaunchWithResult { try await apiA.fetch() }
/// let b = strataLaunchWithResult { try await apiB.fetch() }
/// let (ra, rb) = await (a.value, b.value)
/// ```
@discardableResult
public func strataLaunchWithResult<T: Sendable>(
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable () async throws -> T
) -> Task<StrataResult<T>, Never> {
    Task.detached(priority: priority) {
        await strataRunCatching { try await operation() }
    }
}

/// Collects an `AsyncStream` off the main thread, delivering each value to the main thread.
///
/// Stream iteration runs in a detached task — completely off the main thread.
/// `action` is called on the `@MainActor` for each emitted value, guaranteeing all UI state
/// updates happen on the main thread.
///
/// - Important: Inside a `TrapezioStore`, prefer the store's own `collect(_:action:)` — it tracks
///   the returned task and cancels it when the store deallocates. An untracked collect on a stream
///   that never finishes parks a task for the lifetime of the process.
///
/// ```swift
/// strataCollect(observeUseCase.stream) { value in
///     update { $0.latest = value }
/// }
/// ```
@discardableResult
public func strataCollect<T: Sendable>(
    _ stream: AsyncStream<T>,
    priority: TaskPriority? = nil,
    action: @escaping @MainActor @Sendable (T) -> Void
) -> Task<Void, Never> {
    Task.detached(priority: priority) {
        for await value in stream {
            await MainActor.run { action(value) }
        }
    }
}

/// Launches work on the `@MainActor` for use cases that require main-thread execution.
///
/// Both `work` and `reduce` run on the `@MainActor`. Use this **only** when the work itself
/// must execute on the main thread (e.g., reading `@MainActor`-isolated state or calling
/// main-thread-only APIs). For all other cases, prefer `strataLaunch` which keeps work off
/// the main thread.
///
/// After `work` completes, `Task.isCancelled` is checked. If the task was cancelled during execution,
/// `reduce` is skipped entirely — preventing stale results from being applied to state.
///
/// ```swift
/// strataLaunchMain(
///     work: { someMainActorOnlyAPI() },
///     reduce: { result in update { $0.value = result } }
/// )
/// ```
@discardableResult
public func strataLaunchMain<T: Sendable>(
    priority: TaskPriority? = nil,
    work: @escaping @MainActor @Sendable () async -> T,
    reduce: @escaping @MainActor @Sendable (T) -> Void
) -> Task<Void, Never> {
    Task(priority: priority) { @MainActor in
        let result = await work()
        guard !Task.isCancelled else { return }
        reduce(result)
    }
}
