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

import Foundation
import Trapezio
import TrapezioNavigation
import Strata

@MainActor
final class SummaryStore: TrapezioStore<SummaryScreen, SummaryState, SummaryEvent>, TrapezioLifecycle {
    private let navigator: (any TrapezioNavigator)?
    private let saveUseCase: SaveLastValueUseCase
    private let observeUseCase: ObserveLastValueUseCase

    init(screen: SummaryScreen,
         navigator: (any TrapezioNavigator)?,
         saveUseCase: SaveLastValueUseCase,
         observeUseCase: ObserveLastValueUseCase) {
        self.navigator = navigator
        self.saveUseCase = saveUseCase
        self.observeUseCase = observeUseCase

        super.init(screen: screen, initialState: SummaryState(value: screen.value))
    }

    // MARK: - TrapezioLifecycle

    func onFirstAppear() {
        // Subscribe before triggering — `stream` broadcasts live emissions and does not replay.
        collect(observeUseCase.stream) { [weak self] value in
            self?.update { $0.lastSavedValue = value }
        }
        collect(saveUseCase.inProgressStream) { [weak self] isLoading in
            self?.update { $0.isLoading = isLoading }
        }
        observeUseCase(())
    }

    // MARK: - Events

    override func handle(event: SummaryEvent) {
        switch event {
        case .printValue:
            print("Trapezio Counter Value: \(state.value)")
        case .save:
            launch(
                snapshot: { $0.value },
                work: { [saveUseCase] value in await saveUseCase.execute(params: value) },
                reduce: { [weak self] result in
                    self?.update {
                        $0.saveMessage = result.fold(
                            onSuccess: { _ in "Value saved successfully." },
                            onFailure: { error in "Failed to save: \(error.message)" }
                        )
                    }
                }
            )
        case .dismissMessage:
            update { $0.saveMessage = nil }
        case .back:
            navigator?.dismiss()
        }
    }
}
