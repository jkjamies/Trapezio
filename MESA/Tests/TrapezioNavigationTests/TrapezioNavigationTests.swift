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

import Testing
@testable import Trapezio
@testable import TrapezioNavigation

// MARK: - TrapezioStackNavigator Tests

@Suite("TrapezioStackNavigator")
struct TrapezioStackNavigatorTests {

    @Test("goTo appends screen to path")
    @MainActor func goTo() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.goTo(FakeScreenB())

        #expect(nav.path.count == 1)
    }

    @Test("goTo multiple screens builds stack")
    @MainActor func goToMultiple() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 1))
        nav.goTo(FakeScreenC(id: 2))

        #expect(nav.path.count == 3)
    }

    @Test("goTo ignores a screen already on top of the stack")
    @MainActor func goToIgnoresDuplicateTop() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenB())

        #expect(nav.path.count == 1)
    }

    @Test("goTo allows the same screen again from a deeper position")
    @MainActor func goToAllowsNonAdjacentRepeat() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 1))
        nav.goTo(FakeScreenB())

        #expect(nav.path.count == 3)
    }

    @Test("goTo treats screens differing only in parameters as distinct")
    @MainActor func goToDistinguishesByParameters() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.goTo(FakeScreenC(id: 1))
        nav.goTo(FakeScreenC(id: 2))

        #expect(nav.path.count == 2)
    }

    @Test("dismiss pops last screen")
    @MainActor func dismiss() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 0))

        nav.dismiss()

        #expect(nav.path.count == 1)
    }

    @Test("dismiss on empty path is no-op")
    @MainActor func dismissEmpty() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        nav.dismiss()

        #expect(nav.path.isEmpty)
    }

    @Test("dismissToRoot clears entire path")
    @MainActor func dismissToRoot() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 0))

        nav.dismissToRoot()

        #expect(nav.path.isEmpty)
    }

    @Test("dismissTo pops back to matching screen in path")
    @MainActor func dismissToScreen() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 1))
        nav.goTo(FakeScreenC(id: 2))

        nav.dismissTo(FakeScreenB())

        #expect(nav.path.count == 1)
    }

    @Test("dismissTo root screen clears path")
    @MainActor func dismissToRootScreen() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 0))

        nav.dismissTo(FakeScreenA())

        #expect(nav.path.isEmpty)
    }

    @Test("dismissTo non-existent screen is no-op")
    @MainActor func dismissToNonExistent() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())

        nav.dismissTo(FakeScreenC(id: 0))

        #expect(nav.path.count == 1)
    }

    @Test("dismissTo finds last occurrence when duplicates exist")
    @MainActor func dismissToLastOccurrence() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())       // index 0
        nav.goTo(FakeScreenC(id: 1))  // index 1
        nav.goTo(FakeScreenB())       // index 2
        nav.goTo(FakeScreenC(id: 2))  // index 3

        nav.dismissTo(FakeScreenB())

        // Should keep up to the LAST ScreenB (index 2), so 3 items in path
        #expect(nav.path.count == 3)
    }

    @Test("dismissTo uses Equatable not just hashValue")
    @MainActor func dismissToUsesEquatable() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenC(id: 1))
        nav.goTo(FakeScreenC(id: 2))
        nav.goTo(FakeScreenB())

        // Should find FakeScreenC(id: 1), not FakeScreenC(id: 2)
        nav.dismissTo(FakeScreenC(id: 1))

        #expect(nav.path.count == 1)
    }

    @Test("root is preserved after navigation")
    @MainActor func rootPreserved() {
        let root = FakeScreenA()
        let nav = TrapezioStackNavigator(root: root, onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.dismissToRoot()

        #expect(nav.root != nil)
    }

    @Test("interop handler receives events")
    @MainActor func interopHandler() {
        enum TestEvent: TrapezioInteropEvent { case test }
        var received = false
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: { _ in
            received = true
        })

        nav.interop.send(TestEvent.test)

        #expect(received)
    }

    // MARK: - Result Passing

    @Test("popWithResult stores result and pops")
    @MainActor func popWithResult() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())

        nav.popWithResult(key: "test_key", result: FakeNavigationResult(value: "hello"))

        #expect(nav.path.isEmpty)
    }

    @Test("consumeResult returns stored result")
    @MainActor func consumeResult() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.popWithResult(key: "test_key", result: FakeNavigationResult(value: "hello"))

        let result = nav.consumeResult(forKey: "test_key") as? FakeNavigationResult

        #expect(result == FakeNavigationResult(value: "hello"))
    }

    @Test("consumeResult returns nil on second call")
    @MainActor func consumeResultSingleConsumption() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.popWithResult(key: "test_key", result: FakeNavigationResult(value: "hello"))

        _ = nav.consumeResult(forKey: "test_key")
        let second = nav.consumeResult(forKey: "test_key")

        #expect(second == nil)
    }

    @Test("consumeResult returns nil for unknown key")
    @MainActor func consumeResultUnknownKey() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)

        let result = nav.consumeResult(forKey: "nonexistent")

        #expect(result == nil)
    }

    @Test("multiple results with different keys consumed independently")
    @MainActor func multipleResults() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 1))

        nav.popWithResult(key: "key_a", result: FakeNavigationResult(value: "a"))
        nav.popWithResult(key: "key_b", result: AnotherFakeResult(number: 42))

        let a = nav.consumeResult(forKey: "key_a", as: FakeNavigationResult.self)
        let b = nav.consumeResult(forKey: "key_b", as: AnotherFakeResult.self)

        #expect(a == FakeNavigationResult(value: "a"))
        #expect(b == AnotherFakeResult(number: 42))
    }

    @Test("consumeResult with type returns typed result")
    @MainActor func consumeResultTyped() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.popWithResult(key: "typed", result: FakeNavigationResult(value: "typed"))

        let result = nav.consumeResult(forKey: "typed", as: FakeNavigationResult.self)

        #expect(result == FakeNavigationResult(value: "typed"))
    }

    @Test("consumeResult with wrong type returns nil and preserves result")
    @MainActor func consumeResultTypeMismatchPreserves() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.popWithResult(key: "key", result: FakeNavigationResult(value: "hello"))

        let wrong = nav.consumeResult(forKey: "key", as: AnotherFakeResult.self)

        #expect(wrong == nil)
        // Result should still be available with the correct type
        let correct = nav.consumeResult(forKey: "key", as: FakeNavigationResult.self)
        #expect(correct == FakeNavigationResult(value: "hello"))
    }

    @Test("dismissToRoot clears unconsumed results")
    @MainActor func dismissToRootClearsResults() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.popWithResult(key: "key", result: FakeNavigationResult(value: "stale"))
        nav.goTo(FakeScreenC(id: 1))

        nav.dismissToRoot()

        #expect(nav.path.isEmpty)
        #expect(nav.consumeResult(forKey: "key") == nil)
    }

    @Test("clearResults removes all unconsumed results")
    @MainActor func clearResults() {
        let nav = TrapezioStackNavigator(root: FakeScreenA(), onInterop: nil)
        nav.goTo(FakeScreenB())
        nav.goTo(FakeScreenC(id: 1))
        nav.popWithResult(key: "key_a", result: FakeNavigationResult(value: "a"))
        nav.popWithResult(key: "key_b", result: AnotherFakeResult(number: 42))

        nav.clearResults()

        #expect(nav.consumeResult(forKey: "key_a") == nil)
        #expect(nav.consumeResult(forKey: "key_b") == nil)
    }
}

// MARK: - TrapezioAnyScreen

@Suite("TrapezioAnyScreen")
struct TrapezioAnyScreenTests {

    @Test("two wrappers of an equal screen are distinct path entries")
    func distinctIdentityPerWrap() {
        let first = TrapezioAnyScreen(FakeScreenB())
        let second = TrapezioAnyScreen(FakeScreenB())

        // Identity is per-entry, so the same route can legitimately sit at several depths.
        // This is also why the path itself cannot dedupe, and why `goTo` guards the top instead.
        #expect(first != second)
        #expect(first.hashValue != second.hashValue)
    }

    @Test("a wrapper equals itself")
    func reflexiveEquality() {
        let screen = TrapezioAnyScreen(FakeScreenB())
        let copy = screen

        #expect(screen == copy)
        #expect(screen.hashValue == copy.hashValue)
    }

    @Test("the wrapped screen is preserved")
    func preservesBase() {
        let wrapped = TrapezioAnyScreen(FakeScreenC(id: 7))

        #expect(AnyHashable(wrapped.base) == AnyHashable(FakeScreenC(id: 7)))
    }
}
