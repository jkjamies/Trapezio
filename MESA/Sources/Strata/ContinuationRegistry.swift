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

/// Thread-safe fan-out to a set of `AsyncStream` continuations.
///
/// Held as a stored property by the type that publishes the stream. When the owner
/// deallocates, this registry deallocates with it and finishes every outstanding
/// continuation — which is what lets consumers' `for await` loops terminate instead of
/// parking forever.
internal final class ContinuationRegistry<Element: Sendable>: @unchecked Sendable {

    private let storage = OSAllocatedUnfairLock<[UUID: AsyncStream<Element>.Continuation]>(
        initialState: [:]
    )

    internal init() {}

    /// Number of live subscriptions. Primarily useful in tests.
    internal var count: Int {
        storage.withLock { $0.count }
    }

    /// Registers a continuation and returns the token used to unregister it.
    internal func register(_ continuation: AsyncStream<Element>.Continuation) -> UUID {
        let id = UUID()
        storage.withLock { $0[id] = continuation }
        return id
    }

    internal func unregister(_ id: UUID) {
        storage.withLock { _ = $0.removeValue(forKey: id) }
    }

    /// Delivers `element` to every registered continuation.
    ///
    /// The snapshot is taken under the lock and yielded outside it, so a consumer
    /// re-entering the registry from its own iteration cannot deadlock.
    internal func yield(_ element: Element) {
        let continuations = storage.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(element)
        }
    }

    /// Finishes and drops every registered continuation.
    internal func finishAll() {
        let continuations = storage.withLock { state -> [AsyncStream<Element>.Continuation] in
            let values = Array(state.values)
            state.removeAll()
            return values
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    deinit {
        finishAll()
    }
}
