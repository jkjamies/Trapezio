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

/// A cancellation scope for long-lived work started by a ``TrapezioStore``.
///
/// Tasks started through this bag are cancelled when ``cancelAll()`` is called, and
/// automatically when the bag itself deallocates. Because ``TrapezioStore`` holds its bag
/// as a stored property, a store that goes out of scope cancels everything it started.
///
/// Completed tasks remove themselves from the bag, so a store that launches many short
/// operations does not accumulate handles.
///
/// - Important: A task that captures its store **strongly** keeps that store — and therefore
///   this bag — alive, so the automatic cancellation never runs. Capture `[weak self]` in
///   long-lived work, or call ``cancelAll()`` explicitly during teardown.
public final class TrapezioTaskBag: @unchecked Sendable {

    /// Tracked tasks, plus the ids of tasks that finished before their handle was stored.
    ///
    /// The `completed` set closes a race: a very short task can run to completion inside
    /// `Task.detached` before the calling thread gets as far as recording its handle. Without
    /// the set, that late insert would never be removed.
    private struct Storage {
        var tasks: [UUID: Task<Void, Never>] = [:]
        var completed: Set<UUID> = []
    }

    private let storage = OSAllocatedUnfairLock<Storage>(initialState: Storage())

    public init() {}

    /// Number of tasks currently tracked. Primarily useful in tests.
    public var count: Int {
        storage.withLock { $0.tasks.count }
    }

    /// Starts `operation` in a detached task, tracked for cancellation.
    ///
    /// Detached execution guarantees the work runs off the main thread regardless of the
    /// caller's isolation.
    @discardableResult
    public func addDetached(
        priority: TaskPriority? = nil,
        _ operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let id = UUID()
        let task = Task.detached(priority: priority) { [weak self] in
            await operation()
            self?.finish(id)
        }
        record(task, for: id)
        return task
    }

    /// Starts `operation` on the `@MainActor`, tracked for cancellation.
    @discardableResult
    public func addMain(
        priority: TaskPriority? = nil,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let id = UUID()
        let task = Task(priority: priority) { @MainActor [weak self] in
            await operation()
            self?.finish(id)
        }
        record(task, for: id)
        return task
    }

    /// Cancels every tracked task and empties the bag.
    ///
    /// Safe to call more than once. Cancellation is cooperative: tasks stop at their next
    /// suspension point or `Task.isCancelled` check, not instantly.
    public func cancelAll() {
        let pending = storage.withLock { state -> [Task<Void, Never>] in
            let tasks = Array(state.tasks.values)
            state.tasks.removeAll()
            state.completed.removeAll()
            return tasks
        }
        for task in pending {
            task.cancel()
        }
    }

    private func record(_ task: Task<Void, Never>, for id: UUID) {
        storage.withLock { state in
            // The task already finished — nothing to track.
            if state.completed.remove(id) != nil { return }
            state.tasks[id] = task
        }
    }

    private func finish(_ id: UUID) {
        storage.withLock { state in
            if state.tasks.removeValue(forKey: id) == nil {
                // Finished before the handle was recorded; tell `record` to skip it.
                state.completed.insert(id)
            }
        }
    }

    deinit {
        cancelAll()
    }
}
