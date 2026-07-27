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

/// A fake navigator for testing that records all navigation events.
@MainActor
public final class FakeTrapezioNavigator: TrapezioNavigator {
    /// All recorded events in order.
    public private(set) var events: [NavigationEvent] = []

    /// All screens navigated to, in order.
    public var navigatedScreens: [AnyHashable] {
        events.compactMap(\.navigatedScreen)
    }

    /// Number of dismiss/popWithResult calls.
    public var dismissCount: Int {
        events.filter {
            if case .dismiss = $0 { return true }
            if case .popWithResult = $0 { return true }
            return false
        }.count
    }

    /// Stored results from popWithResult calls.
    public private(set) var results: [String: any TrapezioNavigationResult] = [:]

    private let continuation: AsyncStream<NavigationEvent>.Continuation

    /// Async event stream for await-style assertions.
    ///
    /// Created in `init` rather than lazily, so events recorded before the first read are still
    /// delivered, and finished on deallocation so an `await` loop terminates instead of parking
    /// forever. Buffering is `.bufferingNewest(256)` — generous enough for a test, bounded enough
    /// that an unread stream cannot grow without limit.
    public let eventStream: AsyncStream<NavigationEvent>

    public init() {
        var captured: AsyncStream<NavigationEvent>.Continuation!
        eventStream = AsyncStream<NavigationEvent>(bufferingPolicy: .bufferingNewest(256)) { cont in
            captured = cont
        }
        continuation = captured
    }

    deinit {
        continuation.finish()
    }

    public func goTo(_ screen: any TrapezioScreen) {
        let event = NavigationEvent.navigate(screen: AnyHashable(screen))
        events.append(event)
        continuation.yield(event)
    }

    public func dismiss() {
        let event = NavigationEvent.dismiss
        events.append(event)
        continuation.yield(event)
    }

    public func dismissToRoot() {
        let event = NavigationEvent.dismissToRoot
        events.append(event)
        continuation.yield(event)
    }

    public func dismissTo(_ screen: any TrapezioScreen) {
        let event = NavigationEvent.dismissTo(screen: AnyHashable(screen))
        events.append(event)
        continuation.yield(event)
    }

    public func popWithResult<R: TrapezioNavigationResult>(key: String, result: R) {
        results[key] = result
        let event = NavigationEvent.popWithResult(key: key)
        events.append(event)
        continuation.yield(event)
    }

    public func consumeResult(forKey key: String) -> (any TrapezioNavigationResult)? {
        results.removeValue(forKey: key)
    }

    public func consumeResult<R: TrapezioNavigationResult>(forKey key: String, as type: R.Type) -> R? {
        guard let raw = results.removeValue(forKey: key) else { return nil }
        if let typed = raw as? R { return typed }
        // Type mismatch — restore so result isn't silently lost.
        results[key] = raw
        return nil
    }

    public func clearResults() {
        results.removeAll()
    }

    /// Resets all recorded state.
    public func reset() {
        events.removeAll()
        results.removeAll()
    }
}
