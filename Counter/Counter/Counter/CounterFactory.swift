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
import Trapezio
import TrapezioNavigation

struct CounterFactory {
    @MainActor
    static func make(screen: CounterScreen, navigator: (any TrapezioNavigator)?, interop: (any TrapezioInterop)?) -> some View {
        // Composition Root: what a DI container would otherwise resolve. Everything is built
        // inside the autoclosure so it runs once, not on every view evaluation.
        TrapezioContainer(
            makeStore: CounterStore(
                screen: screen,
                divideUsecase: DivideUsecase(),
                navigator: navigator,
                interop: interop
            ),
            ui: CounterUI()
        )
    }
}
