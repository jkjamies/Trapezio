//
//  File.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import SwiftUI
import Combine

@MainActor
open class TrapezioStore<S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent>: ObservableObject {
    public let screen: S
    @Published public private(set) var state: State
    
    public init(screen: S, initialState: State) {
        self.screen = screen
        self.state = initialState
    }
    
    open func handle(event: Event) { }
    
    public final func update(_ transform: (inout State) -> Void) {
        var copy = self.state
        transform(&copy)
        if copy != self.state {
            self.state = copy
        }
    }

    @MainActor
    public func render<U: TrapezioUI>(with ui: U) -> some View
    where U.State == State, U.Event == Event {
        TrapezioRuntime(presenter: self, ui: ui)
    }
}
