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
final class CounterStore: TrapezioStore<CounterScreen, CounterState, CounterEvent>, TrapezioLifecycle {
    private let divideUsecase: any DivideUsecaseProtocol
    private let navigator: (any TrapezioNavigator)?
    private let interop: (any TrapezioInterop)?
    let messageManager = TrapezioMessageManager()

    init(
        screen: CounterScreen,
        divideUsecase: any DivideUsecaseProtocol,
        navigator: (any TrapezioNavigator)?,
        interop: (any TrapezioInterop)?
    ) {
        self.divideUsecase = divideUsecase
        self.navigator = navigator
        self.interop = interop
        super.init(screen: screen, initialState: CounterState(count: screen.initialValue))
    }

    // MARK: - TrapezioLifecycle

    /// Observation starts once, on first appearance. `collect` tracks the task in the store's
    /// bag, so it is cancelled when the store deallocates.
    func onFirstAppear() {
        collect(messageManager.messagesSequence) { [weak self] messages in
            self?.update { $0.message = messages.first }
        }
    }

    // MARK: - Events

    override func handle(event: CounterEvent) {
        switch event {
        case .increment:
            update { $0.count += 1 }
        case .decrement:
            update { $0.count -= 1 }
        case .divideByTwo:
            // `work` runs off the main actor and so cannot read `state`. The snapshot closure
            // captures what it needs on the main actor first.
            launch(
                snapshot: { $0.count },
                work: { [divideUsecase] count in await divideUsecase.execute(value: count) },
                reduce: { [weak self] result in self?.update { $0.count = result } }
            )
        case .goToSummary:
            navigator?.goTo(SummaryScreen(value: state.count))
        case .requestHelp:
            interop?.send(AppInterop.showAlert(message: "This is a simple counter. Press +/- to change value."))
        case .throwError:
            messageManager.emit(TrapezioMessage(message: "Simulated Failure"))
        case .clearError(let id):
            messageManager.clearMessage(id: id)
        }
    }
}
