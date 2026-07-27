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

import Observation
import SwiftUI

/// The single source of truth for a feature's presentation logic.
///
/// `TrapezioStore` is the brain of every MESA feature. It holds the current ``State``,
/// receives user intents as ``Event`` values, and mutates state via ``update(_:)``.
/// SwiftUI observes state changes through the `@Observable` macro.
///
/// Observation is per *property*, not per field of `State`. ``TrapezioRuntime`` reads the whole
/// ``state`` property, so any change to state invalidates the view — the same granularity
/// `ObservableObject` gave, and a UDF store has one state property by design. ``update(_:)``'s
/// `Equatable` check is what prevents a no-op write from invalidating anything.
///
/// Subclass this for each feature and override ``handle(event:)`` to map events to state changes:
///
/// ```swift
/// final class CounterStore: TrapezioStore<CounterScreen, CounterState, CounterEvent> {
///     override func handle(event: CounterEvent) {
///         switch event {
///         case .increment: update { $0.count += 1 }
///         case .decrement: update { $0.count -= 1 }
///         }
///     }
/// }
/// ```
///
/// ## Asynchronous work
///
/// Start background work through ``launch(priority:snapshot:work:reduce:)`` or
/// ``collect(_:priority:action:)`` rather than the free `strata*` functions. The instance
/// methods track their tasks in ``tasks``, so everything a store started is cancelled when
/// the store deallocates.
///
/// - Important: This class is `@MainActor`. All state reads/writes happen on the main thread.
/// - Note: Use ``TrapezioContainer`` to preserve store identity across SwiftUI view updates.
/// - Note: Conform to ``TrapezioLifecycle`` to receive appear/disappear callbacks from the runtime.
/// - Note: `@Observable` applies to this class only. A subclass's own stored properties are not
///   tracked, which is by design — feature state belongs in ``state``, not in subclass fields.
@MainActor
@Observable
open class TrapezioStore<S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent>: Identifiable {
    @ObservationIgnored
    public let screen: S

    /// Current state snapshot.
    ///
    /// Reads and writes are both `@MainActor`-isolated. To use state inside detached work,
    /// take a `Sendable` snapshot on the main actor first — see
    /// ``launch(priority:snapshot:work:reduce:)``.
    ///
    /// Reading this from a SwiftUI `body` registers a dependency on the whole property, not on
    /// the individual fields touched, so any state change invalidates that view.
    public private(set) var state: State

    /// Cancellation scope for work started by this store.
    ///
    /// Cancelled automatically when the store deallocates. Call ``cancelAll()`` to tear work
    /// down earlier.
    ///
    /// Excluded from observation: it is infrastructure, not display state.
    @ObservationIgnored
    public let tasks = TrapezioTaskBag()

    /// Creates a store with its associated screen and initial state.
    ///
    /// - Parameters:
    ///   - screen: The screen descriptor that identifies this feature in navigation.
    ///   - initialState: The starting state rendered on first appearance.
    public init(screen: S, initialState: State) {
        self.screen = screen
        self.state = initialState
    }

    /// Override this method to map user events to state mutations.
    ///
    /// Called by the runtime whenever the UI emits an event. The default implementation is a no-op.
    ///
    /// - Parameter event: The user intent to handle.
    open func handle(event: Event) { }

    /// Mutates state using copy-on-write semantics.
    ///
    /// Creates a mutable copy of the current state, applies `transform`, and only assigns
    /// the new state if it differs from the current value (checked via `Equatable`).
    /// Assigning an equal value would still notify observers, so the check prevents
    /// unnecessary SwiftUI invalidation.
    ///
    /// - Parameter transform: A closure that mutates the state copy in place.
    public final func update(_ transform: (inout State) -> Void) {
        var copy = self.state
        transform(&copy)
        if copy != self.state {
            self.state = copy
        }
    }

    // MARK: - Work

    /// Runs `work` off the main thread and applies the outcome on the `@MainActor`.
    ///
    /// The task is tracked in ``tasks`` and cancelled when this store deallocates. If the task
    /// is cancelled while `work` is running, `reduce` is skipped so a stale result never lands
    /// in state.
    ///
    /// ```swift
    /// launch(
    ///     work: { await interactor.execute(params: ()) },
    ///     reduce: { result in update { $0.items = result.getOrDefault([]) } }
    /// )
    /// ```
    ///
    /// - Important: `work` cannot read ``state`` — it runs outside the main actor. Use
    ///   ``launch(priority:snapshot:work:reduce:)`` when the work depends on current state.
    @discardableResult
    public final func launch<T: Sendable>(
        priority: TaskPriority? = nil,
        work: @escaping @Sendable () async -> T,
        reduce: @escaping @MainActor @Sendable (T) -> Void
    ) -> Task<Void, Never> {
        tasks.addDetached(priority: priority) {
            let result = await work()
            guard !Task.isCancelled else { return }
            await MainActor.run { reduce(result) }
        }
    }

    /// Captures a `Sendable` slice of state on the main actor, then runs `work` off the main
    /// thread with that value and applies the outcome on the `@MainActor`.
    ///
    /// This is the safe way to feed current state into background work. Reading ``state``
    /// directly from a detached closure would race the main actor's writes.
    ///
    /// ```swift
    /// launch(
    ///     snapshot: { $0.count },
    ///     work: { count in await divideUseCase.execute(value: count) },
    ///     reduce: { result in update { $0.count = result } }
    /// )
    /// ```
    @discardableResult
    public final func launch<V: Sendable, T: Sendable>(
        priority: TaskPriority? = nil,
        snapshot: (State) -> V,
        work: @escaping @Sendable (V) async -> T,
        reduce: @escaping @MainActor @Sendable (T) -> Void
    ) -> Task<Void, Never> {
        let captured = snapshot(state)
        return tasks.addDetached(priority: priority) {
            let result = await work(captured)
            guard !Task.isCancelled else { return }
            await MainActor.run { reduce(result) }
        }
    }

    /// Runs `work` on the `@MainActor` and applies the outcome there too.
    ///
    /// Use only when the work itself must be main-thread isolated. Prefer
    /// ``launch(priority:work:reduce:)`` otherwise.
    @discardableResult
    public final func launchMain<T: Sendable>(
        priority: TaskPriority? = nil,
        work: @escaping @MainActor @Sendable () async -> T,
        reduce: @escaping @MainActor @Sendable (T) -> Void
    ) -> Task<Void, Never> {
        tasks.addMain(priority: priority) {
            let result = await work()
            guard !Task.isCancelled else { return }
            reduce(result)
        }
    }

    /// Iterates `stream` off the main thread, delivering each value to `action` on the `@MainActor`.
    ///
    /// The task is tracked in ``tasks`` and cancelled when this store deallocates.
    ///
    /// ```swift
    /// collect(observeUseCase.stream) { [weak self] value in
    ///     self?.update { $0.latest = value }
    /// }
    /// ```
    @discardableResult
    public final func collect<T: Sendable>(
        _ stream: AsyncStream<T>,
        priority: TaskPriority? = nil,
        action: @escaping @MainActor @Sendable (T) -> Void
    ) -> Task<Void, Never> {
        tasks.addDetached(priority: priority) {
            for await value in stream {
                if Task.isCancelled { break }
                await MainActor.run { action(value) }
            }
        }
    }

    /// Cancels every task this store started.
    ///
    /// Called automatically when the store deallocates. Call it explicitly to stop work at a
    /// well-defined point, such as ``TrapezioLifecycle/onDisappear()``.
    public final func cancelAll() {
        tasks.cancelAll()
    }

    // MARK: - Rendering

    /// Binds this store to a ``TrapezioUI`` and returns the rendered SwiftUI view.
    ///
    /// - Parameter ui: The UI component that maps state to pixels.
    /// - Returns: A view that observes this store's state and routes events back to ``handle(event:)``.
    public func render<U: TrapezioUI>(with ui: U) -> some View
    where U.State == State, U.Event == Event {
        TrapezioRuntime(presenter: self, ui: ui)
    }
}
