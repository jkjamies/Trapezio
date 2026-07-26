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

import SwiftUI

/// The SwiftUI lifecycle owner for Trapezio stores.
///
/// Use this whenever you render a store in SwiftUI so the store isn't recreated
/// during view updates (e.g. when navigating or when parent views re-render).
///
/// - Important: `makeStore` is an `@autoclosure`, so store construction is deferred to
///   `@StateObject` and happens once. **Anything the store depends on must be built inside
///   that autoclosure too.** Dependencies constructed in the surrounding factory body run on
///   every view evaluation and are then discarded, which is expensive for repositories,
///   database contexts, and network clients:
///
///   ```swift
///   // Wrong — a new repository (and ModelContext) per render.
///   let repo = SummaryRepositoryImpl(container: container)
///   return TrapezioContainer(makeStore: SummaryStore(repo: repo), ui: SummaryUI())
///
///   // Right — the whole graph is built once, inside the autoclosure.
///   return TrapezioContainer(
///       makeStore: {
///           let repo = SummaryRepositoryImpl(container: container)
///           return SummaryStore(repo: repo)
///       }(),
///       ui: SummaryUI()
///   )
///   ```
public struct TrapezioContainer<Store: ObservableObject, Content: View>: View {

    @StateObject private var store: Store
    private let content: (Store) -> Content

    public init(
        makeStore: @escaping @autoclosure () -> Store,
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        _store = StateObject(wrappedValue: makeStore())
        self.content = content
    }

    public var body: some View {
        content(store)
    }
}

public extension TrapezioContainer {
    /// Convenience initializer for the common Trapezio pattern: `TrapezioStore + TrapezioUI`.
    ///
    /// The concrete store type is preserved, so `content` and callers keep access to
    /// subclass-specific API rather than seeing the erased `TrapezioStore` base class.
    init<S: TrapezioScreen, AState: TrapezioState, AEvent: TrapezioEvent, UI: TrapezioUI>(
        makeStore: @escaping @autoclosure () -> Store,
        ui: UI
    ) where Store: TrapezioStore<S, AState, AEvent>,
            UI.State == AState,
            UI.Event == AEvent,
            Content == AnyView {
        _store = StateObject(wrappedValue: makeStore())
        self.content = { store in
            AnyView(store.render(with: ui))
        }
    }
}
