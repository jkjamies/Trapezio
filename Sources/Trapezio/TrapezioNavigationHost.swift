//
//  TrapezioNavigationHost.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/11/26.
//

import SwiftUI

/// A lightweight SwiftUI host that owns a `NavigationStack` and a library-managed `TrapezioNavigator`.
///
/// You provide:
/// - A root `TrapezioScreen`
/// - A builder that can render any `TrapezioScreen` using your factories/DI
///
/// Features can request navigation by calling `navigator.goTo(...)` / `dismiss()`.
public struct TrapezioNavigationHost: View {

    /// Receives custom navigation/dismissal requests for legacy interop.
    public typealias CustomNavigationHandler = (_ request: TrapezioCustomNavigationRequest) -> Void

    @StateObject private var navigator: TrapezioStackNavigator

    private let builder: (any TrapezioScreen, any TrapezioNavigator) -> AnyView

    /// - Parameters:
    ///   - root: Root screen for the navigation stack.
    ///   - onCustomNavigation: Called when a feature emits a custom navigation request.
    ///   - builder: Renders a screen into a view. The provided navigator is owned by this host.
    public init<Content: View>(
        root: any TrapezioScreen,
        onCustomNavigation: CustomNavigationHandler? = nil,
        @ViewBuilder builder: @escaping (_ screen: any TrapezioScreen, _ navigator: any TrapezioNavigator) -> Content
    ) {
        _navigator = StateObject(wrappedValue: TrapezioStackNavigator(root: root, onCustomNavigation: onCustomNavigation))
        self.builder = { screen, navigator in
            AnyView(builder(screen, navigator))
        }
    }

    public var body: some View {
        NavigationStack(path: $navigator.path) {
            rootView
                .navigationDestination(for: TrapezioAnyScreen.self) { anyScreen in
                    builder(anyScreen.base, navigator)
                }
        }
    }

    private var rootView: some View {
        if let root = navigator.root {
            return builder(root, navigator)
        }
        return AnyView(EmptyView())
    }
}

/// Custom navigation/dismissal requests emitted by features.
public enum TrapezioCustomNavigationRequest: Equatable {
    case goTo(String)
    case dismissTo(String)
}

/// Type-erased `TrapezioScreen` wrapper used as a `NavigationStack` path element.
///
/// `NavigationStack` requires path elements to be `Hashable`. Hashing an existential
/// screen value can be fragile across toolchains/runtimes.
///
/// This wrapper gives each pushed entry its own stable identity.
public struct TrapezioAnyScreen: Hashable {
    public let id: UUID
    public let base: any TrapezioScreen

    public init(_ base: any TrapezioScreen, id: UUID = UUID()) {
        self.id = id
        self.base = base
    }

    public static func == (lhs: TrapezioAnyScreen, rhs: TrapezioAnyScreen) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A library-owned navigator that drives a `NavigationStack` by mutating its path.
@MainActor
internal final class TrapezioStackNavigator: ObservableObject, TrapezioNavigator {

    @Published fileprivate var path: [TrapezioAnyScreen] = []
    fileprivate var root: (any TrapezioScreen)?

    private let onCustomNavigation: TrapezioNavigationHost.CustomNavigationHandler?

    internal init(root: any TrapezioScreen, onCustomNavigation: TrapezioNavigationHost.CustomNavigationHandler?) {
        self.root = root
        self.onCustomNavigation = onCustomNavigation
    }

    internal func goTo(_ screen: any TrapezioScreen) {
        path.append(TrapezioAnyScreen(screen))
    }

    internal func goTo(custom: String) {
        onCustomNavigation?(.goTo(custom))
    }

    internal func dismiss() {
        guard !path.isEmpty else { return }
        _ = path.popLast()
    }

    internal func dismissToRoot() {
        path.removeAll()
    }

    internal func dismissTo(_ screen: any TrapezioScreen) {
        assertionFailure("dismissTo(_:) is not supported by this host navigator. Use dismissToRoot(), dismiss(), or implement targeting in your app-layer navigator.")
    }

    internal func dismissTo(custom: String) {
        onCustomNavigation?(.dismissTo(custom))
    }
}
