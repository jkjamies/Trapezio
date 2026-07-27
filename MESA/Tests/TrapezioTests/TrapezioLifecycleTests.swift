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
import Observation
import Testing
import os
@testable import Trapezio

// MARK: - Helpers

/// Sendable box for a value written from inside a detached task.
actor ValueBox<T: Sendable> {
    private var stored: T?
    var value: T? { stored }
    func set(_ newValue: T) { stored = newValue }
}

/// Tallies observation callbacks without a captured `var`.
///
/// Deliberately not `@MainActor`: `withObservationTracking` invokes `onChange` from a
/// `@Sendable` closure, so a main-actor call from inside it would not compile.
final class ChangeCounter: @unchecked Sendable {
    private let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
    var value: Int { counter.withLock { $0 } }
    func increment() { counter.withLock { $0 += 1 } }
}

/// A one-shot signal letting a test wait until a task has actually started running.
func makeStartSignal() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
    var continuation: AsyncStream<Void>.Continuation!
    let stream = AsyncStream<Void> { continuation = $0 }
    return (stream, continuation)
}

// MARK: - TrapezioTaskBag

@Suite("TrapezioTaskBag")
struct TrapezioTaskBagTests {

    @Test("cancelAll cancels tracked work")
    func cancelAllCancels() async {
        let bag = TrapezioTaskBag()
        let (started, startedContinuation) = makeStartSignal()
        let observed = ValueBox<Bool>()

        let task = bag.addDetached {
            startedContinuation.yield()
            startedContinuation.finish()
            try? await Task.sleep(for: .seconds(10))
            await observed.set(Task.isCancelled)
        }

        for await _ in started { break }
        bag.cancelAll()
        await task.value

        let wasCancelled = await observed.value
        #expect(wasCancelled == true)
    }

    @Test("completed tasks remove themselves from the bag")
    func completedTasksPrune() async {
        let bag = TrapezioTaskBag()

        let tasks = (0..<5).map { _ in bag.addDetached { } }
        for task in tasks { await task.value }

        // Self-removal is the last statement in each task body, which has now completed.
        #expect(bag.count == 0)
    }

    @Test("bag deallocation cancels outstanding work")
    func deinitCancels() async {
        let (started, startedContinuation) = makeStartSignal()
        let observed = ValueBox<Bool>()

        var bag: TrapezioTaskBag? = TrapezioTaskBag()
        let task = bag!.addDetached {
            startedContinuation.yield()
            startedContinuation.finish()
            try? await Task.sleep(for: .seconds(10))
            await observed.set(Task.isCancelled)
        }

        for await _ in started { break }
        bag = nil
        await task.value

        let wasCancelled = await observed.value
        #expect(wasCancelled == true)
    }

    @Test("cancelAll is safe to call twice")
    func cancelAllIdempotent() {
        let bag = TrapezioTaskBag()
        bag.addDetached { }
        bag.cancelAll()
        bag.cancelAll()

        #expect(bag.count == 0)
    }
}

// MARK: - Store work tracking

@Suite("TrapezioStore work")
struct TrapezioStoreWorkTests {

    @Test("launch reduces on the main actor")
    @MainActor func launchReduces() async {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState())

        let task = store.launch(
            work: { 7 },
            reduce: { value in store.update { $0.count = value } }
        )
        await task.value

        #expect(store.state.count == 7)
    }

    @Test("launch(snapshot:) feeds captured state into detached work")
    @MainActor func launchSnapshot() async {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState(count: 21))

        let task = store.launch(
            snapshot: { $0.count },
            work: { count in count * 2 },
            reduce: { value in store.update { $0.count = value } }
        )
        await task.value

        #expect(store.state.count == 42)
    }

    @Test("cancelAll stops a running collect")
    @MainActor func cancelAllStopsCollect() async {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState())
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        let received = AsyncStream<Int>.makeStream()

        let task = store.collect(stream) { value in
            store.update { $0.count = value }
            received.continuation.yield(value)
        }

        continuation.yield(1)
        for await _ in received.stream { break }
        #expect(store.state.count == 1)

        store.cancelAll()
        await task.value

        // The collect task has ended, so nothing further can land in state.
        continuation.yield(99)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.state.count == 1)
    }

    @Test("store deallocation cancels its tracked work")
    func storeDeinitCancels() async {
        let (started, startedContinuation) = makeStartSignal()
        let observed = ValueBox<Bool>()

        var store: FakeStore? = await FakeStore(screen: FakeScreen(), initialState: FakeState())
        let task = await store!.launch(
            work: {
                startedContinuation.yield()
                startedContinuation.finish()
                try? await Task.sleep(for: .seconds(10))
                await observed.set(Task.isCancelled)
            },
            reduce: { _ in }
        )

        for await _ in started { break }
        store = nil
        await task.value

        let wasCancelled = await observed.value
        #expect(wasCancelled == true)
    }
}

// MARK: - update() publishing

@Suite("TrapezioStore update publishing")
struct TrapezioStoreUpdatePublishingTests {

    @Test("update notifies observers when state changes")
    @MainActor func notifiesOnChange() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState(count: 0))
        let counter = ChangeCounter()

        withObservationTracking {
            _ = store.state
        } onChange: {
            counter.increment()
        }

        store.update { $0.count = 1 }

        #expect(counter.value == 1)
    }

    @Test("update does not notify observers when state is unchanged")
    @MainActor func skipsNotifyWhenEqual() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState(count: 1))
        let counter = ChangeCounter()

        withObservationTracking {
            _ = store.state
        } onChange: {
            counter.increment()
        }

        // Assigning an equal value would still notify, so `update` must skip the write.
        store.update { $0.count = 1 }
        store.update { _ in }

        #expect(counter.value == 0)
    }
}

// MARK: - Message manager teardown

@Suite("TrapezioMessageManager teardown")
struct TrapezioMessageManagerTeardownTests {

    @Test("messagesSequence finishes when the manager deallocates")
    func sequenceFinishesOnDeinit() async {
        var manager: TrapezioMessageManager? = await TrapezioMessageManager()
        let sequence = await manager!.messagesSequence

        let collector = Task { () -> Int in
            var count = 0
            // Only returns once the stream finishes, which is the behaviour under test.
            for await _ in sequence { count += 1 }
            return count
        }

        // Drop the manager; its ContinuationRegistry should finish the stream on dealloc.
        manager = nil

        let count = await collector.value
        #expect(count >= 1)
    }

    @Test("each access to messagesSequence is an independent subscription")
    @MainActor func independentSubscriptions() async {
        let manager = TrapezioMessageManager()

        var first = manager.messagesSequence.makeAsyncIterator()
        var second = manager.messagesSequence.makeAsyncIterator()

        _ = await first.next()
        _ = await second.next()

        let message = TrapezioMessage(message: "broadcast")
        manager.emit(message)

        let a = await first.next()
        let b = await second.next()

        #expect(a == [message])
        #expect(b == [message])
    }
}
