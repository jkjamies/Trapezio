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

/// Holds a store so it is constructed exactly once per view identity.
///
/// `@State` evaluates its initial value on every view initialization and keeps only the first,
/// so putting the store directly in `@State` would rebuild the whole dependency graph on every
/// render and immediately discard it. `@StateObject` avoided that with an `@autoclosure`;
/// `@Observable` has no equivalent, so a cheap box goes in `@State` and the store is built
/// lazily inside it on first use.
///
/// Only ever touched from `body`, which is `@MainActor`.
///
/// `internal` rather than `private` so the resolve-once guarantee can be tested directly — it is
/// the thing standing between adopters and a rebuilt dependency graph on every render.
internal final class TrapezioStoreBox<Store: AnyObject>: @unchecked Sendable {
    private var stored: Store?

    func resolve(_ make: () -> Store) -> Store {
        if let stored { return stored }
        let created = make()
        stored = created
        return created
    }
}

/// The SwiftUI lifecycle owner for Trapezio stores.
///
/// Use this whenever you render a store in SwiftUI so the store isn't recreated
/// during view updates (e.g. when navigating or when parent views re-render).
///
/// - Important: `makeStore` is an `@autoclosure`, so store construction is deferred and happens
///   once. **Anything the store depends on must be built inside that autoclosure too.**
///   Dependencies constructed in the surrounding factory body run on every view evaluation and
///   are then discarded, which is expensive for repositories, database contexts, and network
///   clients:
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
public struct TrapezioContainer<Store: AnyObject, Content: View>: View {

    @State private var box = TrapezioStoreBox<Store>()

    private let makeStore: () -> Store
    private let content: (Store) -> Content

    public init(
        makeStore: @escaping @autoclosure () -> Store,
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        self.makeStore = makeStore
        self.content = content
    }

    public var body: some View {
        content(box.resolve(makeStore))
    }
}

public extension TrapezioContainer {
    /// Convenience initializer for the common Trapezio pattern: `TrapezioStore + TrapezioUI`.
    ///
    /// - Note: `Store` is the erased `TrapezioStore` base class here, so subclass-specific API
    ///   is not reachable from this initializer. `handle(event:)` and `update(_:)` still
    ///   dispatch dynamically to your subclass, so this is the right choice for the common
    ///   case. When you need the concrete type — to read a store's own `messageManager`, say —
    ///   use the primary initializer, which infers `Store` from what you pass it:
    ///
    ///   ```swift
    ///   TrapezioContainer(makeStore: CounterStore(...)) { store in
    ///       store.render(with: CounterUI())        // `store` is a CounterStore
    ///   }
    ///   ```
    init<S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent, UI: TrapezioUI>(
        makeStore: @escaping @autoclosure () -> TrapezioStore<S, State, Event>,
        ui: UI
    ) where Store == TrapezioStore<S, State, Event>, Content == AnyView, UI.State == State, UI.Event == Event {
        self.makeStore = makeStore
        self.content = { store in
            AnyView(store.render(with: ui))
        }
    }
}
