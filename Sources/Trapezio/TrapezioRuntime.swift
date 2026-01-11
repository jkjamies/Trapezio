//
//  TrapezioRuntime.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import SwiftUI

@MainActor
internal struct TrapezioRuntime<S, State, Event, Store, UI>: View
where S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent,
      Store: TrapezioStore<S, State, Event>, UI: TrapezioUI,
      UI.State == State, UI.Event == Event {
    
    @ObservedObject var presenter: Store
    private let ui: UI
    
    internal init(presenter: Store, ui: UI) {
        self.presenter = presenter
        self.ui = ui
    }
    
    public var body: some View {
        ui.map(state: presenter.state) { event in
            presenter.handle(event: event)
        }
    }
}
