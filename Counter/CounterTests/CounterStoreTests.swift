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

import XCTest
import Trapezio
import TrapezioNavigation
@testable import Counter

@MainActor
final class CounterStoreTests: XCTestCase {
    
    var store: CounterStore!
    var interop: FakeInterop!
    
    override func setUp() {
        super.setUp()
        
        // 2. Manual Injection: We provide the fake directly.
        // This is where we "simulate" a DI override.
        let screen = CounterScreen(initialValue: 10)
        let fakeUsecase = FakeDivideUsecase()
        interop = FakeInterop()
        
        store = CounterStore(
            screen: screen,
            divideUsecase: fakeUsecase,
            navigator: nil,
            interop: interop
        )
    }

    func test_increment_increasesCount() {
        store.handle(event: .increment)
        XCTAssertEqual(store.state.count, 11)
    }

    func test_decrement_decreasesCount() {
        store.handle(event: .decrement)
        XCTAssertEqual(store.state.count, 9)
    }

    func test_goToSummary_withNilNavigator_doesNotMutateState() {
        let initialCount = store.state.count
        store.handle(event: .goToSummary)
        XCTAssertEqual(store.state.count, initialCount)
    }

    func test_divideByTwo_isInstantAndDeterministic() async throws {
        store.handle(event: .divideByTwo)
        // The store's launch runs work detached, so we wait for both the detached work and the
        // MainActor hop back into reduce.
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        XCTAssertEqual(store.state.count, 5, "The count should be divided by 2 instantly using the fake.")
    }
    
    /// `onFirstAppear` is what the runtime calls from the view; a headless test calls it directly.
    func test_onFirstAppear_bindsMessageQueue() async throws {
        store.onFirstAppear()
        try await Task.sleep(nanoseconds: 50_000_000) // let the collect task subscribe

        store.handle(event: .throwError)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state.message?.message, "Simulated Failure")

        guard let id = store.state.message?.id else {
            XCTFail("Expected a message to be bound into state")
            return
        }
        store.handle(event: .clearError(id: id))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(store.state.message)
    }

    /// The binding must not start in `init` — a store built but never shown should stay inert.
    func test_messagesAreNotBoundBeforeFirstAppear() async throws {
        store.handle(event: .throwError)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.state.message)
    }

    func test_requestHelp_sendsInteropEvent() {
        store.handle(event: .requestHelp)
        
        XCTAssertEqual(interop.sentEvents.count, 1)
        guard let event = interop.sentEvents.first as? AppInterop else {
            XCTFail("Event was not AppInterop")
            return
        }
        
        if case .showAlert(let message) = event {
            XCTAssertEqual(message, "This is a simple counter. Press +/- to change value.")
        } else {
            XCTFail("Wrong event type")
        }
    }
}
