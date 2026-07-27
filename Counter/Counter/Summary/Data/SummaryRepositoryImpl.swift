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
import SwiftData

public actor SummaryRepositoryImpl: SummaryRepository, ModelActor {
    public let modelContainer: ModelContainer
    public let modelExecutor: any ModelExecutor
    
    // Simple notification bus
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    
    public init(container: ModelContainer) {
        self.modelContainer = container
        let context = ModelContext(container)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }
    
    public func saveValue(_ value: Int) async throws {
        let context = self.modelContext
        // Sorted to match `fetchCurrentValueSafe`, so read and write always agree on which row
        // is "current" when the store holds more than one.
        var descriptor = FetchDescriptor<MESAModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor)

        if let first = existing.first {
            first.lastSavedValue = value
            first.timestamp = Date()
        } else {
            let newModel = MESAModel(lastSavedValue: value)
            context.insert(newModel)
        }
        
        try context.save()
        notifyObservers()
    }
    
    private func notifyObservers() {
        // Drop continuations whose consumer has gone away. `onTermination` normally handles
        // this, but pruning on yield means a missed termination cannot accumulate observers —
        // each stale entry would otherwise cost a redundant fetch on every save.
        var stale: [UUID] = []
        for (id, continuation) in observers {
            if case .terminated = continuation.yield(()) {
                stale.append(id)
            }
        }
        for id in stale {
            observers.removeValue(forKey: id)
        }
    }
    
    public nonisolated func observeLastValue() -> AsyncStream<Int?> {
        // We use a Task to bridge to the actor and manage the observation stream
        return AsyncStream { continuation in
            let id = UUID()
            let (stream, observerContinuation) = AsyncStream<Void>.makeStream()
            
            let task = Task {
                // Register observer on actor
                await self.addObserver(id: id, continuation: observerContinuation)
                
                // Initial emit
                let initial = await self.fetchCurrentValueSafe()
                continuation.yield(initial)
                
                // Forward updates
                for await _ in stream {
                    let updated = await self.fetchCurrentValueSafe()
                    continuation.yield(updated)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
                // Cleanup observer from actor
                Task {
                    await self.removeObserver(id: id)
                }
            }
        }
    }
    
    // Helper to modify state (must be on actor)
    private func addObserver(id: UUID, continuation: AsyncStream<Void>.Continuation) {
        observers[id] = continuation
    }
    
    private func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    private func fetchCurrentValueSafe() -> Int? {
        // Helper running on the actor
        let descriptor = FetchDescriptor<MESAModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try? self.modelContext.fetch(descriptor).first?.lastSavedValue
    }
}
