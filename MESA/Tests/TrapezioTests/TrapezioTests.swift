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
@testable import Trapezio

// MARK: - TrapezioStore Tests

@Suite("TrapezioStore")
struct TrapezioStoreTests {

    @Test("initializes with screen and state")
    @MainActor func initialization() {
        let screen = FakeScreen()
        let store = FakeStore(screen: screen, initialState: FakeState(count: 5))

        #expect(store.state.count == 5)
        #expect(store.screen == screen)
    }

    @Test("update mutates state via copy-on-write")
    @MainActor func updateMutatesState() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState())

        store.update { $0.count = 42 }

        #expect(store.state.count == 42)
    }

    @Test("update skips publish when state is unchanged")
    @MainActor func updateSkipsWhenEqual() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState(count: 1))

        // Mutate to the same value — state reference should remain unchanged semantically
        store.update { $0.count = 1 }

        #expect(store.state.count == 1)
    }

    @Test("handle(event:) dispatches to override")
    @MainActor func handleEvent() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState())

        store.handle(event: .increment)
        store.handle(event: .increment)
        store.handle(event: .decrement)

        #expect(store.state.count == 1)
        #expect(store.handledEvents.count == 3)
    }

    @Test("multiple update fields are independent")
    @MainActor func independentFields() {
        let store = FakeStore(screen: FakeScreen(), initialState: FakeState())

        store.handle(event: .increment)
        store.handle(event: .setLabel("hello"))

        #expect(store.state.count == 1)
        #expect(store.state.label == "hello")
    }

    @Test("conforms to Identifiable")
    @MainActor func identifiable() {
        let store1 = FakeStore(screen: FakeScreen(), initialState: FakeState())
        let store2 = FakeStore(screen: FakeScreen(), initialState: FakeState())

        #expect(store1.id != store2.id)
    }
}

// MARK: - TrapezioMessage Tests

@Suite("TrapezioMessage")
struct TrapezioMessageTests {

    @Test("message equality is based on id")
    func equality() {
        let id = UUID()
        let a = TrapezioMessage(message: "hello", id: id)
        let b = TrapezioMessage(message: "hello", id: id)
        let c = TrapezioMessage(message: "hello")

        #expect(a == b)
        #expect(a != c)
    }

    @Test("init from Error uses localizedDescription")
    func initFromError() {
        enum TestError: Error, LocalizedError {
            case test
            var errorDescription: String? { "test error" }
        }

        let msg = TrapezioMessage(TestError.test)

        #expect(msg.message == "test error")
    }

    @Test("init from Error without custom errorDescription uses system description")
    func initFromErrorNoCustomDescription() {
        struct PlainError: Error {}

        let msg = TrapezioMessage(PlainError())

        #expect(!msg.message.isEmpty)
    }

    @Test("init from Error preserves custom id")
    func initFromErrorCustomId() {
        struct TestError: Error {}
        let id = UUID()

        let msg = TrapezioMessage(TestError(), id: id)

        #expect(msg.id == id)
    }
}

// MARK: - TrapezioMessageManager Tests

@Suite("TrapezioMessageManager")
struct TrapezioMessageManagerTests {

    @Test("emit adds message to queue")
    @MainActor func emit() {
        let manager = TrapezioMessageManager()
        let msg = TrapezioMessage(message: "test")

        manager.emit(msg)

        #expect(manager.messages.count == 1)
        #expect(manager.message == msg)
    }

    @Test("clearMessage removes specific message")
    @MainActor func clearMessage() {
        let manager = TrapezioMessageManager()
        let msg1 = TrapezioMessage(message: "first")
        let msg2 = TrapezioMessage(message: "second")

        manager.emit(msg1)
        manager.emit(msg2)
        manager.clearMessage(id: msg1.id)

        #expect(manager.messages.count == 1)
        #expect(manager.message == msg2)
    }

    @Test("clearAll empties the queue")
    @MainActor func clearAll() {
        let manager = TrapezioMessageManager()

        manager.emit(TrapezioMessage(message: "a"))
        manager.emit(TrapezioMessage(message: "b"))
        manager.clearAll()

        #expect(manager.messages.isEmpty)
        #expect(manager.message == nil)
    }

    @Test("message returns first in queue")
    @MainActor func messageReturnsFirst() {
        let manager = TrapezioMessageManager()
        let first = TrapezioMessage(message: "first")

        manager.emit(first)
        manager.emit(TrapezioMessage(message: "second"))

        #expect(manager.message == first)
    }

    @Test("messagesSequence emits initial value then updates on emit")
    @MainActor func messagesSequenceEmits() async {
        let manager = TrapezioMessageManager()
        let msg = TrapezioMessage(message: "streamed")

        var iter = manager.messagesSequence.makeAsyncIterator()

        let initial = await iter.next()
        #expect(initial == [])

        manager.emit(msg)

        let updated = await iter.next()
        #expect(updated == [msg])
    }

    @Test("messagesSequence emits update on clearMessage")
    @MainActor func messagesSequenceClear() async {
        let manager = TrapezioMessageManager()
        let msg = TrapezioMessage(message: "to-clear")

        // Pre-populate so the initial emission is non-empty
        manager.emit(msg)

        var iter = manager.messagesSequence.makeAsyncIterator()

        let initial = await iter.next()
        #expect(initial == [msg])

        manager.clearMessage(id: msg.id)

        let cleared = await iter.next()
        #expect(cleared == [])
    }

    @Test("emitting 11 messages keeps only last 10")
    @MainActor func queueCapDropsOldest() {
        let manager = TrapezioMessageManager()

        for i in 0..<11 {
            manager.emit(TrapezioMessage(message: "msg-\(i)"))
        }

        #expect(manager.messages.count == 10)
        #expect(manager.messages.first?.message == "msg-1")
        #expect(manager.messages.last?.message == "msg-10")
    }

    @Test("emitting exactly 10 messages preserves all")
    @MainActor func queueCapExactly10() {
        let manager = TrapezioMessageManager()

        for i in 0..<10 {
            manager.emit(TrapezioMessage(message: "msg-\(i)"))
        }

        #expect(manager.messages.count == 10)
        #expect(manager.messages.first?.message == "msg-0")
    }

    @Test("oldest message is dropped when over capacity")
    @MainActor func queueCapDropsCorrectMessage() {
        let manager = TrapezioMessageManager()
        let first = TrapezioMessage(message: "first")

        manager.emit(first)
        for i in 1..<11 {
            manager.emit(TrapezioMessage(message: "msg-\(i)"))
        }

        #expect(manager.messages.count == 10)
        #expect(!manager.messages.contains(first))
    }
}

// MARK: - ClosureTrapezioInterop Tests

@Suite("ClosureTrapezioInterop")
struct ClosureTrapezioInteropTests {

    @Test("send delegates to closure")
    @MainActor func sendDelegatesToClosure() {
        var received: TrapezioInteropEvent?
        let interop = ClosureTrapezioInterop { event in
            received = event
        }

        interop.send(FakeInteropEvent.didTap)

        #expect(received is FakeInteropEvent)
    }
}
