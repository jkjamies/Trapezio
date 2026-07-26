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

/// Binds a store to its UI and drives ``TrapezioLifecycle`` from the hosting view.
///
/// Generic parameters are suffixed `Type` so that `State` unambiguously means `SwiftUI.State`
/// inside this declaration.
@MainActor
internal struct TrapezioRuntime<ScreenType, StateType, EventType, Store, UI>: View
where ScreenType: TrapezioScreen, StateType: TrapezioState, EventType: TrapezioEvent,
      Store: TrapezioStore<ScreenType, StateType, EventType>, UI: TrapezioUI,
      UI.State == StateType, UI.Event == EventType {

    @ObservedObject var presenter: Store
    private let ui: UI

    /// Whether `onFirstAppear` has already been delivered for this view identity.
    @State private var hasAppeared = false

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
