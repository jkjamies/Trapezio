//
//  TrapezioContainer.swift
//  Trapezio
//
//  A SwiftUI-idiomatic container that owns a Store as a @StateObject.
//  This ensures the Store lifecycle matches the view lifecycle
//  (similar to Compose remember/rememberRetained semantics).
//

import SwiftUI

/// The SwiftUI lifecycle owner for Trapezio stores.
///
/// Use this whenever you render a store in SwiftUI so the store isn't recreated
/// during view updates (e.g. when navigating or when parent views re-render).
public struct TrapezioContainer<Store: ObservableObject & AnyObject, Content: View>: View {

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
    init<S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent, UI: TrapezioUI>(
        makeStore: @escaping @autoclosure () -> TrapezioStore<S, State, Event>,
        ui: UI
    ) where Store == TrapezioStore<S, State, Event>, Content == AnyView, UI.State == State, UI.Event == Event {
        _store = StateObject(wrappedValue: makeStore())
        self.content = { store in
            AnyView(store.render(with: ui))
        }
    }
}
