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
import SwiftData

struct SummaryFactory {
    @MainActor
    static func make(screen: SummaryScreen, navigator: (any TrapezioNavigator)?) -> some View {
        // Composition Root: the whole graph is assembled *inside* the autoclosure, so the
        // container builds it once rather than on every view evaluation. Hoisting the
        // repository out of here would allocate a fresh ModelContext per render and discard it.
        TrapezioContainer(
            makeStore: {
                let repository = SummaryRepositoryImpl(container: PersistenceService.shared.container)
                return SummaryStore(
                    screen: screen,
                    navigator: navigator,
                    saveUseCase: SaveLastValueUseCase(repository: repository),
                    observeUseCase: ObserveLastValueUseCase(repository: repository)
                )
            }(),
            ui: SummaryUI()
        )
    }
}
