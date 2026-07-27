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
import Testing
import Trapezio
@testable import TrapezioTest

private struct TestScreen: TrapezioScreen {}

private struct TestState: TrapezioState {
    var count: Int = 0
}

private enum TestEvent: TrapezioEvent {
    case increment
    case asyncIncrement
}

@MainActor
private final class TestStore: TrapezioStore<TestScreen, TestState, TestEvent> {
    override func handle(event: TestEvent) {
        switch event {
        case .increment:
            update { $0.count += 1 }
        case .asyncIncrement:
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                self.update { $0.count += 1 }
            }
        }
    }
}

@Suite("TrapezioStore test() / awaitState()")
struct TrapezioStoreTestExtensionTests {

    @Test("test() provides current state for assertion")
    @MainActor func testProvidesCurrentState() {
        let store = TestStore(screen: TestScreen(), initialState: TestState(count: 5))

        store.test { state in
            #expect(state.count == 5)
        }
    }

    @Test("test() reflects state after event handling")
    @MainActor func testAfterEvent() {
        let store = TestStore(screen: TestScreen(), initialState: TestState())

        store.handle(event: .increment)
        store.handle(event: .increment)

        store.test { state in
            #expect(state.count == 2)
        }
    }

    @Test("awaitState() waits for predicate then validates")
    @MainActor func awaitStateWaitsForPredicate() async {
        let store = TestStore(screen: TestScreen(), initialState: TestState())

        store.handle(event: .asyncIncrement)

        let satisfied = await store.awaitState(
            until: { $0.count > 0 },
            validate: { state in
                #expect(state.count == 1)
            }
        )

        #expect(satisfied)
    }

    @Test("awaitState() returns immediately when predicate already satisfied")
    @MainActor func awaitStateImmediateSatisfaction() async {
        let store = TestStore(screen: TestScreen(), initialState: TestState(count: 10))

        await store.awaitState(
            until: { $0.count == 10 },
            validate: { state in
                #expect(state.count == 10)
            }
        )
    }

    @Test("awaitState() times out and still validates current state")
    @MainActor func awaitStateTimeout() async {
        let store = TestStore(screen: TestScreen(), initialState: TestState())

        let satisfied = await store.awaitState(
            timeout: 0.1,
            until: { $0.count == 999 },
            validate: { state in
                #expect(state.count == 0)
            }
        )

        // The distinguishing signal: validation ran, but the condition never held.
        #expect(!satisfied)
    }
}
