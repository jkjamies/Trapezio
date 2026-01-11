//
//  TrapezioNavigator.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import Foundation

/// Hoists navigation and coordination logic out of the feature.
@MainActor
public protocol TrapezioNavigator: AnyObject {

    // MARK: - Navigation

    /// Requests navigation to a strongly-typed TrapezioScreen.
    func goTo(_ screen: any TrapezioScreen)

    /// Emits a custom navigation/interop request.
    ///
    /// This is intentionally not tied to SwiftUI's `NavigationStack`. Integrators can
    /// interpret this to perform UIKit navigation, deep links, tab switching, etc.
    func goTo(custom: String)

    // MARK: - Dismissal

    /// Dismisses the current active feature.
    func dismiss()

    /// Pops to the root of the current navigation stack.
    func dismissToRoot()

    /// Requests dismissal back to a specific strongly-typed TrapezioScreen.
    func dismissTo(_ screen: any TrapezioScreen)

    /// Emits a custom dismissal/interop request.
    func dismissTo(custom: String)
}
