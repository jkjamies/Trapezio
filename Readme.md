# Trapezio Framework

A type-safe, Circuit-inspired architecture for SwiftUI. This framework enforces a strict separation between logic (Store), presentation (UI), and identity (Screen).

## Core Architecture

### 1. The Screen (Identity)
The `TrapezioScreen` is a "Parcelable" data structure. It acts as the unique identifier for a feature and carries all necessary initialization parameters.

### 2. The Store (Logic)
The `TrapezioStore` is the brain of the feature. It is isolated to the `@MainActor` to ensure thread-safe state management. It receives `Events` and produces a new `State`.

### 3. The UI (Stateless View)
The `TrapezioUI` is a pure mapping function. It takes a `State` and returns a `View`. It communicates user interactions back to the Store via a closure.

### 4. The Runtime (The Weld)
The `TrapezioRuntime` is the engine that connects the Store to the UI. It ensures that the generic types for State and Event match across all components at compile-time.

### 5. SwiftUI lifecycle ownership (Recommended)
When rendering a feature in SwiftUI, use `TrapezioContainer` so the Store is owned as a `@StateObject`.
This avoids Store re-creation during view updates and navigation.

## Example: Counter Feature

```swift
// 1. Definition (Screen, State, Event)
struct CounterScreen: TrapezioScreen { let initialValue: Int }
struct CounterState: TrapezioState { var count: Int }
enum CounterEvent: TrapezioEvent { case increment }

// 2. Store Implementation
final class CounterStore: TrapezioStore<CounterScreen, CounterState, CounterEvent> {
    override func handle(event: CounterEvent) {
        if event == .increment { update { $0.count += 1 } }
    }
}

// 3. UI Implementation
struct CounterUI: TrapezioUI {
    func map(state: CounterState, onEvent: @escaping (CounterEvent) -> Void) -> some View {
        Button("\(state.count)") { onEvent(.increment) }
    }
}
```

## SwiftUI Navigation Host (Recommended)

Use `TrapezioNavigationHost` to drive navigation with a native `NavigationStack`.

- Features call `navigator.goTo(...)`, `navigator.dismiss()`, and `navigator.dismissToRoot()`.
- The host owns the stack state.
- The builder returns `some View` (no `AnyView` required at the call site).

```swift
import SwiftUI
import Trapezio

struct AppRoot: View {
    var body: some View {
        TrapezioNavigationHost(root: CounterScreen(initialValue: 0)) { screen, navigator in
            switch screen {
            case let counter as CounterScreen:
                CounterFactory.make(screen: counter, navigator: navigator)
            case let summary as SummaryScreen:
                SummaryFactory.make(screen: summary, navigator: navigator)
            default:
                EmptyView()
            }
        }
    }
}
```

## Using Trapezio without `TrapezioNavigationHost`

You can render a feature directly in SwiftUI without using the navigation host.

This is useful when:
- the feature is a leaf screen and navigation is handled elsewhere,
- you’re embedding a feature in an existing container,
- you don’t want Trapezio to own the navigation stack.

### Prefer `TrapezioContainer` for Store lifetime

`TrapezioContainer` owns the Store as a `@StateObject`, preventing re-initialization during view updates.

```swift
import SwiftUI
import Trapezio

struct StandaloneCounter: View {
    let screen: CounterScreen

    var body: some View {
        TrapezioContainer(makeStore: CounterStore(screen: screen, initialState: CounterState(count: screen.initialValue))) { store in
            store.render(with: CounterUI())
        }
    }
}
```

> Note: If your Store has dependencies (use cases, repositories, etc.), create it in the `makeStore:` expression (or via a factory/DI layer) and pass them in there.

## Custom interop navigation (optional)

For legacy apps or mixed SwiftUI/UIKit navigation, Stores can emit custom navigation requests:

- `goTo(custom: String)`
- `dismissTo(custom: String)`

These requests do **not** push onto the SwiftUI `NavigationStack`. They are forwarded to the host via `onCustomNavigation`, allowing completely app-defined behavior (UIKit coordinator, deep link router, tab switch, etc.).

### Emitting interop from a Store

```swift
// Inside a TrapezioStore handle(event:)

// Tell the app layer to do something totally custom
navigator?.goTo(custom: "legacy/profile?id=123")

// Or request a custom dismissal target
navigator?.dismissTo(custom: "legacy/home")
```

### Handling interop in the host

```swift
import SwiftUI
import Trapezio

struct AppRoot: View {
    var body: some View {
        TrapezioNavigationHost(
            root: CounterScreen(initialValue: 0),
            onCustomNavigation: { request in
                switch request {
                case .goTo(let route):
                    // Handle route however your app needs.
                    print("Interop goTo(custom:): \(route)")
                case .dismissTo(let route):
                    print("Interop dismissTo(custom:): \(route)")
                }
            },
            builder: { screen, navigator in
                switch screen {
                case let counter as CounterScreen:
                    CounterFactory.make(screen: counter, navigator: navigator)
                case let summary as SummaryScreen:
                    SummaryFactory.make(screen: summary, navigator: navigator)
                default:
                    EmptyView()
                }
            }
        )
    }
}
```

> Note: The included sample app (`TrapezioCounter`) is pure SwiftUI and does not currently use the interop hook.
