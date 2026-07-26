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

/// A transient message to be displayed to the user (e.g., Snackbar, Alert).
public struct TrapezioMessage: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let message: String

    public init(message: String, id: UUID = UUID()) {
        self.message = message
        self.id = id
    }

    /// Creates a message from an `Error`, using its `localizedDescription`.
    ///
    /// Types conforming to `StrataException` supply `message` here, because that protocol
    /// refines `LocalizedError`.
    public init(_ error: Error, id: UUID = UUID()) {
        self.init(message: error.localizedDescription, id: id)
    }
}

/// Manages a queue of transient messages (oldest first).
///
/// Observe ``message`` to show the current message, or ``messagesSequence`` to react to the
/// whole queue. When the queue exceeds ``maxQueueSize`` the oldest entry is dropped (FIFO) to
/// make room for the new one; no error or back-pressure is emitted.
///
/// - Important: The dropped entry is the same one ``message`` returns, so under a burst of more
///   than ``maxQueueSize`` messages the one currently on screen is the one evicted. If your UI
///   needs a displayed message to survive a burst, clear it explicitly via ``clearMessage(id:)``
///   when it is dismissed rather than relying on queue position.
@MainActor
public class TrapezioMessageManager: ObservableObject {

    /// Maximum number of queued messages before the oldest is dropped.
    public static let maxQueueSize = 10

    @Published public private(set) var messages: [TrapezioMessage] = []

    /// Live subscriptions to ``messagesSequence``.
    ///
    /// Held as a sub-object so that when this manager deallocates, the registry deallocates
    /// with it and finishes every outstanding continuation — otherwise consumers would park on
    /// a stream that never ends.
    private let subscribers = ContinuationRegistry<[TrapezioMessage]>()

    /// The oldest queued message, or `nil` when the queue is empty.
    public var message: TrapezioMessage? {
        messages.first
    }

    /// An `AsyncStream` of queue snapshots, starting with the current contents.
    ///
    /// The stream finishes when this manager deallocates.
    ///
    /// - Important: This is a **computed** property — each access opens a new, independent
    ///   subscription. Read it once and hold the result (for example via
    ///   `TrapezioStore.collect(_:action:)`); never read it inside a SwiftUI `body`, which
    ///   would register a subscription per render.
    /// - Note: Buffering is `.bufferingNewest(1)`. A slow consumer sees the latest queue
    ///   snapshot rather than every intermediate one, which is the correct semantic for state
    ///   and keeps memory bounded.
    public var messagesSequence: AsyncStream<[TrapezioMessage]> {
        let current = messages
        let registry = subscribers
        return AsyncStream<[TrapezioMessage]>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Emit the initial value immediately.
            continuation.yield(current)

            let id = registry.register(continuation)
            // Weak: the registry holds the continuation, and the continuation holds this
            // closure. A strong capture here would be a cycle, keeping the registry — and so
            // the stream — alive after the manager is gone.
            continuation.onTermination = { [weak registry] _ in
                registry?.unregister(id)
            }
        }
    }

    public init() {}

    public func emit(_ message: TrapezioMessage) {
        messages.append(message)
        if messages.count > Self.maxQueueSize {
            messages = Array(messages.suffix(Self.maxQueueSize))
        }
        notifySubscribers()
    }

    public func clearMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        notifySubscribers()
    }

    public func clearAll() {
        messages.removeAll()
        notifySubscribers()
    }

    private func notifySubscribers() {
        subscribers.yield(messages)
    }
}
