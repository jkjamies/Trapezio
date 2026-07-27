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
final class SummaryStoreTests: XCTestCase {

    private var repository: FakeSummaryRepository!
    private var navigator: FakeNavigator!
    private var store: SummaryStore!

    override func setUp() {
        super.setUp()
        repository = FakeSummaryRepository()
        navigator = FakeNavigator()
        store = SummaryStore(
            screen: SummaryScreen(value: 42),
            navigator: navigator,
            saveUseCase: SaveLastValueUseCase(repository: repository),
            observeUseCase: ObserveLastValueUseCase(repository: repository)
        )
    }

    override func tearDown() {
        store = nil
        navigator = nil
        repository = nil
        super.tearDown()
    }

    func test_initialState_takesValueFromScreen() {
        XCTAssertEqual(store.state.value, 42)
        XCTAssertNil(store.state.lastSavedValue)
        XCTAssertFalse(store.state.isLoading)
    }

    func test_save_writesThroughToRepository() async throws {
        store.handle(event: .save)
        try await Task.sleep(nanoseconds: 100_000_000) // detached launch + main-actor reduce

        XCTAssertEqual(repository.saved, [42])
        XCTAssertEqual(store.state.saveMessage, "Value saved successfully.")
    }

    func test_save_reportsFailureMessage() async throws {
        repository.shouldFail = true

        store.handle(event: .save)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(repository.saved.isEmpty)
        XCTAssertEqual(store.state.saveMessage?.hasPrefix("Failed to save:"), true)
    }

    func test_dismissMessage_clearsSaveMessage() async throws {
        store.handle(event: .save)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(store.state.saveMessage)

        store.handle(event: .dismissMessage)

        XCTAssertNil(store.state.saveMessage)
    }

    func test_back_dismissesViaNavigator() {
        store.handle(event: .back)

        XCTAssertEqual(navigator.dismissCount, 1)
    }

    /// `onFirstAppear` is what the runtime calls from the view; a headless test calls it directly.
    func test_onFirstAppear_startsObservingSavedValue() async throws {
        store.onFirstAppear()
        try await Task.sleep(nanoseconds: 50_000_000) // let the collect task subscribe

        repository.emit(7)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state.lastSavedValue, 7)
    }

    /// Observation must not start in `init` — a store built but never shown should stay inert.
    func test_observationDoesNotStartBeforeFirstAppear() async throws {
        repository.emit(99)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.state.lastSavedValue)
    }
}
