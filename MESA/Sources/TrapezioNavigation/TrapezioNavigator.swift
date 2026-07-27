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

/// Hoists navigation and coordination logic out of the feature.
@MainActor
public protocol TrapezioNavigator: AnyObject {

    // MARK: - Navigation

    /// Requests navigation to a strongly-typed TrapezioScreen.
    ///
    /// - Note: The stack-backed implementation ignores a push whose screen is already on top of
    ///   the stack, so a double tap cannot enqueue the destination twice. Pushing the same route
    ///   again from a deeper screen still works.
    func goTo(_ screen: any TrapezioScreen)

    // MARK: - Dismissal

    /// Dismisses the current active feature.
    func dismiss()

    /// Pops to the root of the current navigation stack.
    func dismissToRoot()

    /// Requests dismissal back to a specific strongly-typed TrapezioScreen.
    func dismissTo(_ screen: any TrapezioScreen)

    // MARK: - Result Passing

    /// Dismisses the current screen and delivers `result` to the previous screen.
    ///
    /// - Parameters:
    ///   - key: Unique key matching the consumer's `consumeResult(forKey:)` call.
    ///   - result: The result data to pass back.
    func popWithResult<R: TrapezioNavigationResult>(key: String, result: R)

    /// Consumes and returns the pending result for `key`, or `nil` if none.
    /// Results are single-consumption: calling this a second time returns `nil`.
    func consumeResult(forKey key: String) -> (any TrapezioNavigationResult)?

    /// Type-safe convenience that consumes and casts the pending result for `key`.
    /// Returns `nil` if no result exists or if the result is not of the expected type.
    func consumeResult<R: TrapezioNavigationResult>(forKey key: String, as type: R.Type) -> R?

    /// Removes all unconsumed results.
    /// Call during screen lifecycle teardown to prevent stale results from accumulating.
    func clearResults()
}
