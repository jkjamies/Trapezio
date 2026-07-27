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

/// Optional view-lifecycle callbacks for a ``TrapezioStore``.
///
/// Conform your store and ``TrapezioRuntime`` will drive these from the hosting view's
/// `onAppear` / `onDisappear`. Every method has a no-op default, so conformers implement only
/// what they need.
///
/// ```swift
/// final class ListStore: TrapezioStore<ListScreen, ListState, ListEvent>, TrapezioLifecycle {
///     func onFirstAppear() {
///         collect(observeItems.stream) { [weak self] in self?.update { $0.items = $1 } }
///     }
///
///     func onAppear() {
///         // Navigation results are delivered on the way back up the stack.
///         if let result = navigator?.consumeResult(forKey: "edit", as: EditResult.self) {
///             update { $0.name = result.name }
///         }
///     }
/// }
/// ```
///
/// - Note: ``onFirstAppear()`` fires once per view identity and is the right place for
///   one-shot setup such as starting observation. ``onAppear()`` fires every time the view
///   appears, including when it is revealed by a pop, which is what makes it the correct place
///   to consume navigation results.
@MainActor
public protocol TrapezioLifecycle {
    /// Called the first time the hosting view appears, before ``onAppear()``.
    func onFirstAppear()

    /// Called every time the hosting view appears.
    func onAppear()

    /// Called every time the hosting view disappears.
    func onDisappear()
}

public extension TrapezioLifecycle {
    func onFirstAppear() { }
    func onAppear() { }
    func onDisappear() { }
}
