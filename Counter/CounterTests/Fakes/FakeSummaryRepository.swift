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
import Trapezio
import TrapezioNavigation
import os
@testable import Counter

/// In-memory `SummaryRepository` with a controllable observation stream.
///
/// No `Task.sleep` anywhere — saves complete immediately so tests stay deterministic.
final class FakeSummaryRepository: SummaryRepository, @unchecked Sendable {

    struct Failure: Error {}

    private struct Storage {
        var saved: [Int] = []
        var shouldFail = false
        var continuation: AsyncStream<Int?>.Continuation?
    }

    private let storage = OSAllocatedUnfairLock<Storage>(initialState: Storage())

    /// Every value passed to `saveValue`, in order.
    var saved: [Int] { storage.withLock { $0.saved } }

    /// When `true`, `saveValue` throws instead of recording.
    var shouldFail: Bool {
        get { storage.withLock { $0.shouldFail } }
        set { storage.withLock { $0.shouldFail = newValue } }
    }

    func saveValue(_ value: Int) async throws {
        let failing = storage.withLock { state -> Bool in
            if state.shouldFail { return true }
            state.saved.append(value)
            return false
        }
        if failing { throw Failure() }
    }

    func observeLastValue() -> AsyncStream<Int?> {
        AsyncStream { continuation in
            storage.withLock { $0.continuation = continuation }
        }
    }

    /// Pushes a value to whoever is observing.
    func emit(_ value: Int?) {
        let continuation = storage.withLock { $0.continuation }
        continuation?.yield(value)
    }
}

/// Records navigator calls without a navigation stack.
@MainActor
final class FakeNavigator: TrapezioNavigator {
    private(set) var dismissCount = 0
    private(set) var navigatedScreens: [any TrapezioScreen] = []
    private var results: [String: any TrapezioNavigationResult] = [:]

    func goTo(_ screen: any TrapezioScreen) { navigatedScreens.append(screen) }
    func dismiss() { dismissCount += 1 }
    func dismissToRoot() { results.removeAll() }
    func dismissTo(_ screen: any TrapezioScreen) { }

    func popWithResult<R: TrapezioNavigationResult>(key: String, result: R) {
        results[key] = result
        dismissCount += 1
    }

    func consumeResult(forKey key: String) -> (any TrapezioNavigationResult)? {
        results.removeValue(forKey: key)
    }

    func consumeResult<R: TrapezioNavigationResult>(forKey key: String, as type: R.Type) -> R? {
        guard let raw = results.removeValue(forKey: key) else { return nil }
        guard let typed = raw as? R else {
            results[key] = raw
            return nil
        }
        return typed
    }

    func clearResults() { results.removeAll() }
}
