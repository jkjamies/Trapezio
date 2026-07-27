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
import UIKit
import XCTest
import Trapezio
import TrapezioNavigation
@testable import Counter

// MARK: - Harness

/// Mutating this from a test forces the harness body to re-evaluate.
@Observable
private final class Ticker {
    var value = 0
}

/// Records every store the harness builds. A class so the escaping builder can append.
@MainActor
private final class CapturedStores {
    private(set) var stores: [CounterStore] = []
    func append(_ store: CounterStore) { stores.append(store) }
}

/// Builds the store under test. File scope so harness closures never capture the test case.
@MainActor
private func makeCounterStore() -> CounterStore {
    CounterStore(
        screen: CounterScreen(initialValue: 5),
        divideUsecase: FakeDivideUsecase(),
        navigator: nil,
        interop: nil
    )
}

/// A parent view that re-renders on demand, wrapping a `TrapezioContainer`.
private struct Harness: View {
    let ticker: Ticker
    let makeStore: () -> CounterStore

    var body: some View {
        VStack {
            // Reading the ticker is what registers the dependency that drives re-evaluation.
            Text("tick \(ticker.value)")
            TrapezioContainer(
                makeStore: makeStore(),
                ui: CounterUI()
            )
        }
    }
}

// MARK: - Tests

/// Drives `TrapezioContainer` and `TrapezioRuntime` through a real SwiftUI host.
///
/// The unit tests in `MESA/Tests` cover `TrapezioStoreBox` in isolation, which proves the box
/// resolves once. They cannot prove SwiftUI *retains* that box across view updates — and if it
/// does not, every render rebuilds the dependency graph, which is exactly the failure
/// `@StateObject`'s autoclosure used to prevent and which the box now has to prevent instead.
///
/// If these turn out to be flaky in CI, the thing to fix is `settle()`, not the assertions.
@MainActor
final class TrapezioHostTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func host(_ view: some View) -> UIViewController {
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return controller
    }

    /// Lets SwiftUI process a pending invalidation and run the resulting body evaluation.
    private func settle(_ interval: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    func test_store_isBuiltOnceAcrossReRenders() {
        let ticker = Ticker()
        let captured = CapturedStores()

        let controller = host(
            Harness(ticker: ticker) {
                let store = makeCounterStore()
                captured.append(store)
                return store
            }
        )
        settle()
        XCTAssertEqual(captured.stores.count, 1, "store should be built on first render")

        for _ in 0..<3 {
            ticker.value += 1
            controller.view.layoutIfNeeded()
            settle()
        }

        // The autoclosure is recreated on every body evaluation; the box must not call it again.
        XCTAssertEqual(
            captured.stores.count, 1,
            "a re-render rebuilt the store — TrapezioStoreBox is not being retained by @State"
        )
    }

    /// State the UI mutated must survive a parent re-render. This is the point of preserving
    /// store identity, and the user-visible symptom if the box is not retained.
    func test_state_survivesParentReRender() {
        let ticker = Ticker()
        let captured = CapturedStores()

        let controller = host(
            Harness(ticker: ticker) {
                let store = makeCounterStore()
                captured.append(store)
                return store
            }
        )
        settle()

        guard let store = captured.stores.first else {
            XCTFail("no store was built")
            return
        }
        store.handle(event: .increment)
        XCTAssertEqual(store.state.count, 6)

        ticker.value += 1
        controller.view.layoutIfNeeded()
        settle()

        XCTAssertEqual(store.state.count, 6, "state was reset by a parent re-render")
        XCTAssertEqual(captured.stores.count, 1)
    }

    /// `onFirstAppear` is documented as once per view identity. If a re-render re-fired it, every
    /// render would start another observation task and the leak would be back.
    func test_onFirstAppear_firesExactlyOncePerViewIdentity() {
        let ticker = Ticker()
        let captured = CapturedStores()

        let controller = host(
            Harness(ticker: ticker) {
                let store = makeCounterStore()
                captured.append(store)
                return store
            }
        )
        settle()

        for _ in 0..<3 {
            ticker.value += 1
            controller.view.layoutIfNeeded()
            settle()
        }

        guard let store = captured.stores.first else {
            XCTFail("no store was built")
            return
        }

        // CounterStore.onFirstAppear starts exactly one tracked collect, so the bag counts the
        // number of times it ran. A count of 0 would mean onAppear never fired in the host —
        // also a real failure, not a passing test.
        XCTAssertEqual(
            store.tasks.count, 1,
            "expected exactly one observation task; got \(store.tasks.count)"
        )
    }

    /// The runtime must route UI events into the store that the container is holding.
    func test_runtime_routesEventsIntoTheHostedStore() {
        let ticker = Ticker()
        let captured = CapturedStores()

        _ = host(
            Harness(ticker: ticker) {
                let store = makeCounterStore()
                captured.append(store)
                return store
            }
        )
        settle()

        guard let store = captured.stores.first else {
            XCTFail("no store was built")
            return
        }

        store.handle(event: .divideByTwo)
        settle()

        // FakeDivideUsecase is instant, and the reduce lands back on the main actor.
        XCTAssertEqual(store.state.count, 2)
    }
}
