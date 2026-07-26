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
import os
@testable import Trapezio

/// Covers the resolve-once guarantee behind `TrapezioContainer`.
///
/// This is the mechanism that keeps an adopter's dependency graph — repositories, `ModelContext`s,
/// network clients — from being rebuilt and discarded on every view evaluation. `@StateObject`
/// used to provide it via an `@autoclosure`; under `@Observable` the box provides it instead, so
/// it is worth testing directly.
///
/// Scope note: these tests cover the box, not SwiftUI's retention of it across view updates.
/// Verifying that needs a hosted view and is not attempted here.
@Suite("TrapezioStoreBox")
struct TrapezioStoreBoxTests {

    private final class Dummy {}

    @Test("builds the store exactly once across repeated resolves")
    func buildsOnce() {
        let box = TrapezioStoreBox<Dummy>()
        let builds = OSAllocatedUnfairLock<Int>(initialState: 0)

        let make: () -> Dummy = {
            builds.withLock { $0 += 1 }
            return Dummy()
        }

        _ = box.resolve(make)
        _ = box.resolve(make)
        _ = box.resolve(make)

        #expect(builds.withLock { $0 } == 1)
    }

    @Test("returns the same instance on every resolve")
    func returnsSameInstance() {
        let box = TrapezioStoreBox<Dummy>()

        let first = box.resolve { Dummy() }
        let second = box.resolve { Dummy() }

        #expect(first === second)
    }

    @Test("separate boxes hold separate stores")
    func boxesAreIndependent() {
        let first = TrapezioStoreBox<Dummy>().resolve { Dummy() }
        let second = TrapezioStoreBox<Dummy>().resolve { Dummy() }

        #expect(first !== second)
    }

    @Test("the store outlives the closure that built it")
    func storeOutlivesBuilder() {
        let box = TrapezioStoreBox<Dummy>()
        var original: Dummy?

        do {
            let scoped = Dummy()
            original = scoped
            _ = box.resolve { scoped }
        }

        // A second resolve must not reach for the builder again.
        let rebuilt = OSAllocatedUnfairLock<Bool>(initialState: false)
        let resolved = box.resolve { () -> Dummy in
            rebuilt.withLock { $0 = true }
            return Dummy()
        }

        #expect(rebuilt.withLock { $0 } == false)
        #expect(resolved === original)
    }
}

// MARK: - Lifecycle defaults

/// Implements none of the callbacks. That this compiles at all is the point: every requirement
/// on `TrapezioLifecycle` carries a default, so a store opts into only what it needs.
@MainActor
private final class BareLifecycleStore: TrapezioLifecycle {}

@MainActor
private final class PartialLifecycleStore: TrapezioLifecycle {
    private(set) var firstAppearCount = 0
    func onFirstAppear() { firstAppearCount += 1 }
}

@Suite("TrapezioLifecycle defaults")
struct TrapezioLifecycleDefaultTests {

    @Test("a conformer may implement none of the callbacks")
    @MainActor func allDefaultsAreNoOps() {
        let store = BareLifecycleStore()

        // The defaults must be callable and must not trap. Compiling is half the assertion.
        store.onFirstAppear()
        store.onAppear()
        store.onDisappear()
    }

    @Test("implementing one callback leaves the others defaulted")
    @MainActor func partialConformance() {
        let store = PartialLifecycleStore()

        store.onFirstAppear()
        store.onAppear()
        store.onDisappear()

        // onAppear/onDisappear fell through to the defaults without needing an implementation.
        #expect(store.firstAppearCount == 1)
    }
}
