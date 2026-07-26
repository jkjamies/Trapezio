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

@MainActor
internal struct TrapezioRuntime<S, State, Event, Store, UI>: View
where S: TrapezioScreen, State: TrapezioState, Event: TrapezioEvent,
      Store: TrapezioStore<S, State, Event>, UI: TrapezioUI,
      UI.State == State, UI.Event == Event {

    @ObservedObject var presenter: Store
    private let ui: UI

    /// Tracks whether `onFirstAppear` has already been delivered for this view identity.
    @SwiftUI.State private var hasAppeared = false

    internal init(presenter: Store, ui: UI) {
        self.presenter = presenter
        self.ui = ui
    }

    internal var body: some View {
        ui.map(state: presenter.state) { event in
            presenter.handle(event: event)
        }
        .onAppear {
            guard let lifecycle = presenter as? any TrapezioLifecycle else { return }
            if !hasAppeared {
                hasAppeared = true
                lifecycle.onFirstAppear()
            }
            lifecycle.onAppear()
        }
        .onDisappear {
            (presenter as? any TrapezioLifecycle)?.onDisappear()
        }
    }
}
